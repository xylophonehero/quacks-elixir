defmodule Quacks.GameHelpers do
  @moduledoc """
  Test helpers for hand-building and driving `Quacks.Game` structs. Most tests play
  seat 0 of a solo game, so every helper defaults to seat 0.
  """

  alias Quacks.{Game, Player}

  @game_keys [:round, :supply, :fortune_card, :fortune_deck]
  @shopping [:shop, :ready]

  @doc "Apply an action for `seat` (default 0), asserting it is legal."
  def apply!(game, seat \\ 0, action) do
    {:ok, game} = Game.apply(game, seat, action)
    game
  end

  @doc "Apply a list of seat-0 actions in order."
  def run(game, actions), do: Enum.reduce(actions, game, &apply!(&2, &1))

  @doc "Draw exactly these chips, in order, by replacing the bag before each draw."
  def force_draws(game, seat \\ 0, chips),
    do: Enum.reduce(chips, game, &apply!(put(&2, seat, bag: [&1]), seat, :draw))

  @doc """
  Set fields on the game or on `seat`'s player. `phase: :over` sets the game phase.
  `phase: :shop | :ready` puts the game in `:shopping`; when it was not shopping yet,
  every seat gets that sub-phase. Shorthands: `phase: :buy` is `:shop`; `phase:
  :rubies` is `:shop` after the buy (`bought?: true`). Any other `phase:` is the
  player's own phase. `round:`, `supply:`, `fortune_card:` and `fortune_deck:` are
  game fields; the rest are player fields. Unknown keys raise.
  """
  def put(game, seat \\ 0, fields) do
    Enum.reduce(fields, game, fn
      {:phase, :over}, g ->
        %{g | phase: :over}

      {:phase, :buy}, g ->
        put(g, seat, phase: :shop)

      {:phase, :rubies}, %{phase: :shopping} = g ->
        put(g, seat, phase: :shop, bought?: true)

      {:phase, :rubies}, g ->
        g = put(g, seat, phase: :shop)
        %{g | players: Map.new(g.players, fn {s, p} -> {s, %{p | bought?: true}} end)}

      {:phase, sub}, %{phase: :shopping} = g when sub in @shopping ->
        put_in(g.players[seat].phase, sub)

      {:phase, sub}, g when sub in @shopping ->
        players = Map.new(g.players, fn {s, p} -> {s, %{p | phase: sub}} end)
        %{g | phase: :shopping, players: players}

      {:phase, phase}, g ->
        put_in(g.players[seat].phase, phase)

      {key, value}, g when key in @game_keys ->
        Map.replace!(g, key, value)

      {key, value}, g ->
        put_in(g.players[seat], Map.replace!(g.players[seat], key, value))
    end)
  end

  @doc "The player at `seat` (default 0)."
  def me(game, seat \\ 0), do: game.players[seat]

  @doc """
  Every chip in the game per kind: supply + all bags, pots, overflow bowls, offers
  (blue, cards, the silver witch S2) and red chips beside pots.
  """
  def inventory(g) do
    chips =
      g.players
      |> Map.values()
      |> Enum.flat_map(
        &(&1.bag ++ Player.pot_chips(&1) ++ &1.bowl ++ &1.pending ++ &1.witch_offer ++ &1.aside)
      )
      |> Enum.frequencies()

    Map.merge(g.supply, chips, fn _chip, a, b -> a + b end)
  end
end
