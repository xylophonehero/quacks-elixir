defmodule Codex.Targets do
  @moduledoc """
  The legal targets of spells and abilities (research §10, §16, S1 p. 17).

  - A side cannot target an opposing invisible card (no detector; the Tower's
    reveal is not done yet). # REVIEW: the Tower's "reveal 1 invisible thing"
    on your own turn is not implemented, so an opposing Backstabber is never a
    target.
  - Granfalloon Flagbearer: when a spell or ability of side `s` can target an
    opposing flagbearer, it must target one (`combos/4` keeps only those
    target lists).
  - Resist: each opposing target with resist costs that much gold more
    (`resist_cost/3`).
  """

  alias Codex.{Stats, Zones}

  @doc """
  Every legal target list of `slots` for side `s` (a list of lists). A slot
  `{:optional, kind}` takes nil only when it has no candidate. `[]` when a
  mandatory slot has no candidate.
  """
  def combos(game, s, slots, source \\ nil) do
    lists =
      Enum.map(slots, fn
        {:optional, kind} ->
          case candidates(game, s, kind, source) do
            [] -> [nil]
            list -> list
          end

        kind ->
          candidates(game, s, kind, source)
      end)

    combos = for c <- product(lists), distinct?(c), do: c
    flagbearer(game, s, combos)
  end

  defp distinct?(c) do
    ids = Enum.reject(c, &is_nil/1)
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

  @doc "The extra gold for resist of the opposing targets in `targets`."
  def resist_cost(game, s, targets) do
    targets
    |> List.flatten()
    |> Enum.filter(&(is_integer(&1) and Stats.controller(game, &1) == 1 - s))
    |> Enum.map(&Stats.resist(game, &1))
    |> Enum.sum()
  end

  @doc "The candidates of one target kind for side `s`."
  def candidates(game, s, kind, source \\ nil)

  def candidates(game, s, :patroller, _src),
    do: for({_slot, id} <- Zones.patrollers(game, 1 - s), targetable?(game, s, id), do: id)

  def candidates(game, s, :opp_patroller_t01, _src) do
    for {_slot, id} <- Zones.patrollers(game, 1 - s),
        Stats.unit?(game, id),
        Stats.tech(game, id) in [0, 1],
        targetable?(game, s, id),
        do: id
  end

  def candidates(game, s, :force, _src), do: forces(game, s, &Stats.force?(game, &1))
  def candidates(game, s, :unit, src), do: forces(game, s, &(Stats.unit?(game, &1) and &1 != src))

  def candidates(game, s, :my_force_no_plus, _src) do
    for id <- Zones.in_play(game, s), Stats.force?(game, id), game.cards[id].plus == 0, do: id
  end

  def candidates(game, s, :unit_t01, _src),
    do: forces(game, s, &(Stats.unit?(game, &1) and Stats.tech(game, &1) in [0, 1]))

  def candidates(game, s, :unit_t0, _src), do: tech_units(game, s, 0)
  def candidates(game, s, :unit_t1, _src), do: tech_units(game, s, 1)
  def candidates(game, s, :unit_t2, _src), do: tech_units(game, s, 2)

  def candidates(game, s, :my_unit_unpartnered, _src) do
    partnered = partnered(game)
    for id <- Zones.in_play(game, s), Stats.unit?(game, id), id not in partnered, do: id
  end

  def candidates(game, _s, :building, _src) do
    for seat <- [0, 1],
        b <- [:base | game.sides[seat].tech_buildings],
        do: {:building, seat, b}
  end

  defp tech_units(game, s, t),
    do: forces(game, s, &(Stats.unit?(game, &1) and Stats.tech(game, &1) == t))

  # Cards in play of both sides that pass `keep`, and that `s` can target.
  defp forces(game, s, keep) do
    for seat <- [s, 1 - s],
        id <- Zones.in_play(game, seat),
        keep.(id),
        targetable?(game, s, id),
        do: id
  end

  defp targetable?(game, s, id),
    do: Stats.controller(game, id) == s or not Stats.kw?(game, id, :invisible)

  defp partnered(game) do
    for seat <- [0, 1],
        t <- game.sides[seat].zones.in_play,
        game.cards[t].card == "two-step",
        id <- Map.get(game.cards[t].extra, :partners, []),
        do: id
  end
end
