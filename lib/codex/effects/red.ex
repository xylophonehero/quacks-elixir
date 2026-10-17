defmodule Codex.Effects.Red do
  @moduledoc """
  The Red card texts (Blood Anarchs): the starting deck, the heroes Captain
  Zane, Drakk Ramhorn and Jaina Stormborne, and the Anarchy, Blood and Fire
  codex cards. Called by `Codex.Effects`; damage from Red spells and abilities
  goes through `Codex.Effects.burn/5` (Hotter Fire).
  """

  alias Codex.{Effects, Zones}

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

  def spell(game, _s, _slug, _id, _targets), do: game

  defp pirate?(game, id), do: Codex.Cards.fetch!(game.cards[id].card).subtype in ["Pirate"]

  # -- arrivals -------------------------------------------------------------------------------

  @doc "A Red unit's \"Arrives:\" ability."
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
  def ability(game, _s, _id, _name, _targets), do: game

  # Bombaster is sacrificed before its effect: its slug is still on the card.
  defp slug(game, id), do: game.cards[id].card

  # -- triggers -------------------------------------------------------------------------------

  @doc """
  Death triggers of Red cards: Drakk Ramhorn ("Dies: 1 damage to each opposing
  base").
  """
  def dies(game, s, "drakk-ramhorn", _unit?, _commander?),
    do: Effects.burn(game, s, "drakk-ramhorn", {:building, 1 - s, :base}, 1)

  def dies(game, _s, _slug, _unit?, _commander?), do: game

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

  @doc "Red \"Attacks:\" abilities (after the exhaust, before damage)."
  def attacks(game, _s, _a, _slug), do: game

  @doc """
  After a combat of attacker `a`: Captain Zane's middle band (he kills a
  scavenger: 1 gold; a technician: a card).
  """
  def after_combat(game, s, a, _target, %{killed?: true, slot: slot}) do
    c = game.cards[a]

    case {c.card, slot} do
      {"captain-zane", :scavenger} when c.level >= 4 -> Codex.Rules.gain_gold(game, s, 1)
      {"captain-zane", :technician} when c.level >= 4 -> Codex.Rules.draw(game, s, 1, :main)
      _ -> game
    end
  end

  def after_combat(game, _s, _a, _target, _ctx), do: game

  @doc "Red upkeep abilities of side `s`."
  def upkeep(game, _s), do: game

  @doc "Red end-of-turn abilities."
  def end_of_turn(game, _s), do: game
end
