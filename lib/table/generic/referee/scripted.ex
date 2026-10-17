defmodule Table.Generic.Referee.Scripted do
  @moduledoc """
  The hand-written referee of Crazy Eights (`docs/games/generic/crazy_eights.md`,
  spec `crazy_eights.json`). It plays a full game with no LLM, and it is the
  model of what an LLM referee must answer.

  The spec deals the hands and turns the top card of the deck onto the discard
  pile. The counter `suit` is the suit to follow (an 8 sets it); `passes`
  counts the seats in a row that could not play or draw.
  """
  @behaviour Table.Generic.Referee

  alias Table.Generic.Spec

  @suits ~w(clubs diamonds hearts spades)

  @impl true
  def decide(_view, :start), do: [{:phase, "play"}, {:turn, 0}]

  # Before the first turn: the starter card sets the suit. An 8 goes back into the deck.
  def decide(%{counters: %{"suit" => ""}} = v, :continue) do
    [top | _] = cards(v, "discard")

    case Spec.standard(top) do
      {8, _} ->
        [
          {:move, top, "discard", "deck"},
          {:shuffle, "deck"},
          {:move, {:top, 1}, "deck", "discard"}
        ]

      {_, suit} ->
        [{:set, "suit", Atom.to_string(suit)}]
    end
  end

  def decide(%{phase: "play", turn: seat} = v, :continue), do: [ask(v, seat)]

  def decide(v, {seat, {:play, hand, card}}) do
    move = [{:move, card, hand, "discard"}, {:set, "passes", 0}]

    cond do
      length(cards(v, hand)) == 1 ->
        move ++ [{:end, scores(v, seat, card)}]

      match?({8, _}, Spec.standard(card)) ->
        move ++
          [
            {:phase, "choose_suit"},
            {:ask, seat, "You played an 8: choose the suit", @suits}
          ]

      true ->
        {_, suit} = Spec.standard(card)
        move ++ [{:set, "suit", Atom.to_string(suit)}, {:turn, next(v, seat)}]
    end
  end

  def decide(v, {seat, {:choose, suit}}) when suit in @suits,
    do: [{:set, "suit", suit}, {:phase, "play"}, {:turn, next(v, seat)}]

  def decide(v, {seat, {:choose, "draw"}}) do
    refill =
      if cards(v, "deck") == [] do
        [_top | rest] = cards(v, "discard")
        Enum.map(rest, &{:move, &1, "discard", "deck"}) ++ [{:shuffle, "deck"}]
      else
        []
      end

    refill ++ [{:move, {:top, 1}, "deck", "hand:#{seat}"}]
  end

  # Nobody can play or draw: the game ends, the lowest hand wins.
  def decide(v, {seat, {:choose, "pass"}}) do
    if v.counters["passes"] + 1 >= length(v.seats),
      do: [{:end, blocked_scores(v)}],
      else: [{:add, "passes", 1}, {:turn, next(v, seat)}]
  end

  def decide(_view, event), do: {:error, {:unexpected, event}}

  # -- the prompt ------------------------------------------------------------------------

  defp ask(v, seat) do
    hand = "hand:#{seat}"
    [top | _] = cards(v, "discard")
    {top_rank, _} = Spec.standard(top)
    suit = v.counters["suit"]

    playable =
      for c <- cards(v, hand),
          {rank, s} = Spec.standard(c),
          rank == 8 or Atom.to_string(s) == suit or rank == top_rank,
          do: {:card, hand, c}

    can_draw = cards(v, "deck") != [] or length(cards(v, "discard")) > 1

    choices =
      cond do
        can_draw -> ["draw"]
        playable == [] -> ["pass"]
        true -> []
      end

    {:ask, seat, prompt(suit, playable), playable ++ choices}
  end

  defp prompt(suit, []), do: "No card to play on #{suit}: draw"
  defp prompt(suit, _playable), do: "Play a card on #{suit}, or draw"

  defp cards(v, zone), do: v.zones[zone].cards

  defp next(v, seat), do: rem(seat + 1, length(v.seats))

  # -- scores ----------------------------------------------------------------------------

  # The winner scores the cards left in the other hands: 8 is 50, a face card 10,
  # an ace 1, any other card its number.
  defp scores(v, winner, last_card) do
    others =
      for s <- v.seats, s != winner, c <- cards(v, "hand:#{s}"), c != last_card, reduce: 0 do
        sum -> sum + points(c)
      end

    Map.new(v.seats, &{&1, if(&1 == winner, do: others, else: 0)})
  end

  defp blocked_scores(v) do
    totals =
      Map.new(v.seats, fn s -> {s, cards(v, "hand:#{s}") |> Enum.map(&points/1) |> Enum.sum()} end)

    low = totals |> Map.values() |> Enum.min()
    winner = Enum.find(v.seats, &(totals[&1] == low))
    gain = Enum.sum(Map.values(totals)) - low
    Map.new(v.seats, &{&1, if(&1 == winner, do: gain, else: 0)})
  end

  @doc "The points of a card left in a hand."
  @spec points(String.t()) :: non_neg_integer
  def points(card) do
    case Spec.standard(card) do
      {8, _} -> 50
      {r, _} when r in 11..13 -> 10
      {14, _} -> 1
      {r, _} -> r
    end
  end
end
