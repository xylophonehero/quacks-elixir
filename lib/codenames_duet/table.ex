defmodule CodenamesDuet.Table do
  @moduledoc """
  Codenames Duet in a `Table.Server` room: the adapter from the server's callbacks
  to `CodenamesDuet.Game`.

  A room has two people, or one person and a bot partner at seat 1 (level
  `:vectors`, `CodenamesDuet.AI.Vectors`).

  The bot delays (`bot_delay/1`) follow the last log event: a guess about 1.2 s
  after the clue or the guess before it, so the page can show each card turn;
  a longer "thinking" moment before the bot's clue.

  ## Log lines

  Each new event of the game log gives one info line (`log_lines/2`), after
  `codenames_duet <room code>: `:

      new game timer=9 words=breath,winter,...
      clue seat=1 word=due number=2
      guess seat=0 word=debt result=assassin
      side done seat=0
      turn end seat=0 how=neutral timer=8
      sudden death seats=0,1
      game over result=lost reason=assassin found=0 seed=1,2,3 key0=ngg... key1=nna...

  Only the game-over line shows the key (`g` green, `n` bystander, `a` assassin,
  word by word) and the seed.
  """
  @behaviour Table.Server

  alias CodenamesDuet.AI.Vectors
  alias CodenamesDuet.Game

  @impl true
  def new(opts, seed), do: Game.new(opts, seed)

  @impl true
  def seats(%Game{seats: seats}), do: seats

  @impl true
  def legal_actions(game, seat), do: Game.legal_actions(game, seat)

  @impl true
  def apply(game, seat, action), do: Game.apply(game, seat, action)

  # Codenames Duet is co-operative: both seats win together, or nobody.
  @impl true
  def winners(%Game{result: :won, seats: seats}), do: seats
  def winners(%Game{}), do: []

  @impl true
  def status(game), do: Game.status(game)

  @impl true
  def view(game, seat), do: Game.view(game, seat)

  @impl true
  def bot_levels, do: [:vectors]

  @impl true
  def bot_new(:vectors, seed), do: Vectors.new(seed)

  @impl true
  def bot_choose(:vectors, view, bot), do: Vectors.choose(view, bot)

  @impl true
  def log_lines(old, %Game{} = new) do
    new
    |> new_events(old)
    |> Enum.reverse()
    |> Enum.map(&line(&1, new))
  end

  # The events of `new` that `old` does not have (all of them for a new game).
  defp new_events(%Game{log: log}, %Game{log: old}) do
    extra = length(log) - length(old)
    if extra >= 0 and Enum.drop(log, extra) == old, do: Enum.take(log, extra), else: log
  end

  defp new_events(%Game{log: log}, _old), do: log

  defp line({:setup, words, timer}, _game),
    do: "new game timer=#{timer} words=#{Enum.join(words, ",")}"

  defp line({:clue, seat, word, number}, _game),
    do: "clue seat=#{seat} word=#{word} number=#{number}"

  defp line({:guess, seat, i, result}, game),
    do: "guess seat=#{seat} word=#{Enum.at(game.words, i)} result=#{result}"

  defp line({:side_done, seat}, _game), do: "side done seat=#{seat}"

  defp line({:turn_end, seat, how, timer}, _game),
    do: "turn end seat=#{seat} how=#{how} timer=#{timer}"

  defp line({:sudden_death, seats}, _game), do: "sudden death seats=#{Enum.join(seats, ",")}"

  defp line({:game_over, result, reason}, game) do
    {a, b, c} = game.seed

    "game over result=#{result} reason=#{reason} found=#{Game.found(game)} " <>
      "seed=#{a},#{b},#{c} key0=#{key(game.key[0])} key1=#{key(game.key[1])}"
  end

  defp key(side), do: Enum.map_join(side, &(&1 |> Atom.to_string() |> String.first()))

  @impl true
  def bot_delay(%Game{log: [event | _]}), do: delay(event)
  def bot_delay(%Game{}), do: 1200

  # The first clue: the page is new, so a longer look first.
  defp delay({:setup, _, _}), do: 3000
  # A clue from the bot after the turn's end: a "thinking" moment.
  defp delay({:turn_end, _, _, _}), do: 2600
  defp delay({:side_done, _}), do: 2600
  defp delay({:sudden_death, _}), do: 2600
  # The human's clue, or the bot's guess before: the next guess.
  defp delay({:clue, _, _, _}), do: 1500
  defp delay(_event), do: 1200
end
