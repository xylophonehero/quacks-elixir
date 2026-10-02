defmodule QuacksWeb.GameLive do
  @moduledoc """
  The solo game page. One `Quacks.Session` lives in the socket assigns; every button
  the player sees comes from `Quacks.Game.legal_actions/1` and every click goes through
  `Quacks.Session.apply/2`. The page itself knows no rules.

  Actions travel to the browser as a URL-safe binary (see `encode/1`) so tuples like
  `{:buy, [{:green, 2}]}` survive the round trip without a parser per action shape.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.GameComponents

  alias Quacks.{Game, Session}
  alias Quacks.Rules.Chips

  @doc """
  Start a game. `?seed=1,2,3` gives a reproducible game; otherwise the seed is random.
  """
  @impl true
  def mount(params, _session, socket) do
    {:ok, start(socket, seed_from_params(params))}
  end

  @impl true
  def handle_event("action", %{"action" => encoded}, socket) do
    with {:ok, action} <- decode(encoded),
         {:ok, session} <- Session.apply(socket.assigns.session, action) do
      {:noreply, put_session(socket, session)}
    else
      {:error, {:illegal_action, action, _phase}} ->
        {:noreply, put_flash(socket, :error, "#{label(action)} is not allowed right now.")}

      {:error, :bad_action} ->
        {:noreply, put_flash(socket, :error, "That move could not be read.")}
    end
  end

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
    {:noreply, put_session(socket, Session.undo(socket.assigns.session))}
  end

  def handle_event("new_game", _params, socket) do
    {:noreply, start(socket, random_seed())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <header class="flex flex-wrap items-baseline justify-between gap-2">
        <h1 class="text-3xl font-bold">Quacks</h1>
        <p class="text-xs text-zinc-500">
          Seed
          <.link patch={~p"/?seed=#{seed_param(@session.seed)}"} class="underline">{seed_param(
            @session.seed
          )}</.link>
        </p>
      </header>

      <.status game={@game} />
      <.pot game={@game} />

      <section :if={Game.over?(@game)} class="rounded-lg bg-emerald-100 p-4 text-center">
        <p class="text-xl font-bold">Game over: {Game.score(@game)} victory points</p>
        <.button phx-click="new_game" variant="primary" class="mt-3">New game</.button>
      </section>

      <.blue_offer :if={@game.phase == :blue_choice} pending={@game.pending} />

      <.shop :if={@game.phase == :buy_chips} game={@game} selected={@selected} />

      <section
        :if={not Game.over?(@game) and @game.phase != :buy_chips}
        class="flex flex-wrap gap-2"
        aria-label="Actions"
      >
        <.button
          :for={action <- Game.legal_actions(@game)}
          phx-click="action"
          phx-value-action={encode(action)}
          variant="primary"
        >
          {label(action)}
        </.button>
      </section>

      <div class="flex flex-wrap gap-2">
        <.button phx-click="undo" disabled={@session.actions == []}>Undo</.button>
        <.button phx-click="new_game">New game</.button>
      </div>

      <.bag bag={@game.bag} />
      <.action_log log={@game.log} />
    </Layouts.app>
    """
  end

  @doc """
  The shop as a form of checkboxes, one per kind of chip in the shop. The engine decides
  what may be ticked: a box is disabled when adding its chip to the selection is not a
  legal buy (too expensive, same colour, two already ticked, out of supply, not yet in
  the shop). "Buy selected" sends `{:buy, selected}` and is enabled only when that
  exact buy is legal.
  """
  attr :game, Game, required: true
  attr :selected, :list, required: true, doc: "ticked chips, sorted"

  def shop(assigns) do
    total = assigns.selected |> Enum.map(&Chips.price/1) |> Enum.sum()

    assigns =
      assign(assigns,
        actions: Game.legal_actions(assigns.game),
        total: total,
        remaining: assigns.game.coins - total
      )

    ~H"""
    <section class="space-y-3 rounded-lg bg-amber-50 p-3" aria-label="Shop">
      <h2 class="text-sm font-semibold text-amber-900">
        Shop: pick up to two chips of different colours
      </h2>
      <form id="shop" phx-change="select">
        <ul class="grid grid-cols-2 gap-2 sm:grid-cols-3">
          <li :for={chip <- Chips.shop()}>
            <label class={[
              "flex items-center gap-2 rounded-md bg-white px-2 py-1 text-sm",
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
              <span class="ml-auto text-zinc-500">{Chips.price(chip)}c</span>
            </label>
          </li>
        </ul>
      </form>
      <p class="text-sm" data-role="shop-total">
        Selected: {@total} coins. Remaining: {@remaining} of {@game.coins}.
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

  # A ticked chip can always be unticked; an unticked one is blocked unless adding it
  # to the selection is a legal buy.
  defp blocked?(chip, selected, actions),
    do: chip not in selected and {:buy, Enum.sort([chip | selected])} not in actions

  defp start(socket, seed) do
    socket |> assign(page_title: "Quacks") |> put_session(Session.new(seed))
  end

  # `@game` is the session's game, kept as its own assign so templates read `@game.x`.
  # Every state change empties the shop selection; it only means something in the shop.
  defp put_session(socket, session),
    do: assign(socket, session: session, game: session.game, selected: [])

  defp seed_from_params(%{"seed" => seed}) do
    case seed |> String.split(",") |> Enum.map(&Integer.parse/1) do
      [{a, ""}, {b, ""}, {c, ""}] -> {a, b, c}
      _ -> random_seed()
    end
  end

  defp seed_from_params(_params), do: random_seed()

  defp random_seed,
    do: {:rand.uniform(1_000_000), :rand.uniform(1_000_000), :rand.uniform(1_000_000)}

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
