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

  import QuacksWeb.CoreComponents, only: [button: 1, input: 1, sheet: 1]
  import QuacksWeb.Icons, only: [ingredient_icon: 1, piece_icon: 1]

  import QuacksWeb.GameComponents,
    only: [
      book_info: 2,
      book_ink: 1,
      book_seal: 1,
      book_tiers: 1,
      book_tile: 1,
      chip: 1,
      roman: 1
    ]

  alias Phoenix.LiveView.JS
  alias Quacks.Game
  alias Quacks.Rules.Chips

  # The colours with four ingredient books, in the order the form shows them.
  @book_colours [:green, :blue, :red, :yellow, :purple]
  # Orange (Set 2 = the orange 6-chip), black (II–III are The Herb Witches' books) and
  # locoweed (nil = not used; I–II are The Herb Witches' books, III–VI The Alchemists'
  # A–D) in every game.
  @extra_books %{orange: [1, 2], black: [1, 2, 3], locoweed: [nil, 1, 2, 3, 4, 5, 6]}
  # Books the picker shows greyed out without The Alchemists (they need the essence
  # phase).
  @alchemists_only %{{:locoweed, 3} => "needs The Alchemists"}

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
    supply: [:infinite, :limited],
    pot_side: [:front, :back]
  }

  @doc """
  The Ingredient books form (`#books`, event `"sets"`): the two expansion toggles
  as cards on top (both may be on), with the reverse pot side as a third, smaller
  card (that switch belongs to `#options`), then one `book_tile` per colour. The
  host sees compact tiles (icon, name, book seal) in a grid; the picker has the full
  text. Locoweed III is greyed out
  without The Alchemists. The host taps a tile to open its picker sheet, a list
  of book cards (radio buttons `sets[colour]`); a tap on a card picks that book and
  closes the sheet. Other players see the tiles only.
  """
  attr :sets, :map, required: true, doc: "the chosen books; colours left out use their default"
  attr :expansion, :boolean, default: false, doc: "The Herb Witches"
  attr :alchemists, :boolean, default: false, doc: "The Alchemists"

  attr :pot_side, :atom,
    default: :front,
    doc: "the house rule; its checkbox belongs to `#options`"

  attr :players, :integer, default: nil, doc: "the table size, see `book_tiers/1`"
  attr :disabled, :boolean, default: false

  def books_form(assigns) do
    ~H"""
    <form id="books" phx-change="sets" aria-label="Ingredient books">
      <fieldset disabled={@disabled} class="space-y-2">
        <h3 class="font-bold">Expansions</h3>
        <div class="grid grid-cols-2 gap-2" data-role="expansion-cards">
          <.toggle_card
            id="expansion"
            name="expansion"
            checked={@expansion}
            title="The Herb Witches"
            text="Witch cards, overflow bowl"
            icon={:witch}
          />
          <.toggle_card
            id="alchemists"
            name="alchemists"
            checked={@alchemists}
            title="The Alchemists"
            text="Patients and essence"
            icon={:flask}
          />
          <%!-- Part of the house rules form (`form="options"`), shown here beside the expansions. --%>
          <.toggle_card
            id="rules-pot_side"
            name="rules[pot_side]"
            form="options"
            checked={@pot_side == :back}
            title="Pot: reverse side"
            text="Test tubes"
            icon={:tube}
            small
          />
        </div>
        <h3 class="pt-1 font-bold">Ingredient books</h3>
        <p :if={!@disabled} class="text-sm text-ink-soft">Tap a book to pick another.</p>
        <div class={[
          "grid gap-2.5",
          if(@disabled, do: "grid-cols-1 sm:grid-cols-2", else: "grid-cols-2 sm:grid-cols-3")
        ]}>
          <%= for colour <- book_colours() do %>
            <.book_tile
              :if={@disabled}
              colour={colour}
              set={book(@sets, colour)}
              players={@players}
            />
            <button
              :if={!@disabled}
              type="button"
              popovertarget={"book-picker-#{colour}"}
              aria-label={"#{colour} book: change"}
              class="block cursor-pointer rounded-[14px] text-left transition-[translate,scale,box-shadow] duration-150 ease-(--ease-out) hover:-translate-y-0.5 active:scale-[0.97] motion-reduce:transition-none"
            >
              <.book_tile colour={colour} set={book(@sets, colour)} players={@players} compact />
            </button>
            <.book_picker
              :if={!@disabled}
              colour={colour}
              chosen={book(@sets, colour)}
              sets={book_sets(colour)}
              players={@players}
              alchemists={@alchemists}
            />
          <% end %>
        </div>
      </fieldset>
    </form>
    """
  end

  # An on/off card: a switch (a real checkbox, `.switch` in app.css) with an icon, a
  # title and a line of text. The hidden "false" goes first, so an unticked box still
  # sends its name.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :checked, :boolean, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true
  attr :icon, :atom, required: true
  attr :form, :string, default: nil
  attr :small, :boolean, default: false

  defp toggle_card(assigns) do
    ~H"""
    <label
      for={@id}
      class={[
        "toggle-card grid cursor-pointer items-center gap-x-2.5 rounded-xl bg-parchment-light p-2.5 ring-1 ring-ink/15",
        "transition-[box-shadow,background-color,scale] duration-150 ease-out active:scale-[0.98]",
        "has-checked:bg-potion/15 has-checked:ring-2 has-checked:ring-potion-deep/60",
        "has-disabled:cursor-default has-disabled:active:scale-100",
        "has-focus-visible:outline-3 has-focus-visible:outline-offset-2 has-focus-visible:outline-droplet",
        if(@small,
          do: "col-span-2 grid-cols-[auto_1fr_auto] py-2",
          else: "grid-cols-[1fr_auto] content-start gap-y-1"
        )
      ]}
      data-role="toggle-card"
    >
      <.piece_icon
        name={@icon}
        class={["shrink-0 text-ink-soft", if(@small, do: "size-6", else: "size-9")]}
      />
      <span class={["min-w-0", !@small && "col-span-2 row-start-2"]}>
        <span class={[
          "block leading-tight font-bold",
          if(@small, do: "text-sm", else: "font-hand text-lg")
        ]}>
          {@title}
        </span>
        <span class="block text-xs leading-snug text-ink-soft">{@text}</span>
      </span>
      <input type="hidden" name={@name} value="false" form={@form} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        form={@form}
        class={["switch shrink-0", !@small && "col-start-2 row-start-1"]}
      />
    </label>
    """
  end

  # The picker sheet of one colour: a card (radio button) per book.
  attr :colour, :atom, required: true
  attr :chosen, :any, required: true
  attr :sets, :list, required: true
  attr :players, :integer, default: nil
  attr :alchemists, :boolean, default: false

  defp book_picker(assigns) do
    books =
      Enum.map(assigns.sets, fn set ->
        {set, book_info(assigns.colour, set),
         unavailable(assigns.colour, set, assigns.alchemists)}
      end)

    assigns = assign(assigns, books: books, name: books |> hd() |> elem(1) |> Map.get(:name))

    ~H"""
    <.sheet id={"book-picker-#{@colour}"} label={"#{@name} books"}>
      <h2 class="flex items-center gap-2 font-hand text-2xl font-bold text-ink">
        <.ingredient_icon colour={@colour} class={["size-8 shrink-0", book_ink(@colour)]} />
        {@name}
      </h2>
      <p class="text-sm text-ink-soft">
        <span class="capitalize">{@colour}</span>. Tap a book to use it.
      </p>
      <div class="mt-3 grid gap-2.5" role="radiogroup" aria-label={"#{@colour} book"}>
        <label
          :for={{set, book, unavailable} <- @books}
          class={[
            "book-card group grid gap-2 rounded-[14px] bg-parchment-light p-3 pb-3.5 text-ink",
            "has-focus-visible:outline-3 has-focus-visible:outline-offset-2 has-focus-visible:outline-droplet",
            if(unavailable, do: "cursor-not-allowed opacity-50 grayscale", else: "cursor-pointer")
          ]}
          data-role="book-card"
          data-set={set || "off"}
          aria-disabled={unavailable && "true"}
        >
          <input
            type="radio"
            name={"sets[#{@colour}]"}
            value={set || ""}
            checked={set == @chosen}
            disabled={unavailable != nil}
            class="sr-only"
            phx-click={JS.dispatch("quacks:close", to: "#book-picker-#{@colour}")}
          />
          <span class="flex min-w-0 items-center gap-2">
            <.book_seal set={set} />
            <span class="min-w-0 flex-1 font-hand text-lg font-bold">
              {if set, do: "Book #{roman(set)}", else: "Not in play"}
            </span>
            <span
              :if={unavailable}
              class="shrink-0 rounded-full bg-ink/10 px-2 py-0.5 text-[11px] font-bold text-ink-soft"
            >
              {unavailable}
            </span>
            <span class="book-check" aria-hidden="true">
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="#3a2508"
                stroke-width="3.5"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M5 12.5l4.5 4.5L19 7.5" />
              </svg>
            </span>
          </span>
          <span :if={book.text != ""} class="text-sm leading-normal text-pretty">{book.text}</span>
          <.book_tiers tiers={book.tiers} players={@players} />
          <span :if={book.chips != []} class="flex flex-wrap gap-1.5">
            <span
              :for={{chip, price} <- book.chips}
              class="inline-flex items-center gap-1.5 rounded-full bg-ink/8 py-0.5 pr-2.5 pl-0.5 text-[13px] font-bold tabular-nums ring-1 ring-ink/12 ring-inset"
            >
              <.chip chip={chip} size={:sm} />{price} <span class="book-coin" />
            </span>
          </span>
          <span :if={book.chips == []} class="text-[13px] text-ink-soft">
            No chips to buy
          </span>
        </label>
      </div>
    </.sheet>
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
          <.rule_stepper
            rule={:explode_above}
            label="Explodes above (white)"
            value={@rules.explode_above}
            disabled={@disabled}
          />
          <.rule_stepper
            rule={:starting_rubies}
            label="Starting rubies"
            value={@rules.starting_rubies}
            disabled={@disabled}
          />
        </div>
        <.input
          type="checkbox"
          id="rules-round6_white"
          name="rules[round6_white]"
          label="Extra white 1-chip before round 6"
          value={@rules.round6_white}
          class="switch"
        />
        <.input
          type="checkbox"
          id="rules-fortune"
          name="rules[fortune]"
          label="Fortune Teller cards"
          value={@rules.fortune}
          class="switch"
        />
        <.input
          type="checkbox"
          id="rules-rats"
          name="rules[rats]"
          label="Rats (2+ players)"
          value={@rules.rats}
          class="switch"
        />
        <.input
          type="checkbox"
          id="rules-overflow"
          name="rules[overflow]"
          label="Overflow bowl (chips past the last space)"
          value={@rules.overflow}
          class="switch"
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
      <div class="segmented flex gap-1 rounded-lg bg-parchment-deep p-1">
        <label
          :for={{value, label} <- @options}
          class="relative flex min-h-10 flex-1 cursor-pointer items-center justify-center px-2 py-1 text-center leading-tight"
        >
          <input
            type="radio"
            id={"rules-#{@name}-#{value}"}
            name={"rules[#{@name}]"}
            value={value}
            checked={@value == value}
            class="segment"
          />
          <span class="relative">{label}</span>
        </label>
      </div>
    </fieldset>
    """
  end

  @doc """
  The colours the Ingredient books form offers: the five book colours, orange, black
  and locoweed (in every game).
  """
  @spec book_colours() :: [atom]
  def book_colours, do: @book_colours ++ [:orange, :black, :locoweed]

  # The books a colour offers, in the order the picker shows them, with or without
  # the expansion.
  defp book_sets(colour) when is_map_key(@extra_books, colour), do: @extra_books[colour]
  defp book_sets(_colour), do: Enum.to_list(1..6)

  defp unavailable(_colour, _set, true), do: nil
  defp unavailable(colour, set, false), do: @alchemists_only[{colour, set}]

  # The book a colour uses now (orange and locoweed may be left out of `sets`).
  defp book(sets, colour), do: Chips.set(nil, sets, colour)

  @doc """
  The form's `%{"green" => "2", ...}` as `%{green: 2, ...}`. A missing, bad or greyed
  out value is the colour's default book (Set 1, no locoweed); locoweed III only
  with `alchemists?`. The Herb Witches change no book. Black is always in the map; orange 1 and "no locoweed" are left out, so
  default games keep the same `game.sets`.
  """
  @spec parse_sets(map, boolean) :: Chips.sets()
  def parse_sets(params, alchemists? \\ false) do
    book_colours()
    |> Map.new(fn colour ->
      sets = Enum.filter(book_sets(colour), &(unavailable(colour, &1, alchemists?) == nil))
      {colour, parse_set(params[to_string(colour)], sets, book(%{}, colour))}
    end)
    |> Map.reject(&(&1 in [orange: 1, locoweed: nil]))
  end

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
  A number house rule as a − / + stepper (event `"rule_step"`). The value rides in a
  hidden input with the old number input's id, so the form's `"rules"` change still
  sends it.
  """
  attr :rule, :atom, required: true, values: [:explode_above, :starting_rubies]
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :disabled, :boolean, default: false

  def rule_stepper(assigns) do
    assigns = assign(assigns, range: @rule_values[assigns.rule])

    ~H"""
    <div class="mb-2" data-role="rule-stepper" data-rule={@rule}>
      <span class="mb-1 block text-sm font-semibold" id={"rules-#{@rule}-label"}>{@label}</span>
      <div class="flex items-center gap-2" role="group" aria-labelledby={"rules-#{@rule}-label"}>
        <input type="hidden" id={"rules-#{@rule}"} name={"rules[#{@rule}]"} value={@value} />
        <.button
          type="button"
          phx-click="rule_step"
          phx-value-rule={@rule}
          phx-value-to={@value - 1}
          disabled={@disabled or @value <= @range.first}
          aria-label={"#{@label}: less"}
          variant={:secondary}
          class="size-11 px-0 text-xl"
        >
          −
        </.button>
        <span class="w-6 text-center text-2xl font-bold tabular-nums" data-role="rule-value">
          {@value}
        </span>
        <.button
          type="button"
          phx-click="rule_step"
          phx-value-rule={@rule}
          phx-value-to={@value + 1}
          disabled={@disabled or @value >= @range.last}
          aria-label={"#{@label}: more"}
          variant={:secondary}
          class="size-11 px-0 text-xl"
        >
          +
        </.button>
      </div>
    </div>
    """
  end

  @doc """
  The house rules after one stepper tap: `rules` with `rule` (a string from the
  page) set to `to`. A bad rule or value changes nothing.
  """
  @spec step_rule(Game.rules(), String.t(), String.t()) :: Game.rules()
  def step_rule(rules, rule, to) when rule in ["explode_above", "starting_rubies"] do
    key = String.to_existing_atom(rule)

    case Integer.parse(to) do
      {n, ""} -> if n in @rule_values[key], do: Map.put(rules, key, n), else: rules
      _ -> rules
    end
  end

  def step_rule(rules, _rule, _to), do: rules

  @doc """
  The Options form's `%{"explode_above" => "9", "rats" => "false", ...}` as house
  rules. A missing or bad value keeps its default (`Quacks.Game.default_rules/0`).
  The reverse-side checkbox sends `"pot_side" => "true"` (the saved config `"back"`).
  """
  @spec parse_rules(map) :: Game.rules()
  def parse_rules(params) do
    params =
      case params["pot_side"] do
        "true" -> Map.put(params, "pot_side", "back")
        "false" -> Map.put(params, "pot_side", "front")
        _other -> params
      end

    Map.new(@rule_values, fn {key, values} ->
      default = Game.default_rules()[key]
      {key, Enum.find(values, default, &(to_string(&1) == params[to_string(key)]))}
    end)
  end
end
