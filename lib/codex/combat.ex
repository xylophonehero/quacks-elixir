defmodule Codex.Combat do
  @moduledoc """
  Attacks (S1 p. 5, p. 17, p. 21; research §9, §10).

  ## Who can attack

  A unit or hero of the active side, in play or in its patrol zone, ready, and
  under its control since the start of the turn (haste skips that), and not
  "can't attack". Readiness: it does not exhaust, but attacks once per turn.
  Moment's Peace: opposing units cannot attack that side.

  ## What it can attack (`targets/2`)

  An opposing unit, hero or building (a base, a tech building, an add-on, a
  building card). If it can attack the opposing squad leader, it must; else if
  it can attack another patroller, it must attack a patroller (any one). A
  patroller that the attacker cannot attack, or may ignore, does not hold it
  back:

  - flying: may ignore patrollers without flying; a ground attacker without
    anti-air cannot attack a flier;
  - anti-air: may ignore patrolling fliers;
  - unstoppable: ignores patrollers; "unstoppable by tech 0 units" (Tiny
    Basilisk, Predator Tiger) ignores tech 0 patrollers; Tiny Basilisk cannot
    be attacked by tech 0 units;
  - stealth and invisible: ignore patrollers unless the defender has a Tower
    that has not detected anything this turn. An invisible card is attackable
    only while it patrols. Stalking Tiger has stealth while it attacks a unit.

  ## Damage (`attack/3`)

  The attacker exhausts (out of the patrol zone if it was there), its
  "Attacks:" abilities happen, then both deal their ATK at the same time
  (swift strike first). A building deals no damage back; a defender without
  long-range deals none to a long-range attacker. Armor (armor piercing skips
  it), deathtouch, sparkshot, overpower, Stampede, the Tower and anti-air
  fly-over damage follow research §7, §10. Then the "kills" and "deals combat
  damage" abilities.
  """

  alias Codex.{CardRules, Effects, Rules, Stats, Zones}

  @doc "The units and heroes of side `s` that can attack now."
  def attackers(game, s) do
    peace? = Stats.side_effect(game, 1 - s, :peace) != nil

    for id <- Zones.in_play(game, s),
        Stats.force?(game, id),
        not (peace? and Stats.unit?(game, id)),
        not Stats.kw?(game, id, :cant_attack),
        can_attack?(game, id),
        do: id
  end

  defp can_attack?(game, id) do
    c = game.cards[id]
    ready? = if Stats.readiness?(game, id), do: not c.attacked, else: not c.exhausted
    ready? and (not c.fatigued or Stats.haste?(game, id))
  end

  @doc "The legal targets of attacker `a`."
  def targets(game, a) do
    normal = targets(game, a, Stats.stealth?(game, a))

    if game.cards[a].card == "stalking-tiger" and not Stats.stealth?(game, a) do
      sneaky = for t <- targets(game, a, true), is_integer(t), Stats.unit?(game, t), do: t
      Enum.uniq(normal ++ sneaky)
    else
      normal
    end
  end

  defp targets(game, a, stealth?) do
    s = Stats.controller(game, a)
    opp = 1 - s
    patrollers = Zones.patrollers(game, opp)

    attackable =
      for {slot, d} <- patrollers, Stats.force?(game, d), attackable?(game, a, d), do: {slot, d}

    blockers = for {slot, d} <- attackable, not ignores?(game, a, d, stealth?), do: {slot, d}

    forced =
      cond do
        Enum.any?(blockers, &(elem(&1, 0) == :squad_leader)) ->
          [patrollers |> List.keyfind(:squad_leader, 0) |> elem(1)]

        blockers != [] ->
          Enum.map(attackable, &elem(&1, 1))

        true ->
          nil
      end

    case forced do
      nil -> all_targets(game, a, opp)
      list -> Enum.uniq(list ++ bypass(game, a, opp))
    end
  end

  defp all_targets(game, a, opp) do
    forces =
      for d <- Zones.in_play(game, opp), Stats.force?(game, d), attackable?(game, a, d), do: d

    forces ++ building_targets(game, a, opp)
  end

  defp building_targets(game, a, opp) do
    cards = for d <- Zones.in_play(game, opp), Stats.building_card?(game, d), do: d

    buildings =
      for b <- [:base | game.sides[opp].tech_buildings],
          base_attackable?(game, a, opp, b),
          do: {:building, opp, b}

    cards ++ buildings
  end

  # Lawbringer Gryphon: "Your base gains flying" (ground forces without anti-air can't attack it).
  defp base_attackable?(game, a, opp, :base) do
    not Stats.controls?(game, opp, "lawbringer-gryphon") or Stats.kw?(game, a, :flying) or
      Stats.kw?(game, a, :anti_air)
  end

  defp base_attackable?(_game, _a, _opp, _b), do: true

  # The targets that attacker `a` may attack past the patrollers: Traffic
  # Director ("unstoppable when attacking a building"), Wight ("unstoppable
  # when attacking heroes").
  defp bypass(game, a, opp) do
    buildings =
      if Stats.kw?(game, a, :vs_building_unstoppable),
        do: building_targets(game, a, opp),
        else: []

    heroes =
      if Stats.kw?(game, a, :vs_hero_unstoppable),
        do:
          for(d <- Zones.in_play(game, opp), Stats.hero?(game, d), attackable?(game, a, d), do: d),
        else: []

    buildings ++ heroes
  end

  @doc "True when `a` can attack card `d` at all (flying, invisible, tech 0 vs Tiny Basilisk)."
  def attackable?(game, a, d) do
    not (flier_out_of_reach?(game, a, d) or
           (Stats.kw?(game, d, :invisible) and Zones.slot_of(game, d) == nil) or
           (Stats.kw?(game, d, :t0_proof) and Stats.tech(game, a) == 0) or
           Stats.kw?(game, d, :unattackable))
  end

  defp flier_out_of_reach?(game, a, d) do
    Stats.kw?(game, d, :flying) and
      not (Stats.kw?(game, a, :flying) or Stats.kw?(game, a, :anti_air))
  end

  # True when attacker `a` may ignore patroller `d`.
  defp ignores?(game, a, d, stealth?) do
    defender = 1 - Stats.controller(game, a)
    detected? = tower_ready?(game, defender) or Stats.detector?(game, defender)
    sneaky? = stealth? or Stats.kw?(game, a, :invisible)

    Stats.kw?(game, a, :unstoppable) or (sneaky? and not detected?) or
      past_tech0?(game, a, d) or flies_past?(game, a, d) or unstoppable_by?(game, a, d)
  end

  # "Unstoppable by" some patrollers: Patriot Gryphon (units with 2 ATK or
  # less), Shrine of Forbidden Knowledge (your Demons: by units).
  defp unstoppable_by?(game, a, d) do
    shrine? =
      Stats.subtype?(game, a, "Demon") and
        Stats.controls?(game, Stats.controller(game, a), "shrine-of-forbidden-knowledge")

    (shrine? and Stats.unit?(game, d)) or
      case game.cards[a].card do
        "patriot-gryphon" -> Stats.unit?(game, d) and Stats.atk(game, d) <= 2
        # Cursed Ghoul: unstoppable by units with -1/-1 runes.
        "cursed-ghoul" -> Stats.unit?(game, d) and game.cards[d].minus > 0
        _ -> false
      end
  end

  # "Unstoppable by tech 0 units": it may ignore tech 0 patrollers.
  defp past_tech0?(game, a, d),
    do:
      Stats.tech(game, d) == 0 and
        (Stats.kw?(game, a, :t0_proof) or Stats.kw?(game, a, :t0_unstoppable))

  defp flies_past?(game, a, d) do
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

    sneaky? =
      Stats.stealth?(game, a) or Stats.kw?(game, a, :invisible) or
        (game.cards[a].card == "stalking-tiger" and is_integer(target) and
           Stats.unit?(game, target))

    # The Tower sees a stealth or invisible attacker only with its detection.
    {game, seen?} =
      cond do
        not sneaky? -> {game, true}
        tower_ready?(game, opp) -> {Rules.update_side(game, opp, &%{&1 | tower_used: true}), true}
        true -> {game, false}
      end

    ctx = %{
      back: 0,
      first: :both,
      seen?: seen?,
      tower?: tower?(game, opp),
      flew_over: fly_over(game, a, target),
      slot: Zones.slot_of(game, target),
      dealt: 0,
      base_hit: false,
      building_hit: false
    }

    game =
      game
      |> exhaust(a)
      |> attacks(s, a, target)
      |> Rules.deaths()

    {game, ctx} = fight(game, a, target, ctx)
    game |> after_combat(s, a, target, ctx) |> Rules.deaths() |> clear_hits()
  end

  # The combat-damage marks end with the attack.
  defp clear_hits(game) do
    Enum.reduce(game.cards, game, fn {id, c}, game ->
      if Map.has_key?(c.this_turn, :combat_hit),
        do:
          Zones.update_card(game, id, &%{&1 | this_turn: Map.delete(&1.this_turn, :combat_hit)}),
        else: game
    end)
  end

  defp exhaust(game, a) do
    game = Zones.update_card(game, a, &%{&1 | attacked: true})
    if Stats.readiness?(game, a), do: game, else: Effects.exhaust(game, a)
  end

  # "Attacks:" abilities, after the target and the exhaust, before damage.
  defp attacks(game, s, a, target) do
    c = game.cards[a]
    opp_base = {:building, 1 - s, :base}

    game =
      case c.card do
        "troq-bashar" when c.level >= 5 ->
          Effects.deal(game, opp_base, 1)

        # REVIEW: Brick Thief's "attacks:" building is the attacked building, else the opposing base.
        "brick-thief" ->
          Effects.brick(game, s, building_or_base(target, opp_base))

        # REVIEW: Trojan Duck's "attacks:" 4 damage goes to the attacked building, else the opposing base.
        "trojan-duck" ->
          Effects.deal(game, building_or_base(target, opp_base), 4)

        _ ->
          game
          |> Effects.Red.attacks(s, a, c.card)
          |> Effects.Green.attacks(s, a, c.card)
          |> Effects.Blue.attacks(s, a, c.card, target)
          |> Effects.Black.attacks(s, a, c.card, target)
      end

    game |> attached_attacks(s, a) |> obliterate(s, a)
  end

  # Final Showdown (its hero draws a card) and Spirit of the Panda ("Attacks: Gain ①").
  defp attached_attacks(game, s, a) do
    Enum.reduce(Stats.attachments(game, a), game, fn x, game ->
      case game.cards[x].card do
        "final-showdown" -> Rules.draw(game, s, 1, :main)
        "spirit-of-the-panda" -> Rules.gain_gold(game, s, 1)
        _ -> game
      end
    end)
  end

  defp building_or_base({:building, _, _} = b, _base), do: b
  defp building_or_base(_target, base), do: base

  # Obliterate X: destroy the defender's X lowest-tech units first.
  # REVIEW: ties go to the unit that came first (lowest id); the attacked unit counts too.
  defp obliterate(game, s, a) do
    case CardRules.keyword(game.cards[a].card, :obliterate) do
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
      first = first(game, a, target)
      ctx = Map.merge(ctx, %{back: back_damage(game, a, target), first: first})
      exchange(game, a, target, ctx, first)
    else
      {game, ctx}
    end
  end

  # Who deals combat damage first: swift strike against no swift strike.
  defp first(game, a, target) do
    ss_a = Stats.swift?(game, a)
    ss_d = is_integer(target) and Stats.force?(game, target) and Stats.swift?(game, target)

    cond do
      ss_a and not ss_d -> :attacker
      ss_d and not ss_a -> :defender
      true -> :both
    end
  end

  defp exchange(game, a, target, ctx, :attacker) do
    {game, ctx} = strike(game, a, target, ctx)
    {game |> Rules.deaths() |> back(a, target), ctx}
  end

  defp exchange(game, a, target, ctx, :defender) do
    game = game |> back(a, target) |> Rules.deaths()
    strike(game, a, target, ctx)
  end

  defp exchange(game, a, target, ctx, :both) do
    back = back_damage(game, a, target)
    {game, ctx} = strike(game, a, target, ctx)
    {deal_back(game, a, target, back), ctx}
  end

  defp in_play?(game, id), do: Zones.zone_name(Zones.locate(game, id)) in [:in_play, :patrol]
  defp present?(game, id) when is_integer(id), do: in_play?(game, id)
  defp present?(game, {:building, s, :base}), do: game.sides[s].base_hp > 0
  defp present?(game, {:building, s, b}), do: b in game.sides[s].tech_buildings

  defp building?(_game, {:building, _, _}), do: true
  defp building?(game, id), do: Stats.building_card?(game, id)

  # The attacker's damage (with sparkshot, overpower, Stampede, the Tower and fly-over).
  defp strike(game, a, target, ctx) do
    if in_play?(game, a) and present?(game, target) do
      bonus =
        if building?(game, target),
          do: CardRules.keyword(game.cards[a].card, :vs_buildings) || 0,
          else: 0

      atk = max(Stats.atk(game, a) + bonus + attack_mod(game, a, target), 0)
      piercing = Stats.kw?(game, a, :armor_piercing)
      excess = excess(game, target, atk, piercing)

      game =
        game
        |> Effects.deal(target, atk, piercing: piercing, combat: true, runes: runes?(game, a))
        |> deathtouch(a, target, atk)
        |> sparkshot(a, target)
        |> spill(a, target, excess)
        |> tower(a, ctx)
        |> fly_over_damage(a, ctx.flew_over)

      ctx = %{
        ctx
        | dealt: atk,
          base_hit: match?({:building, _, :base}, target) and atk > 0,
          building_hit: building?(game, target) and atk > 0
      }

      {game, ctx}
    else
      {game, ctx}
    end
  end

  # The defender's damage back, when the attacker is still there.
  defp back(game, a, target) do
    if in_play?(game, a) and present?(game, target),
      do: deal_back(game, a, target, back_damage(game, a, target)),
      else: game
  end

  defp deal_back(game, a, target, n) do
    if in_play?(game, a),
      do:
        game
        |> Effects.deal(a, n, combat: true, runes: is_integer(target) and runes?(game, target))
        |> deathtouch(target, a, n),
      else: game
  end

  # "Deals damage to units and heroes in the form of -1/-1 runes."
  defp runes?(game, id), do: Map.has_key?(game.cards, id) and Stats.kw?(game, id, :rune_damage)

  # ATK changes for this attack only: Air Hammer (+2 against a damaged
  # building), Debilitator Alpha (as squad leader: its attackers get -1 ATK).
  defp attack_mod(game, a, target) do
    hammer =
      if game.cards[a].card == "air-hammer" and building?(game, target) and
           Effects.building_damage(game, target) > 0,
         do: 2,
         else: 0

    alpha =
      if is_integer(target) and game.cards[target].card == "debilitator-alpha" and
           Zones.slot_of(game, target) == :squad_leader,
         do: -1,
         else: 0

    hammer + alpha
  end

  # A building deals none; a ground defender without anti-air deals none to a
  # flier; a defender without long-range deals none to a long-range attacker.
  defp back_damage(game, a, d) do
    cond do
      building?(game, d) ->
        0

      Stats.kw?(game, a, :long_range) and not Stats.kw?(game, d, :long_range) ->
        0

      Stats.kw?(game, a, :flying) and
          not (Stats.kw?(game, d, :flying) or Stats.kw?(game, d, :anti_air)) ->
        0

      true ->
        max(Stats.atk(game, d), 0)
    end
  end

  # Deathtouch: its combat damage (even to armor) kills a unit or hero.
  defp deathtouch(game, source, target, n) do
    if n > 0 and is_integer(source) and is_integer(target) and Map.has_key?(game.cards, source) and
         deathtouch?(game, source, target) and in_play?(game, target) and
         Stats.force?(game, target),
       do:
         Zones.update_card(game, target, fn c ->
           %{
             c
             | damage: max(c.damage, Stats.hp(game, target)),
               this_turn: Map.put(c.this_turn, :combat_hit, true)
           }
         end),
       else: game
  end

  # Deathtouch, and Wight's "deathtouch when attacking heroes".
  defp deathtouch?(game, source, target) do
    Stats.kw?(game, source, :deathtouch) or
      (game.cards[source].card == "wight" and Stats.hero?(game, target) and
         Stats.controller(game, source) == game.active)
  end

  # Damage above what the target can take (its HP left and armor).
  defp excess(game, d, atk, piercing) do
    if is_integer(d) and Stats.force?(game, d) do
      left = Stats.hp(game, d) - game.cards[d].damage
      armor = if piercing, do: 0, else: Stats.armor(game, d)
      max(atk - left - armor, 0)
    else
      0
    end
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
        [n | _] -> Effects.deal(game, n, 1, combat: true)
        [] -> game
      end
    else
      _ -> game
    end
  end

  # Stampede: excess combat damage to units and heroes hits that opponent's base
  # (before overpower). Overpower: excess combat damage to a patroller hits one
  # other thing it could attack.
  # REVIEW: overpower picks another attackable patroller first (left to right), else the opposing base.
  defp spill(game, _a, _target, 0), do: game

  defp spill(game, a, target, excess) do
    s = Stats.controller(game, a)

    cond do
      Stats.side_effect(game, s, :stampede) == true and Stats.unit?(game, a) ->
        Effects.deal(game, {:building, 1 - s, :base}, excess, combat: true)

      Stats.kw?(game, a, :overpower) ->
        overpower(game, a, target, excess)

      true ->
        game
    end
  end

  defp overpower(game, a, target, excess) do
    case Zones.locate(game, target) do
      {s, :patrol, _} ->
        other =
          Enum.find_value(Zones.patrollers(game, s), fn {_slot, d} ->
            d != target and attackable?(game, a, d) and d
          end)

        Effects.deal(game, other || {:building, s, :base}, excess, combat: true)

      _ ->
        game
    end
  end

  # The Tower: 1 damage to each attacker it can see.
  defp tower(game, a, %{tower?: true, seen?: true}), do: Effects.deal(game, a, 1, combat: true)
  defp tower(game, _a, _ctx), do: game

  defp fly_over_damage(game, a, anti_air) do
    Enum.reduce(anti_air, game, fn d, game ->
      if in_play?(game, d),
        do: Effects.deal(game, a, max(Stats.atk(game, d), 0), combat: true),
        else: game
    end)
  end

  # After the combat damage: the "kills" and "deals combat damage" abilities.
  defp after_combat(game, s, a, target, ctx) do
    game = Rules.deaths(game)
    killed? = is_integer(target) and not in_play?(game, target)

    ctx = Map.put(ctx, :killed?, killed?)

    game
    |> Effects.Red.after_combat(s, a, target, ctx)
    |> Effects.Green.after_combat(s, a, target, ctx)
    |> Effects.Blue.after_combat(s, a, target, ctx)
    |> Effects.Black.after_combat(s, a, target, ctx)
  end
end
