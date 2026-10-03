defmodule QuacksWeb.GameLive do
  @moduledoc """
  The game page, `/g/:id`, for 1 to 4 players (5 with The Herb Witches). The game itself lives in a
  `Quacks.GameServer` process; this LiveView asks it for a seat on mount (by the
  browser's player token), subscribes to the game's PubSub topic and re-renders on
  every `{:game, id, game}` broadcast. Every button comes from
  `Quacks.Game.legal_actions/2` for this browser's seat and every click goes through
  `Quacks.GameServer.apply/3`. The page itself knows no rules. A browser without a
  seat (the game is full) watches: it sees every pot and no buttons.

  Before the game begins (`GameServer` status `:waiting`) the page is the waiting
  room: one slot per seat (a name or "empty"), a link to share and, for the creator,
  a "Start game" button (`GameServer.begin/2`). Closing the page before the start
  frees the seat (`terminate/2`).

  While everyone brews or shops at the same time, each player card shows what that
  seat does now (`GameComponents.seat_state/2`), and a player who has finished sees
  who they wait for. A stopped player's Stop button becomes Resume.

  With The Herb Witches the page also shows the 3 witches (a sheet on phones, the
  right column on large screens) with a button to call one when the engine allows
  it, and the overflow bowl under the pot.

  Actions travel to the browser as a URL-safe binary (see `encode/1`) so tuples like
  `{:buy, [{:green, 2}]}` survive the round trip without a parser per action shape.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.GameComponents

  alias Quacks.{Game, GameServer}
  alias Quacks.Rules.{Books, Chips, Fortune}

  # The shop, one row per colour. The single-value colours share the top row; the
  # other rows run 1 / 2 / 4 from left to right.
  @shop_rows [
    [{:orange, 1}, {:purple, 1}, {:black, 1}],
    [{:green, 1}, {:green, 2}, {:green, 4}],
    [{:blue, 1}, {:blue, 2}, {:blue, 4}],
    [{:red, 1}, {:red, 2}, {:red, 4}],
    [{:yellow, 1}, {:yellow, 2}, {:yellow, 4}]
  ]
  # Orange Set 2 and locoweed (on with The Herb Witches) add a row under the top one.
  @expansion_row [{:orange, 6}, {:locoweed, 1}]

  @doc "Join game `id`: take a free seat, or watch when the game is full."
  @impl true
  def mount(%{"id" => id}, session, socket) do
    case GameServer.get(id) do
      {:ok, table} ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))

        seat =
          case GameServer.claim_seat(id, session["player_token"]) do
            {:ok, seat} -> seat
            {:error, _full} -> nil
          end

        # The claim may have added our own name; read the table again for it.
        {:ok, table} = if seat, do: GameServer.get(id), else: {:ok, table}

        {:ok,
         socket
         |> assign(
           page_title: "Quacks #{id}",
           id: id,
           token: session["player_token"],
           seat: seat,
           seed: table.seed,
           players: table.players,
           names: table.names,
           creator: table.creator
         )
         |> put_game(table.game)}

      {:error, :not_found} ->
        {:ok,
         socket |> put_flash(:error, "Game #{id} does not exist.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("action", %{"action" => encoded}, %{assigns: %{seat: seat}} = socket)
      when is_integer(seat) do
    with {:ok, action} <- decode(encoded),
         {:ok, game} <- GameServer.apply(socket.assigns.id, seat, action) do
      {:noreply, put_game(socket, game)}
    else
      {:error, {:illegal_action, action, _phase}} ->
        {:noreply, put_flash(socket, :error, "#{label(action)} is not allowed right now.")}

      {:error, :bad_action} ->
        {:noreply, put_flash(socket, :error, "That move could not be read.")}
    end
  end

  def handle_event("action", _params, socket),
    do: {:noreply, put_flash(socket, :error, "You are watching this game.")}

  # The shop form re-sends every ticked checkbox on each change; no key means none.
  def handle_event("select", params, socket) do
    selected =
      params
      |> Map.get("chips", [])
      |> Enum.flat_map(fn encoded ->
        case decode(encoded) do
          {:ok, {colour, value}} when is_atom(colour) and is_integer(value) -> [{colour, value}]
          _ -> []
        end
      end)
      |> Enum.sort()

    {:noreply, assign(socket, selected: selected)}
  end

  def handle_event("begin", _params, socket) do
    case GameServer.begin(socket.assigns.id, socket.assigns.token) do
      {:ok, game} -> {:noreply, socket |> reseat() |> put_game(game)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Only the creator can start.")}
    end
  end

  def handle_event("undo", _params, socket) do
    case GameServer.undo(socket.assigns.id) do
      {:ok, game} -> {:noreply, put_game(socket, game)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Undo is for solo games only.")}
    end
  end

  # A new game for the same number of players, books, house rules and expansion,
  # with this browser in seat 0.
  def handle_event("new_game", _params, socket) do
    %{sets: sets, rules: rules, expansion: expansion} = socket.assigns.game
    {:ok, id} = GameServer.start(socket.assigns.players, nil, sets, rules, expansion)
    {:ok, 0} = GameServer.claim_seat(id, socket.assigns.token)
    {:noreply, push_navigate(socket, to: ~p"/g/#{id}")}
  end

  # The nickname input sends its value when it loses focus.
  def handle_event("rename", %{"value" => name}, %{assigns: %{seat: seat}} = socket)
      when is_integer(seat) do
    :ok = GameServer.rename(socket.assigns.id, seat, name)
    {:noreply, socket}
  end

  def handle_event("rename", _params, socket), do: {:noreply, socket}

  @impl true
  # The game began: seats were renumbered, so ask for ours again.
  def handle_info({:game, _id, game}, %{assigns: %{game: nil}} = socket),
    do: {:noreply, socket |> reseat() |> put_game(game)}

  # Our own moves arrive twice (reply and broadcast); skip the copy we already have.
  def handle_info({:game, _id, game}, socket) do
    if game == socket.assigns.game,
      do: {:noreply, socket},
      else: {:noreply, put_game(socket, game)}
  end

  # While waiting, a seat change may also change the creator.
  def handle_info({:names, _id, _names}, %{assigns: %{game: nil}} = socket),
    do: {:noreply, reseat(socket)}

  def handle_info({:names, _id, names}, socket), do: {:noreply, assign(socket, names: names)}

  # A page closed before the game began gives its seat back.
  @impl true
  def terminate(_reason, %{assigns: %{game: nil, seat: seat}} = socket) when is_integer(seat),
    do: GameServer.leave_seat(socket.assigns.id, socket.assigns.token)

  def terminate(_reason, _socket), do: :ok

  defp reseat(socket) do
    %{id: id, token: token} = socket.assigns
    {:ok, table} = GameServer.get(id)

    seat =
      case GameServer.claim_seat(id, token) do
        {:ok, seat} -> seat
        {:error, _full} -> nil
      end

    assign(socket,
      seat: seat,
      players: table.players,
      names: table.names,
      creator: table.creator
    )
  end

  # Phones: one screen, no page scroll. Rows: header, status, notices, the pot (takes
  # the free space), the bottom bar. Bag, log, players, card text and the menu are
  # sheets; a decision opens as a dialog over the pot. Large screens add a right
  # column where the bag, log and players sheets show in place.
  @impl true
  def render(%{game: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="font-hand text-2xl font-bold">
        <.link navigate={~p"/"}>Quacks</.link>
        <span class="font-mono text-xs font-normal text-parchment-dim">{@id}</span>
      </h1>
      <section class="paper space-y-3 rounded-lg p-3" aria-label="Waiting room">
        <h2 class="text-lg font-bold">Waiting room</h2>
        <p class="rounded-md bg-droplet/25 px-2 py-1" data-role="waiting-for-players">
          {map_size(@names)} of {@players} seated.
        </p>
        <ol class="space-y-1" aria-label="Seats">
          <li
            :for={seat <- 0..(@players - 1)}
            class="flex min-h-9 items-center gap-2 rounded-md bg-parchment-light px-2"
            data-seat={seat}
            data-role="seat-slot"
          >
            <.seat_dot seat={seat} />
            <span :if={@names[seat]} class="font-semibold">{@names[seat]}</span>
            <span :if={!@names[seat]} class="text-ink-soft italic">empty</span>
            <span :if={@names[seat] && seat == @creator} class="text-xs text-ink-soft">host</span>
            <span :if={seat == @seat} class="ml-auto text-xs font-semibold">you</span>
          </li>
        </ol>
        <label :if={@seat} class="block space-y-1 text-sm">
          <span class="font-semibold">Your name</span>
          <input
            type="text"
            value={name(@names, @seat)}
            phx-blur="rename"
            maxlength="20"
            aria-label="Your name"
            class="w-full rounded-md border border-ink-soft bg-parchment-light px-2 py-2 text-base text-ink"
          />
        </label>
        <label class="block space-y-1 text-sm">
          <span class="font-semibold">Share this link to invite players</span>
          <input
            type="text"
            readonly
            value={url(~p"/g/#{@id}")}
            data-role="share-link"
            class="w-full rounded-md border border-ink-soft bg-parchment-light px-2 py-2 font-mono text-sm text-ink"
          />
        </label>
        <.button
          :if={starter?(@seat, @creator)}
          phx-click="begin"
          class="min-h-12 w-full rounded-lg bg-gold font-semibold text-ink shadow"
        >
          Start game
        </.button>
        <p :if={@seat && !starter?(@seat, @creator)} data-role="waiting-for-host">
          Waiting for {name(@names, @creator)} to start the game.
        </p>
      </section>
      <p :if={is_nil(@seat)} class="rounded-md bg-iron-dark px-2 py-1" data-role="spectator">
        All seats are taken. You are watching.
      </p>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full>
      <div class="lg:grid lg:h-dvh lg:grid-cols-[minmax(0,1fr)_22rem]">
        <div
          class="grid h-dvh grid-rows-[auto_auto_auto_minmax(0,1fr)_auto] overflow-hidden lg:px-4"
          data-role={@seat && "my-seat"}
        >
          <header class="flex items-center gap-2 px-3 pt-[max(0.25rem,env(safe-area-inset-top))]">
            <h1 class="font-hand text-2xl leading-none font-bold">
              <.link navigate={~p"/"}>Quacks</.link>
              <span class="font-mono text-xs font-normal text-parchment-dim">{@id}</span>
            </h1>
            <div class="ml-auto"><.round_phase game={@game} seat={@seat || 0} /></div>
            <button
              :if={results?(@game)}
              type="button"
              phx-click={JS.dispatch("quacks:modal", to: "#round-results")}
              aria-label="Round results"
              class="inline-flex size-11 items-center justify-center"
              data-role="open-results"
            >
              <.icon name="hero-trophy" class="size-6" />
            </button>
            <button
              type="button"
              popovertarget="sheet-menu"
              aria-label="Menu"
              class="-mr-2 inline-flex size-11 items-center justify-center"
            >
              <.icon name="hero-bars-3" class="size-6" />
            </button>
          </header>

          <div class="px-2">
            <.status :if={@seat} game={@game} seat={@seat} />
            <div
              :if={@players > 1}
              class="mt-1 grid grid-cols-[repeat(auto-fit,minmax(10.5rem,1fr))] gap-1 lg:hidden"
              aria-label="Other players"
            >
              <.player_line
                :for={seat <- @game.seats}
                :if={seat != @seat}
                game={@game}
                seat={seat}
                name={name(@names, seat)}
              />
            </div>
          </div>

          <div class="space-y-1 px-2 pt-1 text-sm">
            <.sheet_button
              :if={@game.fortune_card}
              for="sheet-fortune"
              class="w-full justify-start lg:hidden"
            >
              <.icon name="hero-sparkles" class="size-4 text-gold" />
              <span class="truncate">{Fortune.card(@game.fortune_card).name}</span>
              <.icon name="hero-information-circle" class="ml-auto size-5 text-parchment-dim" />
            </.sheet_button>
            <.sheet :if={@game.fortune_card} id="sheet-fortune" label="Fortune teller card" inline_lg>
              <.fortune_card id={@game.fortune_card} />
            </.sheet>
            <p :if={is_nil(@seat)} class="rounded-md bg-iron-dark px-2 py-1" data-role="spectator">
              All seats are taken. You are watching.
            </p>
            <p
              :if={@players > 1 and not Game.over?(@game)}
              class="px-1 font-semibold"
              data-role="turn"
            >
              {turn_text(@game, @seat, @names)}
            </p>
          </div>

          <div class="relative min-h-0 p-2">
            <.pot
              game={@game}
              seat={@seat || 0}
              class="block size-full"
              rings={rings(@game)}
              flask={@me && if(@me.flask, do: :full, else: :empty)}
              flask_click={if :use_flask in @actions, do: encode(:use_flask)}
            />
            <div :if={@me && @me.aside != []} class="absolute bottom-2 left-2">
              <.aside chips={@me.aside} />
            </div>
            <div :if={@game.expansion} class="absolute right-2 bottom-2 max-w-[45%]">
              <.bowl chips={@game.players[@seat || 0].bowl} />
            </div>
          </div>

          <footer class="space-y-2 px-2 pt-1 pb-[max(0.5rem,env(safe-area-inset-bottom))]">
            <nav class="flex gap-2 *:flex-1 lg:hidden" aria-label="Sheets">
              <.sheet_button :if={@me} for="sheet-bag">Bag {length(@me.bag)}</.sheet_button>
              <.sheet_button for="sheet-log">Log</.sheet_button>
              <.sheet_button :if={@players > 1} for="sheet-players">Players</.sheet_button>
              <.sheet_button :if={@game.witches} for="sheet-witches">Witches</.sheet_button>
            </nav>
            <section
              :if={extra_actions(@actions) != []}
              class="flex flex-wrap gap-2 *:min-h-11 *:flex-1 *:touch-manipulation"
              aria-label="More actions"
            >
              <.button
                :for={action <- extra_actions(@actions)}
                phx-click="action"
                phx-value-action={encode(action)}
              >
                {action_label(action, @game, @me)}
              </.button>
            </section>
            <.button
              :if={@decision}
              class="min-h-12 w-full rounded-lg bg-gold font-semibold text-ink shadow"
              phx-click={JS.dispatch("quacks:modal", to: "#decision-#{@decision}")}
            >
              {if @decision == :buy,
                do: "Open the shop",
                else: "Choose: #{phase_name(@decision)}"}
            </.button>
            <.button
              :if={Game.over?(@game)}
              class="min-h-12 w-full rounded-lg bg-gold font-semibold text-ink shadow"
              phx-click={JS.dispatch("quacks:modal", to: "#game-over")}
            >
              Show the result
            </.button>
            <%!-- Fixed slots: Stop (Resume while stopped), then Draw on the right.
                 Never moved, only disabled. --%>
            <section
              :if={@seat}
              class="grid grid-cols-2 gap-2 *:min-h-12 *:touch-manipulation"
              aria-label="Actions"
              data-role="action-bar"
            >
              <.button
                phx-click="action"
                phx-value-action={encode(@stop_slot)}
                disabled={@stop_slot not in @actions}
                data-slot="stop"
              >
                {if @stop_slot == :resume, do: "Resume", else: "Stop"}
              </.button>
              <.button
                phx-click="action"
                phx-value-action={encode(:draw)}
                disabled={:draw not in @actions}
                variant="primary"
                data-slot="draw"
              >
                Draw a chip
              </.button>
            </section>
          </footer>
        </div>

        <aside class="contents lg:flex lg:h-dvh lg:flex-col lg:gap-3 lg:overflow-y-auto lg:py-3 lg:pr-3">
          <.sheet :if={@game.witches} id="sheet-witches" label="Herb witches" inline_lg>
            <section class="space-y-2" aria-label="Herb witches">
              <.witch_card
                :for={{colour, id} <- witches(@game)}
                id={id}
                spent={@me != nil and not @me.pennies[colour]}
              >
                <div :if={@seat} class="flex flex-wrap gap-2 *:min-h-11">
                  <.button
                    :for={action <- calls(@all_actions, colour)}
                    phx-click="action"
                    phx-value-action={encode(action)}
                    variant="primary"
                  >
                    {call_text(action)}
                  </.button>
                </div>
              </.witch_card>
            </section>
          </.sheet>
          <.sheet :if={@players > 1} id="sheet-players" label="Other players" inline_lg>
            <section class="grid grid-cols-2 gap-2 lg:grid-cols-1" aria-label="Other players">
              <.player_card
                :for={seat <- @game.seats}
                :if={seat != @seat}
                game={@game}
                seat={seat}
                name={name(@names, seat)}
              />
            </section>
          </.sheet>
          <.sheet id="sheet-log" label="Log" inline_lg>
            <.action_log log={@game.log} names={if @players > 1, do: @names} />
          </.sheet>
          <.sheet :if={@me} id="sheet-bag" label="Bag" inline_lg>
            <.bag bag={@me.bag} />
          </.sheet>
        </aside>
      </div>

      <.sheet id="sheet-menu" label="Menu">
        <div class="space-y-3 text-sm">
          <h2 class="text-lg font-bold">Game {@id}</h2>
          <label :if={@seat && @players > 1} class="block space-y-1">
            <span class="flex items-center gap-1.5 font-semibold">
              <.seat_dot seat={@seat} /> Your name
            </span>
            <input
              type="text"
              value={name(@names, @seat)}
              phx-blur="rename"
              maxlength="20"
              aria-label="Your name"
              class="w-full rounded-md border border-ink-soft bg-parchment-light px-2 py-2 text-base text-ink"
            />
          </label>
          <div class="flex flex-wrap gap-2 *:min-h-11">
            <.button :if={@seat && @players == 1} phx-click="undo" disabled={@game.log == []}>
              Undo
            </.button>
            <.button :if={@seat && @players == 1} phx-click="new_game">New game</.button>
            <.button navigate={~p"/"}>Lobby</.button>
            <.sheet_button for="sheet-books">Books</.sheet_button>
          </div>
          <p>
            Seed
            <.link navigate={~p"/?seed=#{seed_param(@seed)}"} class="underline">{seed_param(@seed)}</.link>
          </p>
          <.books sets={@game.sets} />
          <.house_rules rules={@game.rules} />
        </div>
      </.sheet>

      <.sheet id="sheet-books" label="Ingredient books">
        <h2 class="mb-2 text-lg font-bold">Ingredient books</h2>
        <.book_list books={Books.in_play(@game.expansion, @game.sets)} />
      </.sheet>

      <.dialog_sheet :if={@decision} id={"decision-#{@decision}"} label={phase_name(@decision)}>
        <.shop :if={@decision == :buy} game={@game} seat={@seat} selected={@selected} />
        <div :if={@decision != :buy} class="space-y-3">
          <h2 class="text-xl font-bold">{phase_name(@decision)}</h2>
          <.fortune_card :if={@decision == :fortune_choice} id={@game.fortune_card} />
          <.blue_offer :if={@decision == :blue_choice} pending={@me.pending} />
          <.blue_offer
            :if={@decision == :witch_offer}
            pending={@me.witch_offer}
            title="The silver witch drew:"
            hint="Place them one by one, in any order, or return the rest."
            label="Silver witch offer"
            accent="border-penny-silver"
          />
          <.witch_card :for={id <- witches_acting(@game, @all_actions)} id={id} />
          <.blue_offer
            :if={@decision == :red_choice}
            pending={@me.pending}
            title="Toadstool chips beside the pot:"
            hint="For each: place it after your last chip, keep it for later, or return it to the bag."
            label="Toadstool choice"
            accent="border-ruby"
          />
          <.fortune_offer
            :if={@decision == :fortune_choice and @me.pending != []}
            card={@game.fortune_card}
            pending={@me.pending}
          />
          <section class="flex flex-col gap-2 *:min-h-11" aria-label="Actions">
            <.button
              :for={action <- @all_actions}
              phx-click="action"
              phx-value-action={encode(action)}
              variant="primary"
            >
              {action_label(action, @game, @me)}
            </.button>
          </section>
        </div>
      </.dialog_sheet>

      <%!-- After the decision dialog, so it opens on top of the shop. --%>
      <.dialog_sheet :if={results?(@game)} id="round-results" label="Round results">
        <.round_results game={@game} names={if @players > 1, do: @names} />
      </.dialog_sheet>

      <.dialog_sheet :if={Game.over?(@game)} id="game-over" label="Game over">
        <section class="space-y-3 text-center font-hand">
          <p :if={@players == 1} class="text-2xl font-bold">
            Game over: {Game.score(@game)[0]} victory points
          </p>
          <div :if={@players > 1}>
            <p class="text-2xl font-bold">Game over</p>
            <ol class="mt-2">
              <li :for={{seat, vp} <- ranking(@game)}>{name(@names, seat)}: {vp} victory points</li>
            </ol>
          </div>
          <.button
            phx-click="new_game"
            variant="primary"
            class="min-h-11 rounded-lg bg-gold px-6 font-semibold text-ink"
          >
            New game
          </.button>
        </section>
      </.dialog_sheet>
    </Layouts.app>
    """
  end

  @doc """
  The shop as a form of checkboxes, one per kind of chip, in a row per colour (see
  `shop_rows/0`), priced with the game's Ingredient books (`Chips.price/2`). The engine decides what may be ticked: a box is disabled when adding
  its chip to the selection is not a legal buy (too expensive, same colour, two already
  ticked, out of supply, not yet in the shop). "Buy selected" sends `{:buy, selected}`
  and is enabled only when that exact buy is legal.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0
  attr :selected, :list, required: true, doc: "ticked chips, sorted"

  def shop(assigns) do
    sets = assigns.game.sets
    total = assigns.selected |> Enum.map(&Chips.price(&1, sets)) |> Enum.sum()
    coins = assigns.game.players[assigns.seat].coins

    actions = Game.legal_actions(assigns.game, assigns.seat)

    assigns =
      assign(assigns,
        actions: actions,
        copper: copper_actions(actions, assigns.selected),
        sets: sets,
        rows: shop_rows(assigns.game.expansion, sets),
        total: total,
        coins: coins,
        remaining: coins - total
      )

    ~H"""
    <section class="space-y-2" aria-label="Shop">
      <h2 class="text-xl font-bold">Shop</h2>
      <p class="text-sm">Pick up to two chips of different colours.</p>
      <.books sets={@sets} />
      <form id="shop" phx-change="select" class="space-y-1.5">
        <ul
          :for={{row, i} <- Enum.with_index(@rows)}
          class="grid grid-cols-[1fr_1fr_1fr_auto] gap-1.5"
          data-role="shop-row"
        >
          <li :for={chip <- row}>
            <label class={[
              "flex min-h-11 items-center gap-1.5 rounded-md bg-parchment-light px-2 text-sm",
              blocked?(chip, @selected, @actions) && "opacity-40"
            ]}>
              <input
                type="checkbox"
                name="chips[]"
                value={encode(chip)}
                checked={chip in @selected}
                disabled={blocked?(chip, @selected, @actions)}
              />
              <.chip chip={chip} size={:sm} />
              <span class="sr-only sm:not-sr-only">{chip_name(chip)}</span>
              <span class="ml-auto text-ink-soft" data-role="price">
                {Chips.price(chip, @sets)}c
              </span>
            </label>
          </li>
          <li class="col-start-4">
            <button
              type="button"
              popovertarget={"shop-book-#{i}"}
              class="inline-flex size-11 items-center justify-center text-ink-soft"
              data-role="book-info"
            >
              <.icon name="hero-information-circle" class="size-6" />
              <span class="sr-only">Book</span>
            </button>
          </li>
        </ul>
      </form>
      <.sheet
        :for={{row, i} <- Enum.with_index(@rows)}
        id={"shop-book-#{i}"}
        label="Ingredient book"
      >
        <.book_list books={row_books(row, @game)} />
      </.sheet>
      <p class="text-sm" data-role="shop-total">
        Selected: {@total} coins. Remaining: {@remaining} of {@coins}.
      </p>
      <div class="flex gap-2 *:min-h-11 *:flex-1">
        <.button
          phx-click="action"
          phx-value-action={encode({:buy, @selected})}
          variant="primary"
          disabled={@selected == [] or {:buy, @selected} not in @actions}
        >
          Buy selected
        </.button>
        <.button phx-click="action" phx-value-action={encode({:buy, []})}>Buy nothing</.button>
      </div>
      <.witch_card :if={@copper != []} id={@game.witches.copper}>
        <div class="flex flex-col gap-2 *:min-h-11">
          <.button
            :for={action <- @copper}
            phx-click="action"
            phx-value-action={encode(action)}
            variant="primary"
          >
            {label(action)}
          </.button>
        </div>
      </.witch_card>
    </section>
    """
  end

  # The copper witch buttons in the shop. C3 (a buy with a free copy) shows only for
  # the chips ticked now.
  defp copper_actions(actions, selected) do
    Enum.filter(actions, fn
      {:witch, :copper, {:buy, chips, _copy}} -> chips == selected
      {:witch, :copper, _} -> true
      {:witch, :copper} -> true
      _ -> false
    end)
  end

  @doc """
  The shop's chips as rows, one per colour; together they are `Chips.shop/2` for
  `expansion` and `sets`. The orange 6 and locoweed row shows only when one of them
  is in play.
  """
  @spec shop_rows(Chips.expansion(), Chips.sets()) :: [[Chips.chip()]]
  def shop_rows(expansion \\ nil, sets \\ %{}) do
    shop = Chips.shop(expansion, sets)

    case Enum.filter(@expansion_row, &(&1 in shop)) do
      [] -> @shop_rows
      row -> [hd(@shop_rows), row | tl(@shop_rows)]
    end
  end

  # The books of the colours in a shop row, e.g. orange, purple and black.
  defp row_books(row, game) do
    for colour <- row |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
        do: {colour, Chips.set(game.expansion, game.sets, colour)}
  end

  # A ticked chip can always be unticked; an unticked one is blocked unless adding it
  # to the selection is a legal buy.
  defp blocked?(chip, selected, actions),
    do: chip not in selected and {:buy, Enum.sort([chip | selected])} not in actions

  # `@game` is the game and `@me` this browser's player (nil when watching).
  # Every state change empties the shop selection; it only means something in the shop.
  # `@decision` is the phase whose choice this seat must make now (shown in a
  # dialog), or nil. `@actions` are the brewing buttons of the bottom bar.
  # `@stop_slot` is the action of the bar's left slot: `:resume` while this seat is
  # `:stopped`, else `:stop`.
  # `@all_actions` are every legal action of this seat; witch calls show on the witch
  # cards, so the bottom bar leaves them out. The silver witch S2's offer is a
  # decision of its own (`:witch_offer`).
  defp put_game(socket, nil) do
    assign(socket,
      game: nil,
      me: nil,
      selected: [],
      decision: nil,
      all_actions: [],
      actions: [],
      stop_slot: :stop
    )
  end

  defp put_game(socket, game) do
    seat = socket.assigns.seat
    me = if seat, do: game.players[seat]
    actions = if seat && not Game.over?(game), do: Game.legal_actions(game, seat), else: []
    decision = decision(actions, seat && Game.phase(game, seat), me)

    assign(socket,
      game: game,
      me: me,
      selected: [],
      decision: decision,
      all_actions: actions,
      actions: if(decision, do: [], else: Enum.reject(actions, &witch?/1)),
      stop_slot: if(me && me.phase == :stopped, do: :resume, else: :stop)
    )
  end

  # The round results show from the shop until the round ends (round 9 has no shop).
  defp results?(game), do: game.phase == :shopping

  # The creator starts the game; once the creator left, any seated player may.
  defp starter?(nil, _creator), do: false
  defp starter?(seat, creator), do: creator in [nil, seat]

  # Every seat's scoring space, for the rings on the big pot.
  defp rings(game), do: Map.new(game.seats, &{&1, Game.scoring_index(game, &1)})

  # Bar actions without a fixed slot (Draw, Stop/Resume) or a pot control (the flask),
  # e.g. B3's restart or R6's place.
  defp extra_actions(actions), do: actions -- [:draw, :stop, :resume, :use_flask]

  defp decision([], _phase, _me), do: nil
  defp decision(_actions, :potions, %{witch_offer: [_ | _]}), do: :witch_offer
  defp decision(_actions, :potions, _me), do: nil
  defp decision(_actions, :stopped, _me), do: nil
  defp decision(_actions, phase, _me), do: phase

  defp witch?({:witch, _}), do: true
  defp witch?({:witch, _, _}), do: true
  defp witch?(_action), do: false

  # The witches in penny order: silver, copper, gold.
  defp witches(game), do: for(c <- [:silver, :copper, :gold], do: {c, game.witches[c]})

  # The witches that `actions` can call, for the decision dialog.
  defp witches_acting(%{witches: nil}, _actions), do: []

  defp witches_acting(game, actions) do
    for {colour, id} <- witches(game), calls(actions, colour) != [], do: id
  end

  # The calls a witch card offers: the plain call, and S3's two choices. Choices
  # that belong to a dialog (S2's offer, the copper choices in the shop) stay there.
  defp calls(actions, colour) do
    Enum.filter(actions, fn
      {:witch, ^colour} -> true
      {:witch, ^colour, n} -> is_integer(n)
      _ -> false
    end)
  end

  defp call_text({:witch, _colour}), do: "Call"
  defp call_text({:witch, _colour, 1}), do: "Call: the last white back"
  defp call_text({:witch, _colour, n}), do: "Call: the last #{n} whites back"

  # A button label; G4 makes the rubies phase cost 1 ruby.
  defp action_label({:rubies, :droplet}, _game, %{ruby_price: 1}),
    do: "Spend 1 ruby: droplet +1"

  defp action_label({:rubies, :flask}, _game, %{ruby_price: 1}),
    do: "Spend 1 ruby: refill flask"

  defp action_label(action, game, _me), do: label(action, game.fortune_card)

  defp name(names, seat), do: Map.get(names, seat, GameServer.default_name(seat))

  # While everyone acts at once, a seat that has finished sees who it waits for.
  defp turn_text(%{phase: phase} = game, seat, names) when phase in [:potions, :shopping] do
    case waiting_for(game, seat) do
      [] when phase == :potions ->
        "Everyone brews at the same time."

      [] ->
        "Everyone shops at the same time."

      seats ->
        "Waiting for #{length(seats)} #{if length(seats) == 1, do: "player", else: "players"}: " <>
          Enum.map_join(seats, ", ", &name(names, &1)) <> "."
    end
  end

  defp turn_text(%{phase: phase, turn: seat}, seat, _names),
    do: "Your turn: #{phase_verb(phase)}."

  defp turn_text(%{phase: phase, turn: turn}, _seat, names),
    do: "#{name(names, turn)}'s turn: #{phase_verb(phase)}."

  # The seats `seat` waits for: empty unless `seat` has stopped (or is done) while
  # others brew, or is ready while others shop. Watchers wait for nobody.
  defp waiting_for(game, seat) do
    finished = if game.phase == :potions, do: [:stopped, :done], else: [:ready]

    if seat && game.players[seat].phase in finished,
      do: Enum.reject(game.seats, &(game.players[&1].phase in finished)),
      else: []
  end

  defp phase_verb(:fortune_choice), do: "resolve the fortune teller card"
  defp phase_verb(:chip_choice), do: "choose chip actions"
  defp phase_verb(:witch_choice), do: "decide on the gold witch"

  # Seats by VP, highest first.
  defp ranking(game), do: game |> Game.score() |> Enum.sort_by(fn {_seat, vp} -> -vp end)

  defp seed_param({a, b, c}), do: "#{a},#{b},#{c}"

  @doc "Turn an action term into a URL-safe string for `phx-value-action`."
  @spec encode(Game.action()) :: String.t()
  def encode(action), do: action |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)

  @doc """
  Reverse of `encode/1`. Uses `Plug.Crypto.non_executable_binary_to_term/2` with `:safe`,
  so a crafted payload can create neither functions nor new atoms.
  """
  @spec decode(String.t()) :: {:ok, term} | {:error, :bad_action}
  def decode(encoded) when is_binary(encoded) do
    with {:ok, binary} <- Base.url_decode64(encoded, padding: false) do
      {:ok, Plug.Crypto.non_executable_binary_to_term(binary, [:safe])}
    end
  rescue
    ArgumentError -> {:error, :bad_action}
  else
    {:ok, term} -> {:ok, term}
    :error -> {:error, :bad_action}
  end
end
