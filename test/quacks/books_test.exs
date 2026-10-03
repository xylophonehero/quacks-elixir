defmodule Quacks.BooksTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Rules.{Books, Chips}

  doctest Books
  doctest Chips

  @seed {1, 2, 3}

  defp base(sets), do: Game.new(seed: @seed, fortune: false, sets: sets)
  defp buys(g), do: Game.legal_actions(put(g, phase: :buy, coins: 22))

  test "every supported {colour, set} has a book with a name, text and trigger" do
    supported =
      for(colour <- [:green, :blue, :red, :yellow, :purple], set <- 1..6, do: {colour, set}) ++
        [black: 1, black: 5, black: 6, locoweed: 5, locoweed: 6, locoweed: 8, locoweed: 9] ++
        [locoweed: 10, orange: 1, orange: 2, white: 1]

    assert Enum.sort(supported) == Books.keys()

    for key <- supported do
      book = Books.get(key)
      assert book.name != "" and book.text != ""
      assert book.trigger in [:on_draw, :step_b, :passive, :none]
    end

    assert Books.get({:orange, 2}).prices == [3, 22]
    assert Books.get({:white, 1}).prices == []
  end

  test "tiered books list their tiers; the rest have none" do
    assert [{"1 purple", "black 1 · 1 VP · 1 ruby"}, {"2 purple", _}, {"3 purple", three}] =
             Books.get({:purple, 2}).tiers

    assert three == "yellow 4 · 6 VP · 1 ruby · droplet +2"
    assert length(Books.get({:purple, 4}).tiers) == 3
    assert Books.get({:green, 1}).tiers == []

    for key <- [green: 2, red: 1, yellow: 3, yellow: 4, purple: 1, purple: 3, black: 1] do
      assert [_ | _] = Books.get(key).tiers
    end

    assert {"space 10–19", "1 VP"} in Books.get({:purple, 3}).tiers
  end

  test "book texts are one sentence and say what the audit found missing" do
    for key <- Books.keys(), do: refute(Books.get(key).text =~ ~r/\.\s+\S/)
    assert Books.get({:purple, 3}).text =~ "number printed on its space"
    assert Books.get({:blue, 2}).text =~ "no bonus die"
    assert Books.get({:purple, 5}).text =~ "different colours"
  end

  test "a base game with locoweed: 5 has locoweed in the shop and the supply" do
    g = base(%{locoweed: 5})
    assert {:buy, [{:locoweed, 1}]} in buys(g)
    assert g.supply[{:locoweed, 1}] == 25
    refute {:buy, [{:locoweed, 1}]} in buys(base(%{}))
  end

  test "a base game with orange: 2 offers the orange 6 at 22; orange: 1 does not" do
    g = base(%{orange: 2})
    assert {:buy, [{:orange, 6}]} in buys(g)
    assert Chips.price({:orange, 6}, g.sets) == 22 and g.supply[{:orange, 6}] == 20
    refute {:buy, [{:orange, 6}]} in buys(base(%{orange: 1}))
    refute Map.has_key?(base(%{orange: 1}).supply, {:orange, 6})
  end

  test "the expansion can leave locoweed and the orange 6 out" do
    g =
      Game.new(
        seed: @seed,
        fortune: false,
        expansion: :herb_witches,
        sets: %{locoweed: nil, orange: 1}
      )

    refute {:locoweed, 1} in Chips.shop(g.expansion, g.sets)
    refute {:orange, 6} in Chips.shop(g.expansion, g.sets)
    assert_raise ArgumentError, fn -> base(%{locoweed: 4}) end
  end

  test "locoweed Set 5 in a base solo game moves 1" do
    g = force_draws(base(%{locoweed: 5}), [{:locoweed, 1}])
    assert me(g).pot_index == 1
  end

  test "in_play lists the chosen books in table order" do
    assert Books.in_play(nil, %{green: 2}) ==
             [orange: 1, green: 2, blue: 1, red: 1, yellow: 1, purple: 1, black: 1]

    assert List.last(Books.in_play(:herb_witches, %{})) == {:locoweed, 5}
  end
end
