defmodule Quacks.FleaMarketTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Game.Fortune

  defp new(players),
    do: Game.new(seed: {1, 2, 3}, players: players, fortune: false, rules: %{supply: :limited})

  defp flea(g), do: g |> put(fortune_card: :p13) |> Fortune.resolve()

  test "flea_market/1: what each seat drew, traded and got this round" do
    g =
      new(2)
      |> put(0, bag: [{:green, 1}, {:green, 1}, {:orange, 1}, {:white, 1}])
      |> put(1, bag: List.duplicate({:white, 1}, 4))
      |> flea()

    assert %{0 => seat0, 1 => seat1} = Fortune.flea_market(g)

    assert Enum.sort(seat0.drew) ==
             Enum.sort([{:green, 1}, {:green, 1}, {:orange, 1}, {:white, 1}])

    assert seat0.choosing? and seat0.traded == nil and seat0.got == nil
    assert seat1.drew == List.duplicate({:white, 1}, 4)
    assert seat1.got == {:green, 1} and not seat1.choosing?

    g = apply!(g, 0, {:fortune, {:upgrade, {:green, 1}}})
    assert %{traded: {:green, 1}, got: {:green, 2}, choosing?: false} = Fortune.flea_market(g)[0]
  end

  test "flea_market/1 is empty under any other card" do
    assert Fortune.flea_market(new(2) |> put(fortune_card: :p6)) == %{}
  end

  test "flea_block/2 names why a chip cannot be traded up" do
    g = new(1)
    assert Fortune.flea_block(g, {:white, 1}) == :white
    assert Fortune.flea_block(g, {:orange, 1}) == :top
    assert Fortune.flea_block(g, {:green, 4}) == :top
    assert Fortune.flea_block(g, {:green, 1}) == nil
    # yellow's book opens in a later round
    assert Fortune.flea_block(g, {:yellow, 1}) == :none_left
  end
end
