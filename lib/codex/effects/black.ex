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

  def spell(game, _s, _slug, _id, _targets), do: game

  # -- arrivals -------------------------------------------------------------------------------

  @doc "A Black unit's \"Arrives:\" ability."
  def arrive(game, _s, id, "skeleton-javelineer", []),
    do: Effects.add_counter(game, id, :javelin, 1)

  def arrive(game, s, _id, "thieving-imp", []), do: Effects.discard_random(game, 1 - s)

  def arrive(game, _s, _id, _slug, _targets), do: game

  # -- abilities ------------------------------------------------------------------------------

  @doc "A Black activated ability (costs paid)."
  # Skeleton Javelineer: remove a javelin rune → long-range this turn.
  def ability(game, _s, id, :javelin, []),
    do: Zones.update_card(game, id, &%{&1 | this_turn: Map.put(&1.this_turn, :long_range, true)})

  # Graveyard: play a buried unit (its cost is paid by `Codex.Rules`); it enters play.
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
      |> Enum.filter(fn id ->
        d = Cards.fetch!(game.cards[id].card)

        d.type in ["Unit", "Legendary Unit"] and d.tech in [1, 2] and (d.cost || 0) <= 5 and
          :"tech_#{d.tech}" in side.tech_buildings and
          (d.tech < 2 or d.spec == nil or d.spec == side.tech_spec)
      end)
      |> Enum.max_by(&(Cards.fetch!(game.cards[&1].card).cost || 0), fn -> nil end)

    if unit, do: Effects.enter(game, s, unit, []), else: game
  end

  def max_level(game, _s, _id, _slug), do: game

  @doc "A Black building or upgrade comes into play."
  def permanent(game, _s, _id, _slug), do: game

  @doc """
  Black "Attacks:" abilities: Poisonblade Rogue gets armor piercing and deals
  its damage as -1/-1 runes this turn.
  """
  def attacks(game, _s, a, "poisonblade-rogue", _target) do
    Zones.update_card(game, a, fn c ->
      %{c | this_turn: Map.merge(c.this_turn, %{armor_piercing: true, rune_damage: true})}
    end)
  end

  def attacks(game, _s, _a, _slug, _target), do: game

  @doc "Black abilities after a combat."
  def after_combat(game, _s, _a, _target, _ctx), do: game

  @doc """
  Black triggers when a card dies (`ctx` from `Codex.Effects.die/2`): Jandra
  dies from combat damage (destroy all your units except Demons), a Graveyard
  buries your non-token units, Orpal Gloor's max band.
  """
  def died(game, ctx) do
    game
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

  @doc "The end of side `s`'s turn."
  def end_of_turn(game, s),
    do: Rules.update_side(game, s, &%{&1 | effects: Map.delete(&1.effects, :orpal_used)})
end
