defmodule QuacksWeb.LobbyLive do
  @moduledoc """
  The start page: create a game for 1 to 4 players, or join an open game on this
  node. Creating a game seats this browser in seat 0 and opens `/g/:id`.

  The "Ingredient books" form picks the Set (1–4) per colour for the games created
  here. It is a plain `phx-change` form: every change sends all selects, and the
  chosen sets wait in the assigns until a New game button is clicked.

  `?seed=1,2,3` makes the games created here reproducible.
  """
  use QuacksWeb, :live_view

  alias Quacks.GameServer

  # The colours with four ingredient books, in the order the form shows them.
  @book_colours [:green, :blue, :red, :yellow, :purple]

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.lobby_topic())

    {:ok,
     assign(socket,
       page_title: "Quacks",
       token: session["player_token"],
       seed: parse_seed(params["seed"]),
       sets: Map.new(@book_colours, &{&1, 1}),
       games: GameServer.open_games()
     )}
  end

  @impl true
  def handle_event("new_game", %{"players" => players}, socket) do
    {:ok, id} =
      GameServer.start(String.to_integer(players), socket.assigns.seed, socket.assigns.sets)

    {:ok, 0} = GameServer.claim_seat(id, socket.assigns.token)
    {:noreply, push_navigate(socket, to: ~p"/g/#{id}")}
  end

  def handle_event("sets", %{"sets" => params}, socket) when is_map(params),
    do: {:noreply, assign(socket, sets: parse_sets(params))}

  # A game started, filled up or stopped somewhere: list the open games again.
  @impl true
  def handle_info(:games_changed, socket),
    do: {:noreply, assign(socket, games: GameServer.open_games())}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-bold">Quacks</h1>

      <form id="books" phx-change="sets" aria-label="Ingredient books">
        <h2 class="text-sm font-semibold text-zinc-600">Ingredient books</h2>
        <div class="mt-2 grid grid-cols-2 gap-x-2 sm:grid-cols-5">
          <.input
            :for={colour <- book_colours()}
            type="select"
            id={"sets-#{colour}"}
            name={"sets[#{colour}]"}
            label={String.capitalize(to_string(colour))}
            value={@sets[colour]}
            options={Enum.map(1..4, &{"Set #{&1}", &1})}
          />
        </div>
      </form>

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

  @doc "The colours the Ingredient books form offers."
  @spec book_colours() :: [atom]
  def book_colours, do: @book_colours

  @doc """
  The form's `%{"green" => "2", ...}` as `%{green: 2, ...}`. A missing or bad value
  is Set 1, so a crafted request cannot break the game.
  """
  @spec parse_sets(map) :: %{atom => 1..4}
  def parse_sets(params) do
    Map.new(@book_colours, fn colour ->
      with value when is_binary(value) <- params[to_string(colour)],
           {set, ""} when set in 1..4 <- Integer.parse(value) do
        {colour, set}
      else
        _ -> {colour, 1}
      end
    end)
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
