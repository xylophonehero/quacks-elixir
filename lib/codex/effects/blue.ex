defmodule Codex.Effects.Blue do
  @moduledoc """
  The Blue card texts (Flagstone Dominion): the starting deck, the heroes Bigby
  Hayes, General Onimaru and Sirus Quince, and the Law, Peace and Truth codex
  cards. Called by `Codex.Effects`, `Codex.Combat` and `Codex.Rules`.
  """

  alias Codex.{Effects, Rules, Stats, Zones}

  # -- spells -----------------------------------------------------------------------------------

  @doc "Resolve a Blue spell."
  def spell(game, s, "lawful-search", _id, []), do: Rules.draw(game, s, 1, :main)
  def spell(game, _s, "arrest", _id, [t]), do: Effects.disable(game, t)

  # Manufactured Truth: one of your tech 0/I units becomes a copy of another tech 0/I unit until end of turn.
  def spell(game, _s, "manufactured-truth", _id, [mine, other])
      when is_integer(mine) and is_integer(other),
      do: Effects.copy(game, mine, game.cards[other].card, %{until: :end_of_turn})

  def spell(game, _s, _slug, _id, _targets), do: game

  # -- arrivals -------------------------------------------------------------------------------

  @doc "A Blue unit's \"Arrives:\" ability."
  # Reputable Newsman: the chosen cost (`:cost_n`) holds while he is in play.
  def arrive(game, _s, id, "reputable-newsman", [choice])
      when is_atom(choice) and choice != nil do
    "cost_" <> n = Atom.to_string(choice)
    Zones.update_card(game, id, &%{&1 | extra: Map.put(&1.extra, :number, String.to_integer(n))})
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

  @doc "\"Whenever you play a unit from your hand\" (nothing in the starting deck)."
  def played_unit(game, _s, _id), do: game

  @doc """
  Jail: an opposing unit played from the hand goes to jail (the trash, marked)
  instead of arriving. The unit already there is released and arrives in play
  for its owner (with its "Arrives:" ability, no targets). When the Jail leaves
  play, the jailed unit goes to its owner's discard pile (`Codex.Effects.leave/4`).
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

  def ability(game, _s, _id, _name, _targets), do: game

  # -- triggers -------------------------------------------------------------------------------

  @doc "General Onimaru, \"Max level: Summon three 1/1 blue Soldier tokens with sparkshot.\""
  def max_level(game, s, _id, "general-onimaru"), do: Effects.summon(game, s, "soldier", 3)
  def max_level(game, _s, _id, _slug), do: game

  @doc "A Blue building or upgrade comes into play."
  def permanent(game, _s, _id, _slug), do: game

  @doc "Blue \"Attacks:\" abilities (after the exhaust, before damage)."
  def attacks(game, _s, _a, _slug, _target), do: game

  @doc "Blue abilities after a combat."
  def after_combat(game, _s, _a, _target, _ctx), do: game

  @doc "Blue triggers when a card dies (`ctx` from `Codex.Effects.die/2`)."
  def died(game, _ctx), do: game

  @doc "Blue upkeep abilities of side `s`."
  def upkeep(game, _s), do: game

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

    if Stats.side_effect(game, s, :silenced) == game.sides[s].turn,
      do: Rules.update_side(game, s, &%{&1 | effects: Map.delete(&1.effects, :silenced)}),
      else: game
  end
end
