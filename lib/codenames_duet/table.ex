defmodule CodenamesDuet.Table do
  @moduledoc """
  Codenames Duet in a `Table.Server` room: the adapter from the server's callbacks
  to `CodenamesDuet.Game`.

  A room has two people, or one person and a bot partner at seat 1 (level
  `:vectors`, `CodenamesDuet.AI.Vectors`).

  The bot delays (`bot_delay/1`) follow the last log event: a guess about 1.2 s
  after the clue or the guess before it, so the page can show each card turn;
  a longer "thinking" moment before the bot's clue.
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
