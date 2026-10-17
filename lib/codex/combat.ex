defmodule Codex.Combat do
  @moduledoc """
  Attacks (S1 p. 5, p. 17, p. 21; research §9, §10).

  ## Who can attack

  A unit or hero of the active side, in play or in its patrol zone, ready, and
  under its control since the start of the turn (haste skips that). Readiness
  (Troq Bashar at max level): it does not exhaust, but attacks once per turn.

  ## What it can attack (`targets/2`)

  An opposing unit, hero or building. If it can attack the opposing squad
  leader, it must; else if it can attack another patroller, it must attack a
  patroller (any one). A patroller that the attacker cannot attack, or may
  ignore, does not hold it back:

  - flying: may ignore patrollers without flying; a ground attacker without
    anti-air cannot attack a flier;
  - anti-air: may ignore patrolling fliers;
  - unstoppable: ignores patrollers;
  - stealth (this turn) and invisible: ignore patrollers unless the defender
    has a Tower that has not detected anything this turn. An invisible card is
    attackable only while it patrols.

  ## Damage (`attack/3`)

  The attacker exhausts (out of the patrol zone if it was there), its
  "Attacks:" abilities happen, then both deal their ATK at the same time
  (swift strike first). A building deals no damage back. Armor, sparkshot,
  overpower, the Tower and anti-air fly-over damage follow research §7, §10.
  """

  alias Codex.{Effects, Stats, Zones}

  @doc "The units and heroes of side `s` that can attack now."
  def attackers(game, s) do
    for id <- Zones.in_play(game, s), Stats.force?(game, id), can_attack?(game, id), do: id
  end

  defp can_attack?(game, id) do
    c = game.cards[id]
    ready? = if Stats.readiness?(game, id), do: not c.attacked, else: not c.exhausted
    ready? and (not c.fatigued or Stats.haste?(game, id))
  end

  @doc "The legal targets of attacker `a`."
  def targets(game, a) do
    s = Stats.controller(game, a)
    opp = 1 - s
    patrollers = Zones.patrollers(game, opp)
    attackable = for {slot, d} <- patrollers, attackable?(game, a, d), do: {slot, d}
    blockers = for {slot, d} <- attackable, not ignores?(game, a, d), do: {slot, d}

    cond do
      Enum.any?(blockers, &(elem(&1, 0) == :squad_leader)) ->
        [patrollers |> List.keyfind(:squad_leader, 0) |> elem(1)]

      blockers != [] ->
        Enum.map(attackable, &elem(&1, 1))

      true ->
        forces =
          for d <- Zones.in_play(game, opp), Stats.force?(game, d), attackable?(game, a, d), do: d

        buildings = for b <- [:base | game.sides[opp].tech_buildings], do: {:building, opp, b}
        forces ++ buildings
    end
  end

  @doc "True when `a` can attack card `d` at all (flying, invisible)."
  def attackable?(game, a, d) do
    cond do
      Stats.kw?(game, d, :flying) and
          not (Stats.kw?(game, a, :flying) or Stats.kw?(game, a, :anti_air)) ->
        false

      Stats.kw?(game, d, :invisible) and Zones.slot_of(game, d) == nil ->
        false

      true ->
        true
    end
  end

  # True when attacker `a` may ignore patroller `d`.
  defp ignores?(game, a, d) do
    detected? = tower_ready?(game, 1 - Stats.controller(game, a))
    sneaky? = Stats.stealth?(game, a) or Stats.kw?(game, a, :invisible)

    Stats.kw?(game, a, :unstoppable) or
      (sneaky? and not detected?) or
      (Stats.kw?(game, a, :flying) and not Stats.kw?(game, d, :flying)) or
      (Stats.kw?(game, a, :anti_air) and Stats.kw?(game, d, :flying))
  end

  # The defender's Tower can still detect a stealth or invisible attacker this turn.
  defp tower_ready?(game, s),
    do: :tower in game.sides[s].tech_buildings and not game.sides[s].tower_used

  defp tower?(game, s), do: :tower in game.sides[s].tech_buildings

  @doc "Attack: `a` attacks `target` (a card id or `{:building, seat, name}`)."
  def attack(game, a, target) do
    s = Stats.controller(game, a)
    opp = 1 - s
    sneaky? = Stats.stealth?(game, a) or Stats.kw?(game, a, :invisible)

    # The Tower sees a stealth or invisible attacker only with its detection.
    {game, seen?} =
      cond do
        not sneaky? ->
          {game, true}

        tower_ready?(game, opp) ->
          {Codex.Rules.update_side(game, opp, &%{&1 | tower_used: true}), true}

        true ->
          {game, false}
      end

    flew_over = fly_over(game, a, target)

    game
    |> exhaust(a)
    |> attacks(s, a, target)
    |> Codex.Rules.deaths()
    |> fight(a, target, %{seen?: seen?, tower?: tower?(game, opp), flew_over: flew_over})
  end

  defp exhaust(game, a) do
    game =
      if Stats.readiness?(game, a),
        do: Zones.update_card(game, a, &%{&1 | attacked: true}),
        else: Zones.update_card(game, a, &%{&1 | exhausted: true, attacked: true})

    # An exhausted card cannot patrol (S1 p. 5).
    if game.cards[a].exhausted, do: Effects.sideline(game, a), else: game
  end

  # "Attacks:" abilities, after the target and the exhaust, before damage.
  defp attacks(game, s, a, target) do
    c = game.cards[a]
    opp_base = {:building, 1 - s, :base}

    game =
      cond do
        c.card == "troq-bashar" and c.level >= 5 -> Effects.deal(game, opp_base, 1)
        # REVIEW: Brick Thief's "attacks:" building is the attacked building, else the opposing base.
        c.card == "brick-thief" -> Effects.brick(game, s, building_or_base(target, opp_base))
        # REVIEW: Trojan Duck's "attacks:" 4 damage goes to the attacked building, else the opposing base.
        c.card == "trojan-duck" -> Effects.deal(game, building_or_base(target, opp_base), 4)
        true -> game
      end

    obliterate(game, s, a, target)
  end

  defp building_or_base({:building, _, _} = b, _base), do: b
  defp building_or_base(_target, base), do: base

  # Obliterate X: destroy the defender's X lowest-tech units first.
  # REVIEW: ties go to the unit that came first (lowest id); the attacked unit counts too.
  defp obliterate(game, s, a, _target) do
    case Codex.CardRules.keyword(game.cards[a].card, :obliterate) do
      n when is_integer(n) ->
        game
        |> Zones.in_play(1 - s)
        |> Enum.filter(&Stats.unit?(game, &1))
        |> Enum.sort_by(&{Stats.tech(game, &1), &1})
        |> Enum.take(n)
        |> Enum.reduce(game, &Effects.die(&2, &1))

      _ ->
        game
    end
  end

  # The anti-air patrollers that a flier flew over: it attacked past the patrol line.
  # REVIEW: "fly over" counts only when the target is not a patroller.
  defp fly_over(game, a, target) do
    s = Stats.controller(game, a)
    patrollers = Zones.patrollers(game, 1 - s)

    if Stats.kw?(game, a, :flying) and not Enum.any?(patrollers, &(elem(&1, 1) == target)),
      do: for({_slot, d} <- patrollers, Stats.kw?(game, d, :anti_air), do: d),
      else: []
  end

  # Combat damage. When the attacker or the target is gone (an "Attacks:" ability
  # killed it), there is no combat. # REVIEW: no new target is picked then.
  defp fight(game, a, target, ctx) do
    if in_play?(game, a) and present?(game, target) do
      ss_a = Stats.swift?(game, a)
      ss_d = is_integer(target) and Stats.swift?(game, target)

      cond do
        ss_a and not ss_d ->
          game
          |> strike(a, target, ctx)
          |> Codex.Rules.deaths()
          |> maybe(&back(&1, a, target, ctx))

        ss_d and not ss_a ->
          game
          |> back(a, target, ctx)
          |> Codex.Rules.deaths()
          |> maybe(&strike(&1, a, target, ctx))

        true ->
          atk_d = back_damage(game, a, target)
          game |> strike(a, target, ctx) |> deal_back(a, atk_d)
      end
    else
      game
    end
    |> Codex.Rules.deaths()
  end

  defp maybe(game, fun), do: fun.(game)

  defp in_play?(game, id), do: Zones.zone_name(Zones.locate(game, id)) in [:in_play, :patrol]
  defp present?(game, id) when is_integer(id), do: in_play?(game, id)
  defp present?(game, {:building, s, :base}), do: game.sides[s].base_hp > 0
  defp present?(game, {:building, s, b}), do: b in game.sides[s].tech_buildings

  # The attacker's damage (with sparkshot, overpower, the Tower and fly-over).
  defp strike(game, a, target, ctx) do
    if in_play?(game, a) and present?(game, target) do
      atk = max(Stats.atk(game, a), 0)
      excess = excess(game, target, atk)

      game
      |> Effects.deal(target, atk)
      |> sparkshot(a, target)
      |> overpower(a, target, excess)
      |> tower(a, ctx)
      |> fly_over_damage(a, ctx.flew_over)
    else
      game
    end
  end

  # The defender's damage back, when the attacker is still there.
  defp back(game, a, target, _ctx) do
    if in_play?(game, a) and present?(game, target),
      do: deal_back(game, a, back_damage(game, a, target)),
      else: game
  end

  defp deal_back(game, a, n), do: if(in_play?(game, a), do: Effects.deal(game, a, n), else: game)

  # A building deals none; a ground defender without anti-air deals none to a flier.
  defp back_damage(_game, _a, {:building, _, _}), do: 0

  defp back_damage(game, a, d) do
    if Stats.kw?(game, a, :flying) and
         not (Stats.kw?(game, d, :flying) or Stats.kw?(game, d, :anti_air)),
       do: 0,
       else: max(Stats.atk(game, d), 0)
  end

  # Damage above what the target can take (its HP left and armor).
  defp excess(_game, {:building, _, _}, _atk), do: 0

  defp excess(game, d, atk) do
    left = Stats.hp(game, d) - game.cards[d].damage
    armor = if armor_up?(game, d), do: 1, else: 0
    max(atk - left - armor, 0)
  end

  defp armor_up?(game, d) do
    match?({s, :patrol, :squad_leader} when s != game.active, Zones.locate(game, d)) and
      not game.cards[d].armor_used
  end

  # Sparkshot: 1 damage to a patroller next to the attacked patroller.
  # REVIEW: the left neighbour first, else the right one (the player may pick).
  defp sparkshot(game, a, target) do
    with true <- Stats.kw?(game, a, :sparkshot),
         {s, :patrol, slot} <- Zones.locate(game, target) do
      slots = Zones.patrol_slots()
      i = Enum.find_index(slots, &(&1 == slot))

      near =
        for j <- [i - 1, i + 1],
            j in 0..4,
            id = game.sides[s].zones.patrol[Enum.at(slots, j)],
            do: id

      case near do
        [n | _] -> Effects.deal(game, n, 1)
        [] -> game
      end
    else
      _ -> game
    end
  end

  # Overpower: excess combat damage to a patroller hits one other thing it could attack.
  # REVIEW: another attackable patroller first (left to right), else the opposing base.
  defp overpower(game, a, target, excess) do
    with true <- excess > 0 and Stats.kw?(game, a, :overpower),
         {s, :patrol, _} <- Zones.locate(game, target) do
      other =
        Enum.find_value(Zones.patrollers(game, s), fn {_slot, d} ->
          d != target and attackable?(game, a, d) and d
        end)

      Effects.deal(game, other || {:building, s, :base}, excess)
    else
      _ -> game
    end
  end

  # The Tower: 1 damage to each attacker it can see.
  defp tower(game, a, %{tower?: true, seen?: true}), do: Effects.deal(game, a, 1)
  defp tower(game, _a, _ctx), do: game

  defp fly_over_damage(game, a, anti_air) do
    Enum.reduce(anti_air, game, fn d, game ->
      if in_play?(game, d), do: Effects.deal(game, a, max(Stats.atk(game, d), 0)), else: game
    end)
  end
end
