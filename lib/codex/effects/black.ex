defmodule Codex.Effects.Black do
  @moduledoc """
  The Black card texts (Blackhand Scourge): the starting deck, the heroes
  Vandy Anadrose, Orpal Gloor and Garth Torken, and the Demonology, Disease
  and Necromancy codex cards. Called by `Codex.Effects`, `Codex.Combat` and
  `Codex.Rules`.
  """

  alias Codex.{Cards, Effects, Rules, Stats, Zones}

  @graveyard_limit 4

  # -- spells -----------------------------------------------------------------------------------

  @doc "Resolve a Black spell."
  def spell(game, _s, "deteriorate", _id, [t]),
    do: Zones.update_card(game, t, &%{&1 | tmp_atk: &1.tmp_atk - 1, tmp_hp: &1.tmp_hp - 1})

  def spell(game, s, "summon-skeletons", _id, []), do: Effects.summon(game, s, "skeleton", 2)

  # Sacrifice the Weak: each player sacrifices their weakest unit (`Codex.Effects.weakest/3`).
  def spell(game, s, "sacrifice-the-weak", _id, []) do
    Enum.reduce([s, 1 - s], game, fn seat, game ->
      Effects.sacrifice(game, Effects.weakest(game, seat, &Stats.sacrificable?(game, &1)))
    end)
  end

  # -- Demonology --

  # Soul Stone: attach to a unit (+1/+1 and the "would die" save: `Codex.Stats`, `Codex.Effects`).
  def spell(game, _s, "soul-stone", id, [t]) when is_integer(t),
    do: Zones.update_card(game, id, &%{&1 | extra: Map.put(&1.extra, :attached, t)})

  # Dark Pact: 2 damage to a base, then that player draws 2 cards.
  def spell(game, s, "dark-pact", _id, [{:building, seat, :base} = base]) do
    game |> Effects.burn(s, "dark-pact", base, 2) |> Rules.draw(seat, 2, :free)
  end

  # Shadow Blade: 3 damage to a patroller; if it dies from it, its controller discards at random.
  def spell(game, s, "shadow-blade", _id, [t]) when is_integer(t) do
    owner = Stats.controller(game, t)
    game = game |> Effects.burn(s, "shadow-blade", t, 3) |> Rules.deaths()
    if in_play?(game, t), do: game, else: Effects.discard_random(game, owner)
  end

  # Metamorphosis: sacrifice all your units; your non-Demon heroes go to max
  # level and become Demons with two +1/+1 runes, readiness and invisibility.
  def spell(game, s, "metamorphosis", _id, []) do
    units = for id <- Zones.in_play(game, s), Stats.unit?(game, id), do: id
    game = Enum.reduce(units, game, &Effects.sacrifice(&2, &1)) |> Rules.deaths()

    heroes =
      for id <- Zones.in_play(game, s),
          Stats.hero?(game, id),
          not Stats.subtype?(game, id, "Demon"),
          do: id

    Enum.reduce(heroes, game, fn h, game ->
      c = game.cards[h]

      game
      |> Effects.level_up(h, Cards.max_level(c.card) - c.level)
      |> Effects.plus_rune(h)
      |> Effects.plus_rune(h)
      |> Zones.update_card(h, fn c ->
        %{c | extra: Map.merge(c.extra, %{demon: true, readiness: true, invisible: true})}
      end)
    end)
  end

  # -- Disease --

  # Sickness: a -1/-1 rune on up to two units and/or heroes.
  def spell(game, _s, "sickness", _id, targets),
    do: targets |> Enum.reject(&is_nil/1) |> Enum.reduce(game, &Effects.minus_rune(&2, &1))

  # Spreading Plague: destroy all tech 0-II units and heroes that have -1/-1 runes.
  def spell(game, _s, "spreading-plague", _id, []) do
    doomed =
      for seat <- [0, 1],
          id <- Zones.in_play(game, seat),
          game.cards[id].minus > 0,
          Stats.hero?(game, id) or (Stats.unit?(game, id) and Stats.tech(game, id) in [0, 1, 2]),
          do: id

    Enum.reduce(doomed, game, fn id, game ->
      if in_play?(game, id), do: Effects.destroy(game, id), else: game
    end)
  end

  # Carrion Curse: look at an opponent's hand, up to two non-unit cards are discarded.
  # REVIEW: the engine picks the two costliest non-unit cards.
  def spell(game, s, "carrion-curse", _id, []) do
    game.sides[1 - s].zones.hand
    |> Enum.reject(&Stats.unit?(game, &1))
    |> Enum.sort_by(&{-(Cards.fetch!(game.cards[&1].card).cost || 0), &1})
    |> Enum.take(2)
    |> Enum.reduce(game, fn id, game ->
      game |> Zones.move(id, {1 - s, :discard}, 0) |> Effects.log({:discards, id})
    end)
  end

  # Death and Decay: an opponent's units and heroes -3/-3 this turn; 3 damage to all its buildings.
  def spell(game, s, "death-and-decay", _id, []) do
    opp = 1 - s
    forces = for id <- Zones.in_play(game, opp), Stats.force?(game, id), do: id

    game =
      Enum.reduce(forces, game, fn id, game ->
        Zones.update_card(game, id, &%{&1 | tmp_atk: &1.tmp_atk - 3, tmp_hp: &1.tmp_hp - 3})
      end)

    cards = for id <- Zones.in_play(game, opp), Stats.building_card?(game, id), do: id
    buildings = for b <- [:base | game.sides[opp].tech_buildings], do: {:building, opp, b}
    Enum.reduce(cards ++ buildings, game, &Effects.burn(&2, s, "death-and-decay", &1, 3))
  end

  # -- Necromancy --

  # Nether Drain: one hero loses two levels and can't level up this turn; another gains two.
  def spell(game, _s, "nether-drain", _id, [down, up]) do
    game =
      Zones.update_card(game, down, fn c ->
        %{c | level: max(c.level - 2, 1), this_turn: Map.put(c.this_turn, :no_level, true)}
      end)

    if up, do: Effects.level_up(game, up, 2), else: game
  end

  # Lich's Bargain: sacrifice a worker, your base takes 4, a Skeleton, a Zombie and a Horror.
  def spell(game, s, "lich-s-bargain", _id, []) do
    game
    |> Effects.trash_worker(s)
    |> Effects.deal({:building, s, :base}, 4)
    |> Effects.summon(s, "skeleton")
    |> Effects.summon(s, "zombie")
    |> Effects.summon(s, "horror")
  end

  # Doom Grasp: sacrifice a unit; if you do, destroy a tech 0-II unit or hero.
  def spell(game, _s, "doom-grasp", _id, [sac, t]) do
    game |> Effects.sacrifice(sac) |> Rules.deaths() |> destroy_in_play(t)
  end

  # Death Rites: this turn, each of your units that dies destroys an opposing lowest tech unit (`died/2`).
  def spell(game, s, "death-rites", _id, []),
    do: Rules.update_side(game, s, &%{&1 | effects: Map.put(&1.effects, :death_rites, true)})

  def spell(game, _s, _slug, _id, _targets), do: game

  defp destroy_in_play(game, t) when is_integer(t) do
    if in_play?(game, t), do: Effects.destroy(game, t), else: game
  end

  defp destroy_in_play(game, _t), do: game

  # -- arrivals -------------------------------------------------------------------------------

  @doc "A Black unit's \"Arrives:\" ability."
  def arrive(game, _s, id, "skeleton-javelineer", []),
    do: Effects.add_counter(game, id, :javelin, 1)

  def arrive(game, s, _id, "thieving-imp", []), do: Effects.discard_random(game, 1 - s)

  # Terras Q: four 0/1 Warlocks for an opponent; Terras can't attack or patrol while they live.
  def arrive(game, s, id, "terras-q-the-shackled", []) do
    {game, before} = {game, Zones.in_play(game, 1 - s)}
    game = Effects.summon(game, 1 - s, "warlock", 4)

    Enum.reduce(Zones.in_play(game, 1 - s) -- before, game, fn w, game ->
      Zones.update_card(game, w, &%{&1 | extra: Map.put(&1.extra, :shackles, id)})
    end)
  end

  def arrive(game, _s, _id, "cursed-ghoul", [t]), do: minus_in_play(game, t)

  # Hooded Executioner, boosted: destroy each opponent's weakest unit
  # (rulings: not an indestructible one).
  def arrive(game, s, _id, "hooded-executioner", [:boost]) do
    weak = Effects.weakest(game, 1 - s, &(not Stats.kw?(game, &1, :indestructible)))
    if weak, do: Effects.destroy(game, weak), else: game
  end

  def arrive(game, s, _id, "plague-lord", []), do: plague_lord(game, s)

  # Zarramonde, played from hand: destroy a unit, hero, worker, upgrade or ongoing spell.
  def arrive(game, _s, _id, "zarramonde-the-obliterator", [t]), do: Effects.destroy(game, t)

  def arrive(game, _s, _id, _slug, _targets), do: game

  # -- abilities ------------------------------------------------------------------------------

  @doc "A Black activated ability (costs paid)."
  # Skeleton Javelineer: remove a javelin rune → long-range this turn.
  def ability(game, _s, id, :javelin, []),
    do: Zones.update_card(game, id, &%{&1 | this_turn: Map.put(&1.this_turn, :long_range, true)})

  # Graveyard: play a buried unit (its cost is paid by `Codex.Rules`); it enters play.
  # REVIEW: buried units wait in the trash, marked (no Graveyard zone); its
  # "Arrives:" ability gets no targets.
  def ability(game, s, id, :exhume, [u]) when is_integer(u) do
    game
    |> Zones.update_card(
      id,
      &%{&1 | extra: Map.update(&1.extra, :holds, [], fn h -> h -- [u] end)}
    )
    |> Zones.update_card(u, &%{&1 | extra: Map.delete(&1.extra, :buried_in)})
    |> Effects.enter(s, u, [])
  end

  # Vandy Anadrose: discard a card, fetch a Demonology spell from the codex into the hand.
  def ability(game, s, _id, :fetch, [card, spell]) do
    game
    |> Zones.move(card, {s, :discard}, 0)
    |> Zones.move(spell, {s, :hand})
  end

  # Orpal Gloor: sacrifice a non-Demon unit → a -1/-1 rune on a unit.
  def ability(game, _s, _id, :plague, [sac, t]) do
    game |> Effects.sacrifice(sac) |> Rules.deaths() |> minus_in_play(t)
  end

  def ability(game, s, _id, :skeleton, []), do: Effects.summon(game, s, "skeleton")

  def ability(game, s, _id, :bone_draw, [sk]),
    do: game |> Effects.sacrifice(sk) |> Rules.draw(s, 1, :main)

  # Blackhand Resurrector (sacrificed): a hero that died this game arrives at max
  # level (rulings: also on cooldown; its "Max level:" triggers).
  # REVIEW: the hero limit still applies (a summon).
  def ability(game, s, _id, :resurrect, [h]) do
    max = Cards.max_level(game.cards[h].card)

    game
    |> Zones.move(h, {s, :in_play})
    |> Zones.update_card(h, &%{&1 | fatigued: true, level: 1})
    |> Effects.hero_arrives(s, h)
    |> Effects.level_up(h, max - 1)
  end

  # Skeletal Lord (five Skeletons exhausted): a unit from your hand into play
  # (rulings: free, no tech building needed).
  def ability(game, s, _id, :rally, [u]), do: Effects.enter(game, s, u, [])

  def ability(game, s, id, :catapult, [t]), do: Effects.burn(game, s, game.cards[id].card, t, 6)

  # Crypt Crawler: a flier loses flying this turn.
  def ability(game, _s, _id, :ground, [t]),
    do:
      Zones.update_card(
        game,
        t,
        &%{&1 | this_turn: Map.put(&1.this_turn, {:lost, :flying}, true)}
      )

  # Plague Lab: for the cards with runes, another rune of a kind already there.
  # REVIEW: the engine adds a -1/-1 rune to each opposing card with one and a
  # +1/+1 rune to each of yours with one (named runes are not counted).
  def ability(game, s, _id, :plague_lab, []) do
    Enum.reduce(for(seat <- [0, 1], id <- Zones.in_play(game, seat), do: {seat, id}), game, fn
      {seat, id}, game ->
        c = game.cards[id]

        cond do
          seat != s and c.minus > 0 -> Effects.minus_rune(game, id)
          seat == s and c.plus > 0 -> Effects.plus_rune(game, id)
          true -> game
        end
    end)
  end

  # Gargoyle: until your next upkeep not indestructible, flying, +3 ATK, it can attack and patrol.
  def ability(game, s, id, :gargoyle, []),
    do: Zones.update_card(game, id, &%{&1 | extra: Map.put(&1.extra, :gargoyle, s)})

  def ability(game, _s, _id, _name, _targets), do: game

  defp minus_in_play(game, t) when is_integer(t) do
    if in_play?(game, t), do: Effects.minus_rune(game, t), else: game
  end

  defp minus_in_play(game, _t), do: game

  defp in_play?(game, id), do: Zones.zone_name(Zones.locate(game, id)) in [:in_play, :patrol]

  # -- triggers -------------------------------------------------------------------------------

  @doc """
  Vandy Anadrose, "Max level: Give +2/+2 to one friendly and one opposing tech
  0 or I unit. They lose +2/+2 and die at your next upkeep." Garth Torken, "Max
  level: You may put a tech I or II unit that costs 5 or less from your discard
  pile into play if you meet the tech reqs for it."
  # REVIEW: the engine picks: Vandy's opposing unit is the one with the most ATK +
  # HP, her friendly unit the one with the least; Garth's unit is the one with
  # the highest cost.
  """
  def max_level(game, s, _id, "vandy-anadrose") do
    t01 = fn seat ->
      for id <- Zones.in_play(game, seat),
          Stats.unit?(game, id),
          Stats.tech(game, id) in [0, 1],
          do: id
    end

    value = &(Stats.atk(game, &1) + Stats.hp(game, &1))
    mine = Enum.min_by(t01.(s), value, fn -> nil end)
    theirs = Enum.max_by(t01.(1 - s), value, fn -> nil end)

    Enum.reduce(Enum.reject([mine, theirs], &is_nil/1), game, fn id, game ->
      Zones.update_card(game, id, &%{&1 | extra: Map.put(&1.extra, :vandy, s)})
    end)
  end

  def max_level(game, s, _id, "garth-torken") do
    side = game.sides[s]

    unit =
      side.zones.discard
      |> Enum.filter(&garth_unit?(side, Cards.fetch!(game.cards[&1].card)))
      |> Enum.max_by(&(Cards.fetch!(game.cards[&1].card).cost || 0), fn -> nil end)

    if unit, do: Effects.enter(game, s, unit, []), else: game
  end

  def max_level(game, _s, _id, _slug), do: game

  # A tech I or II unit that costs 5 or less, with its tech building (tech II: of its spec).
  defp garth_unit?(side, d) do
    d.type in ["Unit", "Legendary Unit"] and d.tech in [1, 2] and (d.cost || 0) <= 5 and
      :"tech_#{d.tech}" in side.tech_buildings and
      (d.tech < 2 or d.spec == nil or d.spec == side.tech_spec)
  end

  @doc "A Black building or upgrade comes into play: Plague Lab (-1/-1 on each opposing unit)."
  def permanent(game, s, _id, "plague-lab") do
    units = for id <- Zones.in_play(game, 1 - s), Stats.unit?(game, id), do: id
    Enum.reduce(units, game, &Effects.minus_rune(&2, &1))
  end

  def permanent(game, _s, _id, _slug), do: game

  # Plague Lord: a -1/-1 rune on each opposing unit and hero.
  defp plague_lord(game, s) do
    forces = for id <- Zones.in_play(game, 1 - s), Stats.force?(game, id), do: id
    Enum.reduce(forces, game, &Effects.minus_rune(&2, &1))
  end

  @doc """
  Black "Attacks:" abilities: Poisonblade Rogue gets armor piercing and deals
  its damage as -1/-1 runes this turn.
  """
  def attacks(game, _s, a, "poisonblade-rogue", _target) do
    Zones.update_card(game, a, fn c ->
      %{c | this_turn: Map.merge(c.this_turn, %{armor_piercing: true, rune_damage: true})}
    end)
  end

  def attacks(game, s, a, slug, target) do
    game = voidblocker(game, s, a, target)

    case slug do
      "plague-lord" -> plague_lord(game, s)
      # Bone Collector: "Attacks: Summon a 1/1 black Skeleton token."
      "bone-collector" -> Effects.summon(game, s, "skeleton")
      _ -> game
    end
  end

  # Voidblocker: an opponent that attacks it exhausts another of its ready units or heroes.
  # REVIEW: the engine exhausts the one with the least ATK (the attacker picks).
  defp voidblocker(game, s, a, target) when is_integer(target) do
    if game.cards[target].card == "voidblocker" do
      other =
        game
        |> Zones.in_play(s)
        |> Enum.filter(&(&1 != a and Stats.force?(game, &1) and not game.cards[&1].exhausted))
        |> Enum.min_by(&{Stats.atk(game, &1), &1}, fn -> nil end)

      Effects.exhaust(game, other)
    else
      game
    end
  end

  defp voidblocker(game, _s, _a, _target), do: game

  @doc "Black abilities after a combat: Cursed Crow damages a base (a random discard)."
  def after_combat(game, _s, a, {:building, opp, :base}, %{base_hit: true}) do
    if game.cards[a].card == "cursed-crow", do: Effects.discard_random(game, opp), else: game
  end

  def after_combat(game, _s, _a, _target, _ctx), do: game

  @doc """
  Black triggers when a card dies (`ctx` from `Codex.Effects.die/2`): Jandra
  dies from combat damage (destroy all your units except Demons), a Graveyard
  buries your non-token units, Orpal Gloor's max band.
  """
  def died(game, ctx) do
    game
    |> corpses(ctx)
    |> necromancer(ctx)
    |> death_rites(ctx)
    |> gorgon(ctx)
    |> dozer(ctx)
    |> jandra(ctx)
    |> orpal(ctx)
    |> bury(ctx)
  end

  defp jandra(game, %{slug: "jandra-the-negator", combat?: true, s: s}) do
    victims =
      for id <- Zones.in_play(game, s),
          Stats.unit?(game, id),
          not Stats.subtype?(game, id, "Demon"),
          do: id

    Enum.reduce(victims, game, fn id, game ->
      if in_play?(game, id), do: Effects.destroy(game, id), else: game
    end)
  end

  defp jandra(game, _ctx), do: game

  # Corpse Catapult: "Whenever one of your units dies, put a corpse rune on this."
  defp corpses(game, %{unit?: true, s: s}) do
    Enum.reduce(Zones.in_play(game, s), game, fn c, game ->
      if game.cards[c].card == "corpse-catapult",
        do: Effects.add_counter(game, c, :corpse, 1),
        else: game
    end)
  end

  defp corpses(game, _ctx), do: game

  # Necromancer: "Whenever another non-token unit of yours dies, summon a 1/1 black Skeleton token."
  defp necromancer(game, %{unit?: true, token?: false, s: s}) do
    n = Enum.count(Zones.in_play(game, s), &(game.cards[&1].card == "necromancer"))
    if n > 0, do: Effects.summon(game, s, "skeleton", n), else: game
  end

  defp necromancer(game, _ctx), do: game

  # Death Rites: one of your units dies this turn → destroy one of an
  # opponent's lowest tech units (rulings: not an indestructible one).
  # REVIEW: among those, the engine destroys the one with the most ATK + HP.
  defp death_rites(game, %{unit?: true, s: s}) do
    if Stats.side_effect(game, s, :death_rites) do
      units =
        for id <- Zones.in_play(game, 1 - s),
            Stats.unit?(game, id),
            not Stats.kw?(game, id, :indestructible),
            do: id

      case units do
        [] ->
          game

        _ ->
          low = units |> Enum.map(&Stats.tech(game, &1)) |> Enum.min()

          pick =
            units
            |> Enum.filter(&(Stats.tech(game, &1) == low))
            |> Enum.max_by(&{Stats.atk(game, &1) + Stats.hp(game, &1), -&1})

          Effects.destroy(game, pick)
      end
    else
      game
    end
  end

  defp death_rites(game, _ctx), do: game

  defp gorgon(game, %{slug: "gorgon", s: s}), do: Rules.draw(game, s, 1, :free)
  defp gorgon(game, _ctx), do: game

  # Blackhand Dozer dies: the active player destroys one of its side's lowest tech units.
  # REVIEW: the engine picks for the active player: its own weakest, or the opponent's strongest.
  defp dozer(game, %{slug: "blackhand-dozer", s: s}) do
    units = for id <- Zones.in_play(game, s), Stats.unit?(game, id), do: id

    case units do
      [] ->
        game

      _ ->
        low = units |> Enum.map(&Stats.tech(game, &1)) |> Enum.min()
        lowest = Enum.filter(units, &(Stats.tech(game, &1) == low))
        value = &{Stats.atk(game, &1) + Stats.hp(game, &1), -&1}

        pick =
          if game.active == s, do: Enum.min_by(lowest, value), else: Enum.max_by(lowest, value)

        Effects.destroy(game, pick)
    end
  end

  defp dozer(game, _ctx), do: game

  # Orpal Gloor, max band: the first time each turn a unit with a -1/-1 rune
  # dies, the active player puts a -1/-1 rune on two units friendly to it.
  # REVIEW: the engine picks the two with the least HP left.
  defp orpal(game, %{unit?: true, minus?: true, s: s}) do
    orpal =
      Enum.find(for(seat <- [0, 1], h <- Zones.in_play(game, seat), do: h), fn h ->
        game.cards[h].card == "orpal-gloor" and game.cards[h].level >= 6 and
          not Stats.silenced?(game, h)
      end)

    if orpal && Stats.side_effect(game, game.active, :orpal_used) == nil do
      victims =
        game
        |> Zones.in_play(s)
        |> Enum.filter(&Stats.unit?(game, &1))
        |> Enum.sort_by(&{Stats.hp(game, &1) - game.cards[&1].damage, &1})
        |> Enum.take(2)

      game
      |> Rules.update_side(game.active, &%{&1 | effects: Map.put(&1.effects, :orpal_used, true)})
      |> then(&Enum.reduce(victims, &1, fn v, g -> Effects.minus_rune(g, v) end))
    else
      game
    end
  end

  defp orpal(game, _ctx), do: game

  # Graveyard: "Whenever your non-token units die, bury them here. Sacrifice
  # Graveyard when four or more units are buried in it."
  defp bury(game, %{unit?: true, token?: false, s: s, id: id}) do
    gy = Enum.find(Zones.in_play(game, s), &(game.cards[&1].card == "graveyard"))

    if gy && id in game.sides[game.cards[id].seat].zones.discard do
      game =
        game
        |> Zones.move(id, :trash)
        |> Zones.update_card(id, &%{&1 | extra: Map.put(&1.extra, :buried_in, gy)})
        |> Zones.update_card(
          gy,
          &%{&1 | extra: Map.update(&1.extra, :holds, [id], fn h -> h ++ [id] end)}
        )
        |> Effects.log({:buried, id})

      if length(game.cards[gy].extra.holds) >= @graveyard_limit,
        do: Effects.sacrifice(game, gy),
        else: game
    else
      game
    end
  end

  defp bury(game, _ctx), do: game

  @doc """
  Black upkeep abilities of side `s`: Vandy Anadrose's marked units lose +2/+2
  and die.
  """
  def upkeep(game, s) do
    game = game |> gargoyles(s) |> shrine(s) |> banefire(s) |> plague_lord_upkeep(s)

    marked =
      for seat <- [0, 1],
          id <- Zones.in_play(game, seat),
          Map.get(game.cards[id].extra, :vandy) == s,
          do: id

    Enum.reduce(marked, game, fn id, game ->
      game
      |> Zones.update_card(id, &%{&1 | extra: Map.delete(&1.extra, :vandy)})
      |> Effects.destroy(id)
    end)
  end

  # Plague Lord: "Upkeep: Each player's base takes 1 damage for each -1/-1 rune
  # on their units and heroes."
  defp plague_lord_upkeep(game, s) do
    lords = Enum.count(Zones.in_play(game, s), &(game.cards[&1].card == "plague-lord"))

    Enum.reduce(1..lords//1, game, fn _, game ->
      Enum.reduce([0, 1], game, fn seat, game ->
        runes =
          game
          |> Zones.in_play(seat)
          |> Enum.filter(&Stats.force?(game, &1))
          |> Enum.map(&game.cards[&1].minus)
          |> Enum.sum()

        Effects.burn(game, s, "plague-lord", {:building, seat, :base}, runes)
      end)
    end)
  end

  # Gargoyles unlocked by side `s` lock again.
  defp gargoyles(game, s) do
    Enum.reduce(game.cards, game, fn {id, c}, game ->
      if Map.get(c.extra, :gargoyle) == s,
        do: Zones.update_card(game, id, &%{&1 | extra: Map.delete(&1.extra, :gargoyle)}),
        else: game
    end)
  end

  # Shrine of Forbidden Knowledge: "Upkeep: Your base takes 1 damage."
  defp shrine(game, s) do
    n =
      Enum.count(
        Zones.in_play(game, s),
        &(game.cards[&1].card == "shrine-of-forbidden-knowledge")
      )

    Effects.deal(game, {:building, s, :base}, n)
  end

  # Banefire Golem: "Upkeep: Sacrifice a unit. If you do, deal 1 damage to each
  # opposing unit, hero, and building."
  # REVIEW: the engine sacrifices your weakest other unit, else the Golem itself.
  defp banefire(game, s) do
    golems = for id <- Zones.in_play(game, s), game.cards[id].card == "banefire-golem", do: id

    Enum.reduce(golems, game, fn g, game ->
      if in_play?(game, g), do: golem(game, s, g), else: game
    end)
  end

  defp golem(game, s, g) do
    victim =
      Effects.weakest(game, s, &(&1 != g and Stats.sacrificable?(game, &1))) ||
        if(Stats.sacrificable?(game, g), do: g)

    if victim, do: game |> Effects.sacrifice(victim) |> Rules.deaths() |> bane(s), else: game
  end

  defp bane(game, s) do
    opp = 1 - s

    cards =
      for id <- Zones.in_play(game, opp),
          Stats.force?(game, id) or Stats.building_card?(game, id),
          do: id

    buildings = for b <- [:base | game.sides[opp].tech_buildings], do: {:building, opp, b}
    Enum.reduce(cards ++ buildings, game, &Effects.burn(&2, s, "banefire-golem", &1, 1))
  end

  @doc "The end of side `s`'s turn."
  def end_of_turn(game, s),
    do: Rules.update_side(game, s, &%{&1 | effects: Map.delete(&1.effects, :orpal_used)})
end
