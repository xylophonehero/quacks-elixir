defmodule QuacksWeb.LobbyLive do
  @moduledoc """
  The start page: create a game for 1 to 4 players (5 with The Herb Witches), or
  join an open game on this node. Creating a game seats this browser in seat 0 and
  opens `/g/:id`.

  The "Ingredient books" form picks the Set (1–4) per colour for the games created
  here. Its "Herb Witches expansion" checkbox turns the expansion on: Sets 5 and 6,
  the black book and a 5-player game, and it switches orange to Set 2 and locoweed
  to Set 5. Under each select the chosen book's text shows (`Quacks.Rules.Books`).
  It is a plain `phx-change` form: every change sends all selects and the checkbox,
  and the choice waits in the assigns until a New game button is clicked. The "Options" form under it works the
  same way for the house rules (`Quacks.Game.t:rules/0`).

  `?seed=1,2,3` makes the games created here reproducible.
  """
  use QuacksWeb, :live_view

  import QuacksWeb.GameComponents, only: [book_list: 1, book_text: 1]

  alias Quacks.{Game, GameServer}
  alias Quacks.Rules.{Books, Chips}

  # The colours with four ingredient books, in the order the form shows them.
  @book_colours [:green, :blue, :red, :yellow, :purple]
  # Orange (Set 2 = the orange 6-chip) and locoweed (nil = not used) in every game.
  @extra_books %{orange: [1, 2], locoweed: [nil, 5, 6]}
  # The Herb Witches adds Sets 5 and 6 and the black books.
  @expansion_books %{black: [1, 5, 6]}

  # Every house rule the Options form offers, with the values it accepts.
  @rule_values %{
    explode_above: 5..9,
    starting_rubies: 0..3,
    round6_white: [true, false],
    fortune: [true, false],
    rats: [true, false],
    black_solo: [:droplet, :droplet_ruby],
    die: [:standard, :no_orange]
  }

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.lobby_topic())

    {:ok,
     assign(socket,
       page_title: "Quacks",
       token: session["player_token"],
       seed: parse_seed(params["seed"]),
       sets: Map.new(@book_colours, &{&1, 1}),
       expansion: false,
       rules: Game.default_rules(),
       games: GameServer.open_games()
     )}
  end

  @impl true
  def handle_event("new_game", %{"players" => players}, socket) do
    %{seed: seed, sets: sets, rules: rules, expansion: expansion} = socket.assigns
    expansion = if expansion, do: :herb_witches

    {:ok, id} = GameServer.start(String.to_integer(players), seed, sets, rules, expansion)

    {:ok, 0} = GameServer.claim_seat(id, socket.assigns.token)
    {:noreply, push_navigate(socket, to: ~p"/g/#{id}")}
  end

  def handle_event("sets", %{"sets" => params} = form, socket) when is_map(params) do
    expansion = form["expansion"] == "true"
    # The toggle resets orange and locoweed to the new default (expansion: 2 and 5).
    params =
      if expansion == socket.assigns.expansion,
        do: params,
        else: Map.drop(params, ["orange", "locoweed"])

    {:noreply, assign(socket, sets: parse_sets(params, expansion), expansion: expansion)}
  end

  def handle_event("rules", %{"rules" => params}, socket) when is_map(params),
    do: {:noreply, assign(socket, rules: parse_rules(params))}

  # A game started, filled up or stopped somewhere: list the open games again.
  @impl true
  def handle_info(:games_changed, socket),
    do: {:noreply, assign(socket, games: GameServer.open_games())}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-3xl font-bold">Quacks</h1>

      <form id="books" phx-change="sets" aria-label="Ingredient books" class="paper rounded-lg p-3">
        <h2 class="text-lg font-bold">Ingredient books</h2>
        <.input
          type="checkbox"
          id="expansion"
          name="expansion"
          label="Herb Witches expansion"
          value={@expansion}
        />
        <div class="mt-2 grid grid-cols-1 gap-x-3 gap-y-2 sm:grid-cols-2 lg:grid-cols-3">
          <div :for={colour <- book_colours(@expansion)} data-role="book" data-colour={colour}>
            <.input
              type="select"
              id={"sets-#{colour}"}
              name={"sets[#{colour}]"}
              label={String.capitalize(to_string(colour))}
              value={book(@sets, colour, @expansion)}
              options={Enum.map(book_sets(colour, @expansion), &{set_name(&1, colour), &1})}
              class="w-full rounded-lg border border-ink-soft bg-parchment-light px-3 py-2 text-sm text-ink"
            />
            <div :if={book(@sets, colour, @expansion)} data-role="chosen-book">
              <.book_text book={Books.get({colour, book(@sets, colour, @expansion)})} />
            </div>
            <details class="text-xs">
              <summary class="cursor-pointer text-ink-soft">
                All {colour} books
              </summary>
              <div class="mt-1">
                <.book_list books={for set <- book_sets(colour, @expansion), set, do: {colour, set}} />
              </div>
            </details>
          </div>
        </div>
      </form>

      <details>
        <summary class="cursor-pointer text-sm font-semibold text-zinc-600">Options</summary>
        <form id="options" phx-change="rules" aria-label="House rules" class="mt-2 space-y-2">
          <div class="grid grid-cols-2 gap-x-2">
            <.input
              type="number"
              id="rules-explode_above"
              name="rules[explode_above]"
              label="Explodes above (white)"
              value={@rules.explode_above}
              min="5"
              max="9"
            />
            <.input
              type="number"
              id="rules-starting_rubies"
              name="rules[starting_rubies]"
              label="Starting rubies"
              value={@rules.starting_rubies}
              min="0"
              max="3"
            />
          </div>
          <.input
            type="checkbox"
            id="rules-round6_white"
            name="rules[round6_white]"
            label="Extra white 1-chip before round 6"
            value={@rules.round6_white}
          />
          <.input
            type="checkbox"
            id="rules-fortune"
            name="rules[fortune]"
            label="Fortune Teller cards"
            value={@rules.fortune}
          />
          <.input
            type="checkbox"
            id="rules-rats"
            name="rules[rats]"
            label="Rats (2+ players)"
            value={@rules.rats}
          />
          <.radios
            name="black_solo"
            legend="Solo black chips"
            value={@rules.black_solo}
            options={[droplet: "droplet +1", droplet_ruby: "droplet +1 and 1 ruby (§6.2)"]}
          />
          <.radios
            name="die"
            legend="Bonus die"
            value={@rules.die}
            options={[standard: "standard", no_orange: "ruby instead of orange (unofficial)"]}
          />
        </form>
      </details>

      <section class="flex flex-wrap gap-2" aria-label="New game">
        <.button phx-click="new_game" phx-value-players="1" variant="primary">
          New solo game
        </.button>
        <.button
          :for={n <- 2..if(@expansion, do: 5, else: 4)}
          phx-click="new_game"
          phx-value-players={n}
        >
          New game for {n} players
        </.button>
      </section>

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
              · {map_size(game.names)} of {game.players} seated · round {game.game.round}
            </span>
            <.button navigate={~p"/g/#{game.id}"}>Join</.button>
          </li>
          <li :if={@games == []} class="text-sm text-parchment-dim">No open games. Start one.</li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  # A row of radio buttons for the house rule `name`, one per `{value, label}` option.
  attr :name, :string, required: true
  attr :legend, :string, required: true
  attr :value, :atom, required: true
  attr :options, :list, required: true

  defp radios(assigns) do
    ~H"""
    <fieldset class="text-sm">
      <legend class="mb-1">{@legend}</legend>
      <label :for={{value, label} <- @options} class="mr-4 inline-flex items-center gap-1">
        <input
          type="radio"
          id={"rules-#{@name}-#{value}"}
          name={"rules[#{@name}]"}
          value={value}
          checked={@value == value}
        />
        {label}
      </label>
    </fieldset>
    """
  end

  @doc """
  The colours the Ingredient books form offers: the five book colours, orange and
  locoweed (with the expansion: black too).
  """
  @spec book_colours(boolean) :: [atom]
  def book_colours(expansion \\ false)
  def book_colours(false), do: @book_colours ++ [:orange, :locoweed]
  def book_colours(true), do: @book_colours ++ [:orange, :black, :locoweed]

  # The books a colour offers, in the order the select shows them.
  defp book_sets(colour, _expansion) when is_map_key(@extra_books, colour),
    do: @extra_books[colour]

  defp book_sets(colour, true) when is_map_key(@expansion_books, colour),
    do: @expansion_books[colour]

  defp book_sets(_colour, true), do: Enum.to_list(1..6)
  defp book_sets(_colour, false), do: Enum.to_list(1..4)

  # The book a colour uses now (orange and locoweed may be left out of `sets`).
  defp book(sets, colour, expansion),
    do: Chips.set(if(expansion, do: :herb_witches), sets, colour)

  defp set_name(nil, :locoweed), do: "Not used"
  defp set_name(1, :black), do: "Base"
  defp set_name(2, :orange), do: "Set 2 (+ orange 6)"
  defp set_name(set, _colour), do: "Set #{set}"

  @doc """
  The form's `%{"green" => "2", ...}` as `%{green: 2, ...}`. A missing or bad value
  is the colour's default book (Set 1; with the expansion orange 2 and locoweed 5),
  so a crafted request cannot break the game. With `expansion` the expansion's books
  are allowed and black and locoweed are in the map. Orange (and locoweed in a base
  game) is left out at its default, so default games keep the same `game.sets`.
  """
  @spec parse_sets(map, boolean) :: Chips.sets()
  def parse_sets(params, expansion \\ false) do
    book_colours(expansion)
    |> Map.new(fn colour ->
      default = book(%{}, colour, expansion)
      {colour, parse_set(params[to_string(colour)], book_sets(colour, expansion), default)}
    end)
    |> Map.reject(&engine_default?(&1, expansion))
  end

  # Book values the engine fills in by itself and keeps out of `game.sets`: orange
  # at its default, and "no locoweed" in a base game.
  defp engine_default?({:orange, set}, expansion), do: set == book(%{}, :orange, expansion)
  defp engine_default?({:locoweed, nil}, false), do: true
  defp engine_default?(_book, _expansion), do: false

  # "" is "Not used" (nil) for locoweed.
  defp parse_set(value, sets, default) when is_binary(value) do
    set =
      case Integer.parse(value) do
        {set, ""} -> set
        _ -> if value == "", do: nil, else: :bad
      end

    if set in sets, do: set, else: default
  end

  defp parse_set(_value, _sets, default), do: default

  @doc """
  The Options form's `%{"explode_above" => "9", "rats" => "false", ...}` as house
  rules. A missing or bad value keeps its default (`Quacks.Game.default_rules/0`).
  """
  @spec parse_rules(map) :: Game.rules()
  def parse_rules(params) do
    Map.new(@rule_values, fn {key, values} ->
      default = Game.default_rules()[key]
      {key, Enum.find(values, default, &(to_string(&1) == params[to_string(key)]))}
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
