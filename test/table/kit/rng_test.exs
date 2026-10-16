defmodule Table.Kit.RngTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Table.Kit.Rng

  doctest Rng

  defp seeds, do: tuple({integer(), integer(), integer()})

  test "uniform is the :rand _s API on the same state" do
    rng = Rng.seed({1, 2, 3})
    assert Rng.uniform(6, rng) == :rand.uniform_s(6, :rand.seed_s(:exsss, {1, 2, 3}))
    assert Rng.uniform(rng) == :rand.uniform_s(rng)
  end

  test "fork leaves the main stream alone and differs from it" do
    rng = Rng.seed({1, 2, 3})
    assert Rng.fork(rng) == :rand.jump(rng)
    refute elem(Rng.uniform(1000, Rng.fork(rng)), 0) == elem(Rng.uniform(1000, rng), 0)
  end

  property "uniform stays in 1..n" do
    check all(seed <- seeds(), n <- positive_integer()) do
      {i, _} = Rng.uniform(n, Rng.seed(seed))
      assert i in 1..n
    end
  end

  property "shuffle is a permutation" do
    check all(seed <- seeds(), list <- list_of(integer())) do
      {shuffled, _} = Rng.shuffle(list, Rng.seed(seed))
      assert Enum.sort(shuffled) == Enum.sort(list)
    end
  end

  property "shuffle is deterministic for a seed" do
    check all(seed <- seeds(), list <- list_of(term())) do
      assert Rng.shuffle(list, Rng.seed(seed)) == Rng.shuffle(list, Rng.seed(seed))
    end
  end

  property "pick returns an element of the list" do
    check all(seed <- seeds(), list <- list_of(integer(), min_length: 1)) do
      {x, _} = Rng.pick(list, Rng.seed(seed))
      assert x in list
    end
  end
end
