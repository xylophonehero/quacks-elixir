defmodule Codex.Effects do
  @moduledoc """
  What the cards do: damage, healing, death and its triggers, playing spells
  and permanents, "Arrives:", activated abilities, "Upkeep:" and end-of-turn
  abilities (research §5, §10, §16; rulebook S1). Each function takes the game
  and returns the game. Targets are checked before (`Codex.Targets`).

  The neutral cards are here; the Red and Green card texts are in
  `Codex.Effects.Red` and `Codex.Effects.Green`.

  A target is a card id, a building `{:building, seat, name}` (`:base`, a tech
  building or an add-on), or a worker `{:worker, seat}`.
  """

  alias Codex.{CardRules, Cards, Rules, Stats, Zones}
  alias Codex.Effects.{Green, Red}

  @building_hp %{
    base: 20,
    tech_1: 5,
    tech_2: 5,
    tech_3: 5,
    tower: 4,
    surplus: 4,
    tech_lab: 4,
    heroes_hall: 4
  }
  @dancer_limit 3
  @blood_limit 4

  @doc "The HP of a building."
  def building_hp(name), do: Map.fetch!(@building_hp, name)

  # -- damage ---------------------------------------------------------------------------------

  @doc """
  Deal `n` damage to a card or a building. Armor takes it first (the squad
  leader's, Ironbark Treant's, this turn's; S1 p. 5, p. 19). A tech building
  or add-on that reaches its HP is destroyed and its base takes 2 damage (S1
  p. 4). A building card takes damage like a unit.
  """
  def deal(game, target, n, opts \\ [])
  def deal(game, _target, n, _opts) when n <= 0, do: game
  def deal(game, nil, _n, _opts), do: game

  def deal(game, {:building, s, :base}, n, _opts),
    do: Rules.update_side(game, s, &%{&1 | base_hp: &1.base_hp - n})

  def deal(game, {:building, s, b}, n, _opts) do
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

  def deal(game, id, n, opts) when is_integer(id) do
    {n, game} = if opts[:piercing], do: {n, game}, else: armor(game, id, n)
    Zones.update_card(game, id, &%{&1 | damage: &1.damage + n})
  end

  def deal(game, _target, _n, _opts), do: game

  # Armor absorbs damage before HP, then it is gone for the turn (S1 p. 5, p. 19).
  defp armor(game, id, n) do
    absorbed = if Stats.force?(game, id), do: min(n, Stats.armor(game, id)), else: 0

    if absorbed > 0,
      do:
        {n - absorbed, Zones.update_card(game, id, &%{&1 | armor_dmg: &1.armor_dmg + absorbed})},
      else: {n, game}
  end

  @doc """
  Damage from a spell or an ability of side `s` from card `slug`: Hotter Fire
  adds 1 to red spells and abilities (rulings: each one stacks).
  """
  def ability_damage(game, s, slug, n) do
    if Cards.fetch!(slug).color == "Red",
      do: n + Enum.count(Zones.in_play(game, s), &(game.cards[&1].card == "hotter-fire")),
      else: n
  end

  @doc "Deal spell or ability damage (`ability_damage/4`) from `slug` of side `s`."
  def burn(game, s, slug, target, n), do: deal(game, target, ability_damage(game, s, slug, n))

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

  def repair(game, id, n) when is_integer(id), do: heal(game, id, n)

  @doc "The damage on a building."
  def building_damage(game, {:building, s, :base}), do: 20 - game.sides[s].base_hp
  def building_damage(game, {:building, s, b}), do: Map.get(game.sides[s].building_damage, b, 0)
  def building_damage(game, id) when is_integer(id), do: game.cards[id].damage

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

  @doc "Add `n` to a counter in a card's `extra` (blood runes, growth runes), at most `limit`."
  def add_counter(game, id, key, n, limit \\ 99) do
    Zones.update_card(game, id, fn c ->
      %{c | extra: Map.update(c.extra, key, min(n, limit), &min(&1 + n, limit))}
    end)
  end

  # -- tokens and control ---------------------------------------------------------------------

  @doc "Summon `n` tokens `slug` for side `s` (in play, with arrival fatigue). Returns the game."
  def summon(game, s, slug, n \\ 1) do
    {game, ids} = Codex.Game.add_cards(game, s, List.duplicate(slug, n))

    Enum.reduce(ids, game, fn id, game ->
      game
      |> Zones.insert(id, {s, :in_play}, nil)
      |> Zones.update_card(id, &%{&1 | fatigued: true})
    end)
    |> log({:summon, s, slug, n})
  end

  @doc "Side `s` gains control of card `id` (it arrives with arrival fatigue)."
  def take_control(game, s, id) do
    game
    |> Zones.move(id, {s, :in_play})
    |> Zones.update_card(id, &%{&1 | fatigued: true})
  end

  @doc "Trash a worker of side `seat` (workers are all alike: the first one)."
  def trash_worker(game, seat) do
    case game.sides[seat].zones.workers do
      [w | _] -> game |> leave(w, :trash, nil) |> log({:worker_trashed, seat})
      [] -> game
    end
  end

  @doc "Steal up to `n` gold from side `from` for side `to` (as much as it has)."
  def steal(game, to, from, n) do
    taken = min(n, game.sides[from].gold)

    game
    |> Rules.update_side(from, &%{&1 | gold: &1.gold - taken})
    |> Rules.gain_gold(to, taken)
  end

  # -- leaving play -------------------------------------------------------------------------------

  @doc """
  A unit, hero or building card dies (or is destroyed). A unit goes to its
  owner's discard pile; a token to the trash ("destroyed"); a hero to its
  owner's command zone, back to level 1, and it cannot be summoned until after
  its owner's next turn; one opposing hero in play gets 2 free levels (S1 p. 3).
  A patroller that dies in the scavenger slot gives its side 1 gold, in the
  technician slot a card (S1 p. 5). Then the death triggers.
  """
  def die(game, id) do
    c = game.cards[id]
    loc = Zones.locate(game, id)
    s = Zones.zone_seat(loc)
    slot = if Stats.patrolling?(game, id), do: elem(loc, 2)
    unit? = Stats.unit?(game, id)
    commander? = unit? and Stats.controls?(game, s, "pirate-gang-commander")
    game = log(game, {:dies, id})

    game =
      cond do
        Stats.token?(game, id) ->
          leave(game, id, :trash, nil)

        Stats.hero?(game, id) ->
          owner = c.seat
          turn = game.sides[owner].turn

          game
          |> leave(id, {owner, :command}, nil)
          |> Rules.update_side(
            owner,
            &%{&1 | summon_after: Map.put(&1.summon_after, id, turn + 1)}
          )
          |> free_levels(1 - s)

        true ->
          leave(game, id, {c.seat, :discard}, 0)
      end

    game
    |> patrol_bonus(s, slot)
    |> Red.dies(s, c.card, unit?, commander?)
    |> unit_died(unit?)
  end

  defp patrol_bonus(game, s, :scavenger), do: Rules.gain_gold(game, s, 1)
  defp patrol_bonus(game, s, :technician), do: Rules.draw(game, s, 1, :free)
  defp patrol_bonus(game, _s, _slot), do: game

  # "Whenever a unit dies": Bloodburn gets a blood rune (limit 4); Captured
  # Bugblatter hits the base of its controller's opponent.
  defp unit_died(game, false), do: game

  defp unit_died(game, true) do
    Enum.reduce(for(s <- [0, 1], id <- Zones.in_play(game, s), do: {s, id}), game, fn {s, id},
                                                                                      game ->
      case game.cards[id].card do
        "bloodburn" ->
          add_counter(game, id, :blood, 1, @blood_limit)

        "captured-bugblatter" ->
          burn(game, s, "captured-bugblatter", {:building, 1 - s, :base}, 1)

        _ ->
          game
      end
    end)
  end

  # One hero of side `s` in play that can level up gets 2 levels.
  # REVIEW: with several, the first that can level (the active side picks; the
  # engine picks for it).
  defp free_levels(game, s) do
    hero =
      Enum.find(Zones.in_play(game, s), fn h ->
        Stats.hero?(game, h) and game.cards[h].level < Cards.max_level(game.cards[h].card)
      end)

    if hero, do: game |> level_up(hero, 2) |> log({:free_levels, hero}), else: game
  end

  @doc """
  Level up a hero by `n` (at most its max level). Reaching the middle band or the
  max level heals all its damage (S1 p. 3). Reaching the max level triggers
  "Max level:" (Captain Zane, Argagarg Garg).
  """
  def level_up(game, id, n) do
    c = game.cards[id]
    [_, %{level: mid}, %{level: max}] = Cards.fetch!(c.card).bands
    new = min(c.level + n, max)
    healed? = (c.level < mid and new >= mid) or (c.level < max and new >= max)

    game =
      Zones.update_card(game, id, fn c ->
        %{c | level: new, damage: if(healed?, do: 0, else: c.damage)}
      end)

    if c.level < max and new >= max, do: max_level(game, id), else: game
  end

  defp max_level(game, id) do
    s = Stats.controller(game, id)

    case game.cards[id].card do
      "captain-zane" -> Red.zane_max(game, s, id)
      "argagarg-garg" -> summon(game, s, "water-elemental")
      _ -> game
    end
  end

  @doc "Move a card out of play to `zone`, with its state reset (`Codex.Rules.reset/1`)."
  def leave(game, id, zone, at) do
    game |> Zones.move(id, zone, at) |> Zones.update_card(id, &Rules.reset/1)
  end

  @doc """
  Sacrifice a card you control: a unit or hero dies; a worker is trashed; an
  ongoing spell, upgrade or building card goes to its owner's discard pile.
  """
  def sacrifice(game, id) do
    c = game.cards[id]

    cond do
      Stats.force?(game, id) -> die(game, id)
      Zones.zone_name(Zones.locate(game, id)) == :workers -> leave(game, id, :trash, nil)
      true -> game |> log({:sacrificed, id}) |> leave(id, {c.seat, :discard}, 0)
    end
  end

  @doc "Destroy a card in play (a building card or an upgrade too)."
  def destroy(game, {:worker, seat}), do: trash_worker(game, seat)

  def destroy(game, id) do
    if Stats.force?(game, id),
      do: die(game, id),
      else: game |> log({:destroyed_card, id}) |> leave(id, {game.cards[id].seat, :discard}, 0)
  end

  @doc "Trash a card in play or a worker (removed from the game)."
  def trash(game, {:worker, seat}), do: trash_worker(game, seat)
  def trash(game, id), do: game |> log({:trashed, id}) |> leave(id, :trash, nil)

  @doc "Exhaust a card. Rampaging Elephant readies the first time each turn. An exhausted card cannot patrol."
  def exhaust(game, id) do
    c = game.cards[id]

    if c.card == "rampaging-elephant" and not Map.get(c.this_turn, :readied, false) do
      Zones.update_card(game, id, &%{&1 | this_turn: Map.put(&1.this_turn, :readied, true)})
    else
      game
      |> Zones.update_card(id, &%{&1 | exhausted: true})
      |> sideline(id)
    end
  end

  # -- spells -----------------------------------------------------------------------------------

  @doc """
  Resolve spell `id` of side `s` with `targets`. A one-shot spell then goes to
  its owner's discard pile (Appel Stomp: on top of the draw pile; Detonate,
  Nature Reclaims and Desperation trash themselves); an ongoing spell stays in
  play. A "manual" spell goes into play for a player to resolve in free mode.
  Then each Harmony of `s` (not the spell itself) makes a Dancer (limit 3).
  """
  def cast(game, s, id, targets) do
    c = game.cards[id]

    game =
      Rules.update_side(
        game,
        s,
        &%{&1 | effects: Map.update(&1.effects, :spells, 1, fn n -> n + 1 end)}
      )

    game =
      if CardRules.manual?(c.card) do
        game
        |> Zones.move(id, {s, :in_play})
        |> Zones.update_card(id, &%{&1 | extra: Map.put(&1.extra, :manual, true)})
        |> log({:manual, id})
      else
        game = spell(game, s, c.card, id, targets)

        cond do
          not Map.has_key?(game.cards, id) or Zones.locate(game, id) == nil -> game
          Stats.ongoing?(game, id) -> Zones.move(game, id, {s, :in_play})
          c.card == "appel-stomp" -> Zones.move(game, id, {c.seat, :deck}, 0)
          c.card in ["detonate", "nature-reclaims", "desperation"] -> trash(game, id)
          true -> Zones.move(game, id, {c.seat, :discard}, 0)
        end
      end

    harmony(game, s, id)
  end

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
    if t2, do: take_control(game, s, t2), else: game
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

  defp spell(game, s, "appel-stomp", _id, [t]), do: game |> sideline(t) |> Rules.draw(s, 1, :main)

  defp spell(game, s, slug, id, targets) do
    case Cards.fetch!(slug).color do
      "Red" -> Red.spell(game, s, slug, id, targets)
      "Green" -> Green.spell(game, s, slug, id, targets)
    end
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
      game
      |> summon(s, "dancer")
      |> add_counter(h, :dancers, 1, @dancer_limit)
    end)
  end

  @doc ~s{Harmony's ability: sacrifice it to "stop the music": your Dancers flip to Angry Dancers.}
  def stop_music(game, s, harmony) do
    game = sacrifice(game, harmony)

    Enum.reduce(Zones.in_play(game, s), game, fn d, game ->
      if game.cards[d].card == "dancer",
        do: Zones.update_card(game, d, &%{&1 | card: "angry-dancer"}),
        else: game
    end)
  end

  @doc "Sideline: move a patroller out of the patrol zone (to in play)."
  def sideline(game, nil), do: game

  def sideline(game, id) do
    case Zones.locate(game, id) do
      {s, :patrol, _} -> Zones.move(game, id, {s, :in_play})
      _ -> game
    end
  end

  # -- permanents and arrivals ----------------------------------------------------------------

  @doc "A building or upgrade card comes into play (with arrival fatigue for its ⤵ abilities)."
  def permanent(game, s, id) do
    game
    |> Zones.move(id, {s, :in_play})
    |> Zones.update_card(id, &%{&1 | fatigued: true})
  end

  @doc """
  A unit arrives from the hand: into play with arrival fatigue. A legendary
  unit that its side already has goes to the discard pile instead (S1 p. 17).
  Drakk Ramhorn at max level gives the first one each turn haste. Then its
  "Arrives:" ability.
  """
  def arrive_from_hand(game, s, id, targets) do
    slug = game.cards[id].card
    legendary? = String.starts_with?(Cards.fetch!(slug).type, "Legendary")

    if legendary? and Stats.controls?(game, s, slug) do
      game |> Zones.move(id, {game.cards[id].seat, :discard}, 0) |> log({:legendary, id})
    else
      game
      |> Zones.move(id, {s, :in_play})
      |> Zones.update_card(
        id,
        &%{&1 | fatigued: true, this_turn: Map.put(&1.this_turn, :arrived, true)}
      )
      |> drakk_haste(s, id)
      |> arrive(s, id, targets)
    end
  end

  defp drakk_haste(game, s, id) do
    drakk? =
      Enum.any?(Zones.in_play(game, s), fn h ->
        game.cards[h].card == "drakk-ramhorn" and game.cards[h].level >= 6
      end)

    if drakk? and Stats.side_effect(game, s, :drakk_used) != true do
      game
      |> Zones.update_card(id, &%{&1 | extra: Map.put(&1.extra, :haste, true)})
      |> Rules.update_side(s, &%{&1 | effects: Map.put(&1.effects, :drakk_used, true)})
    else
      game
    end
  end

  @doc "A unit or hero of side `s` arrives: its \"Arrives:\" ability, then the triggers of others."
  def arrive(game, s, id, targets) do
    slug = game.cards[id].card

    game =
      case {slug, targets} do
        {"hired-stomper", [t]} -> deal(game, t, 3)
        {"brick-thief", [t]} -> brick(game, s, t)
        {"trojan-duck", [t]} -> deal(game, t, 4)
        {"sneaky-pig", []} -> Zones.update_card(game, id, &%{&1 | stealth: true})
        _ -> color_arrive(game, s, id, slug, targets)
      end

    arrived(game, s, id)
  end

  defp color_arrive(game, s, id, slug, targets) do
    cond do
      CardRules.manual?(slug) -> game
      Cards.fetch!(slug).color == "Red" -> Red.arrive(game, s, id, slug, targets)
      Cards.fetch!(slug).color == "Green" -> Green.arrive(game, s, id, slug, targets)
      true -> game
    end
  end

  # "Whenever another unit or hero of yours arrives": Blooming Ancient gets a +1/+1 rune.
  defp arrived(game, s, id) do
    Enum.reduce(Zones.in_play(game, s), game, fn b, game ->
      if b != id and game.cards[b].card == "blooming-ancient", do: plus_rune(game, b), else: game
    end)
  end

  @doc "A hero is summoned: Argagarg Garg's \"Arrives:\", then the triggers of others."
  def hero_arrives(game, s, id) do
    game = if game.cards[id].card == "argagarg-garg", do: summon(game, s, "wisp"), else: game
    arrived(game, s, id)
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

  # -- abilities ------------------------------------------------------------------------------

  @doc "The effect of an activated ability (its costs are paid by `Codex.Rules`)."
  def ability(game, _s, _id, :sideline, [t]), do: sideline(game, t)
  def ability(game, _s, _id, :wreck, [t]), do: deal(game, t, 2)
  def ability(game, s, id, :stop_music, []), do: stop_music(game, s, id)

  def ability(game, s, id, name, targets) do
    case Cards.fetch!(game.cards[id].card).color do
      "Red" -> Red.ability(game, s, id, name, targets)
      "Green" -> Green.ability(game, s, id, name, targets)
    end
  end

  # -- upkeep and the end of the turn ----------------------------------------------------------------

  @doc """
  The "Upkeep:" abilities of side `s`: healing (Helpful Turtle, Verdant Tree,
  Spirit of the Panda: heal 1 from all your units and heroes), Star-Crossed
  Starlet takes 1 damage, then the Red and Green upkeep abilities.
  """
  def upkeep(game, s) do
    in_play = Zones.in_play(game, s)
    healers = for h <- in_play, n = CardRules.keyword(game.cards[h].card, :healing), do: n
    panda = for h <- in_play, game.cards[h].card == "spirit-of-the-panda", do: 1
    forces = Enum.filter(in_play, &Stats.force?(game, &1))

    game =
      Enum.reduce(healers ++ panda, game, fn n, game ->
        Enum.reduce(forces, game, &heal(&2, &1, n))
      end)

    game =
      Enum.reduce(in_play, game, fn id, game ->
        if game.cards[id].card == "star-crossed-starlet", do: deal(game, id, 1), else: game
      end)

    game |> Red.upkeep(s) |> Green.upkeep(s)
  end

  @doc """
  The end of side `s`'s turn: Bloodlust's damage, Kidnapping ends, ephemeral
  units die (S1 p. 19; every turn).
  """
  def end_of_turn(game, s) do
    game = Red.end_of_turn(game, s)

    ephemeral =
      for seat <- [0, 1],
          id <- Zones.in_play(game, seat),
          Stats.unit?(game, id),
          Stats.kw?(game, id, :ephemeral) or Map.get(game.cards[id].extra, :ephemeral),
          do: id

    Enum.reduce(ephemeral, game, fn id, game ->
      if Zones.zone_name(Zones.locate(game, id)) in [:in_play, :patrol],
        do: die(game, id),
        else: game
    end)
  end

  @doc """
  The cards that go back to the hand after the draw: every Chameleon Lizzo, and
  side `s`'s Bloodrage Ogres that did not arrive or attack this turn.
  """
  def returns(game, s) do
    lizzos =
      for seat <- [0, 1],
          id <- Zones.in_play(game, seat),
          game.cards[id].card == "chameleon-lizzo",
          do: id

    ogres =
      for id <- Zones.in_play(game, s),
          c = game.cards[id],
          c.card == "bloodrage-ogre",
          not Map.get(c.this_turn, :arrived, false),
          not c.attacked,
          do: id

    lizzos ++ ogres
  end

  @doc "Return cards still in play to their owner's hand."
  def return_to_hand(game, ids) do
    Enum.reduce(ids, game, fn id, game ->
      if Zones.zone_name(Zones.locate(game, id)) in [:in_play, :patrol],
        do: game |> leave(id, {game.cards[id].seat, :hand}, nil) |> log({:returns, id}),
        else: game
    end)
  end

  @doc false
  def log(game, event), do: %{game | log: [event | game.log]}
end
