defmodule Table.Kit.Deck do
  @moduledoc """
  A deck of cards: a face-down draw pile (top card first), a discard pile (newest
  card first) and the cards removed from the game (for example the 9 cards that
  No Thanks! puts back in the box unseen).

      iex> alias Table.Kit.{Deck, Rng}
      iex> {deck, _rng} = Deck.new(1..10) |> Deck.shuffle(Rng.seed({1, 2, 3}))
      iex> {:ok, _card, deck} = Deck.draw(deck)
      iex> Deck.size(deck)
      9
  """

  alias Table.Kit.Rng

  @enforce_keys [:draw]
  defstruct draw: [], discard: [], removed: []

  @type t(card) :: %__MODULE__{draw: [card], discard: [card], removed: [card]}
  @type t :: t(term)

  @doc """
  A deck with `cards` as the draw pile, in the given order (not shuffled).

      iex> Table.Kit.Deck.new([:a, :b])
      %Table.Kit.Deck{draw: [:a, :b], discard: [], removed: []}
  """
  @spec new(Enumerable.t(x)) :: t(x) when x: term
  def new(cards), do: %__MODULE__{draw: Enum.to_list(cards)}

  @doc "Shuffle the draw pile."
  @spec shuffle(t(x), Rng.t()) :: {t(x), Rng.t()} when x: term
  def shuffle(%__MODULE__{} = deck, rng) do
    {draw, rng} = Rng.shuffle(deck.draw, rng)
    {%{deck | draw: draw}, rng}
  end

  @doc "The number of cards in the draw pile."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{draw: draw}), do: length(draw)

  @doc """
  Draw the top card: `{:ok, card, deck}`, or `:empty`. An empty draw pile does not
  take the discard pile; call `reshuffle/2` for that.

      iex> Table.Kit.Deck.draw(Table.Kit.Deck.new([:a, :b]))
      {:ok, :a, %Table.Kit.Deck{draw: [:b], discard: [], removed: []}}
      iex> Table.Kit.Deck.draw(Table.Kit.Deck.new([]))
      :empty
  """
  @spec draw(t(x)) :: {:ok, x, t(x)} | :empty when x: term
  def draw(%__MODULE__{draw: []}), do: :empty
  def draw(%__MODULE__{draw: [top | rest]} = deck), do: {:ok, top, %{deck | draw: rest}}

  @doc """
  Draw up to `n` cards from the top, top card first.

      iex> Table.Kit.Deck.draw(Table.Kit.Deck.new([:a, :b, :c]), 2)
      {[:a, :b], %Table.Kit.Deck{draw: [:c], discard: [], removed: []}}
  """
  @spec draw(t(x), non_neg_integer) :: {[x], t(x)} when x: term
  def draw(%__MODULE__{draw: draw} = deck, n) when is_integer(n) and n >= 0 do
    {top, rest} = Enum.split(draw, n)
    {top, %{deck | draw: rest}}
  end

  @doc """
  The top `n` cards of the draw pile, top first, without drawing them.

      iex> Table.Kit.Deck.peek(Table.Kit.Deck.new([:a, :b, :c]), 2)
      [:a, :b]
  """
  @spec peek(t(x), non_neg_integer) :: [x] when x: term
  def peek(%__MODULE__{draw: draw}, n \\ 1) when is_integer(n) and n >= 0,
    do: Enum.take(draw, n)

  @doc """
  Put `cards` (one card or a list) on the discard pile, the last one on top.

      iex> Table.Kit.Deck.new([]) |> Table.Kit.Deck.discard([:a, :b]) |> Map.get(:discard)
      [:b, :a]
  """
  @spec discard(t(x), x | [x]) :: t(x) when x: term
  def discard(%__MODULE__{} = deck, cards) when is_list(cards),
    do: %{deck | discard: Enum.reverse(cards, deck.discard)}

  def discard(%__MODULE__{} = deck, card), do: discard(deck, [card])

  @doc """
  Shuffle the discard pile and put it under the draw pile.

      iex> alias Table.Kit.{Deck, Rng}
      iex> deck = Deck.new([:a]) |> Deck.discard([:b, :c])
      iex> {deck, _rng} = Deck.reshuffle(deck, Rng.seed({1, 2, 3}))
      iex> {hd(deck.draw), Enum.sort(deck.draw), deck.discard}
      {:a, [:a, :b, :c], []}
  """
  @spec reshuffle(t(x), Rng.t()) :: {t(x), Rng.t()} when x: term
  def reshuffle(%__MODULE__{} = deck, rng) do
    {cards, rng} = Rng.shuffle(deck.discard, rng)
    {%{deck | draw: deck.draw ++ cards, discard: []}, rng}
  end

  @doc """
  Remove the top `n` cards from the game, unseen.

      iex> Table.Kit.Deck.new(1..5) |> Table.Kit.Deck.remove(2)
      %Table.Kit.Deck{draw: [3, 4, 5], discard: [], removed: [1, 2]}
  """
  @spec remove(t(x), non_neg_integer) :: t(x) when x: term
  def remove(%__MODULE__{draw: draw} = deck, n) when is_integer(n) and n >= 0 do
    {gone, rest} = Enum.split(draw, n)
    %{deck | draw: rest, removed: deck.removed ++ gone}
  end

  @doc """
  Deal `n` cards to each seat, one at a time and in seat order, from the top.
  Stops when the draw pile is empty, so the first seats can get one more card.

      iex> Table.Kit.Deck.new(1..7) |> Table.Kit.Deck.deal([0, 1, 2], 2)
      {%{0 => [1, 4], 1 => [2, 5], 2 => [3, 6]},
       %Table.Kit.Deck{draw: [7], discard: [], removed: []}}
  """
  @spec deal(t(x), [seat], non_neg_integer) :: {%{seat => [x]}, t(x)} when x: term, seat: term
  def deal(%__MODULE__{} = deck, seats, n) when is_integer(n) and n >= 0 do
    hands = Map.new(seats, &{&1, []})
    order = for _ <- 1..n//1, seat <- seats, do: seat

    {hands, deck} =
      Enum.reduce_while(order, {hands, deck}, fn seat, {hands, deck} ->
        case draw(deck) do
          {:ok, card, deck} -> {:cont, {Map.update!(hands, seat, &[card | &1]), deck}}
          :empty -> {:halt, {hands, deck}}
        end
      end)

    {Map.new(hands, fn {seat, cards} -> {seat, Enum.reverse(cards)} end), deck}
  end
end
