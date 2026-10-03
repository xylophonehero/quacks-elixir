defmodule QuacksWeb.LobbyLive do
  @moduledoc """
  The start page: a "New game" button and the open games on this node.

  "New game" opens a waiting game for 2 players with this browser in seat 0 (the
  host) and goes to `/g/:id`. There the host sets the game up: the player count,
  the Ingredient books, the options (see `QuacksWeb.GameLive`).

  `?seed=1,2,3` makes the games created here reproducible.
  """
  use QuacksWeb, :live_view

  alias Quacks.GameServer

  # A new game starts as a 2-player game; the host changes it on the configure screen.
  # (Not 1: a solo game begins as soon as its seat is taken.)
  @new_game_players 2

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
  def handle_event("new_game", _params, socket) do
    {:ok, id} = GameServer.start(@new_game_players, socket.assigns.seed)
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
      <h1 class="text-center text-4xl font-bold">Quacks</h1>

      <%!-- The page's one action: hero-sized, a press you can feel. --%>
      <button
        id="new-game"
        type="button"
        phx-click="new_game"
        class={[
          "flex min-h-24 w-full touch-manipulation items-center justify-center gap-3 rounded-2xl",
          "bg-gold px-6 font-hand text-4xl font-bold text-ink shadow-lg ring-2 ring-parchment/60",
          "transition-[scale,filter] duration-150 ease-out hover:brightness-110 active:scale-[0.97]",
          "phx-click-loading:opacity-80 motion-reduce:transition-none"
        ]}
      >
        <.icon name="hero-sparkles" class="size-8" /> New game
      </button>

      <section aria-label="Open games">
        <h2 class="text-lg font-semibold text-parchment-dim">Open games</h2>
        <ul class="mt-2 space-y-2">
          <li
            :for={game <- @games}
            id={"game-#{game.id}"}
            class="paper flex items-center justify-between rounded-md px-3 py-2 text-sm"
          >
            <span>
              <span class="font-mono font-semibold">{game.id}</span>
              · {map_size(game.names)} of {game.players} seated
            </span>
            <.button navigate={~p"/g/#{game.id}"}>Join</.button>
          </li>
          <li :if={@games == []} class="text-sm text-parchment-dim">No open games. Start one.</li>
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
