defmodule QuacksWeb.PanelComponents do
  @moduledoc """
  The sheets and side panels: the ingredient books (book_tile/1, books_in_play/1,
  fold/1), the house rules, the witches (witch_card/1), the fortune teller cards
  (fortune_card/1, fortune_panel/1, fortune_tile/1) and the log (action_log/1,
  announcer/1).
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Quacks.Game
  alias Quacks.Rules.{Books, Chips}
  alias Quacks.Rules.Fortune
  alias Quacks.Rules.Witches

  import QuacksWeb.ChipComponents
  import QuacksWeb.GameText
  import QuacksWeb.Icons

  # Ingredient icons on parchment (`book_ink/1`), as full class names for Tailwind.
  @book_ink %{
    white: "text-ink",
    orange: "text-chip-orange",
    green: "text-chip-green",
    blue: "text-chip-blue",
    red: "text-chip-red",
    yellow: "text-[#b8860b]",
    purple: "text-chip-purple",
    black: "text-chip-black",
    locoweed: "text-chip-locoweed"
  }

  # The witch penny colours, as background classes.
  @pennies %{silver: "bg-penny-silver", copper: "bg-penny-copper", gold: "bg-penny-gold"}

  # A small picture per fortune card: a game piece, an ingredient, or nil (a sparkle).
  @card_motifs %{
    b1: :droplet,
    b2: :cauldron,
    b3: :bag,
    b4: :die,
    b5: :cauldron,
    b6: {:ingredient, :orange},
    b7: :bag,
    b8: :ruby,
    b9: :flask,
    b10: :flask,
    b11: :ruby,
    p1: nil,
    p2: :droplet,
    p3: :ruby,
    p4: :ruby,
    p5: {:ingredient, :green},
    p6: :vp,
    p7: :rat,
    p8: :bag,
    p9: :rat,
    p10: :rat,
    p11: :droplet,
    p12: :die,
    p13: :bag
  }

  @doc """
  This round's Fortune Teller card as a small portrait card in the pot's top left
  corner (round 22, every layout): the colour band, the motif and the name. It
  opens the `sheet-fortune` sheet with the full text, or (round 24, with `click`)
  sends that event: `GameLive` grows it back into the big card over the pot.
  """
  attr :id, :atom, required: true, doc: "`game.fortune_card`"
  attr :dom_id, :string, default: nil
  attr :class, :any, default: nil
  attr :click, :string, default: nil, doc: "an event to push instead of opening the sheet"

  def fortune_tile(assigns) do
    assigns = assign(assigns, card: Fortune.card(assigns.id), motif: @card_motifs[assigns.id])

    ~H"""
    <button
      id={@dom_id}
      type="button"
      popovertarget={!@click && "sheet-fortune"}
      phx-click={@click}
      class={[
        "paper card-portrait flex aspect-[5/7] w-12 max-w-full rotate-3 flex-col items-center overflow-hidden rounded-md text-center touch-manipulation lg:w-20",
        "transition-transform duration-100 ease-out active:scale-95",
        @class
      ]}
      aria-label={"Fortune teller card: #{@card.name}. " <> if(@click, do: "Show it big", else: "Show the text")}
      data-role="fortune-tile"
      data-colour={@card.colour}
    >
      <span class={[
        "h-1.5 w-full shrink-0 lg:h-2",
        @card.colour == :blue && "bg-chip-blue",
        @card.colour == :purple && "bg-chip-purple"
      ]} />
      <span
        class={[
          "mt-1 grid size-6 shrink-0 place-items-center lg:mt-2 lg:size-10",
          @card.colour == :blue && "text-chip-blue",
          @card.colour == :purple && "text-chip-purple"
        ]}
        aria-hidden="true"
      >
        <.card_motif motif={@motif} class="size-4 lg:size-7" />
      </span>
      <%!-- Phones: small enough for the free corner outside the pot's rim. --%>
      <span class="line-clamp-2 px-0.5 font-hand text-[8px] leading-tight font-bold lg:px-1 lg:text-xs">
        {@card.name}
      </span>
    </button>
    """
  end

  @doc """
  The game's Ingredient book per colour, e.g. "green 2 · blue 1 · ...".
  """
  attr :sets, :map, required: true, doc: "`game.sets`"

  def books(assigns) do
    ~H"""
    <p class="text-xs text-ink-soft" data-role="books">
      Ingredient books: {Enum.map_join(
        Enum.filter(Chips.order(), &Map.has_key?(@sets, &1)),
        " · ",
        &"#{&1} #{@sets[&1]}"
      )}
    </p>
    """
  end

  @doc """
  One ingredient book as a short line: name, when it acts, and its text. `book` is
  a `Quacks.Rules.Books.get/1` map.
  """
  attr :book, :map, required: true
  attr :players, :integer, default: nil, doc: "the table size; tier rows for other sizes hide"

  def book_text(assigns) do
    ~H"""
    <p class="text-xs text-ink-soft" data-role="book-text">
      <span class="font-semibold text-ink">{@book.name}</span>
      <span :if={@book.text != ""}>· {trigger_label(@book.trigger)} · {@book.text}</span>
    </p>
    <.book_tiers tiers={@book.tiers} players={@players} />
    """
  end

  @doc """
  A book's reward tiers as a small table (nothing when the book has none). With
  `players` only the rows for that table size show (`Books.tiers_for/2`).
  """
  attr :tiers, :list, required: true
  attr :players, :integer, default: nil

  def book_tiers(assigns) do
    assigns = assign(assigns, :tiers, Books.tiers_for(assigns.tiers, assigns.players))

    ~H"""
    <table :if={@tiers != []} class="mt-1 w-full text-xs" data-role="book-tiers">
      <tbody class="divide-y divide-ink/10">
        <tr :for={{label, text} <- @tiers}>
          <th class="py-0.5 pr-2 text-left font-semibold whitespace-nowrap tabular-nums">
            {label}
          </th>
          <td class="py-0.5">{text}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  A list of books, each with its colour, set and text, e.g. for the menu's "Books"
  sheet. `books` is a list of `{colour, set}` (`Quacks.Rules.Books.in_play/2`).
  """
  attr :books, :list, required: true
  attr :players, :integer, default: nil, doc: "the table size, see `book_tiers/1`"
  attr :rules, :map, default: %{}, doc: "the house rules (`Books.get/2`)"

  def book_list(assigns) do
    assigns = assign(assigns, :colours, chip_classes())

    ~H"""
    <dl class="space-y-2" data-role="book-list">
      <div :for={{colour, set} <- @books} data-book={"#{colour}-#{set}"}>
        <dt class="flex items-center gap-1.5 text-sm font-semibold">
          <.ingredient_icon colour={colour} class={["size-4", book_ink(colour)]} />
          {String.capitalize(to_string(colour))} {book_set_name(colour, set)}
        </dt>
        <dd><.book_text book={Books.get({colour, set}, @rules)} players={@players} /></dd>
      </div>
    </dl>
    """
  end

  @doc """
  One ingredient book as a parchment recipe card: the colour, the ingredient name,
  the book number as a gold seal, the full rule text and the chip prices. `set` nil
  is "no locoweed" (locoweed only). The `book-art` slot shows the ingredient icon.
  `compact`: only the icon, the name and the seal (the configure grid).
  """
  attr :colour, :atom, required: true
  attr :set, :any, required: true, doc: "1..6, or nil for locoweed not in play"
  attr :players, :integer, default: nil, doc: "the table size, see `book_tiers/1`"
  attr :class, :any, default: nil
  attr :compact, :boolean, default: false

  def book_tile(assigns) do
    assigns = assign(assigns, book: book_info(assigns.colour, assigns.set))

    ~H"""
    <div
      class={[
        "paper relative flex h-full flex-col gap-1.5 overflow-hidden rounded-[14px] text-left",
        if(@compact, do: "py-2 pr-2 pl-3", else: "py-3 pr-3 pl-4"),
        "before:absolute before:inset-y-0 before:left-0 before:w-[5px] before:bg-(--c)",
        @class
      ]}
      style={"--c: var(--color-chip-#{@colour})"}
      data-role="book-tile"
      data-colour={@colour}
      data-book={"#{@colour}-#{@set || "off"}"}
    >
      <div class={["flex min-w-0 items-center", if(@compact, do: "gap-1.5", else: "gap-2")]}>
        <div
          data-role="book-art"
          class={["shrink-0", if(@compact, do: "size-7", else: "size-10")]}
          aria-hidden="true"
        >
          <.ingredient_icon colour={@colour} class={["size-full", book_ink(@colour)]} />
        </div>
        <div class="min-w-0 flex-1">
          <p class={[
            "text-[10.5px] font-bold tracking-[0.08em] text-ink-soft uppercase",
            @compact && "sr-only"
          ]}>
            {@colour}
          </p>
          <p class={[
            "font-hand leading-tight font-bold",
            if(@compact, do: "line-clamp-2 text-sm", else: "text-lg")
          ]}>
            {@book.name}
          </p>
        </div>
        <.book_seal set={@set} />
      </div>
      <p :if={!@compact and @book.text != ""} class="text-[13px] leading-snug text-pretty">
        {@book.text}
      </p>
      <.book_tiers :if={!@compact} tiers={@book.tiers} players={@players} />
      <div
        :if={!@compact and @book.chips != []}
        class="mt-auto flex flex-wrap gap-x-2.5 gap-y-1 pt-0.5 text-xs"
      >
        <span
          :for={{chip, price} <- @book.chips}
          class="inline-flex items-center gap-1 font-bold tabular-nums"
        >
          <.chip chip={chip} size={:xs} />{price}
        </span>
      </div>
    </div>
    """
  end

  @doc """
  The ingredient books in play as compact tiles in board order (`Books.in_play/2`):
  the desktop left column (80rem). Round 39: a `<details>`, closed by default; its
  summary opens it. Each tile: the icon, the name, the book number, when it acts
  and its rule; tiered books show their tiers inline, only the rows for this table
  size. `beats` (`%{colour => beat}`) lights a book up on the replay beat of its
  line (app.css `.book-beat`).
  """
  attr :id, :string, required: true
  attr :game, Game, required: true
  attr :beats, :map, default: %{}
  attr :class, :any, default: nil
  attr :rest, :global

  def books_in_play(assigns) do
    assigns =
      assign(assigns,
        books: Books.in_play(assigns.game.expansion, assigns.game.sets),
        players: map_size(assigns.game.players)
      )

    ~H"""
    <.fold id={@id} class={@class} label="Ingredient books" {@rest}>
      <:title>
        <QuacksWeb.CoreComponents.icon name="hero-book-open" class="size-4 self-center" />
        Books in play
        <span class="font-sans text-xs font-normal text-parchment-dim">
          {@players} {if @players == 1, do: "player", else: "players"}
        </span>
      </:title>
      <ol class="space-y-1.5 pb-1" data-role="books-in-play">
        <li :for={{colour, set} <- @books}>
          <.book_line
            colour={colour}
            set={set}
            players={@players}
            beat={@beats[colour]}
            rules={@game.rules}
          />
        </li>
      </ol>
    </.fold>
    """
  end

  @doc """
  Round 39: a block of the desktop left column that folds (`<details>`), closed
  by default. A click on the title opens or closes it; the page keeps that state
  across patches (`JS.ignore_attributes/1` on `open`).
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :title, required: true
  slot :inner_block, required: true

  def fold(assigns) do
    ~H"""
    <details
      id={@id}
      class={["fold group min-h-0", @class]}
      aria-label={@label}
      phx-mounted={JS.ignore_attributes(["open"])}
      {@rest}
    >
      <summary
        class="flex min-h-11 cursor-pointer list-none items-center gap-2 rounded-lg px-1 font-hand text-lg font-bold text-parchment transition-colors duration-150 select-none hover:bg-iron-dark/60 [&::-webkit-details-marker]:hidden"
        data-role="fold-title"
      >
        {render_slot(@title)}
        <QuacksWeb.CoreComponents.icon
          name="hero-chevron-down"
          class="ml-auto size-4 shrink-0 text-parchment-dim transition-transform duration-200 group-open:rotate-180"
        />
      </summary>
      <div class="pt-1.5">{render_slot(@inner_block)}</div>
    </details>
    """
  end

  attr :colour, :atom, required: true
  attr :set, :any, required: true
  attr :players, :integer, required: true
  attr :beat, :integer, default: nil
  attr :rules, :map, default: %{}

  defp book_line(assigns) do
    assigns = assign(assigns, book: book_info(assigns.colour, assigns.set, assigns.rules))

    ~H"""
    <article
      class={[
        "paper relative overflow-hidden rounded-xl py-1.5 pr-2 pl-3 text-left",
        "before:absolute before:inset-y-0 before:left-0 before:w-1 before:bg-(--c)",
        @beat && "book-beat"
      ]}
      style={"--c: var(--color-chip-#{@colour})#{@beat && "; --beat: #{@beat}"}"}
      data-role="book-line"
      data-colour={@colour}
      data-book={"#{@colour}-#{@set || "off"}"}
    >
      <div class="flex min-w-0 items-center gap-1.5">
        <.ingredient_icon colour={@colour} class={["size-6 shrink-0", book_ink(@colour)]} />
        <p class="min-w-0 truncate font-hand text-base leading-tight font-bold">{@book.name}</p>
        <.book_seal set={@set} />
        <span
          :if={@book.trigger != :none}
          class="ml-auto shrink-0 text-[10px] font-bold tracking-wide text-ink-soft uppercase"
        >
          {trigger_tag(@book.trigger)}
        </span>
      </div>
      <p :if={@book.text != ""} class="mt-0.5 text-xs leading-snug text-pretty text-ink-soft">
        {@book.text}
      </p>
      <p
        :if={(tiers = Books.tiers_for(@book.tiers, @players)) != []}
        class="mt-0.5 flex flex-wrap gap-x-2 text-xs leading-snug text-ink-soft"
        data-role="book-tiers"
      >
        <span :for={{label, text} <- tiers}>
          <b class="font-semibold text-ink">{label}:</b> {text}
        </span>
      </p>
    </article>
    """
  end

  defp trigger_tag(:step_b), do: "Evaluation"
  defp trigger_tag(trigger), do: trigger_label(trigger)

  @doc """
  The text class for an ingredient icon on parchment: the chip colour, but ink for
  white and a darker yellow, which would not show on parchment.
  """
  @spec book_ink(Chips.colour()) :: String.t()
  def book_ink(colour), do: @book_ink[colour]

  @doc ~s[A book number as a gold seal: "I".."VI", or "Off" for nil.]
  attr :set, :any, required: true

  def book_seal(assigns) do
    ~H"""
    <span class="book-seal" title={if @set, do: "Book #{@set}", else: "Not in play"}>
      {roman(@set)}
    </span>
    """
  end

  @doc ~s[A book number in Roman numerals ("Off" for nil).]
  @spec roman(1..6 | nil) :: String.t()
  def roman(nil), do: "Off"
  def roman(set), do: Enum.at(~w(I II III IV V VI), set - 1)

  @doc """
  The book `{colour, set}` for display: `Books.get/2` (with the house `rules`) plus `chips`, each buyable
  chip of the colour with its price. Locoweed nil is "not in play"; locoweed III
  (The Alchemists' A) acts in the essence phase.
  """
  @spec book_info(Chips.colour(), 1..6 | nil, map) :: map
  def book_info(colour, set, rules \\ %{})

  def book_info(:locoweed, nil, _rules) do
    %{
      Books.get({:locoweed, 1})
      | text: "No locoweed chips in the shop this game.",
        prices: []
    }
    |> Map.put(:chips, [])
  end

  def book_info(:locoweed, 3, _rules) do
    %{
      Books.get({:locoweed, 1})
      | text:
          "Moves 1; in the essence phase your essence marker moves 1 more space for each locoweed in your pot.",
        prices: [Chips.price({:locoweed, 1}, %{locoweed: 3})]
    }
    |> Map.put(:chips, [{{:locoweed, 1}, Chips.price({:locoweed, 1}, %{locoweed: 3})}])
  end

  def book_info(colour, set, rules) do
    sets = %{colour => set}
    chips = for {^colour, _} = chip <- Chips.shop(:herb_witches, sets), do: chip

    Map.put(
      Books.get({colour, set}, rules),
      :chips,
      Enum.map(chips, &{&1, Chips.price(&1, sets)})
    )
  end

  defp book_set_name(:white, _set), do: ""
  defp book_set_name(:black, 1), do: "(base)"
  defp book_set_name(_colour, set), do: "Set #{set}"

  @doc """
  The game's house rules that differ from the rulebook game, e.g. "House rules:
  explodes above 9 · no rats". Renders nothing with the default rules.
  """
  attr :rules, :map, required: true, doc: "`game.rules`"

  def house_rules(assigns) do
    %{rules: rules} = assigns
    default = Game.default_rules()
    # A fixed order: map keys have no order to rely on.
    keys = [
      :explode_above,
      :starting_rubies,
      :round6_white,
      :fortune,
      :rats,
      :black_solo,
      :black_rule,
      :die,
      :supply,
      :pot_side
    ]

    changed = for key <- keys, rules[key] != default[key], do: {key, rules[key]}
    assigns = assign(assigns, changed: changed)

    ~H"""
    <p :if={@changed != []} class="text-xs text-ink-soft" data-role="house-rules">
      House rules: {Enum.map_join(@changed, " · ", &rule_label/1)}
    </p>
    """
  end

  defp rule_label({:explode_above, n}), do: "explodes above #{n}"
  defp rule_label({:starting_rubies, n}), do: "#{n} starting rubies"
  defp rule_label({:round6_white, false}), do: "no round-6 white"
  defp rule_label({:fortune, false}), do: "no Fortune Teller cards"
  defp rule_label({:rats, false}), do: "no rats"
  defp rule_label({:black_solo, :droplet_ruby}), do: "solo black pays a ruby"
  defp rule_label({:black_rule, :standings}), do: "black chips by standings"
  defp rule_label({:die, :no_orange}), do: "die: ruby instead of orange"
  defp rule_label({:supply, :limited}), do: "limited chip supply"
  defp rule_label({:pot_side, :back}), do: "reverse pot side (test tubes)"

  @doc """
  A herb witch card: a band in her penny colour, her title and her rule. A witch
  whose penny this player has spent is greyed out. The slot holds her buttons.

  ## Examples

      <.witch_card id={:s2} spent={false} />
  """
  attr :id, :atom, required: true, doc: "a witch id from `Quacks.Rules.Witches`"
  attr :spent, :boolean, default: false, doc: "this player has spent her penny"
  slot :inner_block

  def witch_card(assigns) do
    assigns = assign(assigns, card: Witches.card(assigns.id))

    ~H"""
    <section
      class={["paper overflow-hidden rounded-lg text-sm", @spent && "opacity-50 grayscale"]}
      aria-label={"#{@card.colour} witch"}
      data-role="witch-card"
      data-witch={@id}
    >
      <div class={[
        "flex items-center gap-1 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-ink",
        penny_class(@card.colour)
      ]}>
        <.piece_icon name={:witch} class="size-4" /> {@card.colour} witch
        <span class="ml-auto inline-flex items-center gap-1 normal-case">
          <.piece_icon name={:penny} class="size-4" />
          {if @spent, do: "penny spent", else: "1 penny"}
        </span>
      </div>
      <div class="space-y-2 px-3 py-2">
        <h3 class="font-bold">{@card.title}</h3>
        <p class="text-ink-soft">{@card.text}</p>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  defp penny_class(colour), do: @pennies[colour]

  @doc """
  The strip of a chip offer: a title, the chips (the slot; `GameLive` renders them
  as the controls) and a hint. The crow skull, the silver witch S2, the toadstools
  (Set 2) and the fortune cards B7 and P13 use it.
  """
  attr :title, :string, default: "Crow skull drew:"
  attr :hint, :string, default: "Tap a chip to place it, or return them all."
  attr :label, :string, default: "Crow skull offer"
  attr :accent, :string, default: "border-droplet", doc: "left border colour class"
  slot :inner_block, required: true, doc: "the offered chips"

  def blue_offer(assigns) do
    ~H"""
    <div
      class={["paper space-y-1.5 rounded-md border-l-4 p-2 text-sm", @accent]}
      aria-label={@label}
    >
      <p class="font-semibold">{@title}</p>
      {render_slot(@inner_block)}
      <p class="text-ink-soft">{@hint}</p>
    </div>
    """
  end

  @doc """
  The chips a fortune card drew from the bag: B7 Safety Procedure (place one) or
  P13 Flea Market (trade one up). Same strip as the crow skull offer.
  """
  attr :card, :atom, required: true, doc: "`game.fortune_card`"
  slot :inner_block, required: true, doc: "the offered chips"

  def fortune_offer(%{card: :p13} = assigns) do
    ~H"""
    <.blue_offer
      title="Flea Market drew:"
      hint="Tap a chip to trade it for the next value up, or skip."
      label="Fortune teller offer"
      accent="border-chip-purple"
    >
      {render_slot(@inner_block)}
    </.blue_offer>
    """
  end

  def fortune_offer(assigns) do
    ~H"""
    <.blue_offer
      title="Safety Procedure drew:"
      hint="Tap a chip to place it, or return them all. The placed chip cannot explode the pot."
      label="Fortune teller offer"
      accent="border-chip-purple"
    >
      {render_slot(@inner_block)}
    </.blue_offer>
    """
  end

  @doc """
  The Fortune Teller card of this round: a colour band (blue = a rule for the whole
  round, purple = resolved once at the start), a motif (`@card_motifs`), its name in
  Kalam and its full text.

  ## Examples

      <.fortune_card id={:b7} />
  """
  attr :id, :atom, required: true, doc: "a card id from `Quacks.Rules.Fortune`"
  attr :choice, :boolean, default: false, doc: "the card asks this player a choice now"

  attr :flip, :boolean,
    default: false,
    doc:
      "turn the card over (back, then front) when it enters the page: the new card of the round"

  attr :flip_id, :string, default: nil, doc: "the flip's DOM id (default `card-flip-<card>`)"

  def fortune_card(%{flip: true} = assigns) do
    ~H"""
    <div
      id={@flip_id || "card-flip-#{@id}"}
      class="card-flip mx-auto w-full max-w-60"
      data-role="card-flip"
    >
      <div class="card-flip-inner">
        <div class="card-back" aria-hidden="true" data-role="card-back">
          <span class="flex flex-col items-center gap-1 rounded-full bg-[#3b1d78] px-4 py-2 font-hand font-bold text-gold">
            <QuacksWeb.CoreComponents.icon name="hero-sparkles" class="size-8" /> Fortune teller
          </span>
        </div>
        <div class="card-front">
          <.fortune_card id={@id} choice={@choice} />
        </div>
      </div>
    </div>
    """
  end

  def fortune_card(assigns) do
    assigns = assign(assigns, card: Fortune.card(assigns.id), motif: @card_motifs[assigns.id])

    ~H"""
    <section
      class="paper fortune-face card-portrait relative mx-auto flex aspect-[5/7] w-full max-w-60 flex-col overflow-hidden rounded-lg text-sm shadow-md ring-1 shadow-black/25 ring-ink/20"
      aria-label="Fortune teller card"
      data-role="fortune-card"
      data-colour={@card.colour}
    >
      <div class={[
        "flex items-center gap-1 px-2 py-1 text-[10px] font-semibold tracking-wide whitespace-nowrap text-white uppercase",
        @card.colour == :blue && "bg-chip-blue",
        @card.colour == :purple && "bg-chip-purple"
      ]}>
        <QuacksWeb.CoreComponents.icon
          name="hero-sparkles-mini"
          class="size-3.5 shrink-0 opacity-80"
        />
        <span class="truncate">{band_text(@card.colour, @choice)}</span>
      </div>
      <div class="flex min-h-0 flex-1 flex-col items-center justify-center gap-2 p-3 text-center">
        <div
          class={[
            "grid size-16 shrink-0 place-items-center rounded-full ring-2",
            @card.colour == :blue && "bg-chip-blue/12 text-chip-blue ring-chip-blue/35",
            @card.colour == :purple && "bg-chip-purple/12 text-chip-purple ring-chip-purple/35"
          ]}
          aria-hidden="true"
          data-role="card-motif"
          data-motif={motif_name(@motif)}
        >
          <.card_motif motif={@motif} />
        </div>
        <h2 class="font-hand text-xl leading-tight font-bold text-balance">{@card.name}</h2>
        <p class="min-h-0 overflow-y-auto leading-snug text-pretty text-ink-soft">{@card.text}</p>
      </div>
    </section>
    """
  end

  @doc """
  This round's Fortune Teller card as a block for the top of the right column
  (screens ≥ 80rem; under the pot from 64rem): the colour band, the motif, the name and the text in one
  row. Its `id` names the round, so a new card enters the page and plays its
  reveal (a fade and a gold sparkle sweep, app.css `.fortune-panel`).
  """
  attr :id, :string, required: true
  attr :card, :atom, required: true, doc: "`game.fortune_card`"
  attr :class, :any, default: nil

  def fortune_panel(assigns) do
    assigns = assign(assigns, info: Fortune.card(assigns.card), motif: @card_motifs[assigns.card])

    ~H"""
    <section
      id={@id}
      class={[
        "fortune-panel paper relative flex-col overflow-hidden rounded-xl shadow-md ring-1 shadow-black/25 ring-ink/20",
        @class
      ]}
      aria-label="Fortune teller card"
      data-role="fortune-panel"
      data-card={@card}
      data-colour={@info.colour}
    >
      <div class={[
        "flex items-center gap-1 px-3 py-1 text-[10px] font-semibold tracking-wide text-white uppercase",
        @info.colour == :blue && "bg-chip-blue",
        @info.colour == :purple && "bg-chip-purple"
      ]}>
        <QuacksWeb.CoreComponents.icon name="hero-sparkles-mini" class="size-3.5 opacity-80" />
        {band_text(@info.colour, false)}
      </div>
      <div class="flex items-start gap-3 p-3">
        <div
          class={[
            "grid size-12 shrink-0 place-items-center rounded-full ring-2",
            @info.colour == :blue && "bg-chip-blue/12 text-chip-blue ring-chip-blue/35",
            @info.colour == :purple && "bg-chip-purple/12 text-chip-purple ring-chip-purple/35"
          ]}
          aria-hidden="true"
        >
          <.card_motif motif={@motif} class="size-7" />
        </div>
        <div class="min-w-0">
          <h2 class="font-hand text-xl leading-tight font-bold">{@info.name}</h2>
          <p class="text-sm leading-snug text-pretty text-ink-soft">{@info.text}</p>
        </div>
      </div>
      <span class="fortune-sparkle" aria-hidden="true" />
    </section>
    """
  end

  attr :motif, :any, required: true
  attr :class, :any, default: "size-10"

  defp card_motif(%{motif: {:ingredient, colour}} = assigns) do
    assigns = assign(assigns, colour: colour)

    ~H"""
    <.ingredient_icon colour={@colour} class={@class} />
    """
  end

  defp card_motif(%{motif: nil} = assigns) do
    ~H"""
    <QuacksWeb.CoreComponents.icon name="hero-sparkles" class={@class} />
    """
  end

  defp card_motif(assigns) do
    ~H"""
    <.piece_icon name={@motif} class={@class} />
    """
  end

  defp motif_name({:ingredient, colour}), do: colour
  defp motif_name(nil), do: "sparkle"
  defp motif_name(piece), do: piece

  # The card's colour band: a blue card is a rule for the round; a purple one acts
  # once, and says so only when it waits for this player.
  defp band_text(:blue, _choice), do: "Fortune teller · this round"
  defp band_text(_colour, true), do: "Fortune teller · resolve now"
  defp band_text(_colour, false), do: "Fortune teller"

  @doc """
  The last few game events, newest first. Every log entry runs through `label/1`.
  With `names` (multiplayer), each player entry starts with that seat's name; without
  (solo), the seat is left out.
  Actions that an event already narrates (`:draw` → "Drew ...", a buy → "Bought ...",
  spending rubies → "Spent ...") are left out so the log does not say things twice.
  """
  attr :log, :list, required: true, doc: "`game.log`, newest first"
  attr :limit, :integer, default: 20
  attr :names, :map, default: nil, doc: "`%{seat => name}`; nil hides the seat"

  def action_log(assigns) do
    assigns = assign(assigns, entries: log_lines(assigns.log, assigns.limit, assigns.names))

    ~H"""
    <div class="paper rounded-lg p-3">
      <h2 class="sheet-head text-lg font-bold">Log</h2>
      <ol class="mt-1 space-y-1 text-sm" aria-label="Recent actions">
        <li :for={{seat, line} <- @entries} class="flex items-baseline gap-1.5">
          <.seat_dot :if={seat} seat={seat} />
          <span>{line}</span>
        </li>
        <li :if={@entries == []} class="text-ink-soft">Nothing yet. Draw a chip.</li>
      </ol>
    </div>
    """
  end

  @doc """
  A visually hidden `aria-live="polite"` line with the newest log line, in the words
  of `action_log/1`: a screen reader hears each draw, explosion, stop and bot
  action. It holds one line, so each patch announces at most one message.
  """
  attr :log, :list, required: true, doc: "`game.log`, newest first"
  attr :names, :map, default: nil, doc: "`%{seat => name}`; nil leaves the seat out"

  def announcer(assigns) do
    # The newest few entries are enough: most actions log one narrated line.
    line =
      case log_lines(Enum.take(assigns.log, 10), 1, assigns.names) do
        [{_seat, line}] -> line
        [] -> nil
      end

    assigns = assign(assigns, line: line)

    ~H"""
    <p id="announcer" class="sr-only" aria-live="polite" data-role="announcer">{@line}</p>
    """
  end
end
