defmodule Codex.AI.Eval do
  @moduledoc """
  The Codex evaluator (`docs/research/codex-bot.md` §4.2.1): a score of a game
  state for one side. Bigger is better for that side; a win is +1000, a loss
  −1000.

  The score is a linear function:

      score = Σ weight[k] × (feature[k](me) − feature[k](opponent))
              − threat_base × threat.base − threat_patrol × threat.patrol
              − lethal × (1 when threat.base ≥ my base HP)
              + ready × (my forces not exhausted)

  The weights are in `Codex.AI.Weights`. The features (`features/2`) use only
  what the bot's fair view shows (`Codex.Game.bot_view/2`): a hidden zone of
  the other side counts by its size. Changes "this turn" (Bloodlust, Charge,
  ...) do not count: they end with the turn.

  **Threat** (`threat/2`): the damage that the other side can deal on its next
  turn, after this turn ends, with the forces it has in play. Its attackers go
  through the patrol (squad leader first, the weakest attackers first); what
  the patrol does not stop hits the base. Flying, unstoppable and stealth
  attackers pass the patrol. It is a quick count, not a simulation: it does
  not see spells, new units or the damage back.
  """

  alias Codex.{Stats, Zones}

  @win 1000.0
  @kws [:flying, :unstoppable, :swift]
  @tech_buildings [:tech_1, :tech_2, :tech_3]
  @ongoing ["two-step", "harmony"]
  @codex_size 24

  @doc "The score of `game` for side `me` with `weights`."
  @spec score(map, 0 | 1, map) :: float
  def score(%{phase: :over, winner: w}, me, _weights), do: if(w == me, do: @win, else: -@win)

  def score(game, me, w) do
    g = lasting(game)
    mine = features(g, me)
    theirs = features(g, 1 - me)

    board =
      Enum.reduce(mine, 0.0, fn {k, v}, acc -> acc + Map.fetch!(w, k) * (v - theirs[k]) end)

    board - threat_cost(g, me, w) + if(w.ready == 0, do: 0.0, else: w.ready * ready(g, me))
  end

  @doc "The forces of side `s` that are not exhausted (they can still patrol)."
  @spec ready(map, 0 | 1) :: non_neg_integer
  def ready(g, s),
    do: Enum.count(Zones.in_play(g, s), &(Stats.force?(g, &1) and not g.cards[&1].exhausted))

  defp threat_cost(g, me, w) do
    if w.threat_base == 0 and w.threat_patrol == 0 and w.lethal == 0 do
      0.0
    else
      t = threat(g, me)
      lethal = if t.base >= g.sides[me].base_hp, do: 1, else: 0
      w.threat_base * t.base + w.threat_patrol * t.patrol + w.lethal * lethal
    end
  end

  @doc """
  The features of side `s` (numbers, one per weight of `Codex.AI.Weights`
  without the threat and the bot numbers):

  - `base_hp`; `low_hp`: how far the base is below 10 HP.
  - `force_atk`, `force_hp`: the ATK and the HP left of its units and heroes;
    `keywords`: flying, unstoppable and swift strike among them.
  - `heroes`, `hero_levels`: heroes in play and the sum of their levels.
  - `tech_buildings` (tech I–III, started or done), `add_ons`,
    `building_damage`.
  - `gold`, `workers`, `hand` (cards in hand), `tech_cards` (codex cards
    teched so far), `ongoing` (Two Step, Harmony).
  - `patrol_hp`: the HP left and armor of its patrollers.
  """
  @spec features(map, 0 | 1) :: %{atom => number}
  def features(g, s) do
    sd = g.sides[s]
    forces = for id <- Zones.in_play(g, s), Stats.force?(g, id), do: id
    {atk, hp, kws, heroes, levels} = Enum.reduce(forces, {0, 0, 0, 0, 0}, &force(g, &1, &2))
    built = sd.tech_buildings ++ sd.pending
    techs = Enum.count(built, &(&1 in @tech_buildings))

    %{
      base_hp: sd.base_hp,
      low_hp: max(10 - sd.base_hp, 0),
      force_atk: atk,
      force_hp: hp,
      keywords: kws,
      heroes: heroes,
      hero_levels: levels,
      tech_buildings: techs,
      add_ons: length(built) - techs,
      building_damage: sd.building_damage |> Map.values() |> Enum.sum(),
      gold: sd.gold,
      ongoing: Enum.count(sd.zones.in_play, &(g.cards[&1].card in @ongoing)),
      workers: min(count(sd.zones.workers), 10),
      hand: count(sd.zones.hand),
      tech_cards: @codex_size * length(sd.specs) - count(sd.zones.codex),
      patrol_hp: patrol_hp(g, s)
    }
  end

  defp force(g, id, {atk, hp, kws, heroes, levels}) do
    c = g.cards[id]

    {atk + max(Stats.atk(g, id), 0), hp + max(Stats.hp(g, id) - c.damage, 0),
     kws + Enum.count(@kws, &Stats.kw?(g, id, &1)), heroes + if(c.level, do: 1, else: 0),
     levels + (c.level || 0)}
  end

  defp count(n) when is_integer(n), do: n
  defp count(list), do: length(list)

  defp patrol_hp(g, s) do
    for {slot, id} <- Zones.patrollers(g, s), Stats.force?(g, id), reduce: 0 do
      acc -> acc + max(Stats.hp(g, id) - g.cards[id].damage, 0) + armor(g, id, slot)
    end
  end

  # The armor on the other side's turn: it refreshes then.
  defp armor(g, id, slot) do
    if(slot == :squad_leader, do: 1, else: 0) +
      if(g.cards[id].card == "ironbark-treant", do: 2, else: 0)
  end

  @doc """
  The threat to side `me`: `%{base: damage to the base, patrol: value of the
  patrollers that die}` when the other side attacks with all its forces on its
  next turn (see the moduledoc).
  """
  @spec threat(map, 0 | 1) :: %{base: number, patrol: number}
  def threat(g, me) do
    opp = 1 - me
    peace? = Stats.side_effect(g, me, :peace) != nil
    blockers = blockers(g, me)
    fliers? = Enum.any?(blockers, & &1.flying)
    tower? = :tower in g.sides[me].tech_buildings

    attackers =
      for id <- Zones.in_play(g, opp),
          Stats.force?(g, id),
          not (peace? and Stats.unit?(g, id)),
          not Stats.kw?(g, id, :cant_attack),
          a = Stats.atk(g, id),
          a > 0,
          do: {a, evades?(g, id, fliers?, tower?)}

    evading = for {a, true} <- attackers, do: a
    blocked = attackers |> Enum.flat_map(fn {a, e} -> if e, do: [], else: [a] end) |> Enum.sort()
    {left, patrol} = through_patrol(blocked, blockers, 0)
    %{base: Enum.sum(evading) + Enum.sum(left), patrol: patrol}
  end

  # My patrollers that stop attackers: the squad leader first, then the weakest.
  defp blockers(g, me) do
    list =
      for {slot, id} <- Zones.patrollers(g, me), Stats.force?(g, id) do
        hp = max(Stats.hp(g, id) - g.cards[id].damage, 0)

        %{
          leader: slot == :squad_leader,
          hp: hp + armor(g, id, slot),
          value: max(Stats.atk(g, id), 0) + hp,
          flying: Stats.kw?(g, id, :flying)
        }
      end

    Enum.sort_by(list, &{not &1.leader, &1.hp})
  end

  defp evades?(g, id, fliers?, tower?) do
    Stats.kw?(g, id, :unstoppable) or (Stats.kw?(g, id, :flying) and not fliers?) or
      ((Stats.kw?(g, id, :stealth) or Stats.kw?(g, id, :invisible)) and not tower?)
  end

  # Attackers (weakest first) hit the first blocker until it dies.
  defp through_patrol([], _blockers, patrol), do: {[], patrol}
  defp through_patrol(left, [], patrol), do: {left, patrol}

  defp through_patrol([a | rest], [b | bs], patrol) do
    if a >= b.hp,
      do: through_patrol(rest, bs, patrol + b.value),
      else: through_patrol(rest, [%{b | hp: b.hp - a} | bs], patrol)
  end

  @doc false
  # The state with the changes "this turn" gone.
  def lasting(g) do
    ids = Zones.in_play(g, 0) ++ Zones.in_play(g, 1)

    cards =
      Enum.reduce(ids, g.cards, fn id, cards ->
        Map.update!(cards, id, &%{&1 | tmp_atk: 0, tmp_hp: 0, tmp_armor: 0})
      end)

    %{g | cards: cards}
  end
end
