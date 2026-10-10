defmodule QuacksWeb.SetupComponents do
  @moduledoc """
  The forms that set a game up before it starts, in the spell book
  (`QuacksWeb.LobbyLive`): the expansion toggles, the Ingredient books, the house
  rules ("Options") and the seat colour picker (also on the waiting panel).

  The forms are plain `phx-change` forms: every change sends every field, and the
  page turns them into game settings with `parse_sets/2` and `parse_rules/1`. A bad
  or missing value falls back to its default, so a crafted request cannot break a
  game.
  """
  use Phoenix.Component

  import QuacksWeb.CoreComponents, only: [button: 1, icon: 1, input: 1]
  import QuacksWeb.Icons, only: [piece_icon: 1]

  import QuacksWeb.GameComponents,
    only: [book_info: 2, book_seal: 1, book_tiers: 1, book_tile: 1, roman: 1]

  import QuacksWeb.ChipComponents, only: [chip: 1, palette_bg: 1]

  alias Phoenix.LiveView.JS
  alias Quacks.Game
  alias Quacks.Rules.Chips
  alias Quacks.Rules.Witches

  # The herb witch pickers, in the rulebook's penny order, and each colour's band.
  @witch_colours [:copper, :silver, :gold]
  @penny_bg %{copper: "bg-penny-copper", silver: "bg-penny-silver", gold: "bg-penny-gold"}

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
    black_rule: [:neighbours, :standings],
    overflow: [true, false],
    die: [:standard, :no_orange],
    supply: [:infinite, :limited],
    pot_side: [:front, :back]
  }

  @doc """
  The Herb Witches' tiles (round 29: the witches' Customise page): one tile per
  penny colour, "Random" or a card. Each tile links to its colour's page (`patch`),
  where `witch_options/1` draws the radio cards of `#books`.
  """
  attr :witches, :map,
    default: %{},
    doc: "the herb witch picks, `%{copper: :c3}`; a colour left out or nil is dealt"

  attr :patch, :any, required: true, doc: "a function `({:witch, colour} -> path)`"

  def witch_links(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-2" data-role="witch-pickers">
      <.link
        :for={colour <- witch_colours()}
        patch={@patch.({:witch, colour})}
        id={"witch-link-#{colour}"}
        aria-label={"#{colour} witch: change"}
        class="block rounded-lg text-left transition-[translate,scale] duration-150 ease-(--ease-out) hover:-translate-y-0.5 active:scale-[0.97] motion-reduce:transition-none"
      >
        <.witch_tile colour={colour} id={@witches[colour]} />
      </.link>
    </div>
    """
  end

  @doc """
  The Ingredient books form of the spell book (`#books`, event `"sets"`): one
  compact `book_tile` per colour (icon, name, book seal). Each tile links to its
  colour's page (`patch`), where `book_options/1` draws the radio cards of this
  form. The witch radio cards (`witch_options/1`) and the expansion switches of the
  New game page also belong to this form by their `form=` attribute.
  """
  attr :sets, :map, required: true, doc: "the chosen books; colours left out use their default"
  attr :players, :integer, default: nil, doc: "the table size, see `book_tiers/1`"

  attr :heading, :boolean, default: true, doc: "false: the page has its own heading"

  attr :patch, :any,
    required: true,
    doc: "a function `({:book | :witch, colour} -> path)`: the colour page of a tile"

  def books_form(assigns) do
    ~H"""
    <form id="books" phx-change="sets" aria-label="Ingredient books">
      <div class="space-y-2">
        <h3 :if={@heading} class="pt-1 font-bold">Ingredient books</h3>
        <p class="text-sm text-ink-soft">Tap a book to pick another.</p>
        <div class="grid grid-cols-2 gap-2.5 sm:grid-cols-3">
          <.link
            :for={colour <- book_colours()}
            patch={@patch.({:book, colour})}
            id={"book-link-#{colour}"}
            aria-label={"#{colour} book: change"}
            class="block rounded-[14px] text-left transition-[translate,scale,box-shadow] duration-150 ease-(--ease-out) hover:-translate-y-0.5 active:scale-[0.97] motion-reduce:transition-none"
          >
            <.book_tile colour={colour} set={book(@sets, colour)} players={@players} compact />
          </.link>
        </div>
      </div>
    </form>
    """
  end

  @doc """
  An expansion's row on the New game page (round 29): icon, title, a line on the
  current choice, a Customise button (`customise`, a path; nil when the expansion
  has nothing to customise) and the switch. The input names its form with `form=`
  (`#books` or `#options`), so the row may stand outside the form. Customise is off
  while the switch is off; a dot on it marks a changed setting (`changed`).
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :form, :string, required: true
  attr :checked, :boolean, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true
  attr :icon, :atom, required: true, doc: "a piece icon"
  attr :customise, :string, default: nil
  attr :changed, :boolean, default: false

  def expansion_row(assigns) do
    ~H"""
    <div
      id={"row-#{@id}"}
      class={[
        "setup-row flex min-h-16 min-w-0 items-center gap-2 rounded-xl bg-parchment-light py-2 pr-2.5 pl-3 ring-1 ring-ink/15",
        "transition-[box-shadow,background-color] duration-150 ease-out",
        "has-checked:bg-potion/15 has-checked:ring-2 has-checked:ring-potion-deep/60"
      ]}
      data-role="expansion-row"
    >
      <label for={@id} class="flex min-w-0 flex-1 cursor-pointer items-center gap-2.5">
        <.piece_icon name={@icon} class="size-7 shrink-0 text-ink-soft" />
        <span class="min-w-0">
          <span class="block font-hand text-lg leading-tight font-bold max-sm:text-base">
            {@title}
          </span>
          <span class="block truncate text-xs leading-snug text-ink-soft" data-role="row-summary">
            {@text}
          </span>
        </span>
      </label>
      <.customise_button
        :if={@customise}
        id={"customise-#{@id}"}
        patch={@customise}
        changed={@changed}
        disabled={!@checked}
      />
      <input type="hidden" name={@name} value="false" form={@form} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        form={@form}
        class="switch shrink-0"
      />
    </div>
    """
  end

  @doc """
  The Customise button of a New game row: it opens the row's page. A dot marks a
  setting changed from the default.
  """
  attr :id, :string, required: true
  attr :patch, :string, required: true
  attr :changed, :boolean, default: false
  attr :disabled, :boolean, default: false

  def customise_button(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@patch}
      class="customise-button"
      aria-disabled={@disabled && "true"}
      tabindex={@disabled && "-1"}
      data-role="customise"
    >
      Customise
      <span :if={@changed} class="changed-dot" data-role="changed-dot">
        <span class="sr-only">(changed)</span>
      </span>
    </.link>
    """
  end

  @doc """
  An on/off card for the spell book's switches (the Public toggle).
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :checked, :boolean, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true
  attr :icon, :any, required: true, doc: "a piece icon (atom) or a hero icon name"
  attr :form, :string, default: nil
  attr :small, :boolean, default: false

  def switch_card(assigns), do: toggle_card(assigns)

  # A small witch tile: the penny colour band, then the picked card's title or
  # "Random".
  attr :colour, :atom, required: true
  attr :id, :atom, default: nil

  defp witch_tile(assigns) do
    ~H"""
    <span
      class="paper block h-full overflow-hidden rounded-lg text-ink"
      data-role="witch-tile"
      data-colour={@colour}
      data-witch={@id || "random"}
    >
      <span class={[
        "flex items-center gap-1 px-2 py-0.5 text-[11px] font-semibold tracking-wide uppercase",
        penny_bg(@colour)
      ]}>
        <.piece_icon name={:penny} class="size-3.5 shrink-0" /> {@colour}
      </span>
      <span class="block px-2 py-1.5 text-sm leading-tight font-bold">
        {if @id, do: Witches.card(@id).title, else: "Random"}
      </span>
    </span>
    """
  end

  @doc """
  The witch cards of one penny colour: "Random" (dealt from the seed) or one of its
  4 cards, as radio cards `witches[colour]`. `on_pick` runs on a tap (close the
  sheet, or leave the spell book's witch page); `form` names the form when the
  cards stand outside `#books`.
  """
  attr :colour, :atom, required: true
  attr :chosen, :atom, default: nil
  attr :on_pick, :any, default: nil
  attr :form, :string, default: nil
  attr :class, :any, default: nil

  def witch_options(assigns) do
    assigns = assign(assigns, options: [nil | Witches.ids(assigns.colour)])

    ~H"""
    <div class={["grid gap-2", @class]} role="radiogroup" aria-label={"#{@colour} witch"}>
      <label
        :for={id <- @options}
        class="book-card group grid cursor-pointer gap-1 rounded-[14px] bg-parchment-light p-3 text-ink has-focus-visible:outline-3 has-focus-visible:outline-offset-2 has-focus-visible:outline-droplet"
        data-role="witch-option"
        data-witch={id || "random"}
      >
        <input
          type="radio"
          name={"witches[#{@colour}]"}
          value={id || ""}
          checked={id == @chosen}
          form={@form}
          class="sr-only"
          phx-click={@on_pick}
        />
        <span class="flex min-w-0 items-center gap-2">
          <span class="min-w-0 flex-1 font-hand text-lg font-bold">
            {if id, do: Witches.card(id).title, else: "Random"}
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
        <span class="text-sm leading-snug text-pretty text-ink-soft">
          {if id, do: Witches.card(id).text, else: "One of the four, dealt when the game starts."}
        </span>
      </label>
    </div>
    """
  end

  defp penny_bg(colour), do: @penny_bg[colour]

  @doc "The herb witch colours of the pickers, in the rulebook's penny order."
  @spec witch_colours() :: [Witches.colour()]
  def witch_colours, do: @witch_colours

  @doc """
  The herb witch picks of the books form (`witches[colour]`, a witch id or "" for
  Random) as `Quacks.Game.new/1`'s `witches:` option. An unknown id is Random.

      iex> QuacksWeb.SetupComponents.parse_witches(%{"copper" => "c3", "silver" => "", "gold" => "x"})
      %{copper: :c3, silver: nil, gold: nil}
  """
  @spec parse_witches(map | nil) :: %{Witches.colour() => Witches.id() | nil}
  def parse_witches(params) do
    params = if is_map(params), do: params, else: %{}

    Map.new(@witch_colours, fn colour ->
      ids = Witches.ids(colour)
      {colour, Enum.find(ids, &(Atom.to_string(&1) == params[Atom.to_string(colour)]))}
    end)
  end

  # An on/off card: a switch (a real checkbox, `.switch` in app.css) with an icon, a
  # title and a line of text. The hidden "false" goes first, so an unticked box still
  # sends its name.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :checked, :boolean, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true
  attr :icon, :any, required: true
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
          else: [
            "max-lg:grid-cols-[auto_1fr_auto] max-lg:min-h-16 max-lg:px-3",
            "lg:grid-cols-[1fr_auto] lg:content-start lg:gap-y-1"
          ]
        )
      ]}
      data-role="toggle-card"
    >
      <.icon
        :if={is_binary(@icon)}
        name={@icon}
        class={["shrink-0 text-ink-soft", if(@small, do: "size-6", else: "size-8")]}
      />
      <.piece_icon
        :if={is_atom(@icon)}
        name={@icon}
        class={["shrink-0 text-ink-soft", if(@small, do: "size-6", else: "size-8")]}
      />
      <span class={["min-w-0", !@small && "lg:col-span-2 lg:row-start-2"]}>
        <span class={[
          "block leading-tight font-bold",
          if(@small, do: "text-sm", else: "font-hand text-lg")
        ]}>
          {@title}
        </span>
        <span class="block text-xs leading-snug text-ink-soft max-lg:truncate">{@text}</span>
      </span>
      <input type="hidden" name={@name} value="false" form={@form} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        form={@form}
        class={["switch shrink-0", !@small && "lg:col-start-2 lg:row-start-1"]}
      />
    </label>
    """
  end

  @doc """
  The book cards of one colour (title, text, table, chips with prices), as radio
  cards `sets[colour]`. `on_pick` runs on a tap; `form` names the form when the
  cards stand outside `#books` (the spell book's colour pages). `sets: nil` offers
  every book the colour has.
  """
  attr :colour, :atom, required: true
  attr :chosen, :any, required: true
  attr :sets, :list, default: nil
  attr :players, :integer, default: nil
  attr :alchemists, :boolean, default: false
  attr :on_pick, :any, default: nil
  attr :form, :string, default: nil
  attr :class, :any, default: nil

  def book_options(assigns) do
    books =
      Enum.map(assigns.sets || book_sets(assigns.colour), fn set ->
        {set, book_info(assigns.colour, set),
         unavailable(assigns.colour, set, assigns.alchemists)}
      end)

    assigns = assign(assigns, books: books)

    ~H"""
    <div class={["grid gap-2.5", @class]} role="radiogroup" aria-label={"#{@colour} book"}>
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
          form={@form}
          class="sr-only"
          phx-click={@on_pick}
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
          name="black_rule"
          legend="Black chips compare with"
          value={@rules.black_rule}
          options={[neighbours: "neighbours (rulebook)", standings: "players ranked above"]}
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

  @colour_names ~w(gold teal violet coral lime rose sky slate)

  @doc """
  Your seat's colour picker (waiting panel and spell book): the 8 palette
  colours, one tap sends `"colour"`; colours other seats have are struck through and
  cannot be picked. A tap submits `#rename-form` first, so a name typed just before
  is not lost.
  """
  attr :colours, :map, required: true
  attr :seat, :integer, required: true

  def colour_picker(assigns) do
    assigns =
      assign(assigns,
        mine: assigns.colours[assigns.seat],
        taken: assigns.colours |> Map.delete(assigns.seat) |> Map.values(),
        swatches: Enum.with_index(@colour_names, &{&2, &1})
      )

    ~H"""
    <div
      class="flex w-full gap-1.5 pt-0.5 pb-2"
      role="group"
      aria-label="Your colour"
      data-role="colour-picker"
    >
      <button
        :for={{colour, label} <- @swatches}
        type="button"
        phx-click={
          JS.dispatch("submit", to: "#rename-form") |> JS.push("colour", value: %{colour: colour})
        }
        disabled={colour in @taken}
        aria-label={if colour in @taken, do: "#{label} (taken)", else: label}
        aria-pressed={to_string(colour == @mine)}
        data-colour={colour}
        class={[
          "hit-44 aspect-square max-w-8 min-w-0 flex-1 cursor-pointer rounded-full shadow-[inset_0_0_0_1px_rgb(0_0_0/0.25)] transition-transform duration-150 ease-out active:scale-90 disabled:cursor-not-allowed disabled:opacity-35 disabled:active:scale-100",
          palette_bg(colour),
          colour == @mine && "ring-2 ring-ink ring-offset-2 ring-offset-parchment-light"
        ]}
      >
        <span
          :if={colour in @taken}
          class="absolute inset-x-0 top-1/2 h-0.5 -translate-y-1/2 -rotate-45 bg-ink"
          aria-hidden="true"
        />
      </button>
    </div>
    """
  end

  @doc "The ingredient's name of `colour`'s books, e.g. \"Garden spider\" for green."
  @spec book_name(atom) :: String.t()
  def book_name(colour), do: book_info(colour, colour |> book_sets() |> Enum.find(& &1)).name

  @doc """
  The colours the Ingredient books form offers, in the board's order
  (`Chips.order/0`): every colour but white (orange, black and locoweed in every
  game).
  """
  @spec book_colours() :: [atom]
  def book_colours, do: Chips.order() -- [:white]

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

  @doc """
  A random book per colour, as `parse_sets/2` returns them: uniform over the books
  the colour's picker offers (black I–III, orange I–II, the rest I–VI). Locoweed is
  uniform over "no locoweed" and its books, with or without an expansion; a book
  that needs an expansion (locoweed III needs The Alchemists) only when that
  expansion is on. Not the engine, so the process's `:rand` is fine.
  """
  @spec random_sets(boolean) :: Chips.sets()
  def random_sets(alchemists?) do
    book_colours()
    |> Map.new(fn colour ->
      sets = Enum.filter(book_sets(colour), &(unavailable(colour, &1, alchemists?) == nil))
      {colour, Enum.at(sets, :rand.uniform(length(sets)) - 1)}
    end)
    |> Map.reject(&(&1 in [orange: 1, locoweed: nil]))
  end

  @doc "Book I for every colour (no locoweed): the books of a default game."
  @spec default_sets() :: Chips.sets()
  def default_sets, do: parse_sets(%{})

  @doc """
  The books form's params (`"sets"`, `"witches"`, `"expansion"`, `"alchemists"`)
  as settings: `sets`, `witches`, `expansion` (`:herb_witches` or nil) and
  `expansions` (`[:alchemists]` or `[]`), the shape `Quacks.GameServer.configure/3`
  takes.
  """
  @spec parse_books(map) :: map
  def parse_books(form) do
    alchemists = form["alchemists"] in ["true", true]
    sets = if is_map(form["sets"]), do: form["sets"], else: %{}

    %{
      sets: parse_sets(sets, alchemists),
      witches: parse_witches(form["witches"]),
      expansion: if(form["expansion"] in ["true", true], do: :herb_witches),
      expansions: if(alchemists, do: [:alchemists], else: [])
    }
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
  The house rules of a config the browser saved (`ConfigMemory`). A config saved
  before round 27 (no `"v"`, or `"v" => 25`) holds the `black_rule` default of its
  time (neighbours before round 25, standings in rounds 25 and 26), not a choice: it
  is dropped, so the current default (`:neighbours`, the rulebook) applies.

      iex> QuacksWeb.SetupComponents.saved_rules(%{"v" => 25, "rules" => %{"black_rule" => "standings", "rats" => "false"}})
      %{"rats" => "false"}
      iex> QuacksWeb.SetupComponents.saved_rules(%{"rules" => %{"black_rule" => "neighbours"}})
      %{}
      iex> QuacksWeb.SetupComponents.saved_rules(%{"v" => 27, "rules" => %{"black_rule" => "standings"}})
      %{"black_rule" => "standings"}
  """
  @spec saved_rules(map) :: map
  def saved_rules(%{"v" => v, "rules" => rules}) when is_integer(v) and v >= 27 and is_map(rules),
    do: rules

  def saved_rules(%{"rules" => rules}) when is_map(rules), do: Map.delete(rules, "black_rule")

  def saved_rules(_saved), do: %{}

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
