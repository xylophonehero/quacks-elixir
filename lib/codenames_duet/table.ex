defmodule CodenamesDuet.Table do
  @moduledoc """
  Codenames Duet in a `Table.Server` room: the adapter from the server's callbacks
  to `CodenamesDuet.Game`.

  The game needs two people: there are no bots (`bot_levels/0` is empty), so a
  room has 0 bot seats.
  """
  @behaviour Table.Server

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
  def bot_levels, do: []

  @impl true
  def bot_new(_level, _seed), do: nil

  @impl true
  def bot_choose(level, _view, _bot), do: raise(ArgumentError, "no #{inspect(level)} bot")

  @impl true
  def bot_delay(_game), do: 0
end
