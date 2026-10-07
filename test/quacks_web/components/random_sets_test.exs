defmodule QuacksWeb.RandomSetsTest do
  # Round 26: Random picks locoweed on its own, independent of the expansions;
  # locoweed III (needs The Alchemists) only with The Alchemists.
  use ExUnit.Case, async: true

  alias QuacksWeb.SetupComponents

  defp locoweeds(alchemists?) do
    :rand.seed(:exsss, {26, 26, 26})
    for _ <- 1..400, uniq: true, do: SetupComponents.random_sets(alchemists?)[:locoweed]
  end

  test "no expansions: locoweed sometimes, sometimes none, never book III" do
    picks = locoweeds(false)
    assert nil in picks
    assert Enum.any?(picks, &is_integer/1)
    refute 3 in picks
    assert Enum.sort(picks -- [nil]) == [1, 2, 4, 5, 6]
  end

  test "with The Alchemists every locoweed book can appear, book III too" do
    picks = locoweeds(true)
    assert 3 in picks
    assert nil in picks
    assert Enum.sort(picks -- [nil]) == [1, 2, 3, 4, 5, 6]
  end

  test "other colours stay in their pickers' books" do
    :rand.seed(:exsss, {1, 2, 3})

    for _ <- 1..100, sets = SetupComponents.random_sets(false) do
      assert sets.black in 1..3
      assert Map.get(sets, :orange, 1) in 1..2
      assert sets.green in 1..6
    end
  end
end
