defmodule Codex.Effects.Blue do
  @moduledoc """
  The Blue card texts (Flagstone Dominion): the starting deck, the heroes Bigby
  Hayes, General Onimaru and Sirus Quince, and the Law, Peace and Truth codex
  cards. Called by `Codex.Effects`, `Codex.Combat` and `Codex.Rules`.
  """

  alias Codex.{Effects, Rules, Stats, Zones}

  # -- spells -----------------------------------------------------------------------------------

  @doc "Resolve a Blue spell."
  # Lawful Search: draw a card. # REVIEW: the look at a hand or discard pile has
  # no effect in the engine (the hot-seat page shows both hands).
  def spell(game, s, "lawful-search", _id, []), do: Rules.draw(game, s, 1, :main)
  def spell(game, _s, "arrest", _id, [t]), do: Effects.disable(game, t)

  # Manufactured Truth: one of your tech 0/I units becomes a copy of another tech 0/I unit until end of turn.
  def spell(game, _s, "manufactured-truth", _id, [mine, other])
      when is_integer(mine) and is_integer(other),
      do: Effects.copy(game, mine, game.cards[other].card, %{until: :end_of_turn})

  # -- Law --

  # Injunction: disable a tech I/II building (not operational on its side's
  # next turn, `Codex.Rules`) and all of that player's units of its tech level.
  def spell(game, _s, "injunction", _id, [{:building, seat, b}]) do
    level = if b == :tech_1, do: 1, else: 2

    units =
      for id <- Zones.in_play(game, seat),
          Stats.unit?(game, id),
          Stats.tech(game, id) == level,
          do: id

    until = game.sides[seat].turn + 1

    units
    |> Enum.reduce(game, &Effects.disable(&2, &1))
    |> Rules.update_side(seat, &%{&1 | effects: Map.put(&1.effects, :injunction, {b, until})})
  end

  # Community Service: a tech I or II unit from an opponent's discard pile or
  # hand into play under your control (free, no tech building).
  # REVIEW: the engine picks the unit with the highest cost (the hand first on a tie).
  def spell(game, s, "community-service", _id, []) do
    opp = game.sides[1 - s].zones

    unit =
      (opp.hand ++ opp.discard)
      |> Enum.filter(&(Stats.unit?(game, &1) and Stats.tech(game, &1) in [1, 2]))
      |> Enum.max_by(&(Codex.Cards.fetch!(game.cards[&1].card).cost || 0), fn -> nil end)

    if unit, do: Effects.enter(game, s, unit, []), else: game
  end

  # Jurisdiction: play the codex spell (its cost is paid, `Codex.Rules`), then it is discarded.
  def spell(game, s, "jurisdiction", _id, [c | targets]), do: Effects.cast(game, s, c, targets)

  # Judgment Day: destroy all tech 0, I and II units.
  def spell(game, _s, "judgment-day", _id, []) do
    units =
      for seat <- [0, 1],
          id <- Zones.in_play(game, seat),
          Stats.unit?(game, id),
          Stats.tech(game, id) in [0, 1, 2],
          do: id

    Enum.reduce(units, game, fn id, game ->
      if in_play?(game, id), do: Effects.destroy(game, id), else: game
    end)
  end

  # -- Peace --

  # Boot Camp: exhaust a unit or non-Peace hero, a +1/+1 rune on it; draw a card.
  def spell(game, s, "boot-camp", _id, [t]) do
    game
    |> Effects.exhaust(t)
    |> Zones.update_card(t, &%{&1 | exhausted: true})
    |> Effects.plus_rune(t)
    |> Rules.draw(s, 1, :main)
  end

  # Elite Training: up to two of yours get +1 ATK, +1 armor, anti-air and
  # sparkshot until your next upkeep (`Codex.Stats`; `upkeep/2` ends it).
  def spell(game, _s, "elite-training", _id, targets) do
    targets
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(game, fn t, game -> Effects.add_counter(game, t, :elite, 1) end)
  end

  def spell(game, s, "general-s-hammer", _id, [t]),
    do: Effects.burn(game, s, "general-s-hammer", t, 3)

  # The Art of War: your Peace hero is unstoppable, has swift strike and +2 ATK / +2 armor until your next upkeep.
  def spell(game, s, "the-art-of-war", _id, [hero]),
    do: Zones.update_card(game, hero, &%{&1 | extra: Map.put(&1.extra, :art_of_war, s)})

  # -- Truth --

  # Free Speech: silence an opponent until after its next turn (`Codex.Stats.silenced?/2`).
  def spell(game, s, "free-speech", _id, []) do
    until = game.sides[1 - s].turn + 1
    Rules.update_side(game, 1 - s, &%{&1 | effects: Map.put(&1.effects, :silenced, until)})
  end

  # Hallucination: up to two tech 0-II units are Illusions this turn.
  def spell(game, _s, "hallucination", _id, targets) do
    targets
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(game, fn t, game ->
      Zones.update_card(game, t, &%{&1 | this_turn: Map.put(&1.this_turn, :illusion, true)})
    end)
  end

  def spell(game, _s, "dreamscape", _id, []), do: game

  # Mind Control: attach to a tech 0-II unit; you control it. When Mind Control
  # leaves play, the unit goes back to the side that had it (`Codex.Rules`).
  def spell(game, s, "mind-control", id, [t]) when is_integer(t) do
    from = Stats.controller(game, t)

    game
    |> Zones.update_card(id, &%{&1 | extra: Map.put(&1.extra, :attached, t)})
    |> Effects.take_control(s, t)
    |> Zones.update_card(t, &%{&1 | extra: Map.put(&1.extra, :mind_control, {id, from})})
  end

  def spell(game, _s, _slug, _id, _targets), do: game

  defp in_play?(game, id), do: Zones.zone_name(Zones.locate(game, id)) in [:in_play, :patrol]

  # -- arrivals -------------------------------------------------------------------------------

  @doc "A Blue unit's \"Arrives:\" ability."
  # Reputable Newsman: the chosen cost (`:cost_n`) holds while he is in play.
  def arrive(game, _s, id, "reputable-newsman", [choice])
      when is_atom(choice) and choice != nil do
    "cost_" <> n = Atom.to_string(choice)
    Zones.update_card(game, id, &%{&1 | extra: Map.put(&1.extra, :number, String.to_integer(n))})
  end

  def arrive(game, s, _id, "tax-collector", []), do: Effects.steal(game, s, 1 - s, 1)
  def arrive(game, s, _id, "scribe", []), do: Rules.draw(game, s, 1, :main)

  # Insurance Agent: an insurance rune on a unit; when it dies, this agent's
  # controller gains its cost in gold and draws (`died/2`).
  def arrive(game, _s, id, "insurance-agent", [t]) when is_integer(t) do
    Zones.update_card(game, t, fn c ->
      %{c | extra: Map.update(c.extra, :insured_by, [id], &[id | &1])}
    end)
  end

  def arrive(game, _s, _id, _slug, _targets), do: game

  @doc """
  "Whenever a unit of yours arrives": Sirus Quince at max level makes one of
  your Mirror Illusions an Illusion copy of a non-token unit; it is trashed
  when Quince or the original leaves play (`Codex.Rules`).
  # REVIEW: the engine always makes the copy ("you may") with the first plain Mirror.
  """
  def arrived(game, s, id) do
    quince =
      Enum.find(Zones.in_play(game, s), fn h ->
        game.cards[h].card == "sirus-quince" and game.cards[h].level >= 5 and
          not Stats.silenced?(game, h)
      end)

    mirror = Enum.find(Zones.in_play(game, s), &(game.cards[&1].card == "mirror-illusion"))

    if quince && mirror && id != mirror && Stats.unit?(game, id) && not Stats.token?(game, id),
      do: Effects.copy(game, mirror, game.cards[id].card, %{illusion: true, bound: [quince, id]}),
      else: game
  end

  @doc """
  "Whenever you play a unit from your hand": Drill Sergeant gets a +1/+1 rune,
  Flagstone Garrison draws a card (rulings: not a unit put into play by an
  effect, not a spell that summons).
  """
  def played_unit(game, s, _id) do
    Enum.reduce(Zones.in_play(game, s), game, fn c, game ->
      case game.cards[c].card do
        "drill-sergeant" -> Effects.plus_rune(game, c)
        "flagstone-garrison" -> Rules.draw(game, s, 1, :main)
        _ -> game
      end
    end)
  end

  @doc """
  Jail: an opposing unit played from the hand goes to jail (the trash, marked)
  instead of arriving. The unit already there is released and arrives in play
  for its owner (with its "Arrives:" ability, no targets). When the Jail leaves
  play, the jailed unit goes to its owner's discard pile (`Codex.Effects.leave/4`).
  # REVIEW: the engine has no Jail zone: the jailed unit waits in the trash,
  # marked; a released unit's "Arrives:" ability gets no targets.
  """
  def jail(game, jail, id) do
    held = Map.get(game.cards[jail].extra, :holds, [])

    game =
      game
      |> Zones.move(id, :trash)
      |> Zones.update_card(id, &%{&1 | extra: Map.put(&1.extra, :jailed_in, jail)})
      |> Zones.update_card(jail, &%{&1 | extra: Map.put(&1.extra, :holds, [id])})
      |> Effects.log({:jailed, id})

    Enum.reduce(held, game, fn h, game ->
      if h in game.trash do
        game
        |> Zones.update_card(h, &%{&1 | extra: Map.delete(&1.extra, :jailed_in)})
        |> Effects.enter(game.cards[h].seat, h, [])
        |> Effects.log({:released, h})
      else
        game
      end
    end)
  end

  # -- abilities ------------------------------------------------------------------------------

  @doc "A Blue activated ability (costs paid)."
  # Porkhand Magistrate: disable a unit or hero; its controller draws a card.
  def ability(game, _s, _id, :magistrate, [t]) when is_integer(t) do
    owner = Stats.controller(game, t)
    game |> Effects.disable(t) |> Rules.draw(owner, 1, :main)
  end

  # Bigby Hayes, stash: keep this card in the draw/discard step (`Codex.Rules`).
  def ability(game, s, _id, :stash, [card]) do
    Rules.update_side(game, s, fn side ->
      %{side | effects: side.effects |> Map.put(:stash, true) |> Map.put(:stash_card, card)}
    end)
  end

  def ability(game, s, _id, :bigby_draw, []), do: Rules.draw(game, s, 1, :main)

  # Sirus Quince: another Mirror Illusion (at most 2).
  def ability(game, s, _id, :mirror, []), do: Effects.summon(game, s, "mirror-illusion")

  # Sirus Quince, middle band: a Mirror becomes an Illusion copy of a tech 0-II
  # unit; it is trashed at the end of the turn.
  def ability(game, _s, _id, :mirror_copy, [mirror, unit])
      when is_integer(mirror) and is_integer(unit) do
    Effects.copy(game, mirror, game.cards[unit].card, %{illusion: true, until: :trash})
  end

  # Drill Sergeant: remove a +1/+1 rune (paid) → a +1/+1 rune on another unit.
  def ability(game, _s, _id, :rune_move, [t]), do: Effects.plus_rune(game, t)

  # Eyes of the Chancellor: a friendly unit is invisible until your next upkeep.
  def ability(game, s, _id, :eyes, [t]),
    do: Zones.update_card(game, t, &%{&1 | extra: Map.put(&1.extra, :eyes, s)})

  # Arresting Constable: disable a tech 0, I or II unit.
  def ability(game, _s, _id, :arrest, [t]), do: Effects.disable(game, t)

  def ability(game, _s, _id, _name, _targets), do: game

  # -- triggers -------------------------------------------------------------------------------

  @doc "General Onimaru, \"Max level: Summon three 1/1 blue Soldier tokens with sparkshot.\""
  def max_level(game, s, _id, "general-onimaru"), do: Effects.summon(game, s, "soldier", 3)
  def max_level(game, _s, _id, _slug), do: game

  @doc "A Blue building or upgrade comes into play."
  def permanent(game, _s, _id, _slug), do: game

  @doc "Blue \"Attacks:\" abilities (after the exhaust, before damage)."
  def attacks(game, _s, _a, _slug, _target), do: game

  @doc """
  Blue abilities after a combat: Guardian of the Gates disables a unit it
  dealt combat damage to (rulings: also when armor took it all).
  """
  def after_combat(game, s, a, target, ctx) do
    guardian? = is_integer(target) and game.cards[target].card == "guardian-of-the-gates"
    struck? = ctx.back > 0 and not (ctx.first == :attacker and not in_play?(game, target))

    game =
      if guardian? and struck? and in_play?(game, a) and Stats.unit?(game, a),
        do: Effects.disable(game, a),
        else: game

    game |> spy(s, a, ctx) |> patriot(s, a, target, ctx)
  end

  # Flagstone Spy deals combat damage to a building: steal 1 gold (seeing the hand changes nothing here).
  defp spy(game, s, a, %{building_hit: true}) do
    if game.cards[a].card == "flagstone-spy", do: Effects.steal(game, s, 1 - s, 1), else: game
  end

  defp spy(game, _s, _a, _ctx), do: game

  # Patriot Gryphon destroys a building: he deals his ATK to that opponent's base too.
  defp patriot(game, s, a, target, %{building_hit: true}) do
    destroyed? =
      case target do
        {:building, opp, b} when b != :base -> b not in game.sides[opp].tech_buildings
        id when is_integer(id) -> not in_play?(game, id)
        _ -> false
      end

    if game.cards[a].card == "patriot-gryphon" and destroyed? and in_play?(game, a),
      do: Effects.deal(game, {:building, 1 - s, :base}, max(Stats.atk(game, a), 0)),
      else: game
  end

  defp patriot(game, _s, _a, _target, _ctx), do: game

  @doc """
  Blue triggers when a card dies (`ctx` from `Codex.Effects.die/2`): an
  insured unit pays its cost in gold and a card to each Insurance Agent still
  in play that insured it; Reteller of Truths returns an Illusion.
  """
  def died(game, ctx), do: game |> insurance(ctx) |> reteller(ctx)

  defp insurance(game, %{insured: [_ | _] = agents, slug: slug}) do
    cost = Codex.Cards.fetch!(slug).cost || 0

    agents
    |> Enum.filter(&in_play?(game, &1))
    |> Enum.reduce(game, fn agent, game ->
      s = Stats.controller(game, agent)
      game |> Rules.gain_gold(s, cost) |> Rules.draw(s, 1, :free)
    end)
  end

  defp insurance(game, _ctx), do: game

  # Reteller of Truths: the first two times each turn one of your non-token
  # Illusion units dies (Reteller too), it returns to its owner's hand.
  defp reteller(
         game,
         %{illusion?: true, token?: false, unit?: true, s: s, id: id, owner: owner} = ctx
       ) do
    key = {:retold, game.active, game.sides[game.active].turn}
    used = Map.get(game.sides[s].effects, key, 0)
    reteller? = ctx.slug == "reteller-of-truths" or Stats.controls?(game, s, "reteller-of-truths")

    if reteller? and used < 2 and id in game.sides[owner].zones.discard do
      game
      |> Zones.move(id, {owner, :hand})
      |> Rules.update_side(s, &%{&1 | effects: Map.put(&1.effects, key, used + 1)})
      |> Effects.log({:returns, id})
    else
      game
    end
  end

  defp reteller(game, _ctx), do: game

  @doc "Blue upkeep abilities of side `s`: Elite Training and The Art of War end."
  def upkeep(game, s) do
    Enum.reduce(game.cards, game, fn {id, c}, game ->
      cond do
        Map.get(c.extra, :art_of_war) == s ->
          Zones.update_card(game, id, &%{&1 | extra: Map.delete(&1.extra, :art_of_war)})

        Map.has_key?(c.extra, :elite) and Stats.controller(game, id) == s ->
          Zones.update_card(game, id, &%{&1 | extra: Map.delete(&1.extra, :elite)})

        Map.get(c.extra, :eyes) == s ->
          Zones.update_card(game, id, &%{&1 | extra: Map.delete(&1.extra, :eyes)})

        true ->
          game
      end
    end)
  end

  @doc """
  The end of side `s`'s turn: copies "until end of turn" end (Manufactured
  Truth), Sirus Quince's copies are trashed, and a silence of `s` (Free
  Speech) ends after its turn.
  """
  def end_of_turn(game, s) do
    copies =
      for seat <- [0, 1],
          id <- Zones.in_play(game, seat),
          until = get_in(game.cards[id].extra, [:copy, :until]),
          do: {id, until}

    game =
      Enum.reduce(copies, game, fn
        {id, :end_of_turn}, game -> Effects.uncopy(game, id)
        {id, :trash}, game -> Effects.trash(game, id)
      end)

    turn = game.sides[s].turn

    game =
      if Stats.side_effect(game, s, :silenced) == turn,
        do: Rules.update_side(game, s, &%{&1 | effects: Map.delete(&1.effects, :silenced)}),
        else: game

    # Injunction: its building works again after that side's turn.
    case Stats.side_effect(game, s, :injunction) do
      {_b, ^turn} ->
        Rules.update_side(game, s, &%{&1 | effects: Map.delete(&1.effects, :injunction)})

      _ ->
        game
    end
  end
end
