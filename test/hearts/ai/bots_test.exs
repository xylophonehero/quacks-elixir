defmodule Hearts.AI.BotsTest do
  use ExUnit.Case, async: true

  import Hearts.Scenario

  alias Hearts.AI.{Bench, Heuristic, Random}
  alias Hearts.Game

  doctest Random
  doctest Bench

  defp choose(game, seat), do: game |> Game.view(seat) |> Heuristic.choose(nil) |> elem(0)

  test "the heuristic passes the high spades first, then the high hearts" do
    game = at_play(%{0 => "QS AS 3S AH 2H KD 2C"}) |> Map.put(:phase, :passing)
    assert choose(game, 0) == {:pass, cards("QS AS AH")}
  end

  test "the heuristic ducks under the trick with its highest lower card" do
    game = at_play(%{0 => "2C", 1 => "3C 9C KC"}, tricks: 1, turn: 1, trick: [{0, card("10C")}])
    assert choose(game, 1) == {:play, card("9C")}
  end

  test "the heuristic dumps the Q♠ when void, then the highest heart" do
    game = at_play(%{0 => "2C", 1 => "QS AH 5D"}, tricks: 1, turn: 1, trick: [{0, card("10C")}])
    assert choose(game, 1) == {:play, card("QS")}
    game = at_play(%{0 => "2C", 1 => "4H AH 5D"}, tricks: 1, turn: 1, trick: [{0, card("10C")}])
    assert choose(game, 1) == {:play, card("AH")}
  end

  test "the heuristic does not win with the Q♠ when it has another card" do
    game = at_play(%{0 => "2C", 1 => "QS AS"}, tricks: 1, turn: 1, trick: [{0, card("10S")}])
    assert choose(game, 1) == {:play, card("AS")}
  end

  test "random and heuristic bots play only legal actions to the end" do
    result = Bench.run(games: 4, seed: 7)
    assert result.games == 4
    assert result.win_rate >= 0 and result.win_rate <= 1
  end

  test "the heuristic beats random bots" do
    result = Bench.run(games: 40, seed: 3)
    assert result.win_rate > result.baseline
  end
end
