defmodule Table.Kit.PlayingCardsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Table.Kit.{PlayingCards, Rng}

  doctest PlayingCards

  test "the deck has 52 different cards, 13 per suit" do
    deck = PlayingCards.deck()
    assert length(Enum.uniq(deck)) == 52
    assert deck |> Enum.frequencies_by(&elem(&1, 1)) |> Map.values() == [13, 13, 13, 13]
  end

  test "a card off the led suit never wins without trumps" do
    trick = [{0, {2, :clubs}}, {1, {14, :spades}}, {2, {14, :hearts}}]
    assert PlayingCards.trick_winner(trick) == {0, {2, :clubs}}
    assert PlayingCards.trick_winner(trick, :diamonds) == {0, {2, :clubs}}
  end

  test "the highest trump wins" do
    trick = [{0, {14, :clubs}}, {1, {3, :hearts}}, {2, {9, :hearts}}]
    assert PlayingCards.trick_winner(trick, :hearts) == {2, {9, :hearts}}
  end

  property "sort keeps the cards and is stable for any shuffle" do
    check all(seed <- tuple({integer(), integer(), integer()})) do
      {shuffled, _} = Rng.shuffle(PlayingCards.deck(), Rng.seed(seed))
      assert PlayingCards.sort(shuffled) == PlayingCards.deck()
    end
  end

  property "playable cards are in the hand and follow suit when they can" do
    check all(
            seed <- tuple({integer(), integer(), integer()}),
            n <- integer(1..13),
            led <- member_of(PlayingCards.suits())
          ) do
      {deck, _} = Rng.shuffle(PlayingCards.deck(), Rng.seed(seed))
      hand = Enum.take(deck, n)
      playable = PlayingCards.playable(hand, led)
      assert playable != [] and Enum.all?(playable, &(&1 in hand))

      if Enum.any?(hand, &(elem(&1, 1) == led)),
        do: assert(Enum.all?(playable, &(elem(&1, 1) == led)))
    end
  end
end
