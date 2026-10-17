defmodule Codex.Effects.Red do
  @moduledoc """
  The Red card texts (Blood Anarchs): the starting deck, the heroes Captain
  Zane, Drakk Ramhorn and Jaina Stormborne, and the Anarchy, Blood and Fire
  codex cards. Called by `Codex.Effects`; damage from Red spells and abilities
  goes through `Codex.Effects.burn/5` (Hotter Fire).
  """

  alias Codex.{Effects, Rules, Stats, Zones}
  alias Table.Kit.Rng

  # -- spells -----------------------------------------------------------------------------------

  @doc "Resolve a Red spell."
  def spell(game, s, "scorch", _id, [t]), do: Effects.burn(game, s, "scorch", t, 2)

  # Charge: one of your units gets haste and +1 ATK this turn.
  def spell(game, _s, "charge", _id, [t]) do
    Zones.update_card(
      game,
      t,
      &%{&1 | tmp_atk: &1.tmp_atk + 1, this_turn: Map.put(&1.this_turn, :haste, true)}
    )
  end

  # Pillage: 1 damage to a base and steal 1 gold; with a Pirate, 2 and 2.
  def spell(game, s, "pillage", _id, []) do
    n = if Enum.any?(Zones.in_play(game, s), &pirate?(game, &1)), do: 2, else: 1

    game
    |> Effects.burn(s, "pillage", {:building, 1 - s, :base}, n)
    |> Effects.steal(s, 1 - s, n)
  end

  # -- Anarchy --

  # Chaos Mirror: swap the printed ATK of two units and/or heroes until end of turn.
  # A target that died when targeted (an Illusion) is nil: the effect skips it.
  def spell(game, _s, "chaos-mirror", _id, [a, b]) when is_nil(a) or is_nil(b), do: game
  def spell(game, _s, "kidnapping", _id, [nil]), do: game

  def spell(game, _s, "chaos-mirror", _id, [a, b]) do
    {atk_a, _} = Stats.printed(game.cards[a])
    {atk_b, _} = Stats.printed(game.cards[b])

    game
    |> Zones.update_card(a, &%{&1 | this_turn: Map.put(&1.this_turn, :printed_atk, atk_b)})
    |> Zones.update_card(b, &%{&1 | this_turn: Map.put(&1.this_turn, :printed_atk, atk_a)})
  end

  # Detonate: trash a worker or building card (then it trashes itself, `Codex.Effects.cast/4`).
  def spell(game, _s, "detonate", _id, [t]), do: Effects.trash(game, t)

  def spell(game, s, "surprise-attack", _id, []), do: Effects.summon(game, s, "shark", 2)

  # Maximum Anarchy: destroy all units and heroes.
  def spell(game, _s, "maximum-anarchy", _id, []) do
    all = for seat <- [0, 1], id <- Zones.in_play(game, seat), Stats.force?(game, id), do: id

    Enum.reduce(all, game, fn id, game ->
      if in_play?(game, id), do: Effects.die(game, id), else: game
    end)
  end

  # -- Blood --

  # Desperation (the hand was empty): draw three, discard the hand at the end of the main phase.
  def spell(game, s, "desperation", _id, []) do
    game
    |> Rules.draw(s, 3, :main)
    |> Rules.update_side(s, &%{&1 | effects: Map.put(&1.effects, :desperation, true)})
  end

  # Kidnapping: control an opposing tech 0-II unit until end of turn; ready it, haste.
  def spell(game, s, "kidnapping", _id, [t]) do
    from = Zones.controller(game, t)

    game
    |> Zones.move(t, {s, :in_play})
    |> Zones.update_card(t, fn c ->
      %{
        c
        | exhausted: false,
          extra: Map.put(c.extra, :kidnapped_from, from),
          this_turn: Map.put(c.this_turn, :haste, true)
      }
    end)
  end

  # Bloodlust: up to two units and/or heroes +1 ATK and haste this turn; 1 damage each at end of turn.
  def spell(game, _s, "bloodlust", _id, targets) do
    targets
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(game, fn t, game ->
      Zones.update_card(game, t, fn c ->
        %{
          c
          | tmp_atk: c.tmp_atk + 1,
            this_turn: Map.merge(c.this_turn, %{haste: true, bloodlust: true})
        }
      end)
    end)
  end

  def spell(game, _s, "war-drums", _id, []), do: game

  # -- Fire --

  def spell(game, s, "fire-dart", _id, [t]),
    do: Effects.burn(game, s, "fire-dart", t, if(building?(game, t), do: 2, else: 3))

  def spell(game, s, "flame-arrow", _id, [t]),
    do: Effects.burn(game, s, "flame-arrow", t, if(building?(game, t), do: 3, else: 4))

  # Ember Sparks: 3 damage divided (one target per point). Hotter Fire adds its
  # damage to the total. # REVIEW: the extra point goes to the first target.
  def spell(game, s, "ember-sparks", _id, targets) do
    extra = Effects.ability_damage(game, s, "ember-sparks", 0)
    [first | rest] = targets
    game = Effects.deal(game, first, 1 + extra)
    Enum.reduce(rest, game, &Effects.deal(&2, &1, 1))
  end

  def spell(game, _s, _slug, _id, _targets), do: game

  defp destroyed?(game, {:building, s, b}),
    do: b != :base and b not in game.sides[s].tech_buildings

  defp destroyed?(game, id) when is_integer(id), do: not in_play?(game, id)

  defp building?(_game, {:building, _, _}), do: true
  defp building?(game, id) when is_integer(id), do: Stats.building_card?(game, id)
  defp building?(_game, _t), do: false

  defp in_play?(game, id), do: Zones.zone_name(Zones.locate(game, id)) in [:in_play, :patrol]

  defp pirate?(game, id), do: Codex.Cards.fetch!(game.cards[id].card).subtype in ["Pirate"]

  # -- arrivals -------------------------------------------------------------------------------

  @doc "A Red unit's \"Arrives:\" ability."
  def arrive(game, _s, id, "disguised-monkey", []),
    do: Zones.update_card(game, id, &%{&1 | stealth: true})

  # Marauder, boosted: trash a worker. # REVIEW: an opposing worker (the point of the boost; rulings).
  def arrive(game, s, _id, "marauder", [:boost]), do: Effects.trash_worker(game, 1 - s)

  def arrive(game, s, _id, "pirate-gang-commander", []), do: Effects.summon(game, s, "pirate", 3)

  def arrive(game, s, _id, "bamstamper-lizzo", [t]),
    do: Effects.burn(game, s, "bamstamper-lizzo", t, 3)

  def arrive(game, _s, _id, _slug, _targets), do: game

  # -- abilities ------------------------------------------------------------------------------

  @doc "A Red activated ability (costs paid)."
  def ability(game, s, id, :blast, [t]), do: Effects.burn(game, s, slug(game, id), t, 2)

  def ability(game, s, id, :shoot, [t]) do
    slug = slug(game, id)

    game
    |> Effects.burn(s, slug, t, 1)
    |> Effects.burn(s, slug, {:building, s, :base}, 1)
  end

  def ability(game, s, id, :burn, [t]), do: Effects.burn(game, s, slug(game, id), t, 1)
  def ability(game, s, id, :jaina_1, [t]), do: Effects.burn(game, s, slug(game, id), t, 1)
  def ability(game, s, id, :jaina_3, [t]), do: Effects.burn(game, s, slug(game, id), t, 3)
  # Sanatorium: draw a card, then put up to two tech 0-II units from your hand
  # into play (free, no tech building) with haste and ephemeral for good.
  # REVIEW: the units are picked before the draw (the drawn card cannot be one).
  def ability(game, s, _id, :sanatorium, targets) do
    game = Rules.draw(game, s, 1, :main)

    targets
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(game, fn u, game ->
      game
      |> Effects.take_control(s, u)
      |> Zones.update_card(
        u,
        &%{&1 | extra: Map.merge(&1.extra, %{haste: true, ephemeral: true})}
      )
      |> Effects.arrive(s, u, [])
    end)
  end

  def ability(game, s, id, :lob, [t]), do: Effects.burn(game, s, slug(game, id), t, 1)
  def ability(game, s, id, :firebat, [t]), do: Effects.burn(game, s, slug(game, id), t, 2)

  # Firehouse: 2 damage to a unit, hero or building; if that destroys it, ready the Firehouse.
  def ability(game, s, id, :firehouse, [t]) do
    game = game |> Effects.burn(s, "firehouse", t, 2) |> Rules.deaths()

    if destroyed?(game, t),
      do: Zones.update_card(game, id, &%{&1 | exhausted: false}),
      else: game
  end

  # Rickety Mine: gain 3, flip a coin; tails: sacrifice it and the base takes 2.
  def ability(game, s, id, :mine, []) do
    {flip, rng} = Rng.uniform(2, game.rng)
    game = %{game | rng: rng} |> Rules.gain_gold(s, 3)

    if flip == 1 do
      Effects.log(game, {:coin, :heads})
    else
      game
      |> Effects.log({:coin, :tails})
      |> Effects.sacrifice(id)
      |> Effects.deal({:building, s, :base}, 2)
    end
  end

  def ability(game, _s, _id, _name, _targets), do: game

  # Bombaster is sacrificed before its effect: its slug is still on the card.
  defp slug(game, id), do: game.cards[id].card

  # -- triggers -------------------------------------------------------------------------------

  @doc """
  Death triggers of Red cards: Drakk Ramhorn ("Dies: 1 damage to each opposing
  base"), Crash Bomber, and the Pirate-Gang Commander's gift to your units
  (`commanders`: how many its side had).
  """
  def dies(game, s, slug, commanders) do
    game
    |> dies(s, slug)
    |> then(
      &Enum.reduce(1..commanders//1, &1, fn _, g ->
        Effects.burn(g, s, "pirate-gang-commander", {:building, 1 - s, :base}, 1)
      end)
    )
  end

  defp dies(game, s, "drakk-ramhorn"),
    do: Effects.burn(game, s, "drakk-ramhorn", {:building, 1 - s, :base}, 1)

  # Crash Bomber dies on your turn: 1 damage to a patroller or building; on
  # another player's turn: 1 damage to that player's base.
  # REVIEW: on its turn the engine picks an opposing patroller it kills, else the opposing base.
  defp dies(game, s, "crash-bomber") do
    if s == game.active do
      target =
        Enum.find_value(Zones.patrollers(game, 1 - s), fn {_slot, p} ->
          Stats.force?(game, p) and
            Stats.hp(game, p) - game.cards[p].damage + Stats.armor(game, p) <= 1 and p
        end)

      Effects.burn(game, s, "crash-bomber", target || {:building, 1 - s, :base}, 1)
    else
      Effects.burn(game, s, "crash-bomber", {:building, game.active, :base}, 1)
    end
  end

  defp dies(game, _s, _slug), do: game

  @doc """
  Captain Zane, "Max level: Shove a patroller to an empty slot in its patrol
  zone, then deal 1 damage to it." # REVIEW: the engine picks the opposing
  squad leader (else the first patroller) and the first empty slot.
  """
  def zane_max(game, s, _zane) do
    opp = 1 - s

    case Zones.patrollers(game, opp) do
      [] ->
        game

      patrollers ->
        {_slot, p} = List.keyfind(patrollers, :squad_leader, 0) || hd(patrollers)
        empty = Enum.find(Zones.patrol_slots(), &(game.sides[opp].zones.patrol[&1] == nil))
        game = if empty, do: Zones.move(game, p, {opp, :patrol}, empty), else: game
        Effects.burn(game, s, "captain-zane", p, 1)
    end
  end

  @doc "Red \"Attacks:\" abilities (after the exhaust, before damage): Doubleshot Archer."
  def attacks(game, s, _a, "doubleshot-archer"),
    do: Effects.burn(game, s, "doubleshot-archer", {:building, 1 - s, :base}, 3)

  def attacks(game, _s, _a, _slug), do: game

  @doc """
  After a combat of attacker `a`: Captain Zane's middle band (he kills a
  scavenger: 1 gold; a technician: a card).
  """
  def after_combat(game, s, a, target, %{killed?: true, slot: slot} = ctx) do
    game = game |> recruit(s, a, target, ctx) |> firebird(s, a, ctx)
    c = game.cards[a]

    case {c.card, slot} do
      # Gunpoint Taxman kills a patroller: steal 1 gold.
      {"gunpoint-taxman", slot} when slot != nil -> Effects.steal(game, s, 1 - s, 1)
      {"captain-zane", :scavenger} when c.level >= 4 -> Rules.gain_gold(game, s, 1)
      {"captain-zane", :technician} when c.level >= 4 -> Rules.draw(game, s, 1, :main)
      _ -> game
    end
  end

  def after_combat(game, s, a, target, ctx),
    do: game |> recruit(s, a, target, ctx) |> firebird(s, a, ctx)

  # Molting Firebird damages a building: 1 damage to every unit and hero that opponent controls.
  defp firebird(game, s, a, %{building_hit: true}) do
    if game.cards[a].card == "molting-firebird" do
      forces = for id <- Zones.in_play(game, 1 - s), Stats.force?(game, id), do: id
      Enum.reduce(forces, game, &Effects.burn(&2, s, "molting-firebird", &1, 1))
    else
      game
    end
  end

  defp firebird(game, _s, _a, _ctx), do: game

  # Ogre Recruiter: "Attacks: If this survives the combat, gain control of a tech 0 or tech I unit."
  # REVIEW: the engine takes the opposing tech 0/I unit with the most ATK + HP.
  defp recruit(game, s, a, _target, _ctx) do
    if game.cards[a].card == "ogre-recruiter" and in_play?(game, a) do
      unit =
        game
        |> Zones.in_play(1 - s)
        |> Enum.filter(&(Stats.unit?(game, &1) and Stats.tech(game, &1) in [0, 1]))
        |> Enum.max_by(&(Stats.atk(game, &1) + Stats.hp(game, &1)), fn -> nil end)

      if unit, do: Effects.take_control(game, s, unit), else: game
    else
      game
    end
  end

  @doc """
  Red upkeep abilities of side `s`: Land Octopus ("Sacrifice two workers or
  Land Octopus"). # REVIEW: the engine sacrifices two workers when the side
  keeps at least 6 after, else the Octopus.
  """
  def upkeep(game, s) do
    octopi = for id <- Zones.in_play(game, s), game.cards[id].card == "land-octopus", do: id
    Enum.reduce(octopi, game, &octopus(&2, s, &1))
  end

  defp octopus(game, s, id) do
    cond do
      not in_play?(game, id) ->
        game

      length(game.sides[s].zones.workers) >= 8 ->
        game |> Effects.trash_worker(s) |> Effects.trash_worker(s)

      true ->
        Effects.sacrifice(game, id)
    end
  end

  @doc """
  The end of a turn: Bloodlust's 1 damage; Kidnapping ends (the unit goes back
  to the side it was taken from).
  """
  def end_of_turn(game, _s) do
    all = for seat <- [0, 1], id <- Zones.in_play(game, seat), do: id

    Enum.reduce(all, game, fn id, game ->
      c = game.cards[id]

      game =
        if Map.get(c.this_turn, :bloodlust) == true and in_play?(game, id),
          do: Effects.deal(game, id, 1),
          else: game

      case Map.get(c.extra, :kidnapped_from) do
        nil ->
          game

        from ->
          game
          |> Zones.move(id, {from, :in_play})
          |> Zones.update_card(id, &%{&1 | extra: Map.delete(&1.extra, :kidnapped_from)})
      end
    end)
  end

  @doc "A \"Max level:\" trigger of a hero of this colour (none here)."
  def max_level(game, _s, _id, _slug), do: game

  @doc "A building or upgrade card of this colour comes into play (nothing here)."
  def permanent(game, _s, _id, _slug), do: game
end
