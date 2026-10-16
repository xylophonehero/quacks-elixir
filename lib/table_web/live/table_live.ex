defmodule TableWeb.TableLive do
  @moduledoc """
  The page of one room of a table game, `/games/:game/:code` (Hearts first).

  On mount it takes a seat (`Table.Server.join/3`, by the browser's player
  token: a reload gets the same seat), or watches when every seat is taken. It
  subscribes to its seat's topic and keeps the newest `Table.View` (by
  `version`). The game's board (`TableWeb.Board`, found in config by the game
  key) draws it and turns taps into actions; this page sends them to the room.
  """
  use QuacksWeb, :live_view

  alias Table.Server

  @impl true
  def mount(%{"game" => key, "code" => code}, session, socket) do
    code = String.upcase(code)
    token = session["player_token"]

    with %{board: board} = game <- Table.game(key),
         {:ok, joined} <- Server.join(key, code, token) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Quacks.PubSub, Server.topic(key, code))
        Phoenix.PubSub.subscribe(Quacks.PubSub, Server.seat_topic(key, code, joined.seat))
      end

      socket =
        socket
        |> assign(
          key: key,
          code: code,
          token: token,
          game: game,
          board: board,
          seat: joined.seat,
          seats: joined.seats,
          env: joined.view,
          page_title: "#{game.name} #{code}"
        )
        |> board.init()
        |> board.put_view(joined.view, nil)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "No game with the code #{code}.")
         |> push_navigate(to: ~p"/games")}
    end
  end

  @impl true
  def handle_event("play_again", _params, socket) do
    %{key: key, code: code, token: token} = socket.assigns

    case Server.play_again(key, code, token) do
      :ok -> {:noreply, socket}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event(event, params, socket) do
    case socket.assigns.board.handle_event(event, params, socket) do
      {:act, action, socket} -> act(socket, action)
      {:ready, socket} -> ready(socket)
      {:noreply, socket} -> {:noreply, socket}
    end
  end

  defp act(socket, action) do
    %{key: key, code: code, token: token} = socket.assigns

    case Server.act(key, code, token, action) do
      {:ok, env} -> {:noreply, put_env(socket, env)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Not now (#{inspect(reason)}).")}
    end
  end

  defp ready(socket) do
    %{key: key, code: code, token: token} = socket.assigns
    _ = Server.ready(key, code, token)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:table_view, env}, socket), do: {:noreply, put_env(socket, env)}
  def handle_info({:table_seats, seats}, socket), do: {:noreply, assign(socket, seats: seats)}
  def handle_info(msg, socket), do: socket.assigns.board.handle_info(msg, socket)

  # The reply to our own action and its broadcast are the same version: keep one.
  defp put_env(%{assigns: %{env: old}} = socket, env) do
    if env.version > old.version,
      do: socket |> socket.assigns.board.put_view(env, old) |> assign(env: env),
      else: socket
  end

  @impl true
  def render(assigns), do: assigns.board.render(assigns)
end
