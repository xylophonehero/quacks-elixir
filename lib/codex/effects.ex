defmodule Codex.Effects do
  @moduledoc """
  What the cards do: damage, healing, death, the spells, "Arrives:" and
  "Upkeep:" abilities (research §5, §10, §16). Each function takes the game and
  returns the game. Targets are checked before (`Codex.Targets`).

  A target is a card id or a building `{:building, seat, name}` (`:base`, a tech
  building or an add-on).
  """

  alias Codex.{CardRules, Cards, Rules, Stats, Zones}

  @building_hp %{base: 20, tech_1: 5, tech_2: 5, tech_3: 5, tower: 4, surplus: 4}
  @dancer_limit 3

  @doc "The HP of a building."
  def building_hp(name), do: Map.fetch!(@building_hp, name)

  # -- damage ---------------------------------------------------------------------------------

  @doc """
  Deal `n` damage to a card or a building. A patrolling squad leader's armor
  takes the first point each turn (S1 p. 5). A tech building or add-on that
  reaches its HP is destroyed and its base takes 2 damage (S1 p. 4).
  """
  def deal(game, _target, n) when n <= 0, do: game

  def deal(game, {:building, s, :base}, n),
    do: Rules.update_side(game, s, &%{&1 | base_hp: &1.base_hp - n})

  def deal(game, {:building, s, b}, n) do
    side = game.sides[s]
    dmg = Map.get(side.building_damage, b, 0) + n

    cond do
      b not in side.tech_buildings ->
        game

      dmg >= building_hp(b) ->
        destroy_building(game, s, b)

      true ->
        Rules.update_side(game, s, &%{&1 | building_damage: Map.put(&1.building_damage, b, dmg)})
    end
  end

  def deal(game, id, n) when is_integer(id) do
    {n, game} = armor(game, id, n)
    Zones.update_card(game, id, &%{&1 | damage: &1.damage + n})
  end

  defp armor(game, id, n) do
    case Zones.locate(game, id) do
      {s, :patrol, :squad_leader} when s != game.active ->
        if game.cards[id].armor_used,
          do: {n, game},
          else: {n - 1, Zones.update_card(game, id, &%{&1 | armor_used: true})}

      _ ->
        {n, game}
    end
  end

  @doc "Remove up to `n` damage from a card."
  def heal(game, id, n), do: Zones.update_card(game, id, &%{&1 | damage: max(&1.damage - n, 0)})

  @doc "Repair up to `n` damage on a building (not the base above 20)."
  def repair(game, {:building, s, :base}, n),
    do: Rules.update_side(game, s, &%{&1 | base_hp: min(&1.base_hp + n, 20)})

  def repair(game, {:building, s, b}, n) do
    Rules.update_side(game, s, fn side ->
      %{side | building_damage: Map.update(side.building_damage, b, 0, &max(&1 - n, 0))}
    end)
  end

  @doc "The damage on a building."
  def building_damage(game, {:building, s, :base}), do: 20 - game.sides[s].base_hp
  def building_damage(game, {:building, s, b}), do: Map.get(game.sides[s].building_damage, b, 0)

  # -- runes ------------------------------------------------------------------------------------

  @doc "Put a +1/+1 rune (it destroys a -1/-1 rune instead, S1 p. 17)."
  def plus_rune(game, id) do
    Zones.update_card(game, id, fn c ->
      if c.minus > 0, do: %{c | minus: c.minus - 1}, else: %{c | plus: c.plus + 1}
    end)
  end

  @doc "Put a -1/-1 rune (it destroys a +1/+1 rune instead)."
  def minus_rune(game, id) do
    Zones.update_card(game, id, fn c ->
      if c.plus > 0, do: %{c | plus: c.plus - 1}, else: %{c | minus: c.minus + 1}
    end)
  end

  # -- leaving play -------------------------------------------------------------------------------

  @doc """
  A unit or hero dies (or is destroyed). A unit goes to its owner's discard pile;
  a token to the trash ("destroyed"); a hero to its owner's command zone, back
  to level 1, and it cannot be summoned until after its owner's next turn; one
  opposing hero in play gets 2 free levels (S1 p. 3). A patroller that dies in
  the scavenger slot gives its side 1 gold, in the technician slot a card (S1 p. 5).
  """
  def die(game, id) do
    c = game.cards[id]
    loc = Zones.locate(game, id)
    s = Zones.zone_seat(loc)
    slot = if Stats.patrolling?(game, id), do: elem(loc, 2)
    game = log(game, {:dies, id})

    game =
      cond do
        CardRules.token?(c.card) ->
          leave(game, id, :trash, nil)

        Stats.hero?(game, id) ->
          owner = c.seat
          turn = game.sides[owner].turn

          game
          |> leave(id, {owner, :command}, nil)
          |> Rules.update_side(owner, &%{&1 | summon_after: turn + 1})
          |> free_levels(1 - s)

        true ->
          leave(game, id, {c.seat, :discard}, 0)
      end

    patrol_bonus(game, s, slot)
  end

  defp patrol_bonus(game, s, :scavenger), do: Rules.gain_gold(game, s, 1)
  defp patrol_bonus(game, s, :technician), do: Rules.draw(game, s, 1, :free)
  defp patrol_bonus(game, _s, _slot), do: game

  # One hero of side `s` in play that can level up gets 2 levels (the active side
  # picks; 1-hero mode has at most one).
  defp free_levels(game, s) do
    hero =
      Enum.find(Zones.in_play(game, s), fn h ->
        Stats.hero?(game, h) and game.cards[h].level < Cards.max_level(game.cards[h].card)
      end)

    if hero, do: game |> level_up(hero, 2) |> log({:free_levels, hero}), else: game
  end

  @doc """
  Level up a hero by `n` (at most its max level). Reaching the middle band or the
  max level heals all its damage (S1 p. 3).
  """
  def level_up(game, id, n) do
    c = game.cards[id]
    [_, %{level: mid}, %{level: max}] = Cards.fetch!(c.card).bands
    new = min(c.level + n, max)
    healed? = (c.level < mid and new >= mid) or (c.level < max and new >= max)

    Zones.update_card(game, id, fn c ->
      %{c | level: new, damage: if(healed?, do: 0, else: c.damage)}
    end)
  end

  @doc "Move a card out of play to `zone`, with its state reset (`Codex.Rules.reset/1`)."
  def leave(game, id, zone, at) do
    game |> Zones.move(id, zone, at) |> Zones.update_card(id, &Rules.reset/1)
  end

  @doc "Sacrifice a card you control (an ongoing spell goes to its owner's discard pile)."
  def sacrifice(game, id) do
    c = game.cards[id]

    if Stats.force?(game, id),
      do: die(game, id),
      else: game |> log({:sacrificed, id}) |> leave(id, {c.seat, :discard}, 0)
  end

  # -- spells -----------------------------------------------------------------------------------

  @doc """
  Resolve spell `id` of side `s` with `targets`. A one-shot spell then goes to
  its owner's discard pile (Appel Stomp: on top of the draw pile); an ongoing
  spell stays in play. Then each Harmony of `s` (not the spell itself) makes a
  Dancer (limit 3).
  """
  def cast(game, s, id, targets) do
    c = game.cards[id]
    game = spell(game, s, c.card, id, targets)

    game =
      cond do
        ongoing?(c.card) -> Zones.move(game, id, {s, :in_play})
        c.card == "appel-stomp" -> Zones.move(game, id, {c.seat, :deck}, 0)
        true -> Zones.move(game, id, {c.seat, :discard}, 0)
      end

    harmony(game, s, id)
  end

  @doc "True for an ongoing spell (it stays in play)."
  def ongoing?(slug), do: String.starts_with?(Cards.fetch!(slug).type, "Ongoing")

  defp spell(game, _s, "spark", _id, [t]), do: deal(game, t, 1)
  defp spell(game, _s, "bloom", _id, [t]), do: plus_rune(game, t)
  defp spell(game, _s, "wither", _id, [t]), do: minus_rune(game, t)
  defp spell(game, _s, "wrecking-ball", _id, [t]), do: deal(game, t, 2)
  defp spell(game, _s, "the-boot", _id, [t]), do: die(game, t)

  defp spell(game, _s, "intimidate", _id, [t]),
    do: Zones.update_card(game, t, &%{&1 | tmp_atk: &1.tmp_atk - 4})

  # Final Smash: destroy a tech 0 unit, return a tech I unit to its owner's hand,
  # gain control of a tech II unit (each part may be empty).
  defp spell(game, s, "final-smash", _id, [t0, t1, t2]) do
    game = if t0, do: die(game, t0), else: game
    game = if t1, do: leave(game, t1, {game.cards[t1].seat, :hand}, nil), else: game

    if t2 do
      game
      |> Zones.move(t2, {s, :in_play})
      |> Zones.update_card(t2, &%{&1 | fatigued: true})
    else
      game
    end
  end

  defp spell(game, s, "discord", _id, []) do
    Enum.reduce(Zones.in_play(game, 1 - s), game, fn u, game ->
      if Stats.unit?(game, u) and Stats.tech(game, u) in [0, 1],
        do: Zones.update_card(game, u, &%{&1 | tmp_atk: &1.tmp_atk - 2, tmp_hp: &1.tmp_hp - 1}),
        else: game
    end)
  end

  defp spell(game, _s, "two-step", id, [a, b]),
    do: Zones.update_card(game, id, &%{&1 | extra: %{partners: [a, b]}})

  defp spell(game, _s, "harmony", id, []),
    do: Zones.update_card(game, id, &%{&1 | extra: %{dancers: 0}})

  defp spell(game, s, "appel-stomp", _id, [t]) do
    game |> sideline(t) |> Rules.draw(s, 1, :main)
  end

  # Whenever you play a spell, each Harmony makes a 0/1 Dancer token (limit 3 per Harmony).
  defp harmony(game, s, spell_id) do
    harmonies =
      for h <- game.sides[s].zones.in_play,
          h != spell_id,
          game.cards[h].card == "harmony",
          Map.get(game.cards[h].extra, :dancers, 0) < @dancer_limit,
          do: h

    Enum.reduce(harmonies, game, fn h, game ->
      {game, [dancer]} = Codex.Game.add_cards(game, s, ["dancer"])

      game
      |> Zones.insert(dancer, {s, :in_play}, nil)
      |> Zones.update_card(dancer, &%{&1 | fatigued: true})
      |> Zones.update_card(
        h,
        &%{&1 | extra: Map.update(&1.extra, :dancers, 1, fn n -> n + 1 end)}
      )
      |> log({:dancer, s})
    end)
  end

  @doc "Harmony's ability: sacrifice it to \"stop the music\": your Dancers flip to Angry Dancers."
  def stop_music(game, s, harmony) do
    game = sacrifice(game, harmony)

    Enum.reduce(Zones.in_play(game, s), game, fn d, game ->
      if game.cards[d].card == "dancer",
        do: Zones.update_card(game, d, &%{&1 | card: "angry-dancer"}),
        else: game
    end)
  end

  @doc "Sideline: move a patroller out of the patrol zone (to in play)."
  def sideline(game, id) do
    case Zones.locate(game, id) do
      {s, :patrol, _} -> Zones.move(game, id, {s, :in_play})
      _ -> game
    end
  end

  # -- arrives --------------------------------------------------------------------------------

  @doc "A unit of side `s` arrives: its \"Arrives:\" ability with `targets`."
  def arrive(game, s, id, targets) do
    case {game.cards[id].card, targets} do
      {"hired-stomper", [t]} -> deal(game, t, 3)
      {"brick-thief", [t]} -> brick(game, s, t)
      {"trojan-duck", [t]} -> deal(game, t, 4)
      {"sneaky-pig", []} -> Zones.update_card(game, id, &%{&1 | stealth: true})
      _ -> game
    end
  end

  @doc """
  Brick Thief: deal 1 damage to a building and repair 1 damage from another
  building. # REVIEW: the repair goes to the most damaged other building of
  its own side (the card lets the player pick; the engine picks for them).
  """
  def brick(game, s, target) do
    game = deal(game, target, 1)

    own =
      [{:building, s, :base} | for(b <- game.sides[s].tech_buildings, do: {:building, s, b})]
      |> Enum.reject(&(&1 == target))
      |> Enum.max_by(&building_damage(game, &1), fn -> nil end)

    if own && building_damage(game, own) > 0, do: repair(game, own, 1), else: game
  end

  defp destroy_building(game, s, b) do
    game
    |> Rules.update_side(s, fn side ->
      %{
        side
        | tech_buildings: List.delete(side.tech_buildings, b),
          building_damage: Map.delete(side.building_damage, b),
          destroyed: Enum.uniq([b | side.destroyed])
      }
    end)
    |> log({:destroyed, s, b})
    |> deal({:building, s, :base}, 2)
  end

  # -- upkeep -----------------------------------------------------------------------------------

  @doc """
  The "Upkeep:" abilities of side `s`: healing (each Helpful Turtle heals 1 from
  all your units and heroes), Star-Crossed Starlet takes 1 damage.
  """
  def upkeep(game, s) do
    in_play = Zones.in_play(game, s)
    healers = for h <- in_play, n = CardRules.keyword(game.cards[h].card, :healing), do: n

    forces = Enum.filter(in_play, &Stats.force?(game, &1))

    game =
      Enum.reduce(healers, game, fn n, game -> Enum.reduce(forces, game, &heal(&2, &1, n)) end)

    Enum.reduce(in_play, game, fn id, game ->
      if game.cards[id].card == "star-crossed-starlet", do: deal(game, id, 1), else: game
    end)
  end

  @doc false
  def log(game, event), do: %{game | log: [event | game.log]}
end
