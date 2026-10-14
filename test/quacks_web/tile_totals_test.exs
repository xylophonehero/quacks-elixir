defmodule QuacksWeb.TileTotalsTest do
  @moduledoc """
  Round 47 (audit #3): the tiles' and the pot's ruby counters while the steps
  play. They end on the seat's real rubies, also when this round's card (or an
  other line that is no step) gave rubies, and after a ruby spend.
  """
  use ExUnit.Case, async: true
  alias Quacks.Game
  alias QuacksWeb.{Replay, TileReveal}

  # Seat 0 got 2 rubies from "Give and take" (AP3) and 1 from the scoring space.
  defp game(rubies) do
    g = Game.new(seed: {1, 2, 3}, players: 2)

    %{g | phase: :shopping}
    |> Game.update_player(0, &%{&1 | rubies: rubies})
    |> Game.record(0, {:fortune, :ap3, :rubies})
    |> Game.record(0, {:pot_ruby, 12})
  end

  @space %{kind: :space, rows: [], gains: %{0 => {0, 1}, 1 => {0, 0}}}

  test "AP3's rubies choice gives 2 rubies, not 3" do
    assert Replay.gain({:fortune, :ap3, :rubies}) == {0, 2}
    assert Replay.gain({:fortune, :p1, :rubies}) == {0, 3}
  end

  test "after the last step the counter shows the seat's rubies (a card gave some)" do
    assert {_vp, 3} = TileReveal.totals(game(3), [@space], 0)[0]
    # Before the space step: one ruby less.
    assert {_vp, 2} = TileReveal.totals(game(3), [@space], -1)[0]
  end

  test "after a ruby spend in the rubies step the counter shows what is left" do
    assert {_vp, 1} = TileReveal.totals(game(1), [@space], 0)[0]
  end
end
