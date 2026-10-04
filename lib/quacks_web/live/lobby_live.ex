defmodule QuacksWeb.LobbyLive do
  @moduledoc """
  The start page: a hero (cauldron, title, tagline), a "New game" button and the
  open games on this node as cards (seat dots, expansion badges, Join).

  "New game" opens a waiting game for 2 players with this browser in seat 0 (the
  host) and goes to `/g/:id`. There the host sets the game up: the player count,
  the Ingredient books, the options (see `QuacksWeb.GameLive`).

  `?seed=1,2,3` makes the games created here reproducible.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.GameComponents, only: [palette_bg: 1]

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
      <header class="lobby-hero flex flex-col items-center pt-4 text-center" data-role="lobby-hero">
        <div class="lobby-glow grid size-36 place-items-center" aria-hidden="true">
          <.piece_icon
            name={:cauldron}
            class="size-28 text-parchment drop-shadow-[0_6px_10px_rgb(0_0_0/0.5)]"
          />
        </div>
        <h1 class="font-hand text-[56px] leading-none font-bold tracking-tight text-parchment">
          Quacks
        </h1>
        <p class="mt-2 text-base text-parchment-dim">Brew, push your luck, don't explode.</p>
      </header>

      <%!-- The page's one action: hero-sized, a press you can feel. --%>
      <button
        id="new-game"
        type="button"
        phx-click="new_game"
        class={[
          "flex min-h-20 w-full cursor-pointer touch-manipulation items-center justify-center gap-3 rounded-2xl",
          "bg-gold px-6 font-hand text-4xl font-bold text-ink shadow-lg shadow-black/40 ring-2 ring-parchment/60",
          "transition-[scale,filter] duration-150 ease-out hover:brightness-110 active:scale-[0.97]",
          "phx-click-loading:opacity-80 motion-reduce:transition-none"
        ]}
      >
        <.icon name="hero-sparkles" class="size-8" /> New game
      </button>

      <section aria-label="Open games" class="pt-2">
        <h2 class="font-hand text-xl font-bold text-parchment-dim">Open games</h2>
        <ul class="mt-2 grid gap-2.5 sm:grid-cols-2">
          <li
            :for={game <- @games}
            id={"game-#{game.id}"}
            class="paper flex flex-col gap-2 rounded-[14px] p-3"
            data-role="open-game"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="font-mono text-sm font-semibold">{game.id}</span>
              <span
                :if={host = game.creator && game.names[game.creator]}
                class="truncate text-xs text-ink-soft"
              >
                {host}'s table
              </span>
            </div>
            <div class="flex items-center gap-2">
              <ol class="flex flex-wrap gap-1" aria-hidden="true">
                <li
                  :for={seat <- 0..(game.players - 1)}
                  class={[
                    "size-3.5 rounded-full",
                    if(Map.has_key?(game.names, seat),
                      do: ["ring-1 ring-black/30", palette_bg(Map.get(game.colours, seat, seat))],
                      else: "ring-1 ring-ink-soft/50 ring-inset"
                    )
                  ]}
                  data-role="seat-dot"
                  data-taken={Map.has_key?(game.names, seat) && "true"}
                />
              </ol>
              <span class="text-xs text-ink-soft">
                {map_size(game.names)} of {game.players} seated
              </span>
            </div>
            <div class="flex items-end justify-between gap-2">
              <ul class="flex flex-wrap gap-1" aria-label="Expansions">
                <li
                  :for={{name, icon} <- expansion_badges(game)}
                  class="inline-flex items-center gap-1 rounded-full bg-ink/10 py-0.5 pr-2 pl-1 text-[11px] font-semibold"
                  data-role="expansion-badge"
                >
                  <.piece_icon name={icon} class="size-3.5" />{name}
                </li>
                <li
                  :if={expansion_badges(game) == []}
                  class="text-[11px] text-ink-soft"
                  data-role="expansion-badge"
                >
                  Base game
                </li>
              </ul>
              <.button navigate={~p"/g/#{game.id}"} variant={:primary} class="min-h-11 px-5">
                Join
              </.button>
            </div>
          </li>
          <li
            :if={@games == []}
            class="rounded-[14px] border border-dashed border-parchment-dim/40 px-3 py-4 text-center text-sm text-parchment-dim"
            data-role="no-games"
          >
            No open games. Start one.
          </li>
        </ul>
      </section>

      <%!-- Shown by app.js only: the install button after `beforeinstallprompt`, the
           hint on iOS Safari outside the installed app (see `.pwa-install` in app.css). --%>
      <div id="install-app" class="flex flex-col items-center gap-1 pt-4 text-center">
        <button
          type="button"
          data-role="install"
          class={[
            "pwa-install min-h-11 cursor-pointer items-center gap-2 rounded-full px-4",
            "text-sm font-semibold text-parchment-dim ring-1 ring-parchment-dim/40",
            "transition-colors duration-150 hover:bg-parchment/10 hover:text-parchment"
          ]}
        >
          <.icon name="hero-arrow-down-tray" class="size-4" /> Install app
        </button>
        <p data-role="install-hint" class="pwa-ios-hint text-xs text-parchment-dim">
          Add to Home Screen from the Share menu.
        </p>
      </div>

      <footer id="credits" class="pt-6 text-center text-xs text-parchment-dim">
        Credits: icons by Lorc, Delapouite, Skoll, Cathelineau and DarkZaitzev from <a
          href="https://game-icons.net"
          class="underline hover:text-parchment"
        >game-icons.net</a>,
        <a href="https://creativecommons.org/licenses/by/3.0/" class="underline hover:text-parchment">CC BY 3.0</a>
        (background removed, recoloured).
      </footer>
    </Layouts.app>
    """
  end

  # The expansions of an open game, as badges: name and icon.
  defp expansion_badges(game) do
    for {key, name, icon} <- [
          {:herb_witches, "Herb Witches", :witch},
          {:alchemists, "Alchemists", :flask}
        ],
        MapSet.member?(game.expansions, key),
        do: {name, icon}
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
