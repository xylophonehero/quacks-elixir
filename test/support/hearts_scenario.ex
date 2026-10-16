defmodule Hearts.Scenario do
  @moduledoc """
  Test helpers for `Hearts.Game`: card notation and "given this table" builders.

  Cards are written as `"2C QS 10H AD"` (rank, then suit letter C, D, S or H).
  """

  alias Hearts.Game

  @suits %{"C" => :clubs, "D" => :diamonds, "S" => :spades, "H" => :hearts}
  @ranks %{"J" => 11, "Q" => 12, "K" => 13, "A" => 14}

  @doc "Parses `\"2C QS\"` into `[{2, :clubs}, {12, :spades}]`."
  def cards(text), do: text |> String.split() |> Enum.map(&card/1)

  @doc "Parses one card, e.g. `\"QS\"`."
  def card(text) do
    {rank, suit} = String.split_at(text, -1)
    {Map.get_lazy(@ranks, rank, fn -> String.to_integer(rank) end), Map.fetch!(@suits, suit)}
  end

  @doc "A new game; raises on bad options."
  def new!(opts \\ %{}, seed \\ {1, 2, 3}) do
    {:ok, game} = Game.new(opts, seed)
    game
  end

  @doc """
  A game in the play phase with the given hands (`%{seat => "2C QS ..."}`).
  `fields` overrides struct fields, e.g. `tricks: 1, turn: 2, trick: [{1, card("5C")}]`.
  """
  def at_play(hands, fields \\ [], opts \\ %{}) do
    game = new!(opts)
    hands = Map.new(hands, fn {seat, text} -> {seat, Game.sort_hand(cards(text))} end)
    turn = Keyword.get(fields, :turn, 0)

    struct!(
      %{game | hands: hands, passes: %{}, phase: :playing, leader: turn, turn: turn, log: []},
      fields
    )
  end

  @doc "Applies an action; raises on an error."
  def apply!(game, seat, action) do
    case Game.apply(game, seat, action) do
      {:ok, game} -> game
      {:error, reason} -> raise "#{inspect(action)} by seat #{seat}: #{inspect(reason)}"
    end
  end

  @doc "Every seat that can act takes its first legal action, until `done?.(game)`."
  def play_until(game, done?) do
    if done?.(game) or Game.over?(game) do
      game
    else
      {:playing, [seat | _]} = Game.status(game)
      [action | _] = Game.legal_actions(game, seat)
      game |> apply!(seat, action) |> play_until(done?)
    end
  end

  @doc "Plays the rest of the current hand with first-legal actions."
  def finish_hand(game) do
    hand_no = game.hand_no
    play_until(game, &(&1.hand_no != hand_no))
  end

  @doc "The events of `game` in the order they happened."
  def events(game), do: Enum.reverse(game.log)
end
