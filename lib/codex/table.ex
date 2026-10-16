defmodule Codex.Table do
  @moduledoc """
  The Codex sandbox in a `Table.Server` room: the adapter from the server's
  callbacks to `Codex.Game`.

  Hot-seat: one browser plays both sides, so the room has one seat
  (`Codex.Game.table_seats/0`) and no bots. A second browser watches.
  """
  @behaviour Table.Server

  alias Codex.Game

  @impl true
  def new(opts, seed), do: Game.new(opts, seed)

  @impl true
  def seats(%Game{}), do: Game.table_seats()

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
