defmodule Codex.CardRules do
  @moduledoc """
  The rules data of the cards (research §10, §16): keywords and what each card's
  text targets. Plain data; the logic is in `Codex.Stats`, `Codex.Effects` and
  `Codex.Combat`.

  ## Keywords

  `keywords/1`: the printed keywords of a card (haste, flying, frenzy 1, ...).
  Keywords that other cards give (Nimble Fencer, Blademaster) are in
  `Codex.Stats`.

  ## Targets

  `targets/1`: the target slots of a spell or an "Arrives:" ability, a list of
  target kinds. A kind names the things a slot can take:

  - `:patroller`: an opposing patroller.
  - `:force`: a unit or hero in play (either side).
  - `:my_force_no_plus`: your unit or hero with no +1/+1 rune.
  - `:unit`: a unit in play (either side).
  - `:unit_t01`: a tech 0 or tech I unit. `:unit_t0`, `:unit_t1`, `:unit_t2`:
    a unit of that tech level (Final Smash; each may be skipped).
  - `:my_unit_unpartnered`: your unit with no dance partner (Two Step takes two).
  - `:building`: any building (a base, a tech building, an add-on).
  - `:opp_patroller_t01`: an opposing tech 0 or tech I patroller (River Montoya).
  - `:other_force`, `:my_unit_t01`, `:unit_t012`, `:my_mirror` (your Mirror
    Illusions), `:my_non_demon_unit`, `:my_skeleton`, `:codex_demonology_spell`,
    `:buried_unit` (a unit in this Graveyard): Blue and Black cards.

  Kinds in `@untargeted` are a choice, not a ◎ target: an Illusion does not
  die of them (`untargeted?/1`). A card without the ◎ icon targets nothing.
  """

  @keywords %{
    "timely-messenger" => [haste: true],
    "brick-thief" => [resist: 1],
    "helpful-turtle" => [healing: 1],
    "fruit-ninja" => [frenzy: 1],
    "granfalloon-flagbearer" => [flagbearer: true],
    "angry-dancer" => [unstoppable: true],
    "sneaky-pig" => [haste: true],
    "eggship" => [flying: true],
    "cloud-sprite" => [flying: true],
    "leaping-lizard" => [anti_air: true],
    "revolver-ocelot" => [sparkshot: true],
    "harvest-reaper" => [overpower: true],
    "trojan-duck" => [obliterate: 2],
    "backstabber" => [invisible: true],
    # Red starting deck
    "nautical-dog" => [frenzy: 1],
    "mad-man" => [haste: true],
    "bombaster" => [],
    "makeshift-rambaster" => [haste: true, cant_patrol: true, vs_buildings: 2],
    # Anarchy
    "gunpoint-taxman" => [anti_air: true],
    "disguised-monkey" => [haste: true],
    "chameleon-lizzo" => [haste: true, stealth: true],
    "marauder" => [haste: true],
    "steam-tank" => [vs_buildings: 4],
    "pirate-gunship" => [flying: true, haste: true, long_range: true, resist: 2, obliterate: 2],
    # Blood
    "shoddy-glider" => [haste: true, ephemeral: true, flying: true],
    "crashbarrow" => [haste: true, ephemeral: true, overpower: true],
    "land-octopus" => [overpower: true, cant_patrol: true],
    # Fire
    "lobber" => [haste: true],
    "doubleshot-archer" => [long_range: true],
    "molting-firebird" => [flying: true],
    "cinderblast-dragon" => [flying: true, resist: 2],
    # Tokens
    "shark" => [haste: true, ephemeral: true],
    "hunter" => [anti_air: true],
    "water-elemental" => [anti_air: true],
    # Green starting deck
    "young-treant" => [cant_attack: true],
    "verdant-tree" => [healing: 1],
    # Balance
    "gemscout-owl" => [flying: true, cant_attack: true, resist: 1],
    "tiny-basilisk" => [deathtouch: true, t0_proof: true],
    "chameleon" => [stealth: true],
    "fairie-dragon" => [flying: true],
    "dothram-horselord" => [overpower: true],
    "potent-basilisk" => [untargetable: true, deathtouch: true],
    "tyrannosaurus-rex" => [overpower: true, resist: 2],
    # Feral
    "huntress" => [sparkshot: true, anti_air: true],
    "centaur" => [overpower: true],
    "predator-tiger" => [t0_unstoppable: true],
    "barkcoat-bear" => [resist: 2, overpower: true],
    "gigadon" => [overpower: true],
    "moss-ancient" => [untargetable: true],
    # Growth
    "guargum-eternal-sentinel" => [resist: 2, obliterate: 4],
    # Blue starting deck
    "spectral-aven" => [flying: true],
    "traffic-director" => [untargetable: true, vs_building_unstoppable: true],
    # Black starting deck
    "pestering-haunt" => [unstoppable: true, cant_patrol: true, cant_sacrifice: true, max_atk: 1],
    "jandra-the-negator" => [overpower: true],
    # Tokens
    "soldier" => [sparkshot: true],
    "horror" => [deathtouch: true]
  }

  # Hero keywords by level band: `{from level, keywords}`.
  @hero_keywords %{
    "troq-bashar" => [{8, [readiness: true]}],
    "captain-zane" => [{1, [haste: true]}],
    "jaina-stormborne" => [{1, [sparkshot: true]}],
    "general-onimaru" => [{1, [frenzy: 1]}, {5, [readiness: true]}],
    "vandy-anadrose" => [{1, [sparkshot: true]}, {3, [resist: 1]}],
    "orpal-gloor" => [{1, [rune_damage: true]}]
  }

  @doc "The keywords of a hero at `level`."
  @spec hero_keywords(String.t(), pos_integer) :: keyword
  def hero_keywords(slug, level) do
    for {from, kws} <- Map.get(@hero_keywords, slug, []), level >= from, kw <- kws, do: kw
  end

  # Spells: the target slots. A slot kind in a tuple `{:optional, kind}` may be
  # skipped (nil).
  @spell_targets %{
    "spark" => [:patroller],
    "bloom" => [:my_force_no_plus],
    "wither" => [:force],
    "wrecking-ball" => [:building],
    "the-boot" => [:unit_t01],
    "intimidate" => [:force],
    "final-smash" => [{:optional, :unit_t0}, {:optional, :unit_t1}, {:optional, :unit_t2}],
    "harmony" => [],
    "discord" => [],
    "two-step" => [:my_unit_unpartnered, :my_unit_unpartnered],
    "appel-stomp" => [:patroller],
    # Red starting deck
    "scorch" => [:patroller_or_building],
    "charge" => [:my_unit],
    # REVIEW: Pillage hits the opposing base (it says "a base"); no target pick.
    "pillage" => [],
    # Anarchy
    "chaos-mirror" => [:force, :force],
    "detonate" => [:worker_or_building_card],
    "surprise-attack" => [],
    "maximum-anarchy" => [],
    # Blood
    "desperation" => [],
    "kidnapping" => [:opp_unit_t012],
    "bloodlust" => [:force, {:may, :force}],
    "war-drums" => [],
    # Fire
    "fire-dart" => [:unit_or_building],
    "ember-sparks" => [{:divide, :patroller_or_building, 3}],
    "flame-arrow" => [:force_or_building],
    # Green starting deck
    "rampant-growth" => [:force],
    "forest-s-favor" => [:my_force_no_plus],
    # Balance
    "moment-s-peace" => [],
    "nature-reclaims" => [:upgrade_ongoing_building_card],
    "circle-of-life" => [:circle],
    "final-showdown" => [:my_balance_hero],
    # Feral
    "ferocity" => [],
    "behind-the-ferns" => [],
    "murkwood-allies" => [{:choice, [:beast, :frogs, :boost]}],
    # Growth
    "polymorph-squirrel" => [:unit],
    "dinosize" => [:force],
    "spirit-of-the-panda" => [:unit],
    "stampede" => [],
    # Blue starting deck
    "lawful-search" => [],
    "arrest" => [:patrolling_unit],
    "manufactured-truth" => [:my_unit_t01, :unit_t01],
    # Black starting deck
    "deteriorate" => [:unit],
    "summon-skeletons" => [],
    "sacrifice-the-weak" => []
  }

  # Extra gold for a `:boost` target (Boost X).
  @boost %{"marauder" => 3, "murkwood-allies" => 4}

  # Channeling: the ongoing spell is sacrificed when its side has no hero of this spec.
  @channeling %{
    "harmony" => "Finesse",
    "two-step" => "Finesse",
    "war-drums" => "Blood",
    "behind-the-ferns" => "Feral"
  }

  # Activated abilities of cards: `{name, target slots, costs}`. Costs:
  # `exhaust: true` (⤵), `gold: n`, `sacrifice: true`, `blood: n` (remove blood
  # runes), `rune: true` (remove a +1/+1 rune from it), `spell_played: true`.
  @abilities %{
    "bombaster" => [{:blast, [:patrolling_unit], [gold: 1, sacrifice: true]}],
    "careless-musketeer" => [{:shoot, [:unit_or_building], [exhaust: true]}],
    "bloodburn" => [{:burn, [:unit_or_building], [exhaust: true, blood: 2]}],
    "merfolk-prospector" => [{:prospect, [], [exhaust: true]}],
    "spore-shambler" => [
      {:spore, [:other_unit], [gold: 1, rune: true]},
      {:spore_tap, [:other_unit], [exhaust: true, rune: true]}
    ],
    "verdant-tree" => [{:instant_build, [], [exhaust: true]}],
    "lobber" => [{:lob, [:building], [exhaust: true]}],
    "firebat" => [{:firebat, [:patroller_or_building], [gold: 1, exhaust: true]}],
    "calypso-vystari" => [{:sideline, [:patroller], [exhaust: true, spell_played: true]}],
    "sanatorium" => [
      {:sanatorium, [{:may, :hand_unit_t012}, {:may, :hand_unit_t012}], [gold: 1, exhaust: true]}
    ],
    "rickety-mine" => [{:mine, [], [exhaust: true]}],
    "firehouse" => [{:firehouse, [:force_or_building], [exhaust: true]}],
    "blooming-ancient" => [{:rune_move, [:other_unit], [rune: true]}],
    "blooming-elm" => [{:elm, [:force], [exhaust: true]}],
    # Blue and Black starting decks
    "porkhand-magistrate" => [{:magistrate, [:other_force], [gold: 1, exhaust: true]}],
    "skeleton-javelineer" => [{:javelin, [], [javelin: 1]}],
    # Graveyard: the gold is the cost of the buried unit (`Codex.Rules`).
    "graveyard" => [{:exhume, [:buried_unit], [exhaust: true, unit_cost: true]}]
  }

  # Hero abilities by level: `{from level, name, target slots, costs}`.
  @hero_abilities %{
    "river-montoya" => [{3, :sideline, [:opp_patroller_t01], [exhaust: true]}],
    "jaina-stormborne" => [
      {4, :jaina_1, [:patrolling_unit_or_building], [exhaust: true]},
      {7, :jaina_3, [:unit_or_building], [exhaust: true]}
    ],
    "argagarg-garg" => [{3, :argagarg, [:unit], [exhaust: true]}],
    "calamandra-moss" => [
      {1, :hide, [:hand_card, :hand_card], []},
      {5, :tiger, [:codex_tiger], [gold: 4, exhaust: true]}
    ],
    # Stash: keep a hand card in the draw/discard step (`Codex.Rules`).
    "bigby-hayes" => [
      {1, :stash, [:hand_card], [stash: true]},
      {3, :sideline, [:opp_patroller_t01], [exhaust: true]},
      {5, :bigby_draw, [], [exhaust: true]}
    ],
    "sirus-quince" => [
      {1, :mirror, [], [gold: 2, mirrors: 2]},
      {3, :mirror_copy, [:my_mirror, :unit_t012], [gold: 2]}
    ],
    "vandy-anadrose" => [
      {3, :fetch, [:hand_card, :codex_demonology_spell], [gold: 1, exhaust: true]}
    ],
    "orpal-gloor" => [{4, :plague, [:my_non_demon_unit, :unit], [once: true]}],
    "garth-torken" => [
      {1, :skeleton, [], [gold: 1, once: true]},
      {4, :bone_draw, [:my_skeleton], []}
    ]
  }

  # Cards played as "manual": paid for and put into play; their text is not run.
  # A player resolves it in free mode. (A unit's printed keywords still work.)
  # REVIEW: Burning Volley (5 damage divided among any number of targets) and
  # Feral Strike (two modes, units from the codex or the hand) are manual.
  @manual ~w(burning-volley feral-strike)
  # "Arrives:" abilities with a target. The slot may be empty only when there is
  # no legal target ("do as much as you can", S1 p. 17).
  @arrive_targets %{
    "hired-stomper" => [:unit],
    "brick-thief" => [:building],
    "trojan-duck" => [:building],
    "marauder" => [{:choice, [:plain, :boost]}],
    "bamstamper-lizzo" => [:unit],
    "fairie-dragon" => [{:may, :unit_t12}],
    "potent-basilisk" => [{:may, :upgrade_or_ongoing}],
    "tyrannosaurus-rex" => [{:may, :unit_upgrade_worker}, {:may, :unit_upgrade_worker}],
    "artisan-mantis" => [:my_building],
    # Blue starting deck
    "reputable-newsman" => [
      {:choice, [:cost_0, :cost_1, :cost_2, :cost_3, :cost_4, :cost_5, :cost_6]}
    ]
  }

  # Target kinds that are a choice, not a ◎ target (no Illusion dies of them).
  @untargeted ~w(my_green_unit my_non_demon_unit my_skeleton my_mirror hand_card
                 hand_unit_t012 codex_tiger codex_demonology_spell buried_unit)a

  @doc "True for a target kind that is a choice, not a ◎ target (an Illusion does not die)."
  @spec untargeted?(term) :: boolean
  def untargeted?({_mode, kind}), do: kind in @untargeted
  def untargeted?(kind), do: kind in @untargeted

  @doc "The printed keywords of a card (a keyword list)."
  @spec keywords(String.t()) :: keyword
  def keywords(slug), do: Map.get(@keywords, slug, [])

  @doc "The value of keyword `key` of a card, or nil."
  @spec keyword(String.t(), atom) :: term
  def keyword(slug, key), do: Keyword.get(keywords(slug), key)

  @doc "The target slots of a spell (`[]`: no target), or nil for a card that is not a spell here."
  @spec spell_targets(String.t()) :: [term] | nil
  def spell_targets(slug), do: Map.get(@spell_targets, slug)

  @doc "The target slots of a unit's \"Arrives:\" ability (`[]`: none)."
  @spec arrive_targets(String.t()) :: [term]
  def arrive_targets(slug), do: Map.get(@arrive_targets, slug, [])

  @doc "The extra gold for boosting a card (0: no boost)."
  @spec boost(String.t()) :: non_neg_integer
  def boost(slug), do: Map.get(@boost, slug, 0)

  @doc "The spec whose hero a channeling spell needs, or nil."
  @spec channeling(String.t()) :: String.t() | nil
  def channeling(slug), do: Map.get(@channeling, slug)

  @doc "The activated abilities of a card: `{name, slots, costs}`."
  @spec abilities(String.t()) :: [{atom, list, keyword}]
  def abilities(slug), do: Map.get(@abilities, slug, [])

  @doc "The activated abilities of a hero at `level`."
  @spec hero_abilities(String.t(), pos_integer) :: [{atom, list, keyword}]
  def hero_abilities(slug, level) do
    for {from, name, slots, costs} <- Map.get(@hero_abilities, slug, []),
        level >= from,
        do: {name, slots, costs}
  end

  @doc "The level from which a hero has each ability: `[{name, level}]`."
  @spec hero_ability_levels(String.t()) :: [{atom, pos_integer}]
  def hero_ability_levels(slug),
    do: for({from, name, _slots, _costs} <- Map.get(@hero_abilities, slug, []), do: {name, from})

  @doc "True for a card played as \"manual\" (its text is not run)."
  @spec manual?(String.t()) :: boolean
  def manual?(slug), do: slug in @manual

  @doc "The manual cards."
  @spec manual() :: [String.t()]
  def manual, do: @manual

  @doc "A token: a unit that is never in a deck (Dancer, Angry Dancer, Mercenary)."
  @spec token?(String.t()) :: boolean
  def token?(slug), do: slug in ~w(dancer angry-dancer mercenary)

  @doc "The printed keyword `key` of a card or a hero at `level` (nil: none)."
  @spec keyword(String.t(), atom, pos_integer | nil) :: term
  def keyword(slug, key, nil), do: keyword(slug, key)

  def keyword(slug, key, level),
    do: Keyword.get(keywords(slug) ++ hero_keywords(slug, level), key)
end
