defmodule Quacks.GameHelpers do
  @moduledoc """
  Test helpers for hand-building and driving `Quacks.Game` structs. Most tests play
  seat 0 of a solo game, so every helper defaults to seat 0.
  """

  alias Quacks.{Game, Player}

  @game_keys [:round, :supply, :turn, :fortune_card, :fortune_deck]
  @game_phases [:buy_chips, :spend_rubies, :over]

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
  Set fields on the game or on `seat`'s player. `phase:` sets the game phase (and
  makes `seat` the turn) for `:buy_chips`, `:spend_rubies` and `:over`, otherwise the
  player's own phase. `round:`, `supply:`, `turn:`, `fortune_card:` and
  `fortune_deck:` are game fields; the rest are player fields. Unknown keys raise.
  """
  def put(game, seat \\ 0, fields) do
    Enum.reduce(fields, game, fn
      {:phase, phase}, g when phase in @game_phases -> %{g | phase: phase, turn: seat}
      {:phase, phase}, g -> put_in(g.players[seat].phase, phase)
      {key, value}, g when key in @game_keys -> Map.replace!(g, key, value)
      {key, value}, g -> put_in(g.players[seat], Map.replace!(g.players[seat], key, value))
    end)
  end

  @doc "The player at `seat` (default 0)."
  def me(game, seat \\ 0), do: game.players[seat]

  @doc "Every chip in the game per kind: supply + all bags, pots and blue offers."
  def inventory(g) do
    chips =
      g.players
      |> Map.values()
      |> Enum.flat_map(&(&1.bag ++ Player.pot_chips(&1) ++ &1.pending))
      |> Enum.frequencies()

    Map.merge(g.supply, chips, fn _chip, a, b -> a + b end)
  end
end
