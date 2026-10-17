defmodule Codex.Effects.Green do
  @moduledoc """
  The Green card texts (Moss Sentinels): the starting deck, the heroes Master
  Midori, Calamandra Moss and Argagarg Garg, and the Balance, Feral and Growth
  codex cards. Called by `Codex.Effects`.
  """

  alias Codex.{Effects, Rules, Stats, Zones}

  # -- spells -----------------------------------------------------------------------------------

  @doc "Resolve a Green spell."
  def spell(game, _s, "rampant-growth", _id, [t]), do: more(game, t, 2, 2)
  def spell(game, _s, "forest-s-favor", _id, [t]), do: Effects.plus_rune(game, t)
  # -- Balance --

  def spell(game, s, "moment-s-peace", _id, []),
    do: Rules.update_side(game, s, &%{&1 | effects: Map.put(&1.effects, :peace, true)})

  # Nature Reclaims: trash it (then it trashes itself, `Codex.Effects.cast/4`).
  def spell(game, _s, "nature-reclaims", _id, [t]), do: Effects.trash(game, t)

  # A target that died when targeted (an Illusion) is nil: the effect skips it.
  def spell(game, _s, slug, _id, [nil | _])
      when slug in ["polymorph-squirrel", "spirit-of-the-panda"],
      do: game

  # Circle of Life: sacrifice a green unit; a green unit one tech higher from the codex into play.
  def spell(game, s, "circle-of-life", _id, [u, c]) do
    game
    |> Effects.sacrifice(u)
    |> Effects.take_control(s, c)
    |> Effects.arrive(s, c, [])
  end

  # Final Showdown: attach to your Balance hero; two 3/3 Hunters for the opponent.
  def spell(game, s, "final-showdown", id, [hero]) do
    game
    |> Zones.update_card(id, &%{&1 | extra: Map.put(&1.extra, :attached, hero)})
    |> Effects.summon(1 - s, "hunter", 2)
  end

  # -- Feral --

  # Ferocity: your units get armor piercing and swift strike until your next upkeep.
  def spell(game, s, "ferocity", _id, []),
    do: Rules.update_side(game, s, &%{&1 | effects: Map.put(&1.effects, :ferocity, true)})

  def spell(game, _s, "behind-the-ferns", _id, []), do: game

  # Murkwood Allies: a 4/4 Beast, or four 1/1 Frogs; boosted: both.
  def spell(game, s, "murkwood-allies", _id, [mode]) do
    game = if mode in [:beast, :boost], do: Effects.summon(game, s, "beast"), else: game
    if mode in [:frogs, :boost], do: Effects.summon(game, s, "frog", 4), else: game
  end

  # -- Growth --

  # Polymorph: Squirrel: a 1/1 Squirrel with no abilities until your next upkeep.
  def spell(game, s, "polymorph-squirrel", _id, [t]) do
    Zones.update_card(game, t, fn c ->
      %{c | card: "squirrel", extra: Map.put(c.extra, :polymorph, %{from: c.card, by: s})}
    end)
  end

  def spell(game, _s, "dinosize", _id, [t]), do: more(game, t, 6, 6)

  # Spirit of the Panda: attach to a unit (+2/+2, "Attacks: Gain ①", healing 1: `Codex.Stats`, `Codex.Combat`).
  def spell(game, _s, "spirit-of-the-panda", id, [t]),
    do: Zones.update_card(game, id, &%{&1 | extra: Map.put(&1.extra, :attached, t)})

  # Stampede: your units get +3 ATK / +3 armor this turn; excess combat damage hits the base.
  def spell(game, s, "stampede", _id, []),
    do: Rules.update_side(game, s, &%{&1 | effects: Map.put(&1.effects, :stampede, true)})

  def spell(game, _s, _slug, _id, _targets), do: game

  # +atk ATK and +armor armor this turn.
  defp more(game, t, atk, armor),
    do:
      Zones.update_card(
        game,
        t,
        &%{&1 | tmp_atk: &1.tmp_atk + atk, tmp_armor: &1.tmp_armor + armor}
      )

  # -- arrivals -------------------------------------------------------------------------------

  @doc "A Green unit's \"Arrives:\" ability."
  def arrive(game, s, _id, "young-treant", []), do: Rules.draw(game, s, 1, :main)

  def arrive(game, s, id, slug, []) when slug in ["playful-panda", "giant-panda"] do
    game
    |> Zones.update_card(id, &%{&1 | exhausted: true})
    |> Effects.summon(s, "wisp")
  end

  def arrive(game, _s, id, "spore-shambler", []),
    do: game |> Effects.plus_rune(id) |> Effects.plus_rune(id)

  # Fairie Dragon: you may put a feather rune on a tech I or II unit.
  def arrive(game, _s, _id, "fairie-dragon", [t]) when is_integer(t),
    do: Zones.update_card(game, t, &%{&1 | extra: Map.put(&1.extra, :feather, true)})

  # Potent Basilisk: you may destroy an upgrade or ongoing spell.
  def arrive(game, _s, _id, "potent-basilisk", [t]) when is_integer(t),
    do: Effects.destroy(game, t)

  # Tyrannosaurus Rex: destroy up to two units, upgrades and/or workers.
  def arrive(game, _s, _id, "tyrannosaurus-rex", targets) do
    targets |> Enum.reject(&is_nil/1) |> Enum.reduce(game, &Effects.destroy(&2, &1))
  end

  def arrive(game, s, _id, "moss-ancient", []), do: Effects.summon(game, s, "squirrel", 3)
  def arrive(game, _s, _id, "artisan-mantis", [t]), do: Effects.repair(game, t, 3)

  def arrive(game, _s, _id, _slug, _targets), do: game

  # -- abilities ------------------------------------------------------------------------------

  @doc "A Green activated ability (costs paid)."
  def ability(game, s, _id, :prospect, []), do: Rules.gain_gold(game, s, 1)

  def ability(game, _s, _id, name, [t]) when name in [:spore, :spore_tap, :rune_move],
    do: Effects.plus_rune(game, t)

  # Verdant Tree: your tech buildings build instantly this turn (also those started).
  def ability(game, s, _id, :instant_build, []) do
    game
    |> Rules.update_side(s, &%{&1 | effects: Map.put(&1.effects, :instant_build, true)})
    |> Rules.finish_buildings(s, [:tech_1, :tech_2, :tech_3])
  end

  def ability(game, _s, _id, :argagarg, [t]), do: more(game, t, 1, 1)

  # Blooming Elm: three +1/+1 runes on a unit, or one on a hero, without +1/+1 runes.
  def ability(game, _s, _id, :elm, [nil]), do: game

  def ability(game, _s, _id, :elm, [t]) do
    cond do
      game.cards[t].plus > 0 -> game
      Stats.hero?(game, t) -> Effects.plus_rune(game, t)
      true -> game |> Effects.plus_rune(t) |> Effects.plus_rune(t) |> Effects.plus_rune(t)
    end
  end

  # Calamandra Moss: discard two cards → she gets stealth this turn.
  def ability(game, s, id, :hide, [a, b]) do
    game
    |> Zones.move(a, {s, :discard}, 0)
    |> Zones.move(b, {s, :discard}, 0)
    |> Zones.update_card(id, &%{&1 | stealth: true})
  end

  # Calamandra Moss, max level: a Tiger from your codex into play (free, no tech building).
  def ability(game, s, _id, :tiger, [t]), do: Effects.take_control(game, s, t)

  def ability(game, _s, _id, _name, _targets), do: game

  # -- triggers -------------------------------------------------------------------------------

  @doc "Green \"Attacks:\" abilities (after the exhaust, before damage): Moss Ancient."
  def attacks(game, s, _a, "moss-ancient"), do: Effects.summon(game, s, "squirrel", 3)
  def attacks(game, _s, _a, _slug), do: game

  @doc """
  Green abilities after a combat: Predator Tiger deals combat damage to a base:
  trash a worker at that base.
  """
  def after_combat(game, s, a, target, ctx),
    do: game |> predator(s, a, target, ctx) |> leaf_and_claw(s, ctx)

  defp predator(game, s, a, {:building, opp, :base}, %{base_hit: true}) do
    if game.cards[a].card == "predator-tiger" and s != opp,
      do: Effects.trash_worker(game, opp),
      else: game
  end

  defp predator(game, _s, _a, _target, _ctx), do: game

  # Might of Leaf and Claw: whenever you deal combat damage with an attacker, a growth rune.
  defp leaf_and_claw(game, s, %{dealt: dealt}) when dealt > 0 do
    Enum.reduce(Zones.in_play(game, s), game, fn m, game ->
      if game.cards[m].card == "might-of-leaf-and-claw",
        do: Effects.add_counter(game, m, :growth, 1),
        else: game
    end)
  end

  defp leaf_and_claw(game, _s, _ctx), do: game

  @doc """
  Green upkeep abilities of side `s`: Gemscout Owl (gain 1), Dothram
  Horselord (it joins the player with more total ATK than each other).
  """
  def upkeep(game, s) do
    # Ferocity lasts "until your next upkeep"; so does Polymorph: Squirrel.
    game = Rules.update_side(game, s, &%{&1 | effects: Map.delete(&1.effects, :ferocity)})
    game = unpolymorph(game, s)

    Enum.reduce(Zones.in_play(game, s), game, fn id, game ->
      case game.cards[id].card do
        "gemscout-owl" -> Rules.gain_gold(game, s, 1)
        "dothram-horselord" -> horselord(game, s, id)
        "galina-glimmer" -> galina(game, s)
        _ -> game
      end
    end)
  end

  # Polymorphs cast by side `s` end.
  defp unpolymorph(game, s) do
    Enum.reduce(Map.keys(game.cards), game, fn id, game ->
      case game.cards[id].extra do
        %{polymorph: %{by: ^s}} -> Effects.unpolymorph(game, id)
        _ -> game
      end
    end)
  end

  # Galina Glimmer: gain 1 gold for every two of your green units.
  defp galina(game, s) do
    green =
      Enum.count(
        Zones.in_play(game, s),
        &(Stats.unit?(game, &1) and Stats.color(game, &1) == "Green")
      )

    Rules.gain_gold(game, s, div(green, 2))
  end

  defp horselord(game, s, id) do
    [mine, theirs] = for seat <- [s, 1 - s], do: total_atk(game, seat)
    if theirs > mine, do: Effects.take_control(game, 1 - s, id), else: game
  end

  defp total_atk(game, seat) do
    game
    |> Zones.in_play(seat)
    |> Enum.filter(&Stats.force?(game, &1))
    |> Enum.map(&max(Stats.atk(game, &1), 0))
    |> Enum.sum()
  end

  @doc "A \"Max level:\" trigger of a hero of this colour (none here)."
  def max_level(game, _s, _id, _slug), do: game

  @doc "A building or upgrade card of this colour comes into play (nothing here)."
  def permanent(game, _s, _id, _slug), do: game
end
