defmodule Table.Kit.DiceTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Table.Kit.{Dice, Rng}

  doctest Dice

  test "a roll is a pick of a face" do
    rng = Rng.seed({1, 2, 3})
    assert Dice.roll([:a, :b, :c], rng) == Rng.pick([:a, :b, :c], rng)
  end

  test "every face of a d6 comes up" do
    {faces, _} = Dice.roll(Dice.d(6), 200, Rng.seed({7, 7, 7}))
    assert faces |> Enum.uniq() |> Enum.sort() == [1, 2, 3, 4, 5, 6]
  end

  property "rolls are faces of the die and deterministic" do
    check all(
            seed <- tuple({integer(), integer(), integer()}),
            sides <- integer(1..20),
            n <- integer(0..20)
          ) do
      {faces, _} = Dice.roll(Dice.d(sides), n, Rng.seed(seed))
      assert length(faces) == n and Enum.all?(faces, &(&1 in 1..sides))
      assert {^faces, _} = Dice.roll(Dice.d(sides), n, Rng.seed(seed))
    end
  end
end
