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
  alias Quacks.Rules.Chips

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

  # A new game for the same number of players and books, with this browser in seat 0.
  def handle_event("new_game", _params, socket) do
    {:ok, id} = GameServer.start(socket.assigns.players, nil, socket.assigns.game.sets)
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <header class="flex flex-wrap items-baseline justify-between gap-2">
        <h1 class="text-3xl font-bold">
          <.link navigate={~p"/"}>Quacks</.link>
          <span class="font-mono text-base text-parchment-dim">{@id}</span>
        </h1>
        <p class="text-xs text-parchment-dim">
          Seed
          <.link navigate={~p"/?seed=#{seed_param(@seed)}"} class="underline">{seed_param(@seed)}</.link>
        </p>
      </header>

      <p
        :if={map_size(@names) < @players}
        class="paper rounded-md border-l-4 border-droplet p-2 text-sm"
        data-role="waiting-for-players"
      >
        Waiting for players: {map_size(@names)} of {@players} seated. Share this page's link.
      </p>
      <p :if={is_nil(@seat)} class="paper rounded-md p-2 text-sm" data-role="spectator">
        All seats are taken. You are watching.
      </p>
      <p :if={@players > 1 and not Game.over?(@game)} class="text-sm font-semibold" data-role="turn">
        {turn_text(@game, @seat, @names)}
      </p>

      <.fortune_card :if={@game.fortune_card} id={@game.fortune_card} />

      <section
        :if={@players > 1}
        class="grid gap-2 sm:grid-cols-3"
        aria-label="Other players"
      >
        <.player_card
          :for={seat <- @game.seats}
          :if={seat != @seat}
          game={@game}
          seat={seat}
          name={name(@names, seat)}
        />
      </section>

      <section
        :if={Game.over?(@game)}
        class="paper rounded-lg border-4 border-gold p-4 text-center font-hand"
      >
        <p :if={@players == 1} class="text-2xl font-bold">
          Game over: {Game.score(@game)[0]} victory points
        </p>
        <div :if={@players > 1}>
          <p class="text-2xl font-bold">Game over</p>
          <ol class="mt-2">
            <li :for={{seat, vp} <- ranking(@game)}>{name(@names, seat)}: {vp} victory points</li>
          </ol>
        </div>
        <div class="mt-3">
          <.button phx-click="new_game" variant="primary">New game</.button>
        </div>
      </section>

      <div :if={@seat} class="space-y-4" data-role="my-seat">
        <input
          :if={@players > 1}
          type="text"
          value={name(@names, @seat)}
          phx-blur="rename"
          maxlength="20"
          aria-label="Your name"
          class="rounded-md border border-ink-soft bg-parchment-light px-2 py-1 text-sm text-ink"
        />
        <.status game={@game} seat={@seat} />
        <.pot game={@game} seat={@seat} />

        <.aside :if={@me.aside != []} chips={@me.aside} />
        <.blue_offer :if={Game.phase(@game, @seat) == :blue_choice} pending={@me.pending} />
        <.blue_offer
          :if={Game.phase(@game, @seat) == :red_choice}
          pending={@me.pending}
          title="Toadstool chips beside the pot:"
          hint="For each: place it after your last chip, keep it for later, or return it to the bag."
          label="Toadstool choice"
          accent="border-ruby"
        />
        <.fortune_offer
          :if={Game.phase(@game, @seat) == :fortune_choice and @me.pending != []}
          card={@game.fortune_card}
          pending={@me.pending}
        />

        <.shop
          :if={@game.phase == :buy_chips and @game.turn == @seat}
          game={@game}
          seat={@seat}
          selected={@selected}
        />

        <section
          :if={not Game.over?(@game) and @game.phase != :buy_chips}
          class="flex flex-wrap gap-2"
          aria-label="Actions"
        >
          <.button
            :for={action <- Game.legal_actions(@game, @seat)}
            phx-click="action"
            phx-value-action={encode(action)}
            variant="primary"
          >
            {label(action, @game.fortune_card)}
          </.button>
        </section>

        <div class="flex flex-wrap gap-2">
          <.button :if={@players == 1} phx-click="undo" disabled={@game.log == []}>Undo</.button>
          <.button :if={@players == 1} phx-click="new_game">New game</.button>
          <.button :if={@players > 1} navigate={~p"/"}>Lobby</.button>
        </div>

        <.bag bag={@me.bag} />
      </div>

      <.action_log log={@game.log} names={if @players > 1, do: @names} />
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
    <section class="paper space-y-3 rounded-lg p-3" aria-label="Shop">
      <h2 class="text-lg font-bold">
        Shop: pick up to two chips of different colours
      </h2>
      <.books sets={@sets} />
      <form id="shop" phx-change="select" class="space-y-2">
        <ul :for={row <- shop_rows()} class="grid gap-2 sm:grid-cols-3" data-role="shop-row">
          <li :for={chip <- row}>
            <label class={[
              "flex items-center gap-2 rounded-md bg-parchment-light px-2 py-1 text-sm",
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
              <span>{chip_name(chip)}</span>
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
      <div class="flex flex-wrap gap-2">
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
  defp put_game(socket, game) do
    me = if socket.assigns.seat, do: game.players[socket.assigns.seat]
    assign(socket, game: game, me: me, selected: [])
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
