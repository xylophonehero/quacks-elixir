defmodule Table.Kit.PlayingCards do
  @moduledoc """
  The standard 52-card deck and helpers for trick-taking games.

  A card is `{rank, suit}`. The rank is an integer, 2 to 14: 11 is the jack, 12 the
  queen, 13 the king and 14 the ace (aces are high). The suit is `:clubs`,
  `:diamonds`, `:hearts` or `:spades`.

      iex> Table.Kit.PlayingCards.deck() |> length()
      52
      iex> Table.Kit.PlayingCards.name({12, :spades})
      "Q♠"
  """

  @type suit :: :clubs | :diamonds | :hearts | :spades
  @type rank :: 2..14
  @type card :: {rank, suit}

  @suits [:clubs, :diamonds, :hearts, :spades]
  @ranks Enum.to_list(2..14)
  @symbols %{clubs: "♣", diamonds: "♦", hearts: "♥", spades: "♠"}
  @faces %{11 => "J", 12 => "Q", 13 => "K", 14 => "A"}

  @doc "The four suits, in bridge order (clubs low, spades high)."
  @spec suits() :: [suit]
  def suits, do: @suits

  @doc "The ranks, low to high: 2 to 14 (ace)."
  @spec ranks() :: [rank]
  def ranks, do: @ranks

  @doc "The 52 cards, by suit (`suits/0`), then by rank."
  @spec deck() :: [card]
  def deck, do: for(suit <- @suits, rank <- @ranks, do: {rank, suit})

  @doc """
  A short name: rank then suit symbol.

      iex> Enum.map([{10, :hearts}, {14, :clubs}, {2, :diamonds}], &Table.Kit.PlayingCards.name/1)
      ["10♥", "A♣", "2♦"]
  """
  @spec name(card) :: String.t()
  def name({rank, suit}), do: Map.get(@faces, rank, Integer.to_string(rank)) <> @symbols[suit]

  @doc """
  Sort a hand: by suit (`suits:` gives the order, default `suits/0`), then by rank,
  low to high.

      iex> Table.Kit.PlayingCards.sort([{14, :clubs}, {2, :spades}, {9, :clubs}], suits: [:spades, :clubs])
      [{2, :spades}, {9, :clubs}, {14, :clubs}]
  """
  @spec sort([card], keyword) :: [card]
  def sort(cards, opts \\ []) do
    order = opts |> Keyword.get(:suits, @suits) |> Enum.with_index() |> Map.new()
    Enum.sort_by(cards, fn {rank, suit} -> {Map.fetch!(order, suit), rank} end)
  end

  @doc """
  The cards of `hand` that a player may play when `led` is the suit led: the cards
  of that suit when the hand has some (follow suit), else every card. With `led`
  nil (the player leads), every card.

      iex> hand = [{3, :hearts}, {9, :spades}, {12, :hearts}]
      iex> Table.Kit.PlayingCards.playable(hand, :hearts)
      [{3, :hearts}, {12, :hearts}]
      iex> Table.Kit.PlayingCards.playable(hand, :clubs)
      [{3, :hearts}, {9, :spades}, {12, :hearts}]
  """
  @spec playable([card], suit | nil) :: [card]
  def playable(hand, nil), do: hand

  def playable(hand, led) do
    case Enum.filter(hand, fn {_rank, suit} -> suit == led end) do
      [] -> hand
      follow -> follow
    end
  end

  @doc """
  The winner of a trick: `trick` is the cards in the order played, as
  `{seat, card}`; the first card sets the suit led. The highest trump wins; with no
  trump (or `trump` nil) the highest card of the suit led wins. Returns
  `{seat, card}`.

      iex> trick = [{0, {10, :hearts}}, {1, {14, :clubs}}, {2, {12, :hearts}}]
      iex> Table.Kit.PlayingCards.trick_winner(trick)
      {2, {12, :hearts}}
      iex> Table.Kit.PlayingCards.trick_winner(trick, :clubs)
      {1, {14, :clubs}}
  """
  @spec trick_winner(nonempty_list({seat, card}), suit | nil) :: {seat, card} when seat: term
  def trick_winner([{_seat, {_rank, led}} | _] = trick, trump \\ nil) do
    suit =
      if trump && Enum.any?(trick, fn {_, {_, s}} -> s == trump end), do: trump, else: led

    trick
    |> Enum.filter(fn {_, {_, s}} -> s == suit end)
    |> Enum.max_by(fn {_, {rank, _}} -> rank end)
  end
end
