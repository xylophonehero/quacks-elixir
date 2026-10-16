defmodule CodenamesDuet.Scenario do
  @moduledoc """
  Test helpers for `CodenamesDuet.Game`: a fixed board and key, and short actions.

  `fixed/1` puts the NATO words and the key pairs of `CodenamesDuet.Key.layout/0`
  in order on the board, so each index has a known colour pair:

  | Index | Seat 0 / seat 1 |
  |---|---|
  | 0–2 | green / green |
  | 3–7 | green / bystander |
  | 8–12 | bystander / green |
  | 13 | green / assassin |
  | 14 | assassin / green |
  | 15 | assassin / assassin |
  | 16 | assassin / bystander |
  | 17 | bystander / assassin |
  | 18–24 | bystander / bystander |
  """

  alias CodenamesDuet.{Game, Key}

  @words ~w(alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike
            november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee)

  @doc "The fixed board words (index order)."
  def words, do: @words

  @doc "The indexes of seat 0 green (9) and seat 1 green (9)."
  def greens(0), do: [0, 1, 2, 3, 4, 5, 6, 7, 13]
  def greens(1), do: [0, 1, 2, 8, 9, 10, 11, 12, 14]

  @doc "A new game; raises on bad options."
  def new!(opts \\ %{}, seed \\ {1, 2, 3}) do
    {:ok, game} = Game.new(opts, seed)
    game
  end

  @doc "A new game with the fixed board and key, and an empty log."
  def fixed(opts \\ %{}) do
    %{new!(opts) | words: @words, key: Key.from_pairs(Key.pairs()), log: []}
  end

  @doc "Applies an action; raises on an error."
  def apply!(game, seat, action) do
    case Game.apply(game, seat, action) do
      {:ok, game} -> game
      {:error, reason} -> raise "#{inspect(action)} by seat #{seat}: #{inspect(reason)}"
    end
  end

  @doc "`giver` gives the clue `word: number`."
  def clue(game, giver, word \\ "quokka", number \\ 1),
    do: apply!(game, giver, {:clue, word, number})

  @doc "The partner of `giver` guesses each index in turn."
  def guesses(game, guesser, indexes),
    do: Enum.reduce(indexes, game, &apply!(&2, guesser, {:guess, &1}))

  @doc "One turn: `giver` clues, the partner guesses `indexes`, then stops if the turn is still on."
  def turn(game, giver, indexes) do
    game = game |> clue(giver) |> guesses(1 - giver, indexes)
    if game.phase == :guess, do: apply!(game, 1 - giver, :end_turn), else: game
  end

  @doc "The log, oldest event first."
  def events(game), do: Enum.reverse(game.log)
end
