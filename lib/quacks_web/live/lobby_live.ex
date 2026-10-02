defmodule QuacksWeb.LobbyLive do
  @moduledoc """
  The start page: create a game for 1 to 4 players, or join an open game on this
  node. Creating a game seats this browser in seat 0 and opens `/g/:id`.

  `?seed=1,2,3` makes the games created here reproducible.
  """
  use QuacksWeb, :live_view

  alias Quacks.GameServer

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.lobby_topic())

    {:ok,
     assign(socket,
       page_title: "Quacks",
       token: session["player_token"],
       seed: parse_seed(params["seed"]),
       games: GameServer.open_games()
     )}
  end

  @impl true
  def handle_event("new_game", %{"players" => players}, socket) do
    {:ok, id} = GameServer.start(String.to_integer(players), socket.assigns.seed)
    {:ok, 0} = GameServer.claim_seat(id, socket.assigns.token)
    {:noreply, push_navigate(socket, to: ~p"/g/#{id}")}
  end

  # A game started, filled up or stopped somewhere: list the open games again.
  @impl true
  def handle_info(:games_changed, socket),
    do: {:noreply, assign(socket, games: GameServer.open_games())}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-bold">Quacks</h1>

      <section class="flex flex-wrap gap-2" aria-label="New game">
        <.button phx-click="new_game" phx-value-players="1" variant="primary">
          New solo game
        </.button>
        <.button :for={n <- 2..4} phx-click="new_game" phx-value-players={n}>
          New game for {n} players
        </.button>
      </section>

      <section aria-label="Open games">
        <h2 class="text-sm font-semibold text-zinc-600">Open games</h2>
        <ul class="mt-2 space-y-2">
          <li
            :for={game <- @games}
            id={"game-#{game.id}"}
            class="flex items-center justify-between rounded-md bg-zinc-100 px-3 py-2 text-sm"
          >
            <span>
              <span class="font-mono font-semibold">{game.id}</span>
              · {map_size(game.names)} of {game.players} seated · round {game.game.round}
            </span>
            <.button navigate={~p"/g/#{game.id}"}>Join</.button>
          </li>
          <li :if={@games == []} class="text-sm text-zinc-400">No open games. Start one.</li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  @doc "Parse `\"1,2,3\"` into `{1, 2, 3}`; anything else is `nil` (a random seed)."
  @spec parse_seed(String.t() | nil) :: {integer, integer, integer} | nil
  def parse_seed(seed) when is_binary(seed) do
    case seed |> String.split(",") |> Enum.map(&Integer.parse/1) do
      [{a, ""}, {b, ""}, {c, ""}] -> {a, b, c}
      _ -> nil
    end
  end

  def parse_seed(_seed), do: nil
end
