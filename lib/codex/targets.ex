defmodule Codex.Targets do
  @moduledoc """
  The legal targets of spells and abilities (research §10, §16, S1 p. 17).

  - A side cannot target an opposing invisible card (no detector; the Tower's
    reveal is not done yet). # REVIEW: the Tower's "reveal 1 invisible thing"
    on your own turn is not implemented, so an opposing invisible card is never
    a target.
  - An untargetable card is never a target.
  - Granfalloon Flagbearer: when a spell or ability of side `s` can target an
    opposing flagbearer, it must target one (`combos/4` keeps only those
    target lists).
  - Resist: each opposing target with resist costs that much gold more
    (`resist_cost/3`).

  A target value is a card id, a building `{:building, seat, name}` (`:base`,
  a tech building, an add-on), a worker `{:worker, seat}` (workers are all
  alike), a choice atom (`:boost`, `:beast`, ...), or nil (a skipped part).

  Slots: a target kind; `{:optional, kind}` (nil only when it has no
  candidate); `{:may, kind}` (nil is always allowed: "you may", "up to");
  `{:choice, atoms}`; `{:divide, kind, n}` (n points of damage divided among
  1..n targets: n values in the target list, 1 point each, repeats allowed).
  """

  alias Codex.{Stats, Zones}

  @doc """
  Every legal target list of `slots` for side `s` (a list of lists). `[]` when a
  mandatory slot has no candidate.
  """
  def combos(game, s, slots, source \\ nil) do
    lists = Enum.map(slots, &slot_values(game, s, &1, source))
    combos = for c <- product(lists), distinct?(c), do: Enum.flat_map(c, &spread/1)
    flagbearer(game, s, combos)
  end

  defp slot_values(game, s, {:optional, kind}, source) do
    case candidates(game, s, kind, source) do
      [] -> [nil]
      list -> list
    end
  end

  defp slot_values(game, s, {:may, kind}, source), do: candidates(game, s, kind, source) ++ [nil]
  defp slot_values(_game, _s, {:choice, atoms}, _source), do: atoms

  # n points of damage: n target picks, repeats allowed (1 point each).
  defp slot_values(game, s, {:divide, kind, n}, source),
    do: Enum.map(product(List.duplicate(candidates(game, s, kind, source), n)), &{:divide, &1})

  defp slot_values(game, s, kind, source), do: candidates(game, s, kind, source)

  defp spread({:divide, values}), do: values
  defp spread(value), do: [value]

  defp distinct?(c) do
    ids = Enum.reject(c, &(is_nil(&1) or match?({:divide, _}, &1) or is_atom(&1)))
    length(Enum.uniq(ids)) == length(ids)
  end

  defp product([]), do: [[]]
  defp product([first | rest]), do: for(x <- first, tail <- product(rest), do: [x | tail])

  # Flagbearer: when some target list hits an opposing flagbearer, only those count.
  defp flagbearer(game, s, combos) do
    flags = for c <- combos, Enum.any?(List.flatten(c), &opposing_flag?(game, s, &1)), do: c
    if flags == [], do: combos, else: flags
  end

  defp opposing_flag?(game, s, id) when is_integer(id),
    do: Stats.controller(game, id) == 1 - s and Stats.kw?(game, id, :flagbearer)

  defp opposing_flag?(_game, _s, _target), do: false

  @doc "The extra gold for resist of the opposing targets in `targets` (once per target)."
  def resist_cost(game, s, targets) do
    targets
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.filter(&(is_integer(&1) and Stats.controller(game, &1) == 1 - s))
    |> Enum.map(&Stats.resist(game, &1))
    |> Enum.sum()
  end

  @doc "The candidates of one target kind for side `s`."
  def candidates(game, s, kind, source \\ nil)

  def candidates(game, s, :patroller, _src),
    do: for({_slot, id} <- Zones.patrollers(game, 1 - s), targetable?(game, s, id), do: id)

  def candidates(game, s, :patrolling_unit, _src),
    do: for(id <- candidates(game, s, :patroller), Stats.unit?(game, id), do: id)

  def candidates(game, s, :opp_patroller_t01, _src) do
    for id <- candidates(game, s, :patrolling_unit), Stats.tech(game, id) in [0, 1], do: id
  end

  def candidates(game, s, :force, _src), do: cards(game, s, &Stats.force?(game, &1))
  def candidates(game, s, :unit, src), do: cards(game, s, &(Stats.unit?(game, &1) and &1 != src))
  def candidates(game, s, :other_unit, src), do: candidates(game, s, :unit, src)

  def candidates(game, s, :my_unit, _src),
    do: for(id <- Zones.in_play(game, s), Stats.unit?(game, id), do: id)

  def candidates(game, s, :my_force_no_plus, _src) do
    for id <- Zones.in_play(game, s), Stats.force?(game, id), game.cards[id].plus == 0, do: id
  end

  def candidates(game, s, :force_no_plus, _src),
    do: cards(game, s, &(Stats.force?(game, &1) and game.cards[&1].plus == 0))

  def candidates(game, s, :unit_t01, _src),
    do: cards(game, s, &(Stats.unit?(game, &1) and Stats.tech(game, &1) in [0, 1]))

  def candidates(game, s, :unit_t0, _src), do: tech_units(game, s, [0])
  def candidates(game, s, :unit_t1, _src), do: tech_units(game, s, [1])
  def candidates(game, s, :unit_t2, _src), do: tech_units(game, s, [2])
  def candidates(game, s, :unit_t12, _src), do: tech_units(game, s, [1, 2])

  def candidates(game, s, :opp_unit_t012, _src) do
    for id <- Zones.in_play(game, 1 - s),
        Stats.unit?(game, id),
        Stats.tech(game, id) in [0, 1, 2],
        targetable?(game, s, id),
        do: id
  end

  def candidates(game, s, :my_unit_unpartnered, _src) do
    partnered = partnered(game)
    for id <- Zones.in_play(game, s), Stats.unit?(game, id), id not in partnered, do: id
  end

  def candidates(game, s, :building, _src), do: buildings(game, s, [0, 1])
  def candidates(game, s, :my_building, _src), do: buildings(game, s, [s])

  def candidates(game, s, :unit_or_building, src),
    do: candidates(game, s, :unit, src) ++ candidates(game, s, :building)

  def candidates(game, s, :force_or_building, _src),
    do: candidates(game, s, :force) ++ candidates(game, s, :building)

  def candidates(game, s, :patroller_or_building, _src),
    do: candidates(game, s, :patroller) ++ candidates(game, s, :building)

  def candidates(game, s, :patrolling_unit_or_building, _src),
    do: candidates(game, s, :patrolling_unit) ++ candidates(game, s, :building)

  def candidates(game, s, :worker_or_building_card, _src) do
    workers = for seat <- [1 - s, s], game.sides[seat].zones.workers != [], do: {:worker, seat}
    workers ++ cards(game, s, &Stats.building_card?(game, &1))
  end

  def candidates(game, s, :upgrade_ongoing_building_card, _src) do
    cards(game, s, fn id ->
      Stats.upgrade?(game, id) or Stats.ongoing?(game, id) or Stats.building_card?(game, id)
    end)
  end

  def candidates(game, s, :upgrade_or_ongoing, _src),
    do: cards(game, s, &(Stats.upgrade?(game, &1) or Stats.ongoing?(game, &1)))

  def candidates(game, s, :unit_upgrade_worker, _src) do
    cards(game, s, &(Stats.unit?(game, &1) or Stats.upgrade?(game, &1))) ++
      for seat <- [1 - s, s], game.sides[seat].zones.workers != [], do: {:worker, seat}
  end

  def candidates(game, s, :my_balance_hero, _src) do
    for id <- Zones.in_play(game, s),
        Stats.hero?(game, id),
        Stats.spec(game, id) == "Balance",
        do: id
  end

  def candidates(game, s, :my_green_unit, _src) do
    for id <- Zones.in_play(game, s),
        Stats.unit?(game, id),
        Stats.color(game, id) == "Green",
        do: id
  end

  def candidates(game, s, :hand_card, src), do: game.sides[s].zones.hand -- [src]

  def candidates(game, s, :hand_unit_t012, _src) do
    for id <- game.sides[s].zones.hand,
        Stats.unit?(game, id),
        Stats.tech(game, id) in [0, 1, 2],
        do: id
  end

  def candidates(game, s, :codex_tiger, _src) do
    for id <- game.sides[s].zones.codex,
        Stats.unit?(game, id),
        Codex.Cards.fetch!(game.cards[id].card).subtype == "Tiger",
        uniq: true,
        do: id
  end

  def candidates(game, s, :other_force, src),
    do: cards(game, s, &(Stats.force?(game, &1) and &1 != src))

  def candidates(game, s, :my_unit_t01, _src) do
    for id <- Zones.in_play(game, s),
        Stats.unit?(game, id),
        Stats.tech(game, id) in [0, 1],
        do: id
  end

  def candidates(game, s, :unit_t012, src),
    do:
      cards(game, s, &(Stats.unit?(game, &1) and Stats.tech(game, &1) in [0, 1, 2] and &1 != src))

  # Sirus Quince: your Mirror Illusions that are not a copy now.
  def candidates(game, s, :my_mirror, _src),
    do: for(id <- Zones.in_play(game, s), game.cards[id].card == "mirror-illusion", do: id)

  def candidates(game, s, :my_non_demon_unit, _src) do
    for id <- Zones.in_play(game, s),
        Stats.unit?(game, id),
        not Stats.subtype?(game, id, "Demon"),
        Stats.sacrificable?(game, id),
        do: id
  end

  def candidates(game, s, :my_skeleton, _src) do
    for id <- Zones.in_play(game, s),
        Stats.unit?(game, id),
        Stats.subtype?(game, id, "Skeleton"),
        Stats.sacrificable?(game, id),
        do: id
  end

  def candidates(game, s, :codex_demonology_spell, _src) do
    game.sides[s].zones.codex
    |> Enum.filter(fn id ->
      d = Codex.Cards.fetch!(game.cards[id].card)
      d.spec == "Demonology" and String.contains?(d.type, "Spell")
    end)
    |> Enum.uniq_by(&game.cards[&1].card)
  end

  # Graveyard: the units buried in it (they wait in the trash, marked).
  def candidates(game, _s, :buried_unit, src),
    do: for(id <- game.trash, Map.get(game.cards[id].extra, :buried_in) == src, do: id)

  def candidates(_game, s, :base, _src), do: [{:building, 1 - s, :base}, {:building, s, :base}]

  # Zarramonde: a unit, hero, worker, upgrade or ongoing spell.
  def candidates(game, s, :zarramonde, src) do
    cards(game, s, fn id ->
      id != src and
        (Stats.force?(game, id) or Stats.upgrade?(game, id) or Stats.ongoing?(game, id))
    end) ++ for seat <- [1 - s, s], game.sides[seat].zones.workers != [], do: {:worker, seat}
  end

  def candidates(game, s, :my_force, _src),
    do: for(id <- Zones.in_play(game, s), Stats.force?(game, id), do: id)

  # Boot Camp: a unit or a hero that is not a Peace hero.
  def candidates(game, s, :force_not_peace_hero, _src) do
    cards(game, s, fn id ->
      Stats.unit?(game, id) or (Stats.hero?(game, id) and Stats.spec(game, id) != "Peace")
    end)
  end

  def candidates(game, s, :my_peace_hero, _src) do
    for id <- Zones.in_play(game, s),
        Stats.hero?(game, id),
        Stats.spec(game, id) == "Peace",
        do: id
  end

  # Injunction: a finished tech I or II building of either side.
  def candidates(game, _s, :tech12_building, _src) do
    for seat <- [1, 0],
        b <- [:tech_1, :tech_2],
        b in game.sides[seat].tech_buildings,
        do: {:building, seat, b}
  end

  defp tech_units(game, s, techs),
    do: cards(game, s, &(Stats.unit?(game, &1) and Stats.tech(game, &1) in techs))

  # The buildings of `seats`: the base, finished tech buildings and add-ons,
  # and building cards in play.
  defp buildings(game, s, seats) do
    for(
      seat <- seats,
      b <- [:base | game.sides[seat].tech_buildings],
      do: {:building, seat, b}
    ) ++
      for(
        seat <- seats,
        id <- game.sides[seat].zones.in_play,
        Stats.building_card?(game, id),
        targetable?(game, s, id),
        do: id
      )
  end

  # Cards in play of both sides that pass `keep`, and that `s` can target.
  defp cards(game, s, keep) do
    for seat <- [s, 1 - s],
        id <- Zones.in_play(game, seat),
        keep.(id),
        targetable?(game, s, id),
        do: id
  end

  @doc "True when side `s` may target card `id` (invisible, untargetable)."
  def targetable?(game, s, id) do
    not Stats.kw?(game, id, :untargetable) and
      (Stats.controller(game, id) == s or not Stats.kw?(game, id, :invisible) or
         Stats.detector?(game, s))
  end

  defp partnered(game) do
    for seat <- [0, 1],
        t <- game.sides[seat].zones.in_play,
        game.cards[t].card == "two-step",
        id <- Map.get(game.cards[t].extra, :partners, []),
        do: id
  end
end
