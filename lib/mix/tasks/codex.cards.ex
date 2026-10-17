defmodule Mix.Tasks.Codex.Cards do
  @shortdoc "Crops the Codex card art from the TTS sheet into priv/static/images/codex"
  @moduledoc """
  Makes the card art of Codex: one image per card of the neutral sheet (the
  neutral starting deck, the Bashing and Finesse codex cards and heroes, the
  worker cards, the Dancer tokens, Tower and Surplus), the Red, Green, Blue and
  Black sheets (heroes, starting decks, codex), the add-on and token sheet, and
  the card back.

      mix codex.cards [--sheet PATH] [--back PATH] [--tts DIR] [--out DIR]

  The colour sheets and the token sheet come from the TTS cache (`--tts`, default
  `~/Library/Tabletop Simulator/Mods/Images`); a missing one is skipped.

  The source is the neutral sheet of the TTS mod "Codex Deluxe Set" (research
  `docs/research/codex.md` §15): a 10 × 7 grid, `http://theshobo.com/codex/deck.png`
  (22 MB). It is not in the TTS cache, so the task downloads it (and the card back,
  `card_back.png`) to `tmp/codex/` once. `--sheet` and `--back` use local files.

  For each card the task writes `<out>/<slug>.webp` (300 px wide) and
  `<out>/zoom/<slug>.webp` (the full cell, 500 × 700 px). `<out>` is
  `priv/static/images/codex` by default. The art is © Sirlin Games: git ignores the
  folder, so the images stay on this machine. The board draws a CSS card when an
  image is missing.

  Needs ImageMagick 7 (`magick`) with WebP.
  """
  use Mix.Task

  @sheet_url "http://theshobo.com/codex/deck.png"
  @back_url "http://theshobo.com/codex/card_back.png"
  @cols 10
  @rows 7
  @small 300

  # The index of each card on the neutral sheet (row by row from the top left).
  # Research §15 had 30 names from the TTS save; the rest are named from the crops.
  @sheet %{
    0 => "wrecking-ball",
    1 => "final-smash",
    2 => "grounded-guide",
    3 => "the-boot",
    4 => "nimble-fencer",
    5 => "maestro",
    6 => "intimidate",
    7 => "angry-dancer",
    8 => "tower",
    9 => "surplus",
    10 => "harmony",
    11 => "appel-stomp",
    12 => "leaping-lizard",
    13 => "discord",
    14 => "dancer",
    15 => "blademaster",
    16 => "two-step",
    17 => "eggship",
    18 => "fruit-ninja",
    19 => "backstabber",
    20 => "worker-x5",
    22 => "worker-x4",
    23 => "river-montoya",
    25 => "troq-bashar",
    26 => "timely-messenger",
    27 => "brick-thief",
    28 => "star-crossed-starlet",
    29 => "iron-man",
    30 => "helpful-turtle",
    31 => "spark",
    32 => "older-brother",
    33 => "granfalloon-flagbearer",
    34 => "bloom",
    35 => "wither",
    36 => "hired-stomper",
    37 => "cloud-sprite",
    38 => "tenderfoot",
    39 => "regular-sized-rhinoceros",
    40 => "harvest-reaper",
    41 => "revolver-ocelot",
    42 => "sneaky-pig",
    43 => "trojan-duck"
  }

  # Red sheet (TTS deck 21), Green (deck 29): heroes 0-2, starting deck 3-12,
  # codex 13-48 (research §15; named from the sheets).
  @red ~w(captain-zane drakk-ramhorn jaina-stormborne nautical-dog mad-man bombaster
          careless-musketeer bloodrage-ogre makeshift-rambaster bloodburn scorch pillage
          charge chaos-mirror detonate surprise-attack maximum-anarchy desperation
          kidnapping bloodlust war-drums fire-dart ember-sparks flame-arrow burning-volley
          calypso-vystari gunpoint-taxman crash-bomber rickety-mine lobber firebat
          disguised-monkey chameleon-lizzo marauder steam-tank sanatorium shoddy-glider
          captured-bugblatter crashbarrow land-octopus ogre-recruiter bamstamper-lizzo
          doubleshot-archer molting-firebird firehouse hotter-fire pirate-gunship
          pirate-gang-commander cinderblast-dragon)

  @green ~w(master-midori calamandra-moss argagarg-garg merfolk-prospector tiger-cub
            young-treant playful-panda ironbark-treant spore-shambler verdant-tree
            rich-earth rampant-growth forest-s-favor moment-s-peace nature-reclaims
            circle-of-life final-showdown ferocity behind-the-ferns murkwood-allies
            feral-strike polymorph-squirrel dinosize spirit-of-the-panda stampede
            gemscout-owl tiny-basilisk huntress centaur galina-glimmer giant-panda
            chameleon fairie-dragon dothram-horselord wandering-mimic potent-basilisk
            stalking-tiger predator-tiger barkcoat-bear rampaging-elephant gigadon
            artisan-mantis oversized-rhinoceros blooming-ancient blooming-elm
            might-of-leaf-and-claw tyrannosaurus-rex moss-ancient guargum-eternal-sentinel)

  # Blue sheet (TTS deck 22), Black (deck 31): the same layout.
  @blue ~w(bigby-hayes general-onimaru sirus-quince building-inspector spectral-aven
           bluecoat-musketeer traffic-director porkhand-magistrate reputable-newsman jail
           lawful-search arrest manufactured-truth injunction community-service jurisdiction
           judgment-day boot-camp elite-training general-s-hammer the-art-of-war free-speech
           hallucination dreamscape mind-control tax-collector scribe overeager-cadet
           brave-knight spectral-flagbearer spectral-hound drill-sergeant flagstone-spy
           debilitator-alpha air-hammer flagstone-garrison guardian-of-the-gates
           insurance-agent justice-juggernaut arresting-constable censorship-council
           macciatus-the-whisperer reteller-of-truths spectral-tiger spectral-roc
           eyes-of-the-chancellor lawbringer-gryphon patriot-gryphon liberty-gryphon)

  @black ~w(vandy-anadrose orpal-gloor garth-torken pestering-haunt skeleton-javelineer
            poisonblade-rogue thieving-imp jandra-the-negator graveyard skeletal-archery
            deteriorate summon-skeletons sacrifice-the-weak soul-stone dark-pact shadow-blade
            metamorphosis sickness spreading-plague carrion-curse death-and-decay nether-drain
            lich-s-bargain doom-grasp death-rites gargoyle twilight-baron hooded-executioner
            bone-collector crypt-crawler plague-spitter voidblocker blackhand-dozer
            banefire-golem terras-q-the-shackled shrine-of-forbidden-knowledge gorgon
            cursed-ghoul cursed-crow abomination plague-lab blackhand-resurrector skeletal-lord
            corpse-catapult wight necromancer zarramonde-the-obliterator plague-lord
            lord-of-shadows)

  # Add-ons and tokens (TTS deck 18).
  @tokens %{
    2 => "tech-lab",
    3 => "heroes-hall",
    4 => "pirate",
    5 => "shark",
    6 => "water-elemental",
    7 => "wisp",
    8 => "frog",
    9 => "beast",
    10 => "squirrel",
    11 => "hunter",
    12 => "soldier",
    13 => "mirror-illusion",
    14 => "skeleton",
    15 => "zombie",
    16 => "horror",
    17 => "warlock"
  }

  # The TTS cache images (file name ends with the hash of the sheet URL).
  @tts [
    {"red", "A46870CB2B331265ABD80799E2D08E1DE6BDBA65",
     Map.new(Enum.with_index(@red), fn {s, i} -> {i, s} end)},
    {"green", "F3853E3A4CBEBFB448859849D52C9656F3D04A60",
     Map.new(Enum.with_index(@green), fn {s, i} -> {i, s} end)},
    {"blue", "9CA9E96F2BD8F2847536697F95CFEA4365A16116",
     Map.new(Enum.with_index(@blue), fn {s, i} -> {i, s} end)},
    {"black", "0BAB8B262622F251EBF7205E30890A85845805D1",
     Map.new(Enum.with_index(@black), fn {s, i} -> {i, s} end)},
    {"tokens", "1B48A292B49FAFE11630BDCA58BEBDE2257FBFBD", @tokens}
  ]

  @doc "The sheet index of each card slug (the neutral sheet)."
  @spec sheet() :: %{non_neg_integer => String.t()}
  def sheet, do: @sheet

  @doc "Every sheet map: `{name, index => slug}`."
  @spec sheets() :: [{String.t(), %{non_neg_integer => String.t()}}]
  def sheets, do: [{"neutral", @sheet} | Enum.map(@tts, fn {name, _hash, map} -> {name, map} end)]

  @switches [sheet: :string, back: :string, out: :string, tts: :string]

  @impl true
  def run(argv) do
    {opts, _args} = OptionParser.parse!(argv, strict: @switches)
    out = opts[:out] || "priv/static/images/codex"
    sheet = opts[:sheet] || fetch("tmp/codex/deck.png", @sheet_url)
    back = opts[:back] || fetch("tmp/codex/card_back.png", @back_url)
    File.mkdir_p!(Path.join(out, "zoom"))

    count = crop(sheet, @sheet, out)
    tts = opts[:tts] || Path.expand("~/Library/Tabletop Simulator/Mods/Images")

    count =
      Enum.reduce(@tts, count, fn {name, hash, map}, count ->
        case Path.wildcard(Path.join(tts, "*#{hash}.png")) do
          [file | _] ->
            count + crop(file, map, out)

          [] ->
            Mix.shell().info("No #{name} sheet (*#{hash}.png) in #{tts}: skipped.")
            count
        end
      end)

    magick!(
      [
        back,
        [
          "(",
          "-clone",
          "0",
          "-resize",
          "500x700!",
          "-write",
          Path.join([out, "zoom", "card-back.webp"]),
          "+delete",
          ")"
        ],
        ["-resize", "#{@small}x420!", "-quality", "84", Path.join(out, "card-back.webp")]
      ]
      |> List.flatten()
    )

    Mix.shell().info("Wrote #{count + 1} cards (and their zoom) to #{out}.")
  end

  # Crop each cell of `map` from a 10 × 7 sheet: a small and a zoom WebP.
  defp crop(sheet, map, out) do
    {w, h} = size(sheet)
    cw = div(w, @cols)
    ch = div(h, @rows)

    crops =
      Enum.flat_map(Enum.sort(map), fn {i, slug} ->
        x = round(rem(i, @cols) * w / @cols)
        y = round(div(i, @cols) * h / @rows)

        List.flatten([
          ["(", "-clone", "0", "-crop", "#{cw}x#{ch}+#{x}+#{y}", "+repage"],
          ["-write", Path.join([out, "zoom", slug <> ".webp"])],
          ["-resize", "#{@small}x", "-write", Path.join(out, slug <> ".webp"), "+delete", ")"]
        ])
      end)

    magick!([sheet, "-quality", "84" | crops] ++ ["null:"])
    map_size(map)
  end

  defp fetch(path, url) do
    if File.exists?(path) do
      path
    else
      Mix.shell().info("Downloading #{url} …")
      {:ok, _} = Application.ensure_all_started(:req)
      File.mkdir_p!(Path.dirname(path))

      case Req.get(url, into: File.stream!(path), receive_timeout: 120_000, retry: false) do
        {:ok, %{status: 200}} ->
          path

        other ->
          File.rm(path)
          Mix.raise("Could not download #{url}: #{inspect(other)}. Use --sheet/--back.")
      end
    end
  end

  defp size(path) do
    {out, 0} = System.cmd("magick", ["identify", "-format", "%w %h", path])
    [w, h] = out |> String.split() |> Enum.map(&String.to_integer/1)
    {w, h}
  end

  defp magick!(args) do
    case System.cmd("magick", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, code} -> Mix.raise("magick failed (#{code}): #{out}")
    end
  end
end
