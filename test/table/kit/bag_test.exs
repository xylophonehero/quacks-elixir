defmodule Table.Kit.BagTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Table.Kit.{Bag, Rng}

  doctest Bag

  defp seeds, do: tuple({integer(), integer(), integer()})

  test "an empty bag cannot draw" do
    assert Bag.draw([], Rng.seed({1, 2, 3})) == :empty
    assert {[], [], _} = Bag.draw([], 3, Rng.seed({1, 2, 3}))
  end

  test "one draw takes the item at a uniform index and advances the state" do
    rng = Rng.seed({1, 2, 3})
    {i, next} = Rng.uniform(5, rng)
    bag = [:a, :b, :c, :d, :e]
    assert Bag.draw(bag, rng) == {Enum.at(bag, i - 1), List.delete_at(bag, i - 1), next}
  end

  property "draw n takes min(n, size) items and keeps the rest" do
    check all(seed <- seeds(), bag <- list_of(integer()), n <- non_negative_integer()) do
      {drawn, rest, _} = Bag.draw(bag, n, Rng.seed(seed))
      assert length(drawn) == min(n, length(bag))
      assert Enum.sort(drawn ++ rest) == Enum.sort(bag)
    end
  end

  property "draw n is the same as n single draws" do
    check all(seed <- seeds(), bag <- list_of(integer()), n <- integer(0..10)) do
      rng = Rng.seed(seed)

      {singles, {rest, rng}} =
        Enum.map_reduce(1..min(n, length(bag))//1, {bag, rng}, fn _, {bag, rng} ->
          {x, bag, rng} = Bag.draw(bag, rng)
          {x, {bag, rng}}
        end)

      assert Bag.draw(bag, n, Rng.seed(seed)) == {singles, rest, rng}
    end
  end
end
