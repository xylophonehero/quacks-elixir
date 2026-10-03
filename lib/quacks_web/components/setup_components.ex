defmodule QuacksWeb.SetupComponents do
  @moduledoc """
  The forms that set a game up before it starts, on the configure screen of a
  waiting game (`QuacksWeb.GameLive`): the Ingredient books with the Herb Witches
  toggle, and the house rules ("Options").

  Both are plain `phx-change` forms: every change sends every field, and the page
  turns them into game settings with `parse_sets/2` and `parse_rules/1`. A bad or
  missing value falls back to its default, so a crafted request cannot break a game.
  With `disabled` the forms are read-only (players who are not the host).
  """
  use Phoenix.Component

  import QuacksWeb.CoreComponents, only: [input: 1]
  import QuacksWeb.GameComponents, only: [book_list: 1, book_text: 1]

  alias Quacks.Game
  alias Quacks.Rules.{Books, Chips}

  # The colours with four ingredient books, in the order the form shows them.
  @book_colours [:green, :blue, :red, :yellow, :purple]
  # Orange (Set 2 = the orange 6-chip), black and locoweed (nil = not used) in every game.
  @extra_books %{orange: [1, 2], black: [1, 5, 6], locoweed: [nil, 5, 6]}

  # Every house rule the Options form offers, with the values it accepts.
  @rule_values %{
    explode_above: 5..9,
    starting_rubies: 0..3,
    round6_white: [true, false],
    fortune: [true, false],
    rats: [true, false],
    black_solo: [:droplet, :droplet_ruby],
    overflow: [true, false],
    die: [:standard, :no_orange],
    supply: [:infinite, :limited]
  }

  @doc """
  The Ingredient books form (`#books`, event `"sets"`): the expansion toggle and
  one select per colour, with the chosen book's text under it.
  """
  attr :sets, :map, required: true, doc: "the chosen books; colours left out use their default"
  attr :expansion, :boolean, default: false
  attr :disabled, :boolean, default: false

  def books_form(assigns) do
    ~H"""
    <form id="books" phx-change="sets" aria-label="Ingredient books">
      <fieldset disabled={@disabled} class="space-y-2">
        <h3 class="font-bold">Ingredient books</h3>
        <.input
          type="checkbox"
          id="expansion"
          name="expansion"
          label="Herb Witches expansion"
          value={@expansion}
        />
        <div class="grid grid-cols-1 gap-x-3 gap-y-2 sm:grid-cols-2">
          <div :for={colour <- book_colours()} data-role="book" data-colour={colour}>
            <.input
              type="select"
              id={"sets-#{colour}"}
              name={"sets[#{colour}]"}
              label={String.capitalize(to_string(colour))}
              value={book(@sets, colour, @expansion)}
              options={Enum.map(book_sets(colour, @expansion), &{set_name(&1, colour), &1})}
              class="w-full rounded-lg border border-ink-soft bg-parchment-light px-3 py-2 text-base text-ink sm:text-sm"
            />
            <div :if={book(@sets, colour, @expansion)} data-role="chosen-book">
              <.book_text book={Books.get({colour, book(@sets, colour, @expansion)})} />
            </div>
            <details class="text-xs">
              <summary class="cursor-pointer text-ink-soft">All {colour} books</summary>
              <div class="mt-1">
                <.book_list books={for set <- book_sets(colour, @expansion), set, do: {colour, set}} />
              </div>
            </details>
          </div>
        </div>
      </fieldset>
    </form>
    """
  end

  @doc "The house rules form (`#options`, event `\"rules\"`)."
  attr :rules, :map, required: true, doc: "every house rule, see `Quacks.Game.default_rules/0`"
  attr :disabled, :boolean, default: false

  def options_form(assigns) do
    ~H"""
    <form id="options" phx-change="rules" aria-label="House rules">
      <fieldset disabled={@disabled} class="space-y-2">
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
        <.input
          type="checkbox"
          id="rules-overflow"
          name="rules[overflow]"
          label="Overflow bowl (chips past the last space)"
          value={@rules.overflow}
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
        <.radios
          name="supply"
          legend="Chip supply"
          value={@rules.supply}
          options={[infinite: "infinite", limited: "limited (the chips in the box)"]}
        />
      </fieldset>
    </form>
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
  The colours the Ingredient books form offers: the five book colours, orange, black
  and locoweed (in every game).
  """
  @spec book_colours() :: [atom]
  def book_colours, do: @book_colours ++ [:orange, :black, :locoweed]

  # The books a colour offers, in the order the select shows them.
  defp book_sets(colour, _expansion) when is_map_key(@extra_books, colour),
    do: @extra_books[colour]

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
  is the colour's default book (Set 1; with the expansion orange 2 and locoweed 5).
  With `expansion` Sets 5 and 6 are allowed for the five book colours; black is
  always in the map, locoweed with the expansion. Orange (and locoweed in a base game) is left out at its default, so
  default games keep the same `game.sets`.
  """
  @spec parse_sets(map, boolean) :: Chips.sets()
  def parse_sets(params, expansion \\ false) do
    book_colours()
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
end
