defmodule Codex.Effects.Green do
  @moduledoc """
  The Green card texts (Moss Sentinels): the starting deck, the heroes Master
  Midori, Calamandra Moss and Argagarg Garg, and the Balance, Feral and Growth
  codex cards. Called by `Codex.Effects`.
  """

  alias Codex.{Effects, Rules, Zones}

  # -- spells -----------------------------------------------------------------------------------

  @doc "Resolve a Green spell."
  def spell(game, _s, "rampant-growth", _id, [t]), do: more(game, t, 2, 2)
  def spell(game, _s, "forest-s-favor", _id, [t]), do: Effects.plus_rune(game, t)
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

  @doc "Green \"Attacks:\" abilities (after the exhaust, before damage)."
  def attacks(game, _s, _a, _slug), do: game

  @doc "Green abilities after a combat."
  def after_combat(game, _s, _a, _target, _ctx), do: game

  @doc "Green upkeep abilities of side `s`."
  def upkeep(game, _s), do: game
end
