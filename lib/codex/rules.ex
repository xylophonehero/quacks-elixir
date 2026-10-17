defmodule Codex.Rules do
  @moduledoc """
  The rules of Codex (1-hero mode) on a `Codex.Game`: the turn, the actions of
  the active side and the state checks. Source: `docs/research/codex.md`
  (rulebook v46, "S1", and the official rulings). A `# REVIEW:` comment marks a
  reading of an unclear rule.

  ## The turn (S1 p. 6)

  1. Ready: the active side's cards in play are readied; their arrival fatigue
     ends. (P1 has nothing to ready on its first turn.) Every squad leader's
     armor and the Towers' detection refresh.
  2. Upkeep: 1 gold per worker, at most 20 gold (S1 p. 3); then the "Upkeep:"
     abilities (`Codex.Effects.upkeep/2`).
  3. Main phase: the actions below, in any order.
  4. `:end_turn` ends the main phase: the patrol zone is locked in, buildings
     started this turn finish, the changes "this turn" end, the hand is
     discarded and the side draws that many cards + 2, at most 5 (S1 p. 2).
  5. Tech (`phase: :tech`): `{:tech, card_ids}` puts codex cards into the
     discard pile (2 until the side has 10 workers; then 0, 1 or 2).
  6. Then the other side's turn starts.

  A disabled card (Arrest, Porkhand Magistrate, ...) stays exhausted in its
  controller's next ready step. Stash (Bigby Hayes) keeps one hand card in
  the discard step; the side draws one card less. Shrine of Forbidden
  Knowledge: card draw +1, hand size +1. An Illusion dies when a spell or
  ability ◎ targets it (`Codex.Stats.illusion?/2`), before the effect.

  # REVIEW: patrollers stay in the patrol zone from turn to turn; the owner
  # rearranges them in its main phase (S1 p. 5 does not say that the zone
  # clears).

  ## Actions (main phase)

  - `{:hire, card_id}`: hire a worker: pay 1 gold and put a card from the hand
    face down in the workers zone. At most once per turn (S1 p. 3).
  - `{:play, card_id, targets}`: play a card from the hand: pay its cost (and
    the resist of its targets). A unit arrives in play with arrival fatigue
    (not with haste) and does its "Arrives:" ability on `targets`. A spell needs
    a hero of yours in play (an ultimate spell: one that was at max level at the
    start of the turn); it resolves on `targets`.
  - `{:patrol, card_id, slot}`: a ready unit or hero of yours goes to an empty
    patrol slot. `{:sideline, card_id}`: out of the patrol zone.
  - `{:attack, card_id, target}`: see `Codex.Combat`.
  - `{:summon, hero_id}`: summon a hero from the command zone (2 gold); it
    arrives at level 1 with arrival fatigue. At most 1 hero in play; a hero
    that died waits until after its owner's next turn.
  - `{:level_up, hero_id}`: 1 gold, 1 level (heals at the middle band and at
    the max level).
  - `{:ability, card_id, name, targets}`: an activated ability. River Montoya
    at level 3+: `:sideline`, exhaust it to sideline a tech 0 or tech I
    patroller. Harmony: `:stop_music`. A Virtuoso with Maestro: `:wreck`,
    exhaust it to deal 2 damage to a building.
  - `{:build, name}`: start a tech building (`:tech_1` 1 gold and 6 workers,
    `:tech_2` 4 gold, 8 workers and tech I, `:tech_3` 5 gold, 10 workers and
    tech II) or an add-on (`:tower` 3, `:surplus` 5; one add-on at most).
  - `:end_turn`.

  `legal/1` lists every legal action of the active side; `act/2` refuses any
  other action.
  """

  alias Codex.{CardRules, Cards, Combat, Effects, Stats, Targets, Zones}
  alias Table.Kit.Rng

  @gold_cap 20
  # Side effects that end with the turn.
  @turn_effects [
    :stampede,
    :spells,
    :drakk_used,
    :instant_build,
    :desperation,
    :stash,
    :played,
    :built,
    :death_rites
  ]
  @hand_cap 5
  @spells ["Spell", "Minor Spell", "Ongoing Spell", "Ultimate Spell"]

  # -- legal actions -----------------------------------------------------------------------

  @doc "Every legal rules action of the active side."
  @spec legal(map) :: [term]
  def legal(%{phase: :over}), do: []

  def legal(%{phase: :main, active: s} = game) do
    hires(game, s) ++
      summons(game, s) ++
      level_ups(game, s) ++
      plays(game, s) ++
      abilities(game, s) ++
      patrols(game, s) ++
      attacks(game, s) ++
      builds(game, s) ++ [:end_turn]
  end

  def legal(%{phase: :tech, active: s} = game), do: techs(game, s)

  defp hires(game, s) do
    side = game.sides[s]

    if side.hired or side.gold < hire_cost(game, s),
      do: [],
      else: for(id <- side.zones.hand, do: {:hire, id})
  end

  # Rich Earth: "You may hire workers for free."
  defp hire_cost(game, s), do: if(Stats.controls?(game, s, "rich-earth"), do: 0, else: 1)

  # Summon: a hero from the command zone for its cost (2), at level 1, with
  # arrival fatigue. 1-hero mode: at most 1 hero in play (S1 p. 11). A dead hero
  # waits until after its owner's next turn (S1 p. 3).
  defp summons(game, s) do
    side = game.sides[s]
    heroes_in_play = Enum.count(Zones.in_play(game, s), &Stats.hero?(game, &1))

    for id <- side.zones.command,
        Stats.hero?(game, id),
        heroes_in_play < hero_limit(side),
        side.turn > Map.get(side.summon_after, id, -1),
        side.gold >= (Cards.fetch!(game.cards[id].card).cost || 0),
        do: {:summon, id}
  end

  # Hero limit (S1 p. 11): 1, +1 with a finished tech II, +1 with tech III,
  # +1 with Heroes' Hall. Checked only when a hero is summoned.
  defp hero_limit(side) do
    built = side.tech_buildings
    1 + Enum.count([:tech_2, :tech_3, :heroes_hall], &(&1 in built))
  end

  # Level up: 1 gold per level, up to the max level (S1 p. 3). One action per level.
  defp level_ups(game, s) do
    if game.sides[s].gold >= 1 do
      for id <- Zones.in_play(game, s),
          Stats.hero?(game, id),
          game.cards[id].level < Cards.max_level(game.cards[id].card),
          # Nether Drain: "can't level up this turn".
          not Map.get(game.cards[id].this_turn, :no_level, false),
          do: {:level_up, id}
    else
      []
    end
  end

  # Activated abilities (S1 p. 17). An exhaust cost (⤵) needs the card ready and
  # without arrival fatigue (or with haste).
  defp abilities(game, s) do
    gold = game.sides[s].gold

    for id <- Zones.in_play(game, s),
        {name, slots, costs} <- ability_list(game, s, id),
        costs_ok?(game, s, id, costs),
        targets <- Targets.combos(game, s, slots, id),
        unit_ok?(game, s, costs, targets),
        ability_gold(game, s, costs, targets) + Targets.resist_cost(game, s, targets) <= gold,
        do: {:ability, id, name, targets}
  end

  # The abilities of card `id`: its own (`Codex.CardRules.abilities/1`), a
  # hero's by level, Harmony's, and Maestro's on your Virtuosos.
  defp ability_list(game, s, id) do
    c = game.cards[id]

    hero =
      if c.level != nil and not Stats.silenced?(game, id),
        do: CardRules.hero_abilities(c.card, c.level),
        else: []

    harmony = if c.card == "harmony", do: [{:stop_music, [], []}], else: []

    maestro =
      if Stats.unit?(game, id) and Stats.virtuoso?(game, id) and
           Stats.controls?(game, s, "maestro"),
         do: [{:wreck, [:building], [exhaust: true]}],
         else: []

    CardRules.abilities(c.card) ++ hero ++ harmony ++ maestro
  end

  defp costs_ok?(game, s, id, costs) do
    c = game.cards[id]

    Enum.all?(costs, fn
      {:exhaust, true} -> exhaust_ok?(game, id)
      {:blood, n} -> Map.get(c.extra, :blood, 0) >= n
      {:javelin, n} -> Map.get(c.extra, :javelin, 0) >= n
      {:corpse, n} -> Map.get(c.extra, :corpse, 0) >= n
      {:rune, true} -> c.plus > 0
      {:spell_played, true} -> Map.get(game.sides[s].effects, :spells, 0) > 0
      # Once per turn (Orpal Gloor, Garth Torken, Gargoyle).
      {:once, true} -> not Map.get(c.this_turn, :once, false)
      # Stash: one card per turn.
      {:stash, true} -> Stats.side_effect(game, s, :stash) == nil
      # Sirus Quince: at most n Mirror Illusions.
      {:mirrors, n} -> Enum.count(Zones.in_play(game, s), &mirror?(game, &1)) < n
      # Skeletal Lord: exhaust n of your ready Skeletons.
      {:skeletons, n} -> length(ready_skeletons(game, s)) >= n
      _ -> true
    end)
  end

  defp mirror?(game, id),
    do:
      Map.get(game.cards[id].extra, :copy, %{})[:from] == "mirror-illusion" or
        game.cards[id].card == "mirror-illusion"

  @doc false
  def ready_skeletons(game, s) do
    for id <- Zones.in_play(game, s),
        Stats.unit?(game, id),
        Stats.subtype?(game, id, "Skeleton"),
        not game.cards[id].exhausted,
        do: id
  end

  # Gold beyond the printed cost of an ability: Graveyard pays the cost of the buried unit.
  defp ability_gold(game, s, costs, targets) do
    extra =
      case {costs[:unit_cost], targets} do
        {true, [u]} when is_integer(u) -> cost(game, s, u)
        _ -> 0
      end

    Keyword.get(costs, :gold, 0) + extra
  end

  # Graveyard: the buried unit must meet its tech needs.
  defp unit_ok?(game, s, costs, [u]) when is_integer(u) do
    if costs[:unit_cost], do: tech_ok?(game, s, Cards.fetch!(game.cards[u].card)), else: true
  end

  defp unit_ok?(_game, _s, _costs, _targets), do: true

  defp exhaust_ok?(game, id) do
    c = game.cards[id]
    not c.exhausted and (not c.fatigued or Stats.haste?(game, id))
  end

  @tech_needs %{tech_1: {6, nil}, tech_2: {8, :tech_1}, tech_3: {10, :tech_2}}
  @build_gold %{tech_1: 1, tech_2: 4, tech_3: 5, tower: 3, surplus: 5, heroes_hall: 2}
  @add_ons [:tower, :surplus, :heroes_hall]

  # Build a tech building or an add-on (S1 p. 4; research §7): at most one tech
  # building and one add-on started per turn, one add-on in all. A destroyed
  # tech building is rebuilt for 0 gold. It finishes at the end of the turn.
  # REVIEW: no sacrifice of an add-on to make room for another one yet.
  defp builds(game, s) do
    side = game.sides[s]
    have = side.tech_buildings ++ side.pending

    for b <- Map.keys(@build_gold),
        b not in have,
        build_ok?(game, s, b, have),
        side.gold >= build_cost(game, s, b),
        action <- build_actions(side, b),
        do: action
  end

  # Tech II: with more than one spec, declare its spec when you build it; it is
  # locked for the game (S1 p. 12). Heroes' Hall only in 3-hero mode (S1 p. 4).
  defp build_actions(%{specs: [_, _ | _] = specs, tech_spec: nil}, :tech_2),
    do: for(spec <- specs, do: {:build, :tech_2, spec})

  defp build_actions(%{specs: [_]}, :heroes_hall), do: []
  defp build_actions(_side, b), do: [{:build, b}]

  defp build_ok?(_game, _s, b, have) when b in @add_ons,
    do: not Enum.any?(have, &(&1 in @add_ons))

  defp build_ok?(game, s, b, _have) do
    side = game.sides[s]
    {workers, needs} = @tech_needs[b]

    length(side.zones.workers) >= workers and
      (needs == nil or operational?(side, needs)) and
      not Enum.any?(side.pending, &(&1 not in @add_ons))
  end

  # A finished tech building that works now (Injunction: not on its side's
  # next turn; rulings: no next higher tech building then either).
  defp operational?(side, b) do
    b in side.tech_buildings and not match?({^b, _}, Map.get(side.effects, :injunction))
  end

  @doc "The gold to build `b` (0 to rebuild a destroyed tech building)."
  def build_cost(game, s, b) do
    base = if b in game.sides[s].destroyed, do: 0, else: @build_gold[b]
    base + inspector_tax(game, s)
  end

  # Building Inspector: the first building each opponent builds each turn costs
  # 1 more (rulings: also a rebuild and a building card), for each Inspector.
  @doc false
  def inspector_tax(game, s) do
    if Stats.side_effect(game, s, :built) == true,
      do: 0,
      else: Enum.count(Zones.in_play(game, 1 - s), &(game.cards[&1].card == "building-inspector"))
  end

  # The tech step: 2 codex cards into the discard pile, 2 copies of one card or
  # 1 each of two cards; 0, 1 or 2 once you have 10 workers (S1 p. 6).
  # REVIEW: P1 techs on its first turn too (S1 p. 9 sample turn); the cards go to
  # the discard pile at once, not "just before your next turn".
  defp techs(game, s) do
    side = game.sides[s]
    by_slug = Enum.group_by(side.zones.codex, &game.cards[&1].card)
    slugs = by_slug |> Map.keys() |> Enum.sort()

    pairs =
      for a <- slugs, b <- slugs, a <= b, ids = pair(by_slug, a, b), ids != nil, do: {:tech, ids}

    singles = for a <- slugs, do: {:tech, [hd(by_slug[a])]}

    cond do
      length(side.zones.workers) >= 10 -> [{:tech, []} | singles] ++ pairs
      pairs != [] -> pairs
      true -> if singles == [], do: [{:tech, []}], else: singles
    end
  end

  defp pair(by_slug, a, a) do
    case by_slug[a] do
      [x, y | _] -> [x, y]
      _ -> nil
    end
  end

  defp pair(by_slug, a, b), do: [hd(by_slug[a]), hd(by_slug[b])]

  defp plays(game, s) do
    gold = game.sides[s].gold

    for id <- game.sides[s].zones.hand,
        playable?(game, s, id),
        targets <- play_targets(game, s, id),
        play_cost(game, s, id, targets) <= gold,
        do: {:play, id, targets}
  end

  # Reputable Newsman: opponents can't play spells or upgrades of the chosen
  # cost. # REVIEW: the printed cost counts.
  defp playable?(game, s, id) do
    d = Cards.fetch!(game.cards[id].card)

    banned =
      for n <- Zones.in_play(game, 1 - s),
          game.cards[n].card == "reputable-newsman",
          cost = Map.get(game.cards[n].extra, :number),
          do: cost

    # Censorship Council: opponents can't play more than one card from hand during their turns.
    censored? =
      Stats.controls?(game, 1 - s, "censorship-council") and
        Map.get(game.sides[s].effects, :played, 0) >= 1

    # Twilight Baron: "You can't play tech II or III units."
    baron? =
      d.type in ["Unit", "Legendary Unit"] and (d.tech || 0) >= 2 and
        Stats.controls?(game, s, "twilight-baron")

    not censored? and not baron? and
      not ((spell?(d) or String.contains?(d.type, "Upgrade")) and (d.cost || 0) in banned)
  end

  # Cost + the resist of the targets + boost.
  defp play_cost(game, s, id, targets) do
    boost = if :boost in targets, do: CardRules.boost(game.cards[id].card), else: 0
    building = if Stats.building_card?(game, id), do: inspector_tax(game, s), else: 0

    cost(game, s, id) + Targets.resist_cost(game, s, targets) + boost + building +
      inner(game, s, id, targets)
  end

  # Jurisdiction: the cost of the codex spell it plays.
  defp inner(game, s, id, [c | _]) when is_integer(c) do
    if game.cards[id].card == "jurisdiction", do: cost(game, s, c), else: 0
  end

  defp inner(_game, _s, _id, _targets), do: 0

  # The target lists a card can be played with ([] when it cannot be played).
  defp play_targets(game, s, id) do
    d = Cards.fetch!(game.cards[id].card)

    cond do
      d.type in ["Unit", "Legendary Unit"] ->
        if tech_ok?(game, s, d), do: arrive_combos(game, s, d.slug), else: []

      spell?(d) ->
        spell_combos(game, s, id, d)

      true ->
        # Buildings and upgrades.
        if tech_ok?(game, s, d), do: [[]], else: []
    end
  end

  defp spell?(d), do: String.contains?(d.type, "Spell")

  defp arrive_combos(game, s, slug) do
    case {CardRules.manual?(slug), CardRules.arrive_targets(slug)} do
      {true, _} ->
        [[]]

      {_, []} ->
        [[]]

      {_, slots} ->
        case Targets.combos(game, s, slots) do
          [] -> [[]]
          combos -> combos
        end
    end
  end

  defp spell_combos(game, s, id, d) do
    slots = if CardRules.manual?(d.slug), do: [], else: CardRules.spell_targets(d.slug)

    cond do
      slots == nil -> []
      not hero_for?(game, s, d) -> []
      d.slug == "desperation" and game.sides[s].zones.hand -- [id] != [] -> []
      slots == [:circle] -> circle_combos(game, s)
      slots == [:jurisdiction] -> jurisdiction_combos(game, s)
      slots == [] -> [[]]
      true -> Targets.combos(game, s, slots, id)
    end
  end

  # Jurisdiction: a non-ultimate spell from your codex with its targets
  # (`[codex_id | targets]`); its cost is paid too (`play_cost/4`).
  defp jurisdiction_combos(game, s) do
    for c <- Enum.uniq_by(game.sides[s].zones.codex, &game.cards[&1].card),
        d = Cards.fetch!(game.cards[c].card),
        spell?(d),
        not String.contains?(d.type, "Ultimate"),
        d.slug != "jurisdiction",
        targets <- spell_combos(game, s, c, d),
        do: [c | targets]
  end

  # Circle of Life: sacrifice a green unit, put a green unit one tech higher
  # with a printed cost of 5 or less from your codex into play.
  defp circle_combos(game, s) do
    for u <- Targets.candidates(game, s, :my_green_unit),
        t = Stats.tech(game, u) + 1,
        c <- Enum.uniq_by(game.sides[s].zones.codex, &game.cards[&1].card),
        d = Cards.fetch!(game.cards[c].card),
        d.type in ["Unit", "Legendary Unit"],
        d.color == "Green",
        d.tech == t,
        (d.cost || 0) <= 5,
        do: [u, c]
  end

  # A spell needs a hero of yours in play: a spec spell, the hero of that spec;
  # an ultimate spell, a hero that was at max level at the start of the turn (S1 p. 3).
  # Guargum: Growth spells need no Growth hero.
  defp hero_for?(game, s, d) do
    # Free Speech: a silenced side's heroes can't cast spells.
    heroes =
      for h <- Zones.in_play(game, s), Stats.hero?(game, h), not Stats.silenced?(game, h), do: h

    heroes =
      if d.spec,
        do: Enum.filter(heroes, &(Cards.fetch!(game.cards[&1].card).spec == d.spec)),
        else: heroes

    heroes =
      cond do
        # Judgment Day: "Your max level Law hero can cast this no matter when he arrived or maxed."
        d.slug == "judgment-day" ->
          Enum.filter(heroes, &(game.cards[&1].level >= Cards.max_level(game.cards[&1].card)))

        String.contains?(d.type, "Ultimate") ->
          Enum.filter(heroes, &(&1 in game.sides[s].max_at_start))

        true ->
          heroes
      end

    heroes != [] or
      (d.spec == "Growth" and Stats.controls?(game, s, "guargum-eternal-sentinel"))
  end

  # Tech 0 needs the base; tech I, II, III need that finished tech building (S1 p. 4).
  defp tech_ok?(_game, _s, %{tech: t}) when t in [nil, 0], do: true

  defp tech_ok?(game, s, %{tech: t} = d) do
    side = game.sides[s]
    built? = operational?(side, String.to_existing_atom("tech_#{t}"))
    # Tech II and III make only the cards of the tech II spec (S1 p. 12).
    spec? = t < 2 or d.spec == nil or d.spec == side.tech_spec
    (built? and spec?) or commander_free?(game, s, d)
  end

  # Pirate-Gang Commander: "You may play tech I or II Blood units for free and
  # without any tech buildings."
  defp commander_free?(game, s, d) do
    d.type == "Unit" and d.spec == "Blood" and d.tech in [1, 2] and
      Stats.controls?(game, s, "pirate-gang-commander")
  end

  @doc """
  The gold cost of card `id` for side `s`, with the card effects that change
  it: Maestro (Virtuosos cost 0), River Montoya at max level (tech 0 units cost
  1 less), Master Midori's middle band (units with no abilities cost 1 less),
  Gigadon (1 less per green unit you have), Pirate-Gang Commander (tech I/II
  Blood units free), Guargum (Growth spells free), and the colour tax: a
  coloured minor spell costs 1 more without a hero of its colour in play
  (S1 p. 12).
  """
  def cost(game, s, id) do
    d = Cards.fetch!(game.cards[id].card)
    base = d.cost || 0

    cond do
      d.subtype == "Virtuoso" and Stats.controls?(game, s, "maestro") ->
        0

      commander_free?(game, s, d) ->
        0

      d.type in @spells and d.spec == "Growth" and
          Stats.controls?(game, s, "guargum-eternal-sentinel") ->
        0

      true ->
        max(base - discounts(game, s, d) + color_tax(game, s, d), 0)
    end
  end

  defp discounts(game, s, d), do: river(game, s, d) + midori(game, s, d) + gigadon(game, s, d)

  defp river(game, s, %{type: "Unit"} = d),
    do: if((d.tech || 0) == 0 and river_max?(game, s), do: 1, else: 0)

  defp river(_game, _s, _d), do: 0

  # REVIEW: Master Midori's middle band uses the later patch text (research §14.1):
  # units with no abilities cost 1 less and get +2/+2.
  defp midori(game, s, %{type: "Unit", text: []}),
    do: if(Stats.midori_mid?(game, s), do: 1, else: 0)

  defp midori(_game, _s, _d), do: 0

  defp gigadon(game, s, %{slug: "gigadon"}),
    do:
      Enum.count(
        Zones.in_play(game, s),
        &(Stats.unit?(game, &1) and Stats.color(game, &1) == "Green")
      )

  defp gigadon(_game, _s, _d), do: 0

  defp color_tax(game, s, %{type: "Minor Spell", color: color}) when color != "Neutral" do
    heroes = for h <- Zones.in_play(game, s), Stats.hero?(game, h), do: Stats.color(game, h)
    if color in heroes, do: 0, else: 1
  end

  defp color_tax(_game, _s, _d), do: 0

  defp river_max?(game, s) do
    Enum.any?(Zones.in_play(game, s), fn h ->
      c = game.cards[h]
      c.card == "river-montoya" and c.level >= Cards.max_level(c.card)
    end)
  end

  defp patrols(game, s) do
    zones = game.sides[s].zones
    empty = for slot <- Zones.patrol_slots(), zones.patrol[slot] == nil, do: slot

    # Moment's Peace: "your units can't patrol".
    peace? = Stats.side_effect(game, s, :peace) != nil

    moves =
      for id <- Zones.in_play(game, s),
          Stats.force?(game, id),
          not game.cards[id].exhausted,
          not Stats.kw?(game, id, :cant_patrol),
          not (peace? and Stats.unit?(game, id)),
          slot <- empty,
          do: {:patrol, id, slot}

    moves ++ for({_slot, id} <- Zones.patrollers(game, s), do: {:sideline, id})
  end

  defp attacks(game, s) do
    for a <- Combat.attackers(game, s), t <- Combat.targets(game, a), do: {:attack, a, t}
  end

  # -- doing an action ----------------------------------------------------------------------

  @doc "Do a rules action, or `{:error, reason}` when it is not legal now."
  @spec act(map, term) :: {:ok, map} | {:error, term}
  def act(game, action) do
    if action in legal(game),
      do: {:ok, do_act(game, action)},
      else: {:error, reason(game, action)}
  end

  @doc """
  Do an action that the caller took from `legal(game)`, without the check
  (`act/2` checks). For a bot's look-ahead, where the check costs more than
  the action.
  """
  @spec act_legal(map, term) :: map
  def act_legal(game, action), do: do_act(game, action)

  defp do_act(game, {:hire, id}) do
    s = game.active
    pay = hire_cost(game, s)

    game
    |> Zones.move(id, {s, :workers})
    |> Zones.update_card(id, &%{&1 | face_down: true})
    |> update_side(s, &%{&1 | gold: &1.gold - pay, hired: true})
  end

  defp do_act(game, {:play, id, targets}) do
    s = game.active
    d = Cards.fetch!(game.cards[id].card)
    pay = play_cost(game, s, id, targets)

    game =
      update_side(
        game,
        s,
        &%{
          &1
          | gold: &1.gold - pay,
            effects: Map.update(&1.effects, :played, 1, fn n -> n + 1 end)
        }
      )

    {slots, targeted?} = play_slots(game, d, targets)
    {game, targets} = illusions(game, slots, targets, targeted?)

    cond do
      d.type in ["Unit", "Legendary Unit"] -> Effects.arrive_from_hand(game, s, id, targets)
      spell?(d) -> Effects.cast(game, s, id, targets)
      true -> Effects.permanent(game, s, id)
    end
  end

  defp do_act(game, {:summon, id}) do
    s = game.active
    cost = Cards.fetch!(game.cards[id].card).cost || 0

    game
    |> update_side(s, &%{&1 | gold: &1.gold - cost})
    |> Zones.move(id, {s, :in_play})
    |> Zones.update_card(id, &%{&1 | fatigued: true, level: 1})
    |> Effects.hero_arrives(s, id)
  end

  defp do_act(game, {:level_up, id}) do
    game
    |> update_side(game.active, &%{&1 | gold: &1.gold - 1})
    |> Effects.level_up(id, 1)
  end

  defp do_act(game, {:ability, id, name, targets}) do
    s = game.active
    {_name, slots, costs} = Enum.find(ability_list(game, s, id), &(elem(&1, 0) == name))
    gold = ability_gold(game, s, costs, targets) + Targets.resist_cost(game, s, targets)
    game = update_side(game, s, &%{&1 | gold: &1.gold - gold})
    game = if costs[:exhaust], do: Effects.exhaust(game, id), else: game

    game =
      if costs[:once],
        do: Zones.update_card(game, id, &%{&1 | this_turn: Map.put(&1.this_turn, :once, true)}),
        else: game

    game =
      case costs[:javelin] do
        nil ->
          game

        n ->
          Zones.update_card(
            game,
            id,
            &%{&1 | extra: Map.update(&1.extra, :javelin, 0, fn j -> j - n end)}
          )
      end

    game =
      case costs[:corpse] do
        nil ->
          game

        n ->
          Zones.update_card(
            game,
            id,
            &%{&1 | extra: Map.update(&1.extra, :corpse, 0, fn j -> j - n end)}
          )
      end

    game =
      case costs[:skeletons] do
        nil ->
          game

        n ->
          ready_skeletons(game, s) |> Enum.take(n) |> Enum.reduce(game, &Effects.exhaust(&2, &1))
      end

    {game, targets} = illusions(game, slots, targets, ability_targeted?(game, id, name))

    game =
      case costs[:blood] do
        nil ->
          game

        n ->
          Zones.update_card(
            game,
            id,
            &%{&1 | extra: Map.update(&1.extra, :blood, 0, fn b -> b - n end)}
          )
      end

    game =
      if costs[:rune], do: Zones.update_card(game, id, &%{&1 | plus: &1.plus - 1}), else: game

    game = if costs[:sacrifice], do: Effects.sacrifice(game, id), else: game
    Effects.ability(game, s, id, name, targets)
  end

  defp do_act(game, {:build, :tech_2, spec}) do
    s = game.active

    game
    |> do_act({:build, :tech_2})
    |> update_side(s, &%{&1 | tech_spec: spec})
  end

  defp do_act(game, {:build, b}) do
    s = game.active
    cost = build_cost(game, s, b)

    game =
      update_side(
        game,
        s,
        &%{
          &1
          | gold: &1.gold - cost,
            pending: &1.pending ++ [b],
            effects: Map.put(&1.effects, :built, true)
        }
      )

    # Verdant Tree: "Your tech buildings build instantly this turn."
    if Stats.side_effect(game, s, :instant_build) == true and b in [:tech_1, :tech_2, :tech_3],
      do: finish_buildings(game, s, [b]),
      else: game
  end

  defp do_act(game, {:tech, ids}) do
    s = game.active

    game =
      Enum.reduce(ids, game, fn id, game -> Zones.move(game, id, {s, :discard}, 0) end)

    start_turn(game, 1 - s)
  end

  defp do_act(game, {:patrol, id, slot}), do: Zones.move(game, id, {game.active, :patrol}, slot)
  defp do_act(game, {:sideline, id}), do: Effects.sideline(game, id)
  defp do_act(game, {:attack, a, target}), do: Combat.attack(game, a, target)
  defp do_act(game, :end_turn), do: end_turn(game)

  # Illusions die when a spell or ability ◎ targets them (Macciatus: not yours).
  # The effect then skips them (rulings: an insured Illusion never gets its rune).
  defp illusions(game, _slots, targets, false), do: {game, targets}

  defp illusions(game, slots, targets, true) do
    dying =
      for {slot, t} <- slot_pairs(slots, targets),
          is_integer(t),
          not CardRules.untargeted?(slot),
          in_play?(game, t),
          Stats.illusion?(game, t),
          not Stats.controls?(game, Stats.controller(game, t), "macciatus-the-whisperer"),
          uniq: true,
          do: t

    if dying == [] do
      {game, targets}
    else
      game = Enum.reduce(dying, game, &Effects.die(&2, &1))
      {game, Enum.map(targets, &if(&1 in dying, do: nil, else: &1))}
    end
  end

  # The target slots of a play and whether it ◎ targets (Jurisdiction: those
  # of the codex spell it plays).
  defp play_slots(game, %{slug: "jurisdiction"}, [c | _]) do
    inner = Cards.fetch!(game.cards[c].card)
    {[:codex_spell | CardRules.spell_targets(inner.slug) || []], CardRules.targets?(inner.slug)}
  end

  defp play_slots(_game, d, _targets) do
    slots =
      if spell?(d),
        do: CardRules.spell_targets(d.slug) || [],
        else: CardRules.arrive_targets(d.slug)

    {slots, CardRules.targets?(d.slug)}
  end

  # Each target with its slot (a divided slot spreads over its n values).
  defp slot_pairs(slots, targets) do
    {pairs, _} =
      Enum.reduce(slots, {[], targets}, fn
        {:divide, kind, n}, {acc, ts} ->
          {take, rest} = Enum.split(ts, n)
          {acc ++ Enum.map(take, &{kind, &1}), rest}

        slot, {acc, [t | rest]} ->
          {acc ++ [{slot, t}], rest}

        _slot, {acc, []} ->
          {acc, []}
      end)

    pairs
  end

  # A card's ability ◎ targets when the card has the ◎ icon; a hero's, when
  # the text of the band that gives the ability has it.
  defp ability_targeted?(game, id, name) do
    c = game.cards[id]

    if c.level do
      from =
        Enum.find_value(CardRules.hero_ability_levels(c.card), fn {n, l} -> n == name && l end)

      band = from && Cards.band(c.card, from)
      band != nil and Enum.any?(band.text, &String.contains?(&1, "◎"))
    else
      CardRules.targets?(c.card)
    end
  end

  # Why an action is refused: the first rule that it breaks.
  defp reason(%{phase: :over}, _action), do: :game_over

  defp reason(game, {:hire, id}) do
    side = game.sides[game.active]

    cond do
      side.hired -> :worker_hired
      side.gold < 1 -> :no_gold
      id not in side.zones.hand -> :not_in_hand
      true -> :illegal
    end
  end

  defp reason(game, {:play, id, _targets}) do
    side = game.sides[game.active]

    cond do
      id not in side.zones.hand ->
        :not_in_hand

      Enum.any?(
        plays(put_in(game.sides[game.active].gold, 99), game.active),
        &match?({:play, ^id, _}, &1)
      ) ->
        :no_gold

      true ->
        :illegal
    end
  end

  defp reason(game, {:attack, a, _target}) do
    if a in Combat.attackers(game, game.active), do: :illegal_target, else: :cannot_attack
  end

  defp reason(_game, _action), do: :illegal

  # -- the turn ------------------------------------------------------------------------------

  @doc "Start the turn of `seat`: ready, upkeep, then its main phase."
  @spec start_turn(map, 0 | 1) :: map
  def start_turn(game, seat) do
    game = %{game | active: seat, phase: :main}

    game
    # Moment's Peace lasts "until your next turn".
    |> update_side(seat, &%{&1 | effects: Map.delete(&1.effects, :peace)})
    |> update_side(seat, &%{&1 | turn: &1.turn + 1, hired: false, reshuffled: false})
    |> update_side(0, &%{&1 | tower_used: false})
    |> update_side(1, &%{&1 | tower_used: false})
    |> ready(seat)
    |> upkeep(seat)
    |> max_at_start(seat)
    |> cleanup()
  end

  defp ready(game, seat) do
    # A disabled card does not ready in this ready step (its disable ends).
    game =
      Enum.reduce(Zones.in_play(game, seat), game, fn id, game ->
        Zones.update_card(game, id, fn c ->
          if Map.get(c.extra, :disabled),
            do: %{c | fatigued: false, attacked: false, extra: Map.delete(c.extra, :disabled)},
            else: %{c | exhausted: false, fatigued: false, attacked: false}
        end)
      end)

    # Squad leader armor refreshes each turn.
    Enum.reduce(Map.keys(game.cards), game, fn id, game ->
      Zones.update_card(game, id, &%{&1 | armor_dmg: 0})
    end)
  end

  defp upkeep(game, seat) do
    workers = length(game.sides[seat].zones.workers)

    game = game |> gain_gold(seat, workers) |> Effects.upkeep(seat)

    # Surplus: "Upkeep: Draw a card."
    if :surplus in game.sides[seat].tech_buildings, do: draw(game, seat, 1, :free), else: game
  end

  # The heroes at max level now may cast ultimate spells this turn.
  defp max_at_start(game, seat) do
    maxed =
      for h <- Zones.in_play(game, seat),
          Stats.hero?(game, h),
          game.cards[h].level >= Cards.max_level(game.cards[h].card),
          do: h

    update_side(game, seat, &Map.put(&1, :max_at_start, maxed))
  end

  @doc "Add gold to a side, at most 20 (S1 p. 3)."
  @spec gain_gold(map, 0 | 1, integer) :: map
  def gain_gold(game, seat, n),
    do: update_side(game, seat, &%{&1 | gold: min(&1.gold + n, @gold_cap)})

  # End of the main phase: lock in the patrol zone, end "this turn" changes,
  # discard and draw, then the other side's turn.
  defp end_turn(game) do
    s = game.active
    # Desperation: "Discard your hand at the end of the main phase."
    game = if Stats.side_effect(game, s, :desperation), do: discard_hand(game, s), else: game
    game = game |> lock_patrol(s) |> finish_buildings(s)
    # Chameleon Lizzo and Bloodrage Ogre go back to the hand after the draw (rulings).
    returns = Effects.returns(game, s)

    game =
      game
      |> Effects.end_of_turn(s)
      |> end_of_turn()
      |> update_side(s, &%{&1 | effects: Map.drop(&1.effects, @turn_effects)})
      |> deaths()

    hand = game.sides[s].zones.hand
    # Shrine of Forbidden Knowledge: card draw +1, hand size +1.
    shrines =
      Enum.count(
        Zones.in_play(game, s),
        &(game.cards[&1].card == "shrine-of-forbidden-knowledge")
      )

    count = min(length(hand) + 2 + shrines, @hand_cap + shrines)
    # Stash (Bigby Hayes): keep one card, draw one less.
    # REVIEW: the hand ends at the size it would have had without the stash.
    {keep, count} =
      case Stats.side_effect(game, s, :stash_card) do
        id when is_integer(id) -> if id in hand, do: {id, count - 1}, else: {nil, count}
        _ -> {nil, count}
      end

    game = discard_hand(game, s, keep)
    game = update_side(game, s, &%{&1 | effects: Map.delete(&1.effects, :stash_card)})
    game = draw(game, s, count, :draw_phase)
    game = game |> Effects.return_to_hand(returns) |> deaths()

    if techs(%{game | phase: :tech}, s) == [{:tech, []}],
      do: start_turn(game, 1 - s),
      else: %{game | phase: :tech}
  end

  defp discard_hand(game, s, keep \\ nil) do
    Enum.reduce(game.sides[s].zones.hand -- [keep], game, fn id, game ->
      Zones.move(game, id, {s, :discard}, 0)
    end)
  end

  # Buildings started this turn finish at the end of the turn (S1 p. 4).
  @doc "Finish buildings under construction (all, or only those in `only`)."
  def finish_buildings(game, s, only \\ nil) do
    update_side(game, s, fn side ->
      done = if only, do: Enum.filter(side.pending, &(&1 in only)), else: side.pending

      %{
        side
        | tech_buildings: side.tech_buildings ++ done,
          pending: side.pending -- done,
          destroyed: side.destroyed -- done
      }
    end)
  end

  # Only ready cards patrol (S1 p. 5).
  defp lock_patrol(game, s) do
    Enum.reduce(Zones.patrollers(game, s), game, fn {_slot, id}, game ->
      if game.cards[id].exhausted, do: Effects.sideline(game, id), else: game
    end)
  end

  defp end_of_turn(game) do
    Enum.reduce(Map.keys(game.cards), game, fn id, game ->
      Zones.update_card(
        game,
        id,
        &%{&1 | tmp_atk: 0, tmp_hp: 0, tmp_armor: 0, stealth: false, this_turn: %{}}
      )
    end)
  end

  @doc """
  Draw `n` cards for `seat`. When the deck is empty the discard pile is shuffled
  into a new deck. In the main phase (`:main`) that happens at most once; then
  the draws stop (S1 p. 2). `:draw_phase` and `:free` have no such limit.
  """
  @spec draw(map, 0 | 1, non_neg_integer, :main | :draw_phase | :free) :: map
  def draw(game, _seat, 0, _when), do: game

  def draw(game, seat, n, phase),
    do: Enum.reduce(1..n, game, fn _, g -> draw_one(g, seat, phase) end)

  defp draw_one(game, seat, phase) do
    side = game.sides[seat]

    case side.zones do
      %{deck: [top | rest], hand: hand} ->
        game
        |> Zones.put_zone({seat, :deck}, rest)
        |> Zones.put_zone({seat, :hand}, hand ++ [top])

      %{deck: [], discard: []} ->
        game

      %{deck: [], discard: _} when phase == :main and side.reshuffled ->
        game

      %{deck: [], discard: discard} ->
        {deck, rng} = Rng.shuffle(discard, game.rng)

        %{game | rng: rng, log: [{:reshuffle, seat} | game.log]}
        |> Zones.put_zone({seat, :discard}, [])
        |> Zones.put_zone({seat, :deck}, deck)
        |> update_side(seat, &%{&1 | reshuffled: &1.reshuffled or phase == :main})
        |> draw_one(seat, phase)
    end
  end

  # -- state checks ----------------------------------------------------------------------------

  @doc "The state checks after every action: deaths (`deaths/1`), then the win."
  @spec cleanup(map) :: map
  def cleanup(%{phase: :over} = game), do: game

  def cleanup(game) do
    game = deaths(game)

    case Enum.find([0, 1], &(game.sides[&1].base_hp <= 0)) do
      nil -> game
      loser -> %{game | phase: :over, winner: 1 - loser}
    end
  end

  @doc """
  Units and heroes with damage at least their HP (or HP 0 or less) die, one at
  a time, until none is left. Then channeling spells without their hero, and a
  Two Step that lost a partner, are sacrificed.
  """
  @spec deaths(map) :: map
  def deaths(game) do
    in_play = for(s <- [0, 1], id <- Zones.in_play(game, s), do: id)
    # Only Abomination lowers HP from another card: without one, a card with no
    # damage, no -1/-1 rune and no HP cut this turn has its printed HP (1 or more).
    abomination? = Enum.any?(in_play, &(game.cards[&1].card == "abomination"))

    dead =
      Enum.find(in_play, fn id ->
        c = game.cards[id]

        (abomination? or c.damage > 0 or c.minus > 0 or c.tmp_hp < 0) and
          (Stats.force?(game, id) or Stats.building_card?(game, id)) and
          (Stats.hp(game, id) <= 0 or c.damage >= Stats.hp(game, id)) and
          not (c.damage == 0 and Stats.kw?(game, id, :indestructible))
      end)

    case dead do
      nil -> sacrifices(game)
      id -> game |> Effects.die(id) |> deaths()
    end
  end

  defp sacrifices(game) do
    gone =
      Enum.find(for(s <- [0, 1], id <- game.sides[s].zones.in_play, do: {s, id}), fn {s, id} ->
        lost?(game, s, id)
      end)

    case gone do
      nil -> bound(game)
      {_s, id} -> game |> Effects.sacrifice(id) |> deaths()
    end
  end

  # Sirus Quince's max-level copies are trashed when Quince or the original
  # leaves play.
  defp bound(game) do
    gone =
      Enum.find(for(s <- [0, 1], id <- Zones.in_play(game, s), do: id), fn id ->
        bound = get_in(game.cards[id].extra, [:copy, :bound]) || []
        Enum.any?(bound, &(not in_play?(game, &1)))
      end)

    case gone do
      nil -> mind_control(game)
      id -> game |> Effects.trash(id) |> deaths()
    end
  end

  # Mind Control left play: the unit goes back to the side that had it.
  defp mind_control(game) do
    back =
      Enum.find_value(for(s <- [0, 1], id <- Zones.in_play(game, s), do: id), fn id ->
        case Map.get(game.cards[id].extra, :mind_control) do
          {mc, from} -> if not in_play?(game, mc), do: {id, from}
          _ -> nil
        end
      end)

    case back do
      nil ->
        game

      {id, from} ->
        game
        |> Zones.move(id, {from, :in_play})
        |> Zones.update_card(id, &%{&1 | extra: Map.delete(&1.extra, :mind_control)})
        |> deaths()
    end
  end

  # Channeling (Harmony, Two Step, War Drums, Behind the Ferns): sacrificed when
  # its side has no hero of its spec in play. Two Step: also when its side lost
  # one of the partners. An attached spell (Spirit of the Panda, Final
  # Showdown): when the card it is attached to left play.
  defp lost?(game, s, id) do
    c = game.cards[id]
    spec = CardRules.channeling(c.card)
    partners = Map.get(c.extra, :partners, [])
    host = Map.get(c.extra, :attached)

    (spec != nil and not Stats.spec_hero?(game, s, spec)) or
      Enum.any?(partners, &(Zones.controller(game, &1) != s or not in_play?(game, &1))) or
      (host != nil and not in_play?(game, host))
  end

  defp in_play?(game, id), do: Zones.zone_name(Zones.locate(game, id)) in [:in_play, :patrol]

  @doc "A card that leaves play: no damage, runes, exhaustion or turn state; a hero at level 1."
  @spec reset(map) :: map
  def reset(card) do
    %{
      card
      | damage: 0,
        plus: 0,
        minus: 0,
        exhausted: false,
        fatigued: false,
        attacked: false,
        armor_dmg: 0,
        tmp_armor: 0,
        this_turn: %{},
        tmp_atk: 0,
        tmp_hp: 0,
        stealth: false,
        extra: %{},
        level: card.level && 1
    }
  end

  # -- stats -------------------------------------------------------------------------------------

  @doc "ATK/HP now of every unit and hero in play: `%{id => {atk, hp}}`."
  @spec all_stats(map) :: %{pos_integer => {integer, integer}}
  def all_stats(game) do
    for s <- [0, 1],
        id <- Zones.in_play(game, s),
        Stats.force?(game, id),
        into: %{},
        do: {id, {Stats.atk(game, id), Stats.hp(game, id)}}
  end

  # -- helpers ----------------------------------------------------------------------------------

  @doc false
  def update_side(game, seat, fun), do: update_in(game.sides[seat], fun)
end
