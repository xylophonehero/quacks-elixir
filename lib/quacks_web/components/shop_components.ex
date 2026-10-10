defmodule QuacksWeb.ShopComponents do
  @moduledoc """
  The shop: the buy step and the rubies step (shop/1), one row of chip tiles per
  colour (shop_rows/2), Ghost's breath's buy in the bar (purple_buy/1) and the
  books a chip can offer (offer_books/1).
  """
  use Phoenix.Component

  import QuacksWeb.CoreComponents
  import QuacksWeb.ActionCode
  import QuacksWeb.ChipComponents
  import QuacksWeb.GameText
  import QuacksWeb.PanelComponents
  import QuacksWeb.PotComponents

  alias Phoenix.LiveView.JS
  alias Quacks.{Game, Player}
  alias Quacks.Rules.{Books, Chips}
  alias QuacksWeb.BarComponents

  # The colours with an ingredient book (white has none), for `offer_books/1`.
  @book_colours Chips.order() -- [:white]

  @doc """
  Round 36: Ghost's breath V (purple Set 5, The Herb Witches): the VP of the
  purple spaces buy chips, as in the shop. Round 39 (Nick): a panel in the context
  area, not a sheet: from 64rem in the context column over the bar, below it over
  the pot's lower band, from the bar up (app.css `.pick-panel`). It shows every chip
  of the shop as a tile to tick (the shop's `select` and `@selected`): up to two of
  different colours. A tile that no buy allows with the ticked ones (too dear, or
  not with the other tick) is greyed and says why. The purse and Take are in the
  bar (`bar_choice/1`, `:chip_choice`), so nothing scrolls under them. On a phone
  the panel folds to its title (`.pick-folded`) to show the pot.
  """
  attr :buys, :list, required: true, doc: "the `{:chip, {:buy, chips}}` actions"
  attr :selected, :list, required: true
  attr :game, Game, required: true
  attr :me, Player, required: true

  def purple_buy(assigns) do
    %{buys: buys, game: game, me: me, selected: selected} = assigns
    {coins, remaining} = purple_purse(me, selected, game.sets)
    actions = Enum.map(buys, fn {:chip, buy} -> buy end)

    tiles =
      for chip <- List.flatten(shop_rows(game.expansion, game.sets)) do
        price = Chips.price(chip, game.sets)
        %{chip: chip, price: price, off: purple_off(chip, price, remaining, selected, actions)}
      end

    assigns = assign(assigns, tiles: tiles, coins: coins, id: "purple-buy-panel-#{game.round}")

    ~H"""
    <section
      id={@id}
      class="pick-panel paper"
      aria-label="Ghost's breath: take chips"
      data-role="purple-buy"
    >
      <div class="flex items-start gap-2">
        <div class="min-w-0 flex-1">
          <h2 class="font-hand text-xl leading-tight font-bold">Ghost's breath</h2>
          <p class="text-sm" data-role="purple-buy-hint">
            Your purple spaces pay {@coins} coins: up to two chips of different colours.
          </p>
        </div>
        <button
          type="button"
          class="-m-1 grid size-9 shrink-0 cursor-pointer place-items-center rounded-full text-ink-soft transition-[color,rotate] duration-150 ease-out hit-44 hover:text-ink lg:hidden [.pick-folded_&]:rotate-180"
          phx-click={
            JS.toggle_class("pick-folded", to: "##{@id}")
            |> JS.toggle_attribute({"aria-expanded", "false", "true"})
          }
          aria-expanded="true"
          aria-controls={"purple-buy-#{@game.round}"}
          aria-label="Show or hide the chips"
          data-role="purple-buy-fold"
        >
          <.icon name="hero-chevron-down" class="size-5" />
        </button>
      </div>
      <form
        id={"purple-buy-#{@game.round}"}
        phx-change="select"
        class="pick-tiles mt-2 grid grid-cols-5 gap-1.5"
      >
        <label
          :for={t <- @tiles}
          class={[
            "relative flex min-w-0 flex-col items-center gap-0.5 rounded-lg bg-parchment-light px-1 pt-1.5 pb-1 text-sm",
            "ring-1 ring-ink/20 select-none touch-manipulation",
            "transition-[scale,box-shadow,background-color,opacity] duration-150 ease-out",
            "has-checked:bg-gold/30 has-checked:ring-[3px] has-checked:ring-ink",
            "has-focus-visible:outline-3 has-focus-visible:outline-droplet",
            if(t.off, do: "opacity-40 grayscale", else: "cursor-pointer active:scale-[0.96]")
          ]}
          title={t.off || "#{chip_name(t.chip)}: #{t.price} coins"}
          data-role={if t.off, do: "purple-buy-off", else: "purple-buy-tile"}
          data-chip={chip_name(t.chip)}
        >
          <input
            type="checkbox"
            name="chips[]"
            value={encode(t.chip)}
            checked={t.chip in @selected}
            disabled={t.off != nil}
            class="peer sr-only"
            aria-label={t.off || "#{chip_name(t.chip)}, #{t.price} coins"}
          />
          <span
            class="absolute -top-2 -right-2 hidden size-5 items-center justify-center rounded-full bg-ink text-gold shadow peer-checked:flex"
            data-role="tile-check"
          >
            <.icon name="hero-check" class="size-3.5" />
          </span>
          <.chip chip={t.chip} size={:md} />
          <span
            class="inline-flex items-center gap-0.5 font-semibold tabular-nums text-ink-soft"
            data-role="price"
          >
            {t.price}<span class="book-coin" /><span class="sr-only">coins</span>
          </span>
        </label>
      </form>
    </section>
    """
  end

  @doc "Round 39: Ghost's breath V's coins and what is left after the ticked chips."
  def purple_purse(me, selected, sets) do
    coins = Enum.find_value(me.chip_choices, 0, &(match?({:purple_buy, _}, &1) && elem(&1, 1)))
    {coins, coins - (selected |> Enum.map(&Chips.price(&1, sets)) |> Enum.sum())}
  end

  # Round 39: why a Ghost's breath V tile is greyed, or nil while it can be ticked.
  defp purple_off(chip, price, remaining, selected, actions) do
    cond do
      not blocked?(chip, selected, actions) -> nil
      price > remaining -> "#{chip_name(chip)}: #{price} coins, you have #{remaining} left"
      {:buy, [chip]} not in actions -> "#{chip_name(chip)}: not in the shop this round"
      true -> "#{chip_name(chip)}: not with your other chip"
    end
  end

  @doc """
  The shop dialogs: everything this seat may do between brewing and the next round,
  in two steps (`step`).

  `:shop`, while a buy is legal: on top, every chip the player owns (bag, pot and bowl), as counts. Then, while a
  buy is legal, a form of checkboxes, one per kind of chip, in a row per colour
  (see `shop_rows/0`), priced with the game's Ingredient books (`Chips.price/2`).
  The engine decides what may be ticked: a box is disabled when adding its chip
  to the selection is not a legal buy. "Buy selected" sends `{:buy, selected}`.

  The copper witches are here too. Round 35: there is no Skip; a player always buys
  a chip (a UI rule: the engine still takes `{:buy, []}`, and the bots are as
  before). Buy is the one button, disabled until a chip is ticked. Only when no
  chip is affordable does "Nothing to buy" (`{:buy, []}`) take its place.

  `:rubies`, after the buy (or when there is nothing to buy): the ruby options
  (`{:rubies, _}`), other witch calls, and "Keep rubies" (`:end_round`). Both steps
  are the engine's one `:shop` sub-phase.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0
  attr :selected, :list, required: true, doc: "ticked chips, sorted"
  attr :step, :atom, default: :shop, values: [:shop, :rubies]

  def shop(assigns) do
    sets = assigns.game.sets
    me = assigns.game.players[assigns.seat]
    total = assigns.selected |> Enum.map(&Chips.price(&1, sets)) |> Enum.sum()
    actions = Game.legal_actions(assigns.game, assigns.seat)
    copper = copper_actions(actions, assigns.selected)

    assigns =
      assign(assigns,
        me: me,
        actions: actions,
        buying?: Enum.any?(actions, &match?({:buy, _}, &1)),
        affordable?: Enum.any?(actions, &match?({:buy, [_ | _]}, &1)),
        copper: copper,
        others: Enum.reject(actions, &(match?({:buy, _}, &1) or &1 in [:end_round | copper])),
        owned: Player.pot_chips(me) ++ me.bowl ++ me.bag,
        sets: sets,
        rows: shop_rows(assigns.game.expansion, sets),
        total: total,
        remaining: me.coins - total
      )

    assigns = assign(assigns, locked: locked_colours(assigns.game, assigns.rows))

    ~H"""
    <section :if={@step == :shop} class="space-y-2" aria-label="Shop">
      <h2 class="sheet-head text-xl font-bold">Shop</h2>
      <div class="rounded-md bg-parchment-deep/60 px-2 py-1" data-role="shop-bag">
        <h3 class="text-tag font-semibold text-ink-soft">Your chips: {length(@owned)}</h3>
        <.chip_counts chips={@owned} />
      </div>
      <div :if={@buying?} class="space-y-2">
        <p class="text-sm">Tap up to two chips of different colours.</p>
        <form id="shop" phx-change="select" class="space-y-2">
          <div :for={{row, i} <- Enum.with_index(@rows)} class="space-y-0.5">
            <div class="flex items-center gap-1.5 pl-0.5" data-role="shop-row-label">
              <span class="font-hand text-[15px] leading-tight font-bold">
                {Books.get({elem(hd(row), 0), 1}).name}
              </span>
              <span class="text-tag text-ink-soft">
                {elem(hd(row), 0)} · book {roman(Chips.set(@game.expansion, @sets, elem(hd(row), 0)))}
              </span>
              <%!-- The book's text opens in place, under the row (not another sheet).
                   Round 35: the sheet scrolls so all of it shows (`quacks:reveal`). --%>
              <button
                type="button"
                class="-my-2 ml-auto inline-flex size-9 shrink-0 cursor-pointer items-center justify-center rounded-full text-ink-soft transition-[color,scale] duration-150 ease-out hit-44 hover:text-ink active:scale-90 aria-expanded:text-ink"
                aria-expanded="false"
                aria-controls={"shop-book-#{i}"}
                phx-click={
                  JS.toggle(
                    to: "#shop-book-#{i}",
                    in:
                      {"transition-[opacity,translate] duration-150 ease-out",
                       "opacity-0 -translate-y-1", "opacity-100 translate-y-0"},
                    out: {"transition-opacity duration-100 ease-out", "opacity-100", "opacity-0"}
                  )
                  |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                  |> JS.dispatch("quacks:reveal", to: "#shop-book-#{i}")
                }
                data-role="book-info"
              >
                <.icon name="hero-information-circle" class="size-5" />
                <span class="sr-only">Book</span>
              </button>
            </div>
            <ul class="grid grid-cols-3 gap-1.5" data-role="shop-row">
              <li :for={chip <- row} class="min-w-0">
                <%!-- A tile, not a checkbox: the box is hidden, the tile shows its state. --%>
                <label class={[
                  "relative flex min-h-12 min-w-0 items-center gap-1.5 rounded-lg bg-parchment-light px-2 text-sm",
                  "ring-1 ring-ink/20 select-none touch-manipulation",
                  "transition-[scale,box-shadow,background-color] duration-150 ease-out",
                  "has-checked:bg-gold/30 has-checked:ring-[3px] has-checked:ring-ink",
                  "has-focus-visible:outline-3 has-focus-visible:outline-droplet",
                  cond do
                    elem(chip, 0) in @locked -> "shop-locked"
                    blocked?(chip, @selected, @actions) -> "opacity-40"
                    true -> "cursor-pointer active:scale-[0.96]"
                  end
                ]}>
                  <input
                    type="checkbox"
                    name="chips[]"
                    value={encode(chip)}
                    checked={chip in @selected}
                    disabled={blocked?(chip, @selected, @actions)}
                    class="peer sr-only"
                  />
                  <span
                    class="absolute -top-2 -right-2 hidden size-5 items-center justify-center rounded-full bg-ink text-gold shadow peer-checked:flex"
                    data-role="tile-check"
                  >
                    <.icon name="hero-check" class="size-3.5" />
                  </span>
                  <span
                    :if={elem(chip, 0) in @locked}
                    class="absolute -top-1.5 -left-1.5 grid size-5 place-items-center rounded-full bg-iron-dark text-parchment shadow"
                    data-role="tile-lock"
                  >
                    <.icon name="hero-lock-closed-mini" class="size-3" />
                    <span class="sr-only">Not in the shop yet</span>
                  </span>
                  <.chip chip={chip} size={:md} />
                  <%!-- In a side panel (64rem up) the tile is the phone one: chip, value, price. --%>
                  <span
                    class="sr-only sm:not-sr-only lg:sr-only phone-landscape:sr-only"
                    data-role="tile-name"
                  >
                    {chip_name(chip)}
                  </span>
                  <span
                    class="ml-auto inline-flex shrink-0 items-center gap-1 font-semibold tabular-nums text-ink-soft"
                    data-role="price"
                  >
                    {Chips.price(chip, @sets)}<span class="book-coin" /><span class="sr-only">coins</span>
                  </span>
                </label>
              </li>
            </ul>
            <div
              id={"shop-book-#{i}"}
              class="hidden rounded-lg bg-parchment-deep/60 px-2 py-1.5"
              data-role="shop-book"
            >
              <.book_list
                books={row_books(row, @game)}
                players={map_size(@game.players)}
                rules={@game.rules}
              />
            </div>
          </div>
        </form>
      </div>
      <.witch_card :if={@copper != []} id={@game.witches.copper}>
        <div class="flex flex-col gap-2 *:min-h-11">
          <.button
            :for={action <- @copper}
            phx-click="action"
            phx-value-action={encode(action)}
            variant={:secondary}
            class="justify-start gap-2"
          >
            <%!-- Round 36: C1's pot chips as chips, then what it does. --%>
            <span
              :if={match?({:witch, :copper, {:upgrade, _}}, action)}
              class="inline-flex shrink-0 items-center gap-1.5"
              data-role="copper-chips"
            >
              <.chip :for={chip <- elem(elem(action, 2), 1)} chip={chip} size={:sm} />
              <.icon name="hero-arrow-up-mini" class="size-4" />
            </span>
            {label(action)}
          </.button>
        </div>
      </.witch_card>
      <%!-- The purse and the buttons stay at the bottom of the sheet while it scrolls.
           A size container: the Enter hints show only where the bar has the room
           (round 12: at 64rem the sheet is a narrow column and the bar overflowed). --%>
      <div
        class="@container/shop-bar sticky bottom-0 z-10 -mx-4 mt-3 flex min-w-0 items-center gap-2 bg-parchment px-4 pt-2 pb-[max(0.75rem,env(safe-area-inset-bottom))] shadow-[0_-8px_12px_-10px_rgb(0_0_0/0.35)] *:min-h-12"
        data-role="shop-footer"
      >
        <p
          :if={@buying?}
          class={[
            "flex min-w-0 shrink items-center gap-1 font-hand text-xl leading-none font-bold whitespace-nowrap tabular-nums",
            @remaining < 0 && "text-ruby"
          ]}
          data-role="shop-total"
          aria-label={"#{@me.coins} coins, #{@remaining} left after this buy"}
        >
          <span class="book-coin" />{@me.coins}<span class="text-base text-ink-soft">→</span>{@remaining}
        </p>
        <.button
          :if={!@affordable?}
          phx-click="action"
          phx-value-action={encode({:buy, []})}
          variant={:primary}
          autofocus
          class="min-w-0 flex-1"
          data-role="shop-done"
        >
          Nothing to buy
          <.kbd>Enter</.kbd>
        </.button>
        <.button
          :if={@affordable?}
          phx-click="action"
          phx-value-action={encode({:buy, @selected})}
          variant={:primary}
          class="min-w-0 flex-1 px-3 whitespace-nowrap"
          disabled={@selected == [] or {:buy, @selected} not in @actions}
          data-role="shop-buy"
        >
          <span class="truncate">{buy_label(@selected, @total)}</span>
          <.kbd :if={@selected != []} show={shop_kbd()}>Enter</.kbd>
        </.button>
      </div>
    </section>
    <section :if={@step == :rubies} class="space-y-2" aria-label="Spend rubies">
      <h2 class="sheet-head text-xl font-bold">Spend rubies</h2>
      <div class="space-y-2" data-role="shop-rubies">
        <.witch_card :for={id <- BarComponents.witches_acting(@game, @others)} id={id} />
        <p class="flex items-center gap-1.5 text-sm">
          <.icon name="hero-sparkles" class="size-4 text-ruby" />
          You have {@me.rubies} {if @me.rubies == 1, do: "ruby", else: "rubies"}.
        </p>
        <div class="flex flex-col gap-2 *:min-h-11">
          <.button
            :for={action <- @others}
            phx-click="action"
            phx-value-action={encode(action)}
            variant={:secondary}
          >
            {BarComponents.action_label(action, @game, @me)}
          </.button>
        </div>
      </div>
      <div class="flex *:min-h-12 *:flex-1">
        <.button
          phx-click="action"
          phx-value-action={encode(:end_round)}
          variant={if ruby_options?(@others), do: :ghost, else: :primary}
          autofocus={!ruby_options?(@others)}
          data-role="rubies-done"
        >
          {if ruby_options?(@others), do: "Keep rubies", else: "Done"}
        </.button>
      </div>
    </section>
    """
  end

  # The Buy button's Enter hint: from 64rem, and only when the shop bar is 24rem
  # wide (Done alone always has the room).
  defp shop_kbd, do: "hidden lg:@min-[24rem]/shop-bar:inline-block"

  defp buy_label([], _total), do: "Buy"
  defp buy_label(selected, total), do: "Buy #{length(selected)} · #{total} coins"

  # The colours of `rows` the shop does not sell yet this round (yellow before round
  # 2, purple before 3), though the box has them.
  defp locked_colours(game, rows) do
    for [{colour, _} | _] = row <- rows,
        Enum.any?(row, &Game.in_supply?(game, &1)),
        not Enum.any?(row, &Game.available?(game, &1)),
        do: colour
  end

  @doc false
  def ruby_options?(actions), do: Enum.any?(actions, &match?({:rubies, _}, &1))

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
  The shop's chips as rows, one per colour in the board's order (`Chips.order/0`:
  orange, blue, red, yellow, green, black, purple, locoweed), each from the lowest
  value up; together they are `Chips.shop/2` for `expansion` and `sets`.
  The orange 6 and the locoweed row show only when they are in play.
  """
  @spec shop_rows(Chips.expansion(), Chips.sets()) :: [[Chips.chip()]]
  def shop_rows(expansion \\ nil, sets \\ %{}) do
    shop = Chips.shop(expansion, sets)

    for colour <- Chips.order(),
        row = shop |> Enum.filter(&(elem(&1, 0) == colour)) |> Enum.sort(),
        row != [],
        do: row
  end

  # The books of the colours in a shop row (one colour per row).
  defp row_books([{colour, _value} | _], game),
    do: [{colour, Chips.set(game.expansion, game.sets, colour)}]

  @doc """
  An ⓘ button for a dialog that offers chips: it opens a sheet with the ingredient
  books of the colours in `offer` (any nesting of lists and tuples, e.g. the
  player's `pending` chips and the legal actions). Renders nothing without a
  coloured chip.
  """
  attr :id, :string, required: true
  attr :game, Game, required: true
  attr :offer, :any, required: true

  def offer_books(assigns) do
    colours = assigns.offer |> chip_colours() |> Enum.uniq()

    assigns =
      assign(assigns,
        books:
          for(
            colour <- @book_colours,
            colour in colours,
            do: {colour, Chips.set(assigns.game.expansion, assigns.game.sets, colour)}
          )
      )

    ~H"""
    <span :if={@books != []} class="contents">
      <button
        type="button"
        popovertarget={@id}
        class="-my-2 inline-flex size-11 shrink-0 items-center justify-center text-ink-soft"
        aria-label="Ingredient books"
        data-role="offer-books"
      >
        <.icon name="hero-information-circle" class="size-6" />
      </button>
      <.sheet id={@id} label="Ingredient books">
        <h2 class="sheet-head mb-2 text-lg font-bold">Ingredient books</h2>
        <.book_list books={@books} players={map_size(@game.players)} rules={@game.rules} />
      </.sheet>
    </span>
    """
  end

  defp chip_colours({colour, value}) when colour in @book_colours and is_integer(value),
    do: [colour]

  defp chip_colours(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> chip_colours()
  defp chip_colours(list) when is_list(list), do: Enum.flat_map(list, &chip_colours/1)
  defp chip_colours(_term), do: []

  # A ticked chip can always be unticked; an unticked one is blocked unless adding it
  # to the selection is a legal buy.
  defp blocked?(chip, selected, actions),
    do: chip not in selected and {:buy, Enum.sort([chip | selected])} not in actions
end
