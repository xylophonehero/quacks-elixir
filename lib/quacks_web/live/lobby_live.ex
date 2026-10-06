defmodule QuacksWeb.LobbyLive do
  @moduledoc """
  The start page: a small hero (cauldron, title, tagline) and the **spell book**,
  where a game is joined or a new game is set up.

  The book is a set of pages; the URL's `?step=` says which one shows, so the
  browser's Back button turns back (each step is a `push_patch`):

    * `home` (`#page-home`, no `?step=`): the room-code field and the games on this
      node (`Quacks.GameServer.games/1`) with Resume, Join or Watch, and the
      New game button.
    * `players` (`#page-players`): the player count, the seats (you, open seats,
      bots), your name and colour, the Public toggle; Next.
    * `expansions` (`#page-expansions`): The Herb Witches, The Alchemists and the
      reverse pot side as three cards, the House rules and Ingredient books
      buttons and the Start bar (`#new-game`).
    * `rules` (`#page-rules`): the house rules.
    * `books` (`#page-books`): the presets row (`Quacks.Rules.BookPresets`, plus
      Random), the herb witch tiles and the book tiles. A tile opens its colour's
      page: `book` (`#page-book-green`, `?step=book&colour=green`) or `witch`
      (`#page-witch-copper`), the full cards; a pick goes back to `books`.

  Below 64rem one page shows at a time. From 64rem the book lies open: home or
  players on the left, expansions (or rules, books, a colour page) on the right.
  Every page is always in the DOM and the server hides the others with `hidden` /
  `lg:hidden` (`visible/2`), so the forms keep all their fields: the colour pages'
  radio cards belong to `#books` by their `form` attribute.

  A page's Back arrow goes back in the browser's history (`"quacks:back"` in
  app.js) when the page before it is this book's parent page, else it patches to
  the parent (`back/2`).

  The settings live in this page's assigns until Start: no game exists while the
  host turns pages. Each change goes to the browser's memory (`save_config`, the
  `ConfigMemory` hook), and the book opens with the last settings (`load_config`).
  Start creates the table (`Quacks.GameServer.create/3`) and goes to `/g/:id`: the
  game itself when no seat is left for a human, else the configure screen, where
  the others join by link or room code.

  `?seed=1,2,3` makes the games created here reproducible.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.GameComponents, only: [bot_badge: 1, palette_bg: 1, book_ink: 1]

  import QuacksWeb.SetupComponents,
    only: [
      book_colours: 0,
      book_name: 1,
      book_options: 1,
      books_form: 1,
      colour_picker: 1,
      default_sets: 0,
      expansion_cards: 1,
      options_form: 1,
      parse_books: 1,
      parse_rules: 1,
      random_sets: 1,
      step_rule: 3,
      switch_card: 1,
      witch_colours: 0,
      witch_options: 1
    ]

  alias Quacks.{Game, GameServer}
  alias Quacks.Rules.BookPresets

  @max_players 8

  # Each step's parent page and its depth in the book (home is the root).
  @parents %{
    "players" => "home",
    "expansions" => "players",
    "rules" => "expansions",
    "books" => "expansions",
    "book" => "books",
    "witch" => "books"
  }
  @depth %{
    "home" => 0,
    "players" => 1,
    "expansions" => 2,
    "rules" => 3,
    "books" => 3,
    "book" => 4,
    "witch" => 4
  }
  # The round-17 `?page=` links.
  @old_pages %{"new" => "players", "books" => "books", "join" => "home"}

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.lobby_topic())
    token = session["player_token"]

    {:ok,
     assign(socket,
       page_title: "Quacks",
       token: token,
       seed: parse_seed(params["seed"]),
       games: GameServer.games(token),
       players: 2,
       bots: MapSet.new(),
       name: "",
       colour: 0,
       public: true,
       sets: default_sets(),
       rolled: nil,
       witches: %{},
       expansion: false,
       alchemists: false,
       rules: Game.default_rules(),
       step: "home",
       colour_page: nil,
       entry_depth: nil,
       turned: false
     )}
  end

  # The page to show: `?step=` (and `colour=` for a colour page); a bad value is home.
  @impl true
  def handle_params(params, _uri, socket) do
    {step, colour} = parse_step(params, socket.assigns.expansion)
    depth = @depth[step]
    entry = socket.assigns.entry_depth

    {:noreply,
     assign(socket,
       step: step,
       colour_page: colour,
       entry_depth: if(entry, do: min(entry, depth), else: depth),
       turned: entry != nil
     )}
  end

  defp parse_step(%{"step" => "book", "colour" => colour}, _expansion) do
    case Enum.find(book_colours(), &(Atom.to_string(&1) == colour)) do
      nil -> {"books", nil}
      colour -> {"book", colour}
    end
  end

  defp parse_step(%{"step" => "witch", "colour" => colour}, true) do
    case Enum.find(witch_colours(), &(Atom.to_string(&1) == colour)) do
      nil -> {"books", nil}
      colour -> {"witch", colour}
    end
  end

  defp parse_step(%{"step" => step}, _expansion)
       when step in ~w(players expansions rules books),
       do: {step, nil}

  defp parse_step(%{"step" => step}, _expansion) when step in ~w(book witch), do: {"books", nil}
  defp parse_step(%{"page" => page}, _expansion), do: {Map.get(@old_pages, page, "home"), nil}
  defp parse_step(_params, _expansion), do: {"home", nil}

  # -- the Players page ---------------------------------------------------------------

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

  # -- the Expansions and Ingredient books pages ------------------------------------

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

  # A preset's books; it also turns on the expansions it needs.
  def handle_event("preset", %{"id" => id}, socket) do
    case BookPresets.get(id) do
      nil ->
        {:noreply, socket}

      preset ->
        a = socket.assigns

        {:noreply,
         change(socket,
           sets: preset.sets,
           expansion: a.expansion or :herb_witches in preset.expansions,
           alchemists: a.alchemists or :alchemists in preset.expansions
         )}
    end
  end

  # A random book per colour; another press rolls again.
  def handle_event("random_books", _params, socket) do
    sets = random_sets(socket.assigns.alchemists)
    {:noreply, change(socket, sets: sets, rolled: sets)}
  end

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
       rolled: if(saved["preset"] == "random", do: books.sets),
       witches: books.witches,
       expansion: books.expansion == :herb_witches,
       alchemists: books.expansions == [:alchemists],
       rules: parse_rules(if is_map(saved["rules"]), do: saved["rules"], else: %{})
     )
     |> drop_extra_bots()}
  end

  def handle_event("load_config", _saved, socket), do: {:noreply, socket}

  # Start: the table is created now, set up as the book says.
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

  # -- the home page ------------------------------------------------------------------

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
  # plus `public`, `bots`, `colour` and `preset`).
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
      colour: a.colour,
      preset: preset_id(a)
    }
  end

  # The preset the books are now: a preset's id, "random" (the last roll) or nil
  # (Custom).
  defp preset_id(a) do
    case BookPresets.match(a.sets) do
      nil -> if a.rolled == a.sets, do: "random"
      preset -> to_string(preset.id)
    end
  end

  defp preset_label(a) do
    case preset_id(a) do
      nil -> "Custom"
      "random" -> "Random"
      id -> BookPresets.get(id).name
    end
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

  # -- pages --------------------------------------------------------------------------

  # The path of a page.
  defp page_path(step, colour \\ nil)
  defp page_path("home", _colour), do: ~p"/"
  defp page_path(step, nil), do: ~p"/?#{[step: step]}"
  defp page_path(step, colour), do: ~p"/?step=#{step}&colour=#{colour}"

  defp tile_path({:book, colour}), do: page_path("book", colour)
  defp tile_path({:witch, colour}), do: page_path("witch", colour)

  # Back from the page `step`: the browser's history when this book put the parent
  # page there (the page is deeper than the page the visit began on), else a patch.
  defp back(assigns, step) do
    if @depth[step] > assigns.entry_depth and @depth[assigns.step] == @depth[step],
      do: JS.dispatch("quacks:back"),
      else: JS.patch(page_path(@parents[step]))
  end

  # Is the page `page` (`{step, colour}`) shown: `{on a phone, from 64rem}`.
  defp visible(a, {page, colour}) do
    here = {a.step, a.colour_page}
    left = if a.step == "home", do: "home", else: "players"
    right = if a.step in ~w(home players expansions), do: "expansions", else: a.step

    {here == {page, colour},
     page == left or (page == right and (colour == nil or colour == a.colour_page))}
  end

  attr :a, :map, required: true, doc: "the LiveView's assigns"
  attr :id, :string, required: true
  attr :page, :any, required: true, doc: "`{step, colour}`"
  attr :side, :atom, required: true, values: [:left, :right]
  attr :title, :string, required: true
  attr :back_class, :any, default: nil
  attr :class, :any, default: nil
  slot :title_icon
  slot :inner_block, required: true

  defp book_page(assigns) do
    {step, _colour} = assigns.page
    {phone, wide} = visible(assigns.a, assigns.page)
    assigns = assign(assigns, step: step, phone: phone, wide: wide)

    ~H"""
    <section
      id={@id}
      class={[
        "book-page flex-col",
        if(@side == :left, do: "book-page-left", else: "book-page-right"),
        if(@phone, do: "flex", else: "hidden"),
        if(@wide, do: "lg:flex", else: "lg:hidden"),
        @class
      ]}
      data-step={@step}
      aria-labelledby={"#{@id}-title"}
    >
      <header class="book-heading flex items-center gap-2">
        <button
          :if={@step != "home"}
          type="button"
          phx-click={back(@a, @step)}
          class={[
            "-ml-2 grid size-11 shrink-0 cursor-pointer place-items-center rounded-full text-[#4f1a14]",
            "transition-[background-color,scale] duration-150 ease-out hover:bg-ink/10 active:scale-90",
            @back_class
          ]}
          aria-label="Back"
          data-role="back"
        >
          <.icon name="hero-arrow-left" class="size-6" />
        </button>
        {render_slot(@title_icon)}
        <h2 id={"#{@id}-title"} class="min-w-0 flex-1 truncate outline-none" tabindex="-1">
          {@title}
        </h2>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, open_seats: assigns.players - 1 - MapSet.size(assigns.bots))

    ~H"""
    <Layouts.app flash={@flash} full>
      <div class="mx-auto max-w-6xl px-3 pt-4 pb-6 sm:px-6 lg:pt-6">
        <header
          class={[
            "lobby-hero flex items-center justify-center gap-3 text-left",
            @step != "home" && "max-lg:hidden"
          ]}
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

        <div
          id="spell-book"
          class={["spell-book", if(@step == "home", do: "mt-3", else: "lg:mt-3")]}
          data-step={@step}
          data-turned={@turned}
        >
          <div class="book-cover">
            <div class="book-spread">
              <.home_page {assigns} />
              <.players_page {assigns} />
              <.expansions_page {assigns} />
              <.rules_page {assigns} />
              <.books_page {assigns} />
              <.book_page
                :for={colour <- book_colours()}
                a={assigns}
                id={"page-book-#{colour}"}
                page={{"book", colour}}
                side={:right}
                title={book_name(colour)}
              >
                <:title_icon>
                  <.ingredient_icon colour={colour} class={["size-8 shrink-0", book_ink(colour)]} />
                </:title_icon>
                <p class="text-sm text-ink-soft">
                  <span class="capitalize">{colour}</span>. Tap a book to use it.
                </p>
                <.book_options
                  colour={colour}
                  chosen={Quacks.Rules.Chips.set(nil, @sets, colour)}
                  players={@players}
                  alchemists={@alchemists}
                  form="books"
                  on_pick={back(assigns, "book")}
                  class="mt-3"
                />
              </.book_page>
              <%= if @expansion do %>
                <.book_page
                  :for={colour <- witch_colours()}
                  a={assigns}
                  id={"page-witch-#{colour}"}
                  page={{"witch", colour}}
                  side={:right}
                  title={"#{String.capitalize(to_string(colour))} witch"}
                >
                  <p class="text-sm text-ink-soft">Tap a witch to use her, or Random.</p>
                  <.witch_options
                    colour={colour}
                    chosen={@witches[colour]}
                    form="books"
                    on_pick={back(assigns, "witch")}
                    class="mt-3"
                  />
                </.book_page>
              <% end %>
            </div>
          </div>
        </div>

        <div id="config-memory" phx-hook="ConfigMemory" data-fresh hidden />

        <div :if={@step == "home"} class="contents">
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
      </div>
    </Layouts.app>
    """
  end

  # The first page: a room code, the games on this node, New game.
  defp home_page(assigns) do
    ~H"""
    <.book_page a={assigns} id="page-home" page={{"home", nil}} side={:left} title="Games">
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

      <%!-- Phones: pinned at the screen's foot while the list scrolls. --%>
      <div class="page-foot">
        <.link id="new-game-flow" patch={page_path("players")} class="flow-button">
          <.icon name="hero-sparkles" class="size-5" /> New game
        </.link>
      </div>
    </.book_page>
    """
  end

  # Players, seats, you, Public.
  defp players_page(assigns) do
    ~H"""
    <.book_page a={assigns} id="page-players" page={{"players", nil}} side={:left} title="New game">
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
              do: "Listed on the games page.",
              else: "Private: players join with the room code."
          }
          icon="hero-globe-europe-africa"
          small
        />
      </form>

      <div class="page-foot lg:hidden">
        <.link id="to-expansions" patch={page_path("expansions")} class="flow-button">
          Next <.icon name="hero-arrow-right" class="size-5" />
        </.link>
      </div>
    </.book_page>
    """
  end

  # The expansions, the two buttons to the house rules and books, Start.
  defp expansions_page(assigns) do
    changed = Enum.count(assigns.rules, fn {key, value} -> Game.default_rules()[key] != value end)
    assigns = assign(assigns, changed: changed)

    ~H"""
    <.book_page
      a={assigns}
      id="page-expansions"
      page={{"expansions", nil}}
      side={:right}
      title="Expansions"
      back_class="lg:hidden"
    >
      <.expansion_cards
        expansion={@expansion}
        alchemists={@alchemists}
        pot_side={@rules.pot_side}
        heading={false}
      />

      <nav class="mt-4 mb-6 grid gap-2" aria-label="More settings">
        <.link id="to-rules" patch={page_path("rules")} class="page-link" data-role="to-rules">
          <.icon name="hero-scale" class="size-6 shrink-0 text-ink-soft" />
          <span class="min-w-0 flex-1">
            <span class="block font-hand text-lg leading-tight font-bold">House rules</span>
            <span class="block text-xs text-ink-soft" data-role="rules-summary">
              {if @changed == 0, do: "As in the rulebook", else: "#{@changed} changed"}
            </span>
          </span>
          <.icon name="hero-chevron-right" class="size-5 shrink-0 text-ink-soft" />
        </.link>
        <.link id="to-books" patch={page_path("books")} class="page-link" data-role="to-books">
          <.icon name="hero-book-open" class="size-6 shrink-0 text-ink-soft" />
          <span class="min-w-0 flex-1">
            <span class="block font-hand text-lg leading-tight font-bold">Ingredient books</span>
            <span class="block text-xs text-ink-soft" data-role="books-summary">
              {preset_label(assigns)}
            </span>
          </span>
          <.icon name="hero-chevron-right" class="size-5 shrink-0 text-ink-soft" />
        </.link>
      </nav>

      <div class="start-bar" data-role="start-bar">
        <p class="text-sm leading-snug text-ink-soft" data-role="setup-summary">
          <span class="block font-semibold text-ink">{summary(assigns)}</span>
          {if @open_seats > 0,
            do: "Opens the table: #{waiting(@open_seats)}.",
            else: "The game begins at once."}
        </p>
        <button id="new-game" type="button" phx-click="start" class="start-button">
          <.piece_icon name={:cauldron} class="size-7 shrink-0" /> Start
        </button>
      </div>
    </.book_page>
    """
  end

  defp rules_page(assigns) do
    ~H"""
    <.book_page a={assigns} id="page-rules" page={{"rules", nil}} side={:right} title="House rules">
      <.options_form rules={@rules} />
    </.book_page>
    """
  end

  # The presets row, then the witch and book tiles; a tile opens its colour's page.
  defp books_page(assigns) do
    assigns =
      assign(assigns,
        active: preset_id(assigns),
        presets: BookPresets.all()
      )

    ~H"""
    <.book_page
      a={assigns}
      id="page-books"
      page={{"books", nil}}
      side={:right}
      title="Ingredient books"
    >
      <div class="book-rule">
        <p class="text-sm">
          <span class="font-semibold">Preset:</span>
          <span data-role="preset-label">{preset_label(assigns)}</span>
        </p>
        <ul
          id="presets"
          class="-mx-1 mt-2 flex snap-x gap-2 overflow-x-auto px-1 pb-1"
          aria-label="Presets"
        >
          <li :for={preset <- @presets} class="snap-start">
            <button
              id={"preset-#{preset.id}"}
              type="button"
              phx-click="preset"
              phx-value-id={preset.id}
              aria-pressed={to_string(@active == to_string(preset.id))}
              class="preset-card"
              data-role="preset"
            >
              <span class="block font-hand text-base leading-tight font-bold">{preset.name}</span>
              <span class="mt-0.5 block text-[11px] leading-snug text-ink-soft">
                {preset.blurb}
              </span>
              <span
                :for={exp <- preset.expansions}
                class="mt-1 inline-block rounded-full bg-ink/10 px-1.5 text-[10px] font-semibold"
              >
                {if exp == :alchemists, do: "Alchemists", else: "Herb Witches"}
              </span>
            </button>
          </li>
          <li class="snap-start">
            <button
              id="preset-random"
              type="button"
              phx-click="random_books"
              aria-pressed={to_string(@active == "random")}
              class="preset-card"
              data-role="preset"
            >
              <span class="flex items-center gap-1 font-hand text-base leading-tight font-bold">
                <.icon name="hero-arrow-path-rounded-square" class="size-4" /> Random
              </span>
              <span class="mt-0.5 block text-[11px] leading-snug text-ink-soft">
                A random book per colour. Tap again to roll again.
              </span>
            </button>
          </li>
        </ul>
      </div>

      <div class="mt-3">
        <.books_form
          sets={@sets}
          expansion={@expansion}
          alchemists={@alchemists}
          pot_side={@rules.pot_side}
          players={@players}
          witches={@witches}
          expansion_cards={false}
          heading={false}
          patch={&tile_path/1}
        />
      </div>
    </.book_page>
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
