defmodule TableWeb.Board do
  @moduledoc """
  A game's board on the table page (`TableWeb.TableLive`). The page does the room
  (the seat, the PubSub, the version check); the board draws the game and turns
  taps into actions. Found by the game's key in config (`Table.game/1`).
  """

  alias Phoenix.LiveView.Socket

  @doc "The board's own assigns, on mount."
  @callback init(Socket.t()) :: Socket.t()

  @doc """
  A newer `Table.View` came (`old` is the one before, nil on mount). The board
  assigns what it draws, and the motion from the old view to the new one.
  """
  @callback put_view(Socket.t(), new :: Table.View.t(), old :: Table.View.t() | nil) :: Socket.t()

  @doc """
  A page event: `{:act, action, socket}` sends the action to the room;
  `{:ready, socket}` tells the room that this seat is ready (`Table.Server.ready/3`).
  """
  @callback handle_event(String.t(), map, Socket.t()) ::
              {:noreply, Socket.t()} | {:act, term, Socket.t()} | {:ready, Socket.t()}

  @doc """
  Optional. The room refused `action` with `reason`: the board shows it (for
  example under a form field). Without it the page shows a flash.
  """
  @callback act_error(reason :: term, action :: term, Socket.t()) :: Socket.t()
  @optional_callbacks act_error: 3

  @doc "A message for the board (its own timers)."
  @callback handle_info(term, Socket.t()) :: {:noreply, Socket.t()}

  @doc "The whole page, inside `Layouts.app`."
  @callback render(map) :: Phoenix.LiveView.Rendered.t()
end
