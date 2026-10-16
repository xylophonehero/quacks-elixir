defmodule Table.Kit.DeckTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Table.Kit.{Deck, Rng}

  doctest Deck

  defp seeds, do: tuple({integer(), integer(), integer()})

  test "No Thanks!: 3..35, shuffled, minus 9 cards" do
    {deck, _} = Deck.new(3..35) |> Deck.shuffle(Rng.seed({1, 2, 3}))
    deck = Deck.remove(deck, 9)
    assert Deck.size(deck) == 24 and length(deck.removed) == 9
    assert Enum.sort(deck.draw ++ deck.removed) == Enum.to_list(3..35)
  end

  test "discard and reshuffle bring every card back" do
    deck = Deck.new(1..6)
    {drawn, deck} = Deck.draw(deck, 6)
    assert Deck.draw(deck) == :empty
    {deck, _} = deck |> Deck.discard(drawn) |> Deck.reshuffle(Rng.seed({1, 2, 3}))
    assert Enum.sort(deck.draw) == drawn and deck.discard == []
  end

  test "discard takes one card too" do
    assert Deck.new([]) |> Deck.discard(:a) |> Deck.discard(:b) |> Map.get(:discard) == [:b, :a]
  end

  test "deal stops when the draw pile is empty" do
    assert {%{0 => [1, 3], 1 => [2]}, %Deck{draw: []}} = Deck.deal(Deck.new(1..3), [0, 1], 5)
  end

  property "shuffle is a permutation and deterministic per seed" do
    check all(seed <- seeds(), cards <- list_of(integer())) do
      {a, _} = Deck.shuffle(Deck.new(cards), Rng.seed(seed))
      {b, _} = Deck.shuffle(Deck.new(cards), Rng.seed(seed))
      assert a == b and Enum.sort(a.draw) == Enum.sort(cards)
    end
  end

  property "deal hands out every card it can and keeps the rest" do
    check all(cards <- list_of(integer()), seats <- integer(1..6), n <- integer(0..10)) do
      {hands, deck} = Deck.deal(Deck.new(cards), Enum.to_list(1..seats), n)
      dealt = hands |> Map.values() |> List.flatten()
      assert length(dealt) == min(length(cards), seats * n)
      assert Enum.sort(dealt ++ deck.draw) == Enum.sort(cards)
    end
  end
end
