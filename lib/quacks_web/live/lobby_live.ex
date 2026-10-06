defmodule QuacksWeb.LobbyLive do
  @moduledoc """
  The start page: a small hero (cauldron, title, tagline) and the **spell book**,
  where a new game is set up and a game is joined.

  The book has three pages, each with a ribbon bookmark (`#bookmark-new`,
  `#bookmark-books`, `#bookmark-join`):

    * **New game** (`#page-new`): the player count, the seats (you, open seats,
      bots), your name and colour, the Public toggle, the expansions and the house
      rules.
    * **Ingredient books** (`#page-books`): Random books, Reset to book I, the herb
      witch pickers (with The Herb Witches) and the 7 book pickers. The Start seal
      (`#new-game`) sits at its foot.
    * **Join a game** (`#page-join`): a room-code field and the games on this node
      (`Quacks.GameServer.games/1`) with Join, Resume or Watch.

  From 64rem the book lies open: New game on the left, Ingredient books on the
  right; the Join bookmark puts the Join page on the right. Below 64rem one page
  shows at a time. Which page shows is the book's `data-page` attribute, set in the
  browser by the bookmarks (`turn/1`, a JS command, so no round trip) and placed by
  app.css (`.spell-book`). `?page=join` opens the book at the Join page.

  The settings live in this page's assigns until Start: no game exists while the
  host turns pages. Each change goes to the browser's memory (`save_config`, the
  `ConfigMemory` hook), and the book opens with the last settings (`load_config`).
  Start creates the table (`Quacks.GameServer.create/3`) and goes to `/g/:id`: the
  game itself when no seat is left for a human, else the configure screen, where
  the others join by link or room code.

  `?seed=1,2,3` makes the games created here reproducible.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.GameComponents, only: [bot_badge: 1, palette_bg: 1]

  import QuacksWeb.SetupComponents,
    only: [
      books_form: 1,
      colour_picker: 1,
      default_sets: 0,
      expansion_cards: 1,
      options_form: 1,
      parse_books: 1,
      parse_rules: 1,
      random_sets: 1,
      step_rule: 3,
      switch_card: 1
    ]

  alias Quacks.{Game, GameServer}

  @pages ~w(new books join)
  @max_players 8

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.lobby_topic())
    token = session["player_token"]

    {:ok,
     assign(socket,
       page_title: "Quacks",
       token: token,
       seed: parse_seed(params["seed"]),
       page: if(params["page"] in @pages, do: params["page"], else: "new"),
       games: GameServer.games(token),
       players: 2,
       bots: MapSet.new(),
       name: "",
       colour: 0,
       public: true,
       sets: default_sets(),
       witches: %{},
       expansion: false,
       alchemists: false,
       rules: Game.default_rules()
     )}
  end

  # -- the New game page --------------------------------------------------------------

  @impl true
  def handle_event("players", %{"count" => count}, socket) do
    case Integer.parse(to_string(count)) do
      {n, ""} when n in 1..@max_players -> {:noreply, change(socket, players: n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("add_bot", %{"seat" => seat}, socket),
    do: {:noreply, toggle_bot(socket, seat, &MapSet.put/2)}

  def handle_event("remove_bot", %{"seat" => seat}, socket),
    do: {:noreply, toggle_bot(socket, seat, &MapSet.delete/2)}

  def handle_event("rename", %{"name" => name}, socket) when is_binary(name),
    do: {:noreply, change(socket, name: name |> String.trim() |> String.slice(0, 20))}

  def handle_event("colour", %{"colour" => colour}, socket) do
    case Integer.parse(to_string(colour)) do
      {c, ""} when c in 0..7 -> {:noreply, change(socket, colour: c)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("public", params, socket),
    do: {:noreply, change(socket, public: params["public"] == "true")}

  def handle_event("rules", %{"rules" => params}, socket) when is_map(params),
    do: {:noreply, change(socket, rules: parse_rules(params))}

  def handle_event("rule_step", %{"rule" => rule, "to" => to}, socket),
    do: {:noreply, change(socket, rules: step_rule(socket.assigns.rules, rule, to))}

  # -- the Ingredient books page ------------------------------------------------------

  def handle_event("sets", form, socket) do
    books = parse_books(form)

    {:noreply,
     change(socket,
       sets: books.sets,
       witches: books.witches,
       expansion: books.expansion == :herb_witches,
       alchemists: books.expansions == [:alchemists]
     )}
  end

  # A random book per colour; another press rolls again.
  def handle_event("random_books", _params, socket),
    do: {:noreply, change(socket, sets: random_sets(socket.assigns.alchemists))}

  def handle_event("reset_books", _params, socket),
    do: {:noreply, change(socket, sets: default_sets())}

  # The book opens with this browser's last settings (the `ConfigMemory` hook).
  # Bad or stale values fall back to the defaults.
  def handle_event("load_config", saved, socket) when is_map(saved) do
    books =
      parse_books(%{
        "sets" => saved["sets"],
        "witches" => saved["witches"],
        "expansion" => saved["expansion"],
        "alchemists" => saved["alchemists"]
      })

    players =
      if saved["players"] in 1..@max_players, do: saved["players"], else: socket.assigns.players

    bots = for seat <- List.wrap(saved["bots"]), is_integer(seat), into: MapSet.new(), do: seat

    {:noreply,
     socket
     |> assign(
       players: players,
       bots: bots,
       colour: if(saved["colour"] in 0..7, do: saved["colour"], else: socket.assigns.colour),
       public: saved["public"] != false,
       sets: books.sets,
       witches: books.witches,
       expansion: books.expansion == :herb_witches,
       alchemists: books.expansions == [:alchemists],
       rules: parse_rules(if is_map(saved["rules"]), do: saved["rules"], else: %{})
     )
     |> drop_extra_bots()}
  end

  def handle_event("load_config", _saved, socket), do: {:noreply, socket}

  # The Start seal: the table is created now, set up as the book says.
  def handle_event("start", _params, socket) do
    a = socket.assigns

    config = %{
      players: a.players,
      bots: MapSet.to_list(a.bots),
      name: a.name,
      colour: a.colour,
      public: a.public,
      sets: a.sets,
      rules: a.rules,
      witches: if(a.expansion, do: a.witches, else: %{}),
      expansion: if(a.expansion, do: :herb_witches),
      expansions: if(a.alchemists, do: [:alchemists], else: [])
    }

    case GameServer.create(config, a.token, a.seed) do
      {:ok, id} -> {:noreply, push_navigate(socket, to: ~p"/g/#{id}")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "These settings make no game.")}
    end
  end

  # -- the Join page ------------------------------------------------------------------

  # A room code (or a whole game link) takes you to that game.
  def handle_event("join_code", %{"code" => code}, socket) when is_binary(code) do
    code = code |> String.trim() |> String.trim_trailing("/") |> String.split("/") |> List.last()
    code = String.downcase(code || "")

    case GameServer.get(code) do
      {:ok, _table} ->
        {:noreply, push_navigate(socket, to: ~p"/g/#{code}")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No game has the room code “#{code}”.")}
    end
  end

  def handle_event("join_code", _params, socket), do: {:noreply, socket}

  # A game started, filled up, stopped or reached a new round: list the games again.
  @impl true
  def handle_info(:games_changed, socket),
    do: {:noreply, assign(socket, games: GameServer.games(socket.assigns.token))}

  # A settings change: assign it and keep it in the browser.
  defp change(socket, changes) do
    socket = socket |> assign(changes) |> drop_extra_bots()
    push_event(socket, "save_config", saved_config(socket.assigns))
  end

  # The settings in the shape `ConfigMemory` keeps (the configure screen's shape,
  # plus `public`, `bots` and `colour`).
  defp saved_config(a) do
    form = fn map -> Map.new(map, fn {key, value} -> {key, to_string(value)} end) end

    %{
      players: a.players,
      sets: form.(a.sets),
      rules: form.(a.rules),
      witches: form.(a.witches),
      expansion: a.expansion,
      alchemists: a.alchemists,
      public: a.public,
      bots: a.bots |> MapSet.to_list() |> Enum.sort(),
      colour: a.colour
    }
  end

  defp toggle_bot(socket, seat, fun) do
    case Integer.parse(to_string(seat)) do
      {s, ""} when s in 1..(@max_players - 1)//1 ->
        change(socket, bots: fun.(socket.assigns.bots, s))

      _ ->
        socket
    end
  end

  # Only seats 1..players-1 can hold a bot.
  defp drop_extra_bots(socket) do
    players = socket.assigns.players
    assign(socket, bots: MapSet.filter(socket.assigns.bots, &(&1 in 1..(players - 1)//1)))
  end

  # A bookmark: shows `page` (app.css places it by the book's `data-page`).
  defp turn(page) do
    Enum.reduce(
      @pages,
      JS.set_attribute({"data-page", page}, to: "#spell-book")
      |> JS.set_attribute({"data-turned", ""}, to: "#spell-book"),
      &JS.set_attribute(&2, {"aria-selected", to_string(&1 == page)}, to: "#bookmark-#{&1}")
    )
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        open_seats: assigns.players - 1 - MapSet.size(assigns.bots),
        bookmarks: [
          {"new", "New game", "hero-sparkles", "bg-ruby"},
          {"books", "Books", "hero-book-open", "bg-potion-deep"},
          {"join", "Join", "hero-user-group", "bg-droplet"}
        ]
      )

    ~H"""
    <Layouts.app flash={@flash} full>
      <div class="mx-auto max-w-6xl px-3 pt-4 pb-6 sm:px-6 lg:pt-6">
        <header
          class="lobby-hero flex items-center justify-center gap-3 text-left"
          data-role="lobby-hero"
        >
          <div
            class="lobby-glow grid size-20 shrink-0 place-items-center sm:size-24"
            aria-hidden="true"
          >
            <.piece_icon
              name={:cauldron}
              class="size-16 text-parchment drop-shadow-[0_6px_10px_rgb(0_0_0/0.5)] sm:size-20"
            />
          </div>
          <div>
            <h1 class="font-hand text-5xl leading-none font-bold tracking-tight text-parchment">
              Quacks
            </h1>
            <p class="mt-1 text-sm text-parchment-dim sm:text-base">
              Brew, push your luck, don't explode.
            </p>
          </div>
        </header>

        <div id="spell-book" class="spell-book mt-3" data-page={@page}>
          <%!-- The ribbons hang over the cover's top edge; a tap turns to their page. --%>
          <div
            class="relative z-10 flex justify-center gap-2 px-4 sm:justify-end sm:gap-3 sm:px-10"
            role="tablist"
            aria-label="Spell book pages"
          >
            <button
              :for={{page, label, icon, bg} <- @bookmarks}
              id={"bookmark-#{page}"}
              type="button"
              role="tab"
              aria-selected={to_string(page == @page)}
              aria-controls={"page-#{page}"}
              phx-click={turn(page)}
              data-bookmark={page}
              class={["bookmark", bg]}
            >
              <.icon name={icon} class="size-4 shrink-0" />{label}
            </button>
          </div>

          <div class="book-cover -mt-3">
            <div class="book-spread">
              <.new_game_page {assigns} />
              <.books_page {assigns} />
              <.join_page {assigns} />
            </div>
          </div>
        </div>

        <div id="config-memory" phx-hook="ConfigMemory" data-fresh hidden />

        <%!-- Shown by app.js only: the install button after `beforeinstallprompt`, the
             hint on iOS Safari outside the installed app (see `.pwa-install` in app.css). --%>
        <div id="install-app" class="flex flex-col items-center gap-1 pt-6 text-center">
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
          <a
            href="https://creativecommons.org/licenses/by/3.0/"
            class="underline hover:text-parchment"
          >CC BY 3.0</a>
          (background removed, recoloured).
        </footer>
      </div>
    </Layouts.app>
    """
  end

  # The left page: players, seats, you, Public, expansions, house rules.
  defp new_game_page(assigns) do
    ~H"""
    <section
      id="page-new"
      class="book-page book-page-left"
      data-book-page="new"
      role="tabpanel"
      aria-labelledby="bookmark-new"
    >
      <h2 class="book-heading">New game</h2>

      <div class="book-rule flex items-center gap-3" data-role="player-count">
        <span class="font-semibold">Players</span>
        <.button
          phx-click="players"
          phx-value-count={@players - 1}
          disabled={@players <= 1}
          aria-label="Fewer players"
          variant={:secondary}
          class="size-11 px-0 text-xl"
        >
          −
        </.button>
        <span class="w-6 text-center text-2xl font-bold tabular-nums" data-role="count">
          {@players}
        </span>
        <.button
          phx-click="players"
          phx-value-count={@players + 1}
          disabled={@players >= 8}
          aria-label="More players"
          variant={:secondary}
          class="size-11 px-0 text-xl"
        >
          +
        </.button>
        <span class="ml-auto text-sm text-ink-soft">
          {if @players == 1, do: "Solo", else: "#{@players} at the table"}
        </span>
      </div>

      <ol class="mt-1" aria-label="Seats">
        <li
          :for={seat <- 0..(@players - 1)}
          class="book-line flex min-h-11 flex-wrap items-center gap-x-2"
          data-seat={seat}
          data-role="seat-slot"
        >
          <%= cond do %>
            <% seat == 0 -> %>
              <span class={["size-3 shrink-0 rounded-full ring-1 ring-black/30", palette_bg(@colour)]} />
              <form id="rename-form" phx-change="rename" phx-submit="rename" class="min-w-0 flex-1">
                <input
                  type="text"
                  name="name"
                  id="seat-name"
                  phx-hook="NameMemory"
                  value={@name}
                  placeholder={GameServer.default_name(0)}
                  phx-debounce="300"
                  maxlength="20"
                  autocomplete="off"
                  aria-label="Your name"
                  class="w-full border-0 border-b border-dashed border-ink-soft/40 bg-transparent py-1.5 font-hand text-lg font-bold text-ink outline-none transition-colors duration-150 placeholder:text-ink-soft/70 focus:border-ink-soft"
                />
              </form>
              <span class="text-xs font-semibold text-ink-soft">you · host</span>
              <.colour_picker colours={%{0 => @colour}} seat={0} />
            <% MapSet.member?(@bots, seat) -> %>
              <span class="hero-cpu-chip size-4 shrink-0 text-ink-soft" aria-hidden="true" />
              <span class="font-semibold">Bot</span>
              <.bot_badge />
              <button
                type="button"
                phx-click="remove_bot"
                phx-value-seat={seat}
                aria-label={"Remove the bot in seat #{seat + 1}"}
                data-role="remove-bot"
                class="-mr-1 ml-auto grid size-9 cursor-pointer place-items-center rounded-full text-ink-soft transition-[color,background-color,scale] duration-150 ease-out hover:bg-ink/10 hover:text-ink active:scale-90"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            <% true -> %>
              <span class="size-3 shrink-0 rounded-full ring-1 ring-ink-soft/50 ring-inset" />
              <span class="text-ink-soft italic">Open seat</span>
              <button
                type="button"
                phx-click="add_bot"
                phx-value-seat={seat}
                data-role="add-bot"
                class="hit-44 -mr-1 ml-auto min-h-9 cursor-pointer rounded-full px-3 text-sm font-semibold text-ink-soft transition-[color,background-color,scale] duration-150 ease-out hover:bg-ink/10 hover:text-ink active:scale-95"
              >
                + Add bot
              </button>
          <% end %>
        </li>
      </ol>
      <p :if={@open_seats > 0} class="mt-1 text-sm text-ink-soft" data-role="open-seats-note">
        Open seats wait for players: they join with the link or the room code.
      </p>

      <form id="table-form" phx-change="public" class="mt-4" aria-label="Table">
        <.switch_card
          id="public"
          name="public"
          checked={@public}
          title="Public table"
          text={
            if @public,
              do: "Listed on the Join page.",
              else: "Private: players join with the room code."
          }
          icon="hero-globe-europe-africa"
          small
        />
      </form>

      <.expansion_cards
        expansion={@expansion}
        alchemists={@alchemists}
        pot_side={@rules.pot_side}
        class="mt-4"
      />

      <%!-- The browser owns `open`: a patch must not close it while the host steps. --%>
      <details id="options-section" class="mt-4" phx-mounted={JS.ignore_attributes("open")}>
        <summary class="book-subheading cursor-pointer">House rules</summary>
        <div class="mt-2"><.options_form rules={@rules} /></div>
      </details>

      <%!-- Phones: one page at a time, so the next page is a tap away. --%>
      <button
        type="button"
        phx-click={turn("books") |> JS.focus(to: "#page-books-heading")}
        class="mt-5 flex min-h-12 w-full cursor-pointer items-center justify-center gap-2 rounded-xl bg-potion-deep px-4 font-hand text-lg font-bold text-parchment-light shadow-md transition-[scale,filter] duration-150 ease-out hover:brightness-110 active:scale-[0.98] lg:hidden"
        data-role="to-books"
      >
        Choose the ingredient books <.icon name="hero-arrow-right" class="size-5" />
      </button>
    </section>
    """
  end

  # The right page: random books, witch and book pickers, the Start seal.
  defp books_page(assigns) do
    ~H"""
    <section
      id="page-books"
      class="book-page book-page-right"
      data-book-page="books"
      role="tabpanel"
      aria-labelledby="bookmark-books"
    >
      <h2 id="page-books-heading" class="book-heading outline-none" tabindex="-1">
        Ingredient books
      </h2>
      <div class="book-rule flex flex-wrap items-center gap-2">
        <button
          id="random-books"
          type="button"
          phx-click="random_books"
          class="inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-full bg-ink px-4 text-sm font-bold text-parchment-light shadow-sm transition-[scale,filter] duration-150 ease-out hover:brightness-125 active:scale-95"
        >
          <.icon name="hero-arrow-path-rounded-square" class="size-5" /> Random books
        </button>
        <button
          id="reset-books"
          type="button"
          phx-click="reset_books"
          class="inline-flex min-h-11 cursor-pointer items-center rounded-full px-3 text-sm font-semibold text-ink-soft ring-1 ring-ink-soft/40 transition-[color,background-color,scale] duration-150 ease-out hover:bg-ink/10 hover:text-ink active:scale-95"
        >
          Reset to book I
        </button>
      </div>

      <div class="mt-3 mb-4">
        <.books_form
          sets={@sets}
          expansion={@expansion}
          alchemists={@alchemists}
          pot_side={@rules.pot_side}
          players={@players}
          witches={@witches}
          expansion_cards={false}
          heading={false}
        />
      </div>

      <%!-- The wax seal: always in reach at the page's foot. --%>
      <div class="seal-bar" data-role="start-bar">
        <p class="min-w-0 flex-1 text-sm leading-snug text-ink-soft" data-role="setup-summary">
          <span class="block font-semibold text-ink">{summary(assigns)}</span>
          {if @open_seats > 0,
            do: "Opens the table: #{waiting(@open_seats)}.",
            else: "The game begins at once."}
        </p>
        <button
          id="new-game"
          type="button"
          phx-click="start"
          class="wax-seal"
          aria-label="Start: new game"
        >
          <span aria-hidden="true">Start</span>
        </button>
      </div>
    </section>
    """
  end

  # The third page: a room code, and the games on this node.
  defp join_page(assigns) do
    ~H"""
    <section
      id="page-join"
      class="book-page book-page-right"
      data-book-page="join"
      role="tabpanel"
      aria-labelledby="bookmark-join"
    >
      <h2 class="book-heading">Join a game</h2>
      <form
        id="room-code-form"
        phx-submit="join_code"
        class="book-rule flex items-end gap-2"
        aria-label="Join by room code"
      >
        <label class="min-w-0 flex-1">
          <span class="block text-sm font-semibold">Room code</span>
          <input
            type="text"
            id="room-code"
            name="code"
            placeholder="abcdef"
            autocomplete="off"
            autocapitalize="none"
            spellcheck="false"
            maxlength="80"
            class="w-full border-0 border-b-2 border-ink-soft/50 bg-transparent py-1.5 font-mono text-lg tracking-widest text-ink outline-none placeholder:text-ink-soft/40 focus:border-ink"
          />
        </label>
        <.button type="submit" variant={:primary} class="min-h-11 px-5">Go</.button>
      </form>

      <h3 class="book-subheading mt-4">Games now</h3>
      <ul id="games" class="mt-2 grid gap-2.5 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
        <.game_card :for={game <- @games} game={game} />
        <li
          :if={@games == []}
          class="col-span-full rounded-[14px] border border-dashed border-ink-soft/40 px-3 py-4 text-center text-sm text-ink-soft"
          data-role="no-games"
        >
          No public games now. Start one, or ask for a room code.
        </li>
      </ul>
    </section>
    """
  end

  attr :game, :map, required: true

  defp game_card(assigns) do
    assigns = assign(assigns, action: action(assigns.game))

    ~H"""
    <li
      id={"game-#{@game.id}"}
      class="flex flex-col gap-2 rounded-[14px] bg-parchment-light/80 p-3 ring-1 ring-ink/15"
      data-role="open-game"
      data-status={@game.status}
    >
      <div class="flex items-center justify-between gap-2">
        <span class="flex items-center gap-1.5 font-mono text-sm font-semibold">
          {@game.id}
          <span :if={!@game.public} class="inline-flex text-ink-soft" title="private">
            <.icon name="hero-lock-closed-mini" class="size-3.5" />
            <span class="sr-only">private</span>
          </span>
        </span>
        <span
          :if={host = @game.creator && @game.names[@game.creator]}
          class="truncate text-xs text-ink-soft"
        >
          {host}'s table
        </span>
      </div>
      <div class="flex items-center gap-2">
        <ol class="flex flex-wrap gap-1" aria-hidden="true">
          <li
            :for={seat <- 0..(@game.players - 1)}
            class={[
              "size-3.5 rounded-full",
              if(Map.has_key?(@game.names, seat),
                do: ["ring-1 ring-black/30", palette_bg(Map.get(@game.colours, seat, seat))],
                else: "ring-1 ring-ink-soft/50 ring-inset"
              )
            ]}
            data-role="seat-dot"
            data-taken={Map.has_key?(@game.names, seat) && "true"}
          />
        </ol>
        <span class="text-xs text-ink-soft" data-role="game-status">{status(@game)}</span>
      </div>
      <div class="flex items-end justify-between gap-2">
        <ul class="flex flex-wrap gap-1" aria-label="Expansions">
          <li
            :for={{name, icon} <- expansion_badges(@game)}
            class="inline-flex items-center gap-1 rounded-full bg-ink/10 py-0.5 pr-2 pl-1 text-[11px] font-semibold"
            data-role="expansion-badge"
          >
            <.piece_icon name={icon} class="size-3.5" />{name}
          </li>
          <li
            :if={expansion_badges(@game) == []}
            class="text-[11px] text-ink-soft"
            data-role="expansion-badge"
          >
            Base game
          </li>
        </ul>
        <.button
          navigate={~p"/g/#{@game.id}"}
          variant={if @action == "Watch", do: :secondary, else: :primary}
          class="min-h-11 px-5"
          data-role="game-action"
        >
          {@action}
        </.button>
      </div>
    </li>
    """
  end

  # Resume a game you sit in, Join one with a free seat, Watch the rest.
  defp action(%{mine: seat}) when is_integer(seat), do: "Resume"

  defp action(%{status: :waiting} = game) when map_size(game.names) < game.max_players,
    do: "Join"

  defp action(_game), do: "Watch"

  defp status(%{status: :waiting} = game) do
    free = game.max_players - map_size(game.names)
    "#{map_size(game.names)} of #{game.players} seated · #{seats(free)} free"
  end

  defp status(%{game: game}), do: "Round #{game.round} of 9 · #{length(game.seats)} players"

  defp waiting(1), do: "1 seat waits for a player"
  defp waiting(n), do: "#{n} seats wait for players"

  defp seats(1), do: "1 seat"
  defp seats(n), do: "#{n} seats"

  # "3 players · 1 bot · Herb Witches · The Alchemists · test tubes · private".
  defp summary(a) do
    bots = MapSet.size(a.bots)

    [
      if(a.players == 1, do: "Solo", else: "#{a.players} players"),
      bots > 0 && if(bots == 1, do: "1 bot", else: "#{bots} bots"),
      a.expansion && "Herb Witches",
      a.alchemists && "The Alchemists",
      a.rules.pot_side == :back && "test tubes",
      !a.public && a.players > 1 && "private"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  # The expansions of a game, as badges: name and icon.
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
