defmodule Quacks.AlchemistsTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Rules.{Books, Chips}

  @seed {1, 2, 3}

  defp new(locoweed), do: Game.new(seed: @seed, fortune: false, sets: %{locoweed: locoweed})
  defp effect?(g, book, detail), do: {0, {:effect, book, detail}} in g.log

  describe "data" do
    test "locoweed prices: 5 → 8, 6 → 10, 8 → 16, 9 → 10, 10 → 12" do
      for {set, price} <- [{5, 8}, {6, 10}, {8, 16}, {9, 10}, {10, 12}],
          do: assert(Chips.price({:locoweed, 1}, %{locoweed: set}) == price)
    end

    test "books 8–10 are on-draw locoweed books with their price" do
      for {set, price} <- [{8, 16}, {9, 10}, {10, 12}] do
        assert %{name: "Locoweed", trigger: :on_draw, prices: [^price]} =
                 Books.get({:locoweed, set})
      end
    end

    test "locoweed may be nil, 5, 6, 8, 9 or 10 in every game; 7 is reserved" do
      for set <- [nil, 5, 6, 8, 9, 10], do: assert(new(set).sets.locoweed == set)

      for set <- [7, 11] do
        assert_raise ArgumentError, fn -> new(set) end

        assert_raise ArgumentError, fn ->
          Game.new(seed: @seed, expansion: :herb_witches, sets: %{locoweed: set})
        end
      end

      g = Game.new(seed: @seed, expansion: :herb_witches, sets: %{locoweed: 9})
      assert {:locoweed, 1} in Chips.shop(g.expansion, g.sets)
    end
  end

  describe "book 8: one space per colour" do
    test "3 colours in the pot (white not counted, locoweed counted) move 3" do
      g = force_draws(new(8), [{:white, 1}, {:orange, 1}, {:green, 1}, {:locoweed, 1}])
      assert [{{:locoweed, 1}, 6} | _] = me(g).drawn
      assert effect?(g, {:locoweed, 8}, {:moves, 3})
    end

    test "an empty pot moves 1; a second locoweed adds nothing" do
      g = force_draws(new(8), [{:locoweed, 1}])
      assert me(g).pot_index == 1

      g = force_draws(g, [{:locoweed, 1}])
      assert me(g).pot_index == 2
    end
  end

  describe "book 10: white sum" do
    test "whites 1 + 2 + 3 move 6" do
      g = force_draws(new(10), [{:white, 1}, {:white, 2}, {:white, 3}, {:locoweed, 1}])
      assert [{{:locoweed, 1}, 12} | _] = me(g).drawn
      assert effect?(g, {:locoweed, 10}, {:moves, 6})
    end

    test "no white chips move 1" do
      g = force_draws(new(10), [{:green, 1}, {:locoweed, 1}])
      assert me(g).pot_index == 2
      assert effect?(g, {:locoweed, 10}, {:moves, 1})
    end
  end

  describe "book 9: return a chip" do
    test "moves 1, then offers each coloured pot chip (this locoweed too) or none" do
      g = force_draws(new(9), [{:white, 1}, {:orange, 1}, {:green, 1}, {:locoweed, 1}])
      assert me(g).pot_index == 4
      assert Game.phase(g, 0) == :chip_choice

      assert Game.legal_actions(g, 0) == [
               {:chip, {:return, {:green, 1}}},
               {:chip, {:return, {:locoweed, 1}}},
               {:chip, {:return, {:orange, 1}}},
               :chip_done
             ]
    end

    test "a returned chip goes to the bag and its space stays empty" do
      g = force_draws(new(9), [{:orange, 1}, {:green, 1}, {:locoweed, 1}])
      g = put(g, bag: [])
      g = apply!(g, {:chip, {:return, {:orange, 1}}})

      assert me(g).drawn == [{{:locoweed, 1}, 3}, {{:green, 1}, 2}]
      assert me(g).bag == [{:orange, 1}] and me(g).pot_index == 3
      assert Game.phase(g, 0) == :potions
      assert effect?(g, {:locoweed, 9}, {:returned, {:orange, 1}})
    end

    test "returning the locoweed itself: the next chip counts from the chip before" do
      g = force_draws(new(9), [{:green, 1}, {:locoweed, 1}])
      g = apply!(g, {:chip, {:return, {:locoweed, 1}}})
      assert me(g).drawn == [{{:green, 1}, 1}] and me(g).pot_index == 1

      g = force_draws(g, [{:orange, 1}])
      assert [{{:orange, 1}, 2} | _] = me(g).drawn
    end

    test "declining keeps the pot" do
      g = force_draws(new(9), [{:green, 1}, {:locoweed, 1}])
      g = apply!(g, :chip_done)
      assert length(me(g).drawn) == 2 and Game.phase(g, 0) == :potions
    end
  end
end
