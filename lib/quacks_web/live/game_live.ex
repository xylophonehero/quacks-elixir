defmodule QuacksWeb.GameLive do
  @moduledoc """
  The game page, `/g/:id`, for 1 to 4 players. The game itself lives in a
  `Quacks.GameServer` process; this LiveView asks it for a seat on mount (by the
  browser's player token), subscribes to the game's PubSub topic and re-renders on
  every `{:game, id, game}` broadcast. Every button comes from
  `Quacks.Game.legal_actions/2` for this browser's seat and every click goes through
  `Quacks.GameServer.apply/3`. The page itself knows no rules. A browser without a
  seat (the game is full) watches: it sees every pot and no buttons.

  Actions travel to the browser as a URL-safe binary (see `encode/1`) so tuples like
  `{:buy, [{:green, 2}]}` survive the round trip without a parser per action shape.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.GameComponents

  alias Quacks.{Game, GameServer}
  alias Quacks.Rules.{Chips, Fortune}

  # The shop, one row per colour. The single-value colours share the top row; the
  # other rows run 1 / 2 / 4 from left to right.
  @shop_rows [
    [{:orange, 1}, {:purple, 1}, {:black, 1}],
    [{:green, 1}, {:green, 2}, {:green, 4}],
    [{:blue, 1}, {:blue, 2}, {:blue, 4}],
    [{:red, 1}, {:red, 2}, {:red, 4}],
    [{:yellow, 1}, {:yellow, 2}, {:yellow, 4}]
  ]

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
           names: table.names
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

  def handle_event("undo", _params, socket) do
    case GameServer.undo(socket.assigns.id) do
      {:ok, game} -> {:noreply, put_game(socket, game)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Undo is for solo games only.")}
    end
  end

  # A new game for the same number of players, books and house rules, with this
  # browser in seat 0.
  def handle_event("new_game", _params, socket) do
    %{sets: sets, rules: rules} = socket.assigns.game
    {:ok, id} = GameServer.start(socket.assigns.players, nil, sets, rules)
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
  # Our own moves arrive twice (reply and broadcast); skip the copy we already have.
  def handle_info({:game, _id, game}, socket) do
    if game == socket.assigns.game,
      do: {:noreply, socket},
      else: {:noreply, put_game(socket, game)}
  end

  def handle_info({:names, _id, names}, socket), do: {:noreply, assign(socket, names: names)}

  # Phones: one screen, no page scroll. Rows: header, status, notices, the pot (takes
  # the free space), the bottom bar. Bag, log, players, card text and the menu are
  # sheets; a decision opens as a dialog over the pot. Large screens add a right
  # column where the bag, log and players sheets show in place.
  @impl true
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
            <p
              :if={map_size(@names) < @players}
              class="rounded-md bg-droplet/25 px-2 py-1"
              data-role="waiting-for-players"
            >
              Waiting for players: {map_size(@names)} of {@players} seated. Share this page's link.
            </p>
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
            <.pot game={@game} seat={@seat || 0} class="block size-full" />
            <div :if={@me && @me.aside != []} class="absolute bottom-2 left-2">
              <.aside chips={@me.aside} />
            </div>
          </div>

          <footer class="space-y-2 px-2 pt-1 pb-[max(0.5rem,env(safe-area-inset-bottom))]">
            <nav class="flex gap-2 *:flex-1 lg:hidden" aria-label="Sheets">
              <.sheet_button :if={@me} for="sheet-bag">Bag {length(@me.bag)}</.sheet_button>
              <.sheet_button for="sheet-log">Log</.sheet_button>
              <.sheet_button :if={@players > 1} for="sheet-players">Players</.sheet_button>
            </nav>
            <section
              :if={@actions != []}
              class="flex gap-2 *:min-h-12 *:flex-1 *:touch-manipulation"
              aria-label="Actions"
            >
              <.button
                :for={action <- @actions}
                phx-click="action"
                phx-value-action={encode(action)}
                variant="primary"
              >
                {label(action, @game.fortune_card)}
              </.button>
            </section>
            <.button
              :if={@decision}
              class="min-h-12 w-full rounded-lg bg-gold font-semibold text-ink shadow"
              phx-click={JS.dispatch("quacks:modal", to: "#decision-#{@decision}")}
            >
              {if @decision == :buy_chips,
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
          </footer>
        </div>

        <aside class="contents lg:flex lg:h-dvh lg:flex-col lg:gap-3 lg:overflow-y-auto lg:py-3 lg:pr-3">
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
          <input
            :if={@seat && @players > 1}
            type="text"
            value={name(@names, @seat)}
            phx-blur="rename"
            maxlength="20"
            aria-label="Your name"
            class="w-full rounded-md border border-ink-soft bg-parchment-light px-2 py-2 text-ink"
          />
          <div class="flex flex-wrap gap-2 *:min-h-11">
            <.button :if={@seat && @players == 1} phx-click="undo" disabled={@game.log == []}>
              Undo
            </.button>
            <.button :if={@seat && @players == 1} phx-click="new_game">New game</.button>
            <.button navigate={~p"/"}>Lobby</.button>
          </div>
          <p>
            Seed
            <.link navigate={~p"/?seed=#{seed_param(@seed)}"} class="underline">{seed_param(@seed)}</.link>
          </p>
          <.books sets={@game.sets} />
          <.house_rules rules={@game.rules} />
        </div>
      </.sheet>

      <.dialog_sheet :if={@decision} id={"decision-#{@decision}"} label={phase_name(@decision)}>
        <.shop :if={@decision == :buy_chips} game={@game} seat={@seat} selected={@selected} />
        <div :if={@decision != :buy_chips} class="space-y-3">
          <h2 class="text-xl font-bold">{phase_name(@decision)}</h2>
          <.fortune_card :if={@decision == :fortune_choice} id={@game.fortune_card} />
          <.blue_offer :if={@decision == :blue_choice} pending={@me.pending} />
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
              :for={action <- Game.legal_actions(@game, @seat)}
              phx-click="action"
              phx-value-action={encode(action)}
              variant="primary"
            >
              {label(action, @game.fortune_card)}
            </.button>
          </section>
        </div>
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

    assigns =
      assign(assigns,
        actions: Game.legal_actions(assigns.game, assigns.seat),
        sets: sets,
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
        <ul :for={row <- shop_rows()} class="grid grid-cols-3 gap-1.5" data-role="shop-row">
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
        </ul>
      </form>
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
    </section>
    """
  end

  @doc "The shop's chips as rows, one per colour; together they are `Chips.shop/0`."
  @spec shop_rows() :: [[Chips.chip()]]
  def shop_rows, do: @shop_rows

  # A ticked chip can always be unticked; an unticked one is blocked unless adding it
  # to the selection is a legal buy.
  defp blocked?(chip, selected, actions),
    do: chip not in selected and {:buy, Enum.sort([chip | selected])} not in actions

  # `@game` is the game and `@me` this browser's player (nil when watching).
  # Every state change empties the shop selection; it only means something in the shop.
  # `@decision` is the phase whose choice this seat must make now (shown in a
  # dialog), or nil. `@actions` are the brewing buttons of the bottom bar.
  defp put_game(socket, game) do
    seat = socket.assigns.seat
    me = if seat, do: game.players[seat]
    actions = if seat && not Game.over?(game), do: Game.legal_actions(game, seat), else: []
    phase = seat && Game.phase(game, seat)
    decision = if actions != [] and phase != :potions, do: phase

    assign(socket,
      game: game,
      me: me,
      selected: [],
      decision: decision,
      actions: if(decision, do: [], else: actions)
    )
  end

  defp name(names, seat), do: Map.get(names, seat, GameServer.default_name(seat))

  defp turn_text(%{phase: :potions}, _seat, _names), do: "Everyone brews at the same time."

  defp turn_text(%{phase: phase, turn: seat}, seat, _names),
    do: "Your turn: #{phase_verb(phase)}."

  defp turn_text(%{phase: phase, turn: turn}, _seat, names),
    do: "#{name(names, turn)}'s turn: #{phase_verb(phase)}."

  defp phase_verb(:fortune_choice), do: "resolve the fortune teller card"
  defp phase_verb(:chip_choice), do: "choose chip actions"
  defp phase_verb(:buy_chips), do: "buy chips"
  defp phase_verb(:spend_rubies), do: "spend rubies, then end the round"

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
