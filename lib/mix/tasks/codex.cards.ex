defmodule Mix.Tasks.Codex.Cards do
  @shortdoc "Crops the Codex card art from the TTS sheet into priv/static/images/codex"
  @moduledoc """
  Makes the card art of the Codex sandbox: one image per card of the first slice
  (the neutral starting deck, the Bashing and Finesse codex cards and heroes, the
  worker cards, the Dancer tokens, Tower and Surplus) and the card back.

      mix codex.cards [--sheet PATH] [--back PATH] [--out DIR]

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

  @doc "The sheet index of each card slug."
  @spec sheet() :: %{non_neg_integer => String.t()}
  def sheet, do: @sheet

  @switches [sheet: :string, back: :string, out: :string]

  @impl true
  def run(argv) do
    {opts, _args} = OptionParser.parse!(argv, strict: @switches)
    out = opts[:out] || "priv/static/images/codex"
    sheet = opts[:sheet] || fetch("tmp/codex/deck.png", @sheet_url)
    back = opts[:back] || fetch("tmp/codex/card_back.png", @back_url)
    File.mkdir_p!(Path.join(out, "zoom"))

    {w, h} = size(sheet)
    cw = div(w, @cols)
    ch = div(h, @rows)

    crops =
      Enum.flat_map(Enum.sort(@sheet), fn {i, slug} ->
        geometry = "#{cw}x#{ch}+#{rem(i, @cols) * cw}+#{div(i, @cols) * ch}"

        [
          ["(", "-clone", "0", "-crop", geometry, "+repage"],
          ["-write", Path.join([out, "zoom", slug <> ".webp"])],
          ["-resize", "#{@small}x", "-write", Path.join(out, slug <> ".webp"), "+delete", ")"]
        ]
        |> List.flatten()
      end)

    magick!([sheet, "-quality", "84" | crops] ++ ["null:"])

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

    Mix.shell().info("Wrote #{map_size(@sheet) + 1} cards (and their zoom) to #{out}.")
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
