defmodule Hearts.AI.Heuristic do
  @moduledoc """
  A simple rule-of-thumb bot. It uses only `Hearts.Game.view/2`, so it does not see
  the other hands.

  - Pass: the Q♠, K♠ and A♠ first, then the highest hearts, then the highest cards.
  - Lead: the lowest card.
  - Follow suit: the highest card that loses to the trick ("duck"). If every card
    wins: the highest card when it plays last to a trick with no points, else the
    lowest. It does not win with the Q♠ if it can play another card.
  - Void in the suit led: the Q♠, then the highest heart, then the A♠ or K♠, then
    the highest card.

  The state is not used; `choose/2` returns it unchanged, like `Hearts.AI.Random`.
  """

  alias Hearts.Game

  @queen {12, :spades}

  @doc "The action for this view."
  @spec choose(map(), term) :: {Game.action(), term}
  def choose(%{phase: :passing, hand: hand}, state) do
    pass = hand |> Enum.sort_by(&pass_score/1, :desc) |> Enum.take(3) |> Game.sort_hand()
    {{:pass, pass}, state}
  end

  def choose(%{legal_actions: actions} = view, state) do
    cards = for {:play, card} <- actions, do: card
    {{:play, play(view, cards)}, state}
  end

  defp pass_score({rank, :spades}) when rank >= 12, do: 100 + rank
  defp pass_score({rank, :hearts}), do: 50 + rank
  defp pass_score({rank, _suit}), do: rank

  defp play(%{trick: []}, cards),
    do: Enum.min_by(cards, fn {rank, suit} -> {rank, suit == :hearts} end)

  defp play(%{trick: [{_, {_, led}} | _] = trick} = view, [{_, suit} | _] = cards) do
    if suit == led and Enum.all?(cards, &(elem(&1, 1) == led)),
      do: follow(view, trick, led, cards),
      else: discard(cards)
  end

  defp follow(view, trick, led, cards) do
    high =
      trick
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(elem(&1, 1) == led))
      |> Enum.map(&elem(&1, 0))
      |> Enum.max()

    case Enum.filter(cards, fn {rank, _} -> rank < high end) do
      [] -> win(view, trick, cards)
      ducks -> Enum.max(ducks)
    end
  end

  defp win(view, trick, cards) do
    safe = if cards == [@queen], do: cards, else: cards -- [@queen]
    last? = length(trick) == length(view.seats) - 1
    points? = Game.points(Enum.map(trick, &elem(&1, 1)), view.options) > 0

    if last? and not points?, do: Enum.max(safe), else: Enum.min(safe)
  end

  defp discard(cards) do
    hearts = Enum.filter(cards, &(elem(&1, 1) == :hearts))

    cond do
      @queen in cards -> @queen
      hearts != [] -> Enum.max(hearts)
      true -> Enum.max_by(cards, &discard_score/1)
    end
  end

  defp discard_score({rank, :spades}) when rank > 12, do: 100 + rank
  defp discard_score({rank, _suit}), do: rank
end
