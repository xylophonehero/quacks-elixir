defmodule QuacksWeb.BarComponents do
  @moduledoc """
  The bottom bar and what takes its place: the round and phase (round_phase/1),
  the white fuse above Stop and Draw (fuse_meter/1), the reward and risk line
  (reward_line/1), each decision in the bar (bar_choice/1) with its chip picks
  (chip_picks/1), the crow skull panel and the shop (shop/1, purple_buy/1).
  Rendering only, as every component module of the game page (module map:
  `docs/guide/06-components.md`).
  """
  use Phoenix.Component

  import QuacksWeb.CoreComponents
  import QuacksWeb.ActionCode
  import QuacksWeb.AlchemistsComponents
  import QuacksWeb.ChipComponents
  import QuacksWeb.GameText
  import QuacksWeb.Icons
  import QuacksWeb.PanelComponents
  import QuacksWeb.PotComponents
  import QuacksWeb.TileComponents

  alias Phoenix.LiveView.JS
  alias Quacks.AI.Odds
  alias Quacks.{Game, Player}
  alias Quacks.Game.{Fortune, Potions}
  alias Quacks.Rules.{Alchemists, Books, Chips, PotTrack, TestTubes}

  @doc """
  The action bar: Stop (or Resume), the flask (from 64rem; on the pot it is on
  every screen) and Draw, each with its key. A button is disabled while its
  action is not in `actions`.
  """
  attr :actions, :list, required: true
  attr :stop_slot, :atom, required: true, doc: "`:stop` or `:resume`"
  attr :flask, :boolean, default: true, doc: "false for a page with no seat's flask"
  attr :class, :any, default: nil

  def action_bar(assigns) do
    ~H"""
    <section
      class={["action-bar *:min-h-12 *:touch-manipulation", @class]}
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
        <.kbd>s</.kbd>
      </.button>
      <.button
        :if={@flask}
        phx-click="action"
        phx-value-action={encode(:use_flask)}
        disabled={:use_flask not in @actions}
        class="flex-col gap-0! px-1! max-lg:hidden!"
        aria-label="Use the flask"
        title="Put the white chip back in the bag"
        data-slot="flask"
      >
        <.piece_icon name={:flask} class="size-5" />
        <.kbd>f</.kbd>
      </.button>
      <.button
        phx-click="action"
        phx-value-action={encode(:draw)}
        disabled={:draw not in @actions}
        variant={:primary}
        data-slot="draw"
      >
        Draw
        <.kbd>d</.kbd>
      </.button>
    </section>
    """
  end

  @doc "The round and this seat's phase, for the page header."
  attr :game, Game, required: true
  attr :seat, :integer, default: 0

  def round_phase(assigns) do
    ~H"""
    <dl class="flex items-center gap-2 text-sm">
      <div class="flex items-baseline gap-1">
        <dt class="text-parchment-dim max-sm:sr-only">Round</dt>
        <dd
          class="round-counter font-semibold whitespace-nowrap tabular-nums"
          data-role="round-counter"
        >
          {@game.round} / 9
        </dd>
      </div>
      <div>
        <dt class="sr-only">Phase</dt>
        <dd class="block max-w-[7.5rem] truncate rounded-full bg-parchment/15 px-2 py-0.5 font-semibold max-sm:text-tag sm:max-w-none">
          {round_phase_name(@game, Game.phase(@game, @seat))}
        </dd>
      </div>
    </dl>
    """
  end

  @doc """
  The white total as a fuse: one notch per white point the pot may hold
  (`Potions.explode_above/2`), lit by the white sum. It turns amber one point
  before the limit and red at the limit (one more white explodes) or after an
  explosion. The label inside says "White 5 / 7".
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0

  def fuse_meter(assigns) do
    white = Game.white_sum(assigns.game, assigns.seat)
    limit = Potions.explode_above(assigns.game, assigns.seat)
    exploded? = assigns.game.players[assigns.seat].exploded?

    level =
      cond do
        exploded? or white >= limit -> "danger"
        white == limit - 1 -> "warn"
        true -> "safe"
      end

    assigns = assign(assigns, white: white, limit: limit, level: level, exploded?: exploded?)

    ~H"""
    <div
      id="fuse-meter"
      class="fuse relative h-7 min-w-0 flex-1"
      role="meter"
      aria-label="White total"
      aria-valuemin="0"
      aria-valuemax={@limit}
      aria-valuenow={@white}
      aria-valuetext={"White #{@white} of #{@limit}"}
      data-white={@white}
      data-limit={@limit}
      data-level={@level}
      data-exploded={to_string(@exploded?)}
    >
      <div class="flex h-full gap-0.5 overflow-hidden rounded-md">
        <span
          :for={i <- 1..@limit}
          class="fuse-notch flex-1"
          style={"--i: #{i}"}
          data-lit={to_string(i <= @white)}
        />
      </div>
      <span class="fuse-label">
        White <span class="tabular-nums">{@white} / {@limit}</span>
      </span>
    </div>
    """
  end

  @doc ~s"""
  Beside the white meter (round 29: one row with it): what the scoring space pays,
  as icons (coin and count, VP laurel and count, the ruby when the space has one),
  then the risk that the next draw explodes (`risk`, the menu's Risk setting):
  `:percent` "29%" (`Quacks.AI.Odds.next_draw/2`, whole percent), `:chips` "3/14"
  (white chips in the bag that would explode the pot / chips in the bag,
  `Quacks.AI.Odds.next_draw_count/2`), `:off` nothing. No risk for a seat that
  stopped or exploded (0%, 0/N). Fixed height, so a draw never moves the layout.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0
  attr :risk, :atom, default: :percent, values: [:off, :percent, :chips]

  def reward_line(assigns) do
    {bad, bag} = explode_count(assigns.game, assigns.seat)

    assigns =
      assign(assigns,
        space: PotTrack.at(Game.scoring_index(assigns.game, assigns.seat)),
        final?: assigns.game.round == 9,
        explode: explode_percent(assigns.game, assigns.seat),
        bad: bad,
        bag: bag
      )

    # Round 9 has no shop: the line names the VP, not coins to spend.
    ~H"""
    <p
      class="flex h-7 shrink-0 items-center gap-2.5 text-sm leading-none font-semibold whitespace-nowrap tabular-nums text-parchment"
      data-role="reward-line"
    >
      <span class="flex items-center gap-2" data-role="next-reward">
        <span class="sr-only">Reward:</span>
        <span :if={!@final?} class="flex items-center gap-0.5" data-role="reward-coins">
          <.piece_icon name={:coin} class="size-5 text-gold" /><span class="min-w-[2ch] text-left">{@space.coins}</span>
          <span class="sr-only">
            {plural(@space.coins, "coin", "coins")}
          </span>
        </span>
        <span class="flex items-center gap-0.5 text-gold" data-role="reward-vp">
          <.piece_icon name={:vp} class="size-5" /><span class="min-w-[2ch] text-left">{@space.vp}</span><span class="sr-only"> VP</span>
        </span>
        <%!-- Round 30: the ruby's slot is always there, dim when the space pays none,
             so nothing moves when a ruby comes up. --%>
        <span
          class={["flex items-center", !@space.ruby? && "opacity-25 grayscale"]}
          data-role="reward-ruby"
          data-ruby={to_string(@space.ruby?)}
        >
          <.piece_icon name={:ruby} class="size-5 text-ruby-light" /><span
            :if={@space.ruby?}
            class="sr-only"
          >ruby</span>
        </span>
      </span>
      <span
        :if={@risk != :off}
        class="flex items-center gap-0.5 border-l border-parchment/25 pl-2.5"
        data-role="explode-chance"
        data-percent={@explode}
        data-count={"#{@bad}/#{@bag}"}
        title={"Explosion risk of the next draw: #{@bad} of #{@bag} chips in the bag"}
      >
        <.explosion_icon class="size-5" />
        <span class="sr-only">Explode:</span>
        <%= if @risk == :chips do %>
          <span class="min-w-[5ch] text-left">{@bad}/{@bag}</span>
        <% else %>
          <span class="min-w-[4.5ch] text-left">{@explode}%</span>
        <% end %>
      </span>
    </p>
    """
  end

  defp explode_count(game, seat) do
    p = Game.player(game, seat)

    if p.exploded? or p.phase in [:stopped, :done],
      do: {0, length(p.bag)},
      else: Odds.next_draw_count(game, seat)
  end

  defp explode_percent(game, seat) do
    p = Game.player(game, seat)

    if p.exploded? or p.phase in [:stopped, :done],
      do: 0,
      else: round(Odds.next_draw(game, seat) * 100)
  end

  # Round 9 has no shop: its shopping phase is the final scoring (rubies, Done).
  defp round_phase_name(%Game{round: 9}, :shop), do: "Final scoring"
  defp round_phase_name(_game, phase), do: phase_name(phase)

  # The colours with an ingredient book (white has none), for `offer_books/1`.
  @book_colours Chips.order() -- [:white]

  @doc """
  Round 40 (Nick): the crow skull's choice from 64rem, a panel in the context
  column (as Ghost's breath V's, round 39), not in the bar: the crow skull chip,
  what to do, the drawn chips (large) on the cloth and Skip. Below 64rem it is
  hidden and the bar has the choice (`bar_choice/1`, `:blue_choice`).
  """
  attr :actions, :list, required: true
  attr :game, Game, required: true
  attr :me, Player, required: true

  def crow_panel(assigns) do
    assigns = assign(assigns, chips: crow_chips(assigns), skip?: :return_all in assigns.actions)

    ~H"""
    <section
      id={"crow-panel-#{@game.round}"}
      phx-hook=".FromBag"
      class="paper hidden shrink-0 flex-col gap-3 rounded-2xl border-4 border-iron p-3 text-ink lg:flex"
      aria-label="Crow skull: place one chip in the pot, or return them all to the bag"
      data-role="crow-panel"
    >
      <div class="flex items-center gap-2">
        <.chip chip={{:blue, nil}} size={:md} />
        <div class="min-w-0 flex-1">
          <h2 class="font-hand text-xl leading-tight font-bold">Crow skull</h2>
          <p class="text-sm" data-role="crow-hint">
            Add a chip to the pot, or skip: they all go back in the bag.
          </p>
        </div>
      </div>
      <div class="relative flex flex-wrap justify-center gap-2 p-2" data-role="crow-tray">
        <span class="blue-cloth absolute inset-0 rounded-xl" aria-hidden="true" />
        <button
          :for={c <- @chips}
          id={"crow-chip-#{@game.round}-#{c.id}"}
          type="button"
          phx-click={c.action && "action"}
          phx-value-action={c.action && encode(c.action)}
          disabled={is_nil(c.action)}
          class="pool-chip relative z-10 grid size-12 cursor-pointer place-items-center rounded-full transition-transform duration-100 ease-out hover:scale-105 active:scale-95 disabled:cursor-default disabled:opacity-40"
          aria-label={c.label}
          title={c.label}
          data-pool-chip
        >
          <.chip chip={c.chip} size={:lg} />
        </button>
      </div>
      <.button
        :if={@skip?}
        phx-click="action"
        phx-value-action={encode(:return_all)}
        variant={:secondary}
        class="min-h-11"
        aria-label={action_label(:return_all, @game, @me)}
        data-role="crow-skip"
        data-crow-skip
      >
        Skip
      </.button>
    </section>
    """
  end

  # The crow skull's drawn chips, each with its action (nil: it cannot go in now).
  defp crow_chips(%{actions: actions, game: game, me: me}) do
    picks = Enum.filter(actions, &(pick_chips(&1) != []))

    for {chip, i} <- Enum.with_index(me.pending) do
      action = pool_pick(picks, chip)

      %{
        id: i,
        chip: chip,
        action: action,
        label: if(action, do: action_label(action, game, me), else: chip_name(chip))
      }
    end
  end

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

  # Round 39: Ghost's breath V's coins and what is left after the ticked chips.
  defp purple_purse(me, selected, sets) do
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
        <.witch_card :for={id <- witches_acting(@game, @others)} id={id} />
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
            {action_label(action, @game, @me)}
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

  # Round 33 (sweep): the small choices that left their sheet for the bar.
  @pick_choices [:yellow_choice, :blue_choice, :witch_offer, :red_choice, :essence_offer]

  @doc "Round 33 (sweep): the small choices that left their sheet for the bar."
  @spec pick_choices() :: [atom]
  def pick_choices, do: @pick_choices

  @doc """
  Round 29: a choice in the bar, where Stop and Draw sit (`@bar_choice`), not a sheet.
  It keeps the bar's height (`min-h-12`), so the pot does not move.

  `:explosion_choice`: Take VP or Take coins, each with its icon, its number and a
  one-line hint. On a phone it shows after the explosion's beat (BOOM over the pot,
  about 700 ms, `.bar-choice-late` in app.css), so a tap meant for Draw does not
  choose.

  `:rubies`: Skip, then one button per ruby use, each "2" (the seat's
  `ruby_price`) and the ruby, then its icon: the test tube (reverse pot side only),
  the flask, the pot (droplet +1). A use that is not possible now is disabled and
  says why ("Flask full"). Round 31: it is the evaluation's last step, only when a
  ruby buys something; never in round 9 (the rubies turn into VP by themselves).
  """
  attr :choice, :atom,
    required: true,
    values:
      [:explosion_choice, :rubies, :fortune_choice, :chip_choice, :droplet_choice, :essence_bonus] ++
        @pick_choices

  attr :actions, :list, required: true
  attr :game, Game, required: true
  attr :me, Player, required: true
  attr :seat, :integer, default: 0

  attr :keep, :boolean,
    default: false,
    doc: "round 35: the results' rubies step, its Skip is \"Keep\" (`rubies_keep`)"

  attr :pot_pick, :any,
    default: nil,
    doc: "round 36: the pot chip tapped for its choices (`:chip_choice`)"

  attr :selected, :list,
    default: [],
    doc: "round 39: Ghost's breath V's ticked chips (`:chip_choice`)"

  def bar_choice(%{choice: :explosion_choice} = assigns) do
    space = PotTrack.at(Player.scoring_index(assigns.me))
    assigns = assign(assigns, space: space, final?: assigns.game.round == 9)

    ~H"""
    <section
      id={"bar-explosion-#{@game.round}"}
      class="bar-choice bar-choice-late grid grid-cols-2 gap-2 *:min-h-12 *:touch-manipulation"
      aria-label="Your pot exploded: take the victory points or the coins"
      data-role="bar-explosion"
    >
      <.button
        phx-click="action"
        phx-value-action={encode({:explosion_choice, :vp})}
        disabled={{:explosion_choice, :vp} not in @actions}
        class="flex-col gap-0! px-2! py-1! leading-tight"
        aria-label={action_label({:explosion_choice, :vp}, @game, @me)}
        data-choice="vp"
      >
        <span class="flex items-center gap-1 text-base">
          <.piece_icon name={:vp} class="size-5" /> Take VP +{@space.vp}
        </span>
        <span class="text-xs font-normal opacity-80">Score now, no coins</span>
      </.button>
      <.button
        phx-click="action"
        phx-value-action={encode({:explosion_choice, :buy})}
        disabled={{:explosion_choice, :buy} not in @actions}
        class="flex-col gap-0! px-2! py-1! leading-tight"
        aria-label={action_label({:explosion_choice, :buy}, @game, @me)}
        data-choice="buy"
      >
        <span class="flex items-center gap-1 text-base">
          <.piece_icon name={:coin} class="size-5" /> Take coins {@space.coins}
        </span>
        <span class="text-xs font-normal opacity-80">
          {if @final?, do: "Turn into VP at the end", else: "Shop, no VP"}
        </span>
      </.button>
    </section>
    """
  end

  def bar_choice(%{choice: :rubies} = assigns) do
    assigns =
      assign(assigns,
        uses: ruby_uses(assigns.game),
        witch?: assigns.me.rubies >= 1 and g4_call?(assigns.game, assigns.actions)
      )

    ~H"""
    <section
      id="bar-rubies"
      class="bar-choice flex gap-1.5 *:min-h-12 *:min-w-0 *:flex-1 *:touch-manipulation"
      aria-label={"Spend rubies: you have #{@me.rubies}"}
      data-role="bar-rubies"
    >
      <.button
        :if={@keep}
        phx-click="rubies_keep"
        class="px-1!"
        data-role="rubies-keep"
      >
        Keep
      </.button>
      <.button
        :if={!@keep}
        phx-click="action"
        phx-value-action={encode(:end_round)}
        disabled={:end_round not in @actions}
        class="px-1!"
        data-role="rubies-skip"
      >
        Skip
      </.button>
      <.button
        :for={use <- @uses}
        phx-click="action"
        phx-value-action={encode({:rubies, use})}
        disabled={{:rubies, use} not in @actions}
        variant={:primary}
        class="flex-col gap-0! px-1! py-1! leading-tight"
        aria-label={action_label({:rubies, use}, @game, @me)}
        title={
          if {:rubies, use} in @actions,
            do: action_label({:rubies, use}, @game, @me),
            else: ruby_why(use, @me, @actions)
        }
        data-ruby={use}
      >
        <span class="flex items-center gap-0.5 text-base tabular-nums">
          {ruby_cost(use, @me)}<.piece_icon name={:ruby} class="size-4 text-ruby" />
          <.piece_icon name={ruby_icon(use)} class="ml-0.5 size-5" />
        </span>
        <span class="max-w-full truncate text-[11px] font-normal">
          {ruby_why(use, @me, @actions)}
        </span>
      </.button>
      <%!-- Round 37: the gold witch "Cheap rubies": each use then costs 1 ruby. --%>
      <.button
        :if={@witch?}
        phx-click="action"
        phx-value-action={encode({:witch, :gold})}
        variant={:secondary}
        class="flex-col gap-0! px-1! py-1! leading-tight"
        aria-label="Call the gold witch: each ruby use costs 1 ruby"
        title="Call the gold witch: each ruby use costs 1 ruby"
        data-role="rubies-witch"
      >
        <span class="flex items-center gap-0.5 text-base">
          <.piece_icon name={:witch} class="size-5 text-penny-gold" />
        </span>
        <span class="max-w-full truncate text-[11px] font-normal">Witch: 1 each</span>
      </.button>
    </section>
    """
  end

  # Round 35: Choices, Choices (P1) as one row of what you may take, in the button
  # row only: the black chip, each 2-chip, and the ruby with its 3 inside. A tap
  # takes it; the card stays over the pot, so its text is there to read.
  @p1_rubies 3

  def bar_choice(%{choice: :fortune_choice, game: %Game{fortune_card: :p1}} = assigns) do
    picks = Enum.filter(assigns.actions, &match?({:fortune, _}, &1))
    assigns = assign(assigns, picks: picks, rubies: @p1_rubies)

    ~H"""
    <section
      id={"bar-card-#{@game.round}"}
      class="bar-choice relative z-50 flex min-h-12 items-center justify-center gap-2.5"
      aria-label={"#{Quacks.Rules.Fortune.card(:p1).name}: take one"}
      data-role="bar-card"
      data-card="p1"
    >
      <button
        :for={{:fortune, choice} = action <- @picks}
        type="button"
        phx-click="action"
        phx-value-action={encode(action)}
        class="relative grid size-12 shrink-0 place-items-center rounded-full touch-manipulation transition-transform duration-100 ease-out hover:scale-105 active:scale-95"
        aria-label={action_label(action, @game, @me)}
        title={action_label(action, @game, @me)}
        data-role="card-option"
        data-choice={card_choice_kind(choice)}
      >
        <%= case choice do %>
          <% {:take, chip} -> %>
            <.chip chip={chip} size={:lg} />
          <% _rubies -> %>
            <.piece_icon name={:ruby} class="size-12 text-ruby drop-shadow-md" />
            <span
              class="absolute inset-0 grid place-items-center pt-1 font-hand text-xl leading-none font-bold text-parchment-light drop-shadow-[0_1px_1px_rgb(0_0_0/0.9)]"
              data-role="ruby-count"
            >
              {@rubies}
            </span>
        <% end %>
      </button>
    </section>
    """
  end

  # Round 36: a card's chips are chips to tap (`chip_row/1`); its other choices
  # (rubies, VP, Skip) follow them as buttons. Without chips: the button grid.
  def bar_choice(%{choice: :fortune_choice} = assigns) do
    %{game: game, me: me} = assigns
    card = game.fortune_card
    picks = Enum.filter(assigns.actions, &match?({:fortune, _}, &1))
    {chips, picks} = Enum.split_with(picks, &match?({:fortune, {_kind, {_, _}}}, &1))

    options =
      for {:fortune, {kind, chip}} = action <- chips do
        %{
          chip: chip,
          action: action,
          label: action_label(action, game, me),
          kind: kind,
          to: if(kind == :upgrade, do: Fortune.upgrade(chip))
        }
      end

    assigns = assign(assigns, card: card, picks: picks, options: options)

    ~H"""
    <section
      id={"bar-card-#{@game.round}"}
      class="bar-choice relative z-50"
      aria-label={"#{Quacks.Rules.Fortune.card(@card).name}: choose one"}
      data-role="bar-card"
    >
      <.chip_row :if={@options != []} options={@options}>
        <.choice_button
          :for={{:fortune, choice} = action <- @picks}
          action={action}
          variant={if choice == :skip, do: :secondary, else: :primary}
          label={action_label(action, @game, @me)}
          title={card_choice_title(choice, @card)}
          hint={card_choice_hint(choice, @card, @me)}
          class="min-h-12 min-w-16 flex-1"
          data-choice={card_choice_kind(choice)}
        >
          <:icon><.card_choice_icon choice={choice} /></:icon>
        </.choice_button>
      </.chip_row>
      <.choice_grid :if={@options == []} count={length(@picks)}>
        <.choice_button
          :for={{:fortune, choice} = action <- @picks}
          action={action}
          variant={if choice == :skip, do: :secondary, else: :primary}
          label={action_label(action, @game, @me)}
          title={card_choice_title(choice, @card)}
          hint={card_choice_hint(choice, @card, @me)}
          data-choice={card_choice_kind(choice)}
        >
          <:icon><.card_choice_icon choice={choice} /></:icon>
        </.choice_button>
      </.choice_grid>
    </section>
    """
  end

  # Round 36: the chips to choose are chips to tap (`chip_row/1`): G2's and G5's
  # chips here, a pot chip's choice (P4, locoweed V) on the chip in the pot
  # (`pot_targets/1`; a chip with more than one choice shows them here once
  # tapped, `@pot_pick`), Ghost's breath V's buys in the context area's panel (`purple_buy/1`).
  # The ladders (P2, G4) and Done stay buttons.
  def bar_choice(%{choice: :chip_choice} = assigns) do
    %{actions: actions, game: game, me: me} = assigns
    picks = actions |> Enum.filter(&(pick_chips(&1) != [])) |> Enum.sort_by(&chip_order/1)
    {targets, picks} = Enum.split_with(picks, &pot_action?/1)
    {buys, picks} = Enum.split_with(picks, &match?({:chip, {:buy, _}}, &1))
    rungs = ladder(me, actions, game)
    pick = Enum.filter(targets, &(pot_chip(&1) == assigns.pot_pick))
    options = Enum.map(if(pick == [], do: picks, else: pick), &chip_option(&1, game, me))

    items =
      Enum.map(rungs, &rung_item(&1, game, me)) ++
        for(
          :chip_done <- actions,
          do: %{
            action: :chip_done,
            label: action_label(:chip_done, game, me),
            title: "Done",
            hint: nil,
            reason: nil,
            icon: nil
          }
        )

    titles =
      Enum.uniq(
        Enum.map(picks ++ targets ++ buys, &pick_title(&1, game.fortune_card)) ++
          Enum.map(rungs, &rung_title/1)
      )

    {coins, remaining} = purple_purse(me, assigns.selected, game.sets)

    assigns =
      assign(assigns,
        items: items,
        titles: titles,
        options: options,
        picked: pick != [] && assigns.pot_pick,
        tap?: targets != [],
        buys?: buys != [],
        coins: coins,
        remaining: remaining
      )

    ~H"""
    <section
      id={"bar-chip-actions-#{@game.round}"}
      class="bar-choice flex flex-col gap-1.5"
      aria-label="Chip actions"
      data-role="bar-chip-actions"
    >
      <.info_row id="info-chip-actions">
        <:icon><.piece_icon name={:book} class="size-5" /></:icon>
        <span :for={title <- @titles} class="block truncate" data-role="info-title">{title}</span>
        <span
          :if={@tap? and !@picked}
          class="block truncate text-xs font-normal text-parchment-dim"
          data-role="tap-pot"
        >
          Tap a glowing chip in your pot
        </span>
        <span
          :if={@picked}
          class="block truncate text-xs font-normal text-parchment-dim"
          data-role="pot-picked"
        >
          {chip_name(@picked)}: swap it for
        </span>
      </.info_row>
      <.chip_row options={@options}>
        <.button
          :if={@picked}
          phx-click="pot_pick"
          variant={:secondary}
          class="min-h-12 touch-manipulation px-4"
          data-role="pot-pick-back"
        >
          Back
        </.button>
        <%!-- Round 39: Ghost's breath V's purse and Take; its chips are in the
             context area's panel (`purple_buy/1`). --%>
        <p
          :if={@buys? and !@picked}
          class="flex shrink-0 items-center gap-1 font-hand text-xl leading-none font-bold whitespace-nowrap text-parchment tabular-nums"
          data-role="purple-buy-total"
          aria-label={"#{@coins} coins, #{@remaining} left after this"}
        >
          <span class="book-coin" />{@coins}<span class="text-base text-parchment-dim">→</span>{@remaining}
        </p>
        <.button
          :if={@buys? and !@picked}
          phx-click="action"
          phx-value-action={encode({:chip, {:buy, @selected}})}
          disabled={{:chip, {:buy, @selected}} not in @actions}
          variant={:primary}
          class="min-h-12 min-w-24 flex-1 touch-manipulation px-4"
          data-role="purple-buy-take"
        >
          {if @selected == [], do: "Take", else: "Take #{length(@selected)}"}
        </.button>
        <.choice_button
          :for={item <- @items}
          :if={!@picked}
          action={if(item.reason, do: nil, else: item.action)}
          variant={if item.action == :chip_done, do: :secondary, else: :primary}
          label={if item.reason, do: "#{item.label}: #{item.reason}", else: item.label}
          title={item.title}
          hint={item.hint}
          class="min-h-12 min-w-16 flex-1"
          data-role={if item.reason, do: "ladder-rung-off", else: "chip-action"}
        >
          <:icon :if={item.icon}><.chip_item_icon icon={item.icon} /></:icon>
        </.choice_button>
      </.chip_row>
    </section>
    """
  end

  def bar_choice(%{choice: :droplet_choice} = assigns) do
    assigns = assign(assigns, sources: droplet_sources(assigns.game.log, assigns.seat))

    ~H"""
    <section
      id="bar-droplet"
      class="bar-choice flex flex-col gap-1.5"
      aria-label="Droplet: move your pot droplet or your test-tube droplet"
      data-role="bar-droplet"
    >
      <.info_row id="info-droplet">
        <:icon :if={@sources != []}>
          <span
            :for={{cause, _text} <- @sources}
            class="inline-flex scale-75 [&_.die]:size-7"
            data-role="droplet-source"
          >
            <.droplet_cause cause={cause} />
          </span>
        </:icon>
        <span class="block truncate" data-role="droplet-sources">
          {if @sources == [],
            do: "A free move",
            else: Enum.map_join(@sources, " · ", &elem(&1, 1))}
        </span>
        <span class="block text-xs font-normal text-parchment-dim">
          Move your pot droplet or your test-tube droplet{if @me.droplet_moves > 1,
            do: " (#{@me.droplet_moves} moves)"}
        </span>
      </.info_row>
      <.choice_grid count={2}>
        <.choice_button
          action={{:droplet, :pot}}
          disabled={{:droplet, :pot} not in @actions}
          label={action_label({:droplet, :pot}, @game, @me)}
          title="Pot droplet"
          hint="+1 space"
          data-choice="pot"
        >
          <:icon><.piece_icon name={:pot} class="size-5" /></:icon>
        </.choice_button>
        <.choice_button
          action={{:droplet, :tube}}
          disabled={{:droplet, :tube} not in @actions}
          label={action_label({:droplet, :tube}, @game, @me)}
          title="Test tube"
          hint={tube_hint(@me)}
          data-choice="tube"
        >
          <:icon><.piece_icon name={:tube} class="size-5" /></:icon>
        </.choice_button>
      </.choice_grid>
    </section>
    """
  end

  # Round 36: Chicken eyes (The Alchemists): the 1-chips it may swap glow in the
  # pot (`pot_targets/1`); the bar says so and holds No.
  def bar_choice(%{choice: :essence_bonus} = assigns) do
    ~H"""
    <section
      id={"bar-essence-swap-#{@game.round}"}
      class="bar-choice flex flex-col gap-1.5"
      aria-label={bonus_hint(@me.essence_pending)}
      data-role="bar-essence-swap"
    >
      <.info_row id="info-essence-swap">
        <:icon><.piece_icon name={:pot} class="size-5" /></:icon>
        <span class="block truncate" data-role="info-title">{bonus_hint(@me.essence_pending)}</span>
        <span class="block truncate text-xs font-normal text-parchment-dim" data-role="tap-pot">
          Tap a glowing chip in your pot
        </span>
      </.info_row>
      <div class="flex min-h-12 justify-end *:min-h-12 *:touch-manipulation">
        <.button
          :if={{:essence, :pass} in @actions}
          phx-click="action"
          phx-value-action={encode({:essence, :pass})}
          variant={:secondary}
          class="px-6"
          aria-label={action_label({:essence, :pass}, @game, @me)}
          data-role="essence-pass"
        >
          No
        </.button>
      </div>
    </section>
    """
  end

  # Round 35: the crow skull's chips come out of the bag one by one (`.FromBag`,
  # WAAPI from the bag to their place, 140 ms apart); on a tap the chips not chosen
  # go back into the bag while the row leaves (`phx-remove`, `.bar-to-bag`).
  # Reduced motion: fades. Round 37: the chips lie on a cloth.
  # Round 40 (Nick): the row has the height of Stop and Draw (`h-12`), so nothing
  # moves between brewing and the choice. The crow skull chip and "Add a chip to
  # the pot" are in the info row over it, where the white track is. Up to 5 chips
  # (36 px, 44 px tap targets) and Skip fit in the row at 360 px. From 64rem the
  # choice is a panel in the context column (`crow_panel/1`) and the bar keeps
  # Stop and Draw (disabled) with the white track.
  def bar_choice(%{choice: :blue_choice} = assigns) do
    assigns = assign(assigns, chips: crow_chips(assigns), skip?: :return_all in assigns.actions)

    ~H"""
    <section
      id={"bar-blue-#{@game.round}"}
      phx-hook=".FromBag"
      phx-remove={JS.transition("bar-to-bag", time: 520)}
      class="bar-choice flex flex-col gap-1.5 lg:hidden"
      aria-label="Crow skull: place one chip in the pot, or return them all to the bag"
      data-role="bar-blue"
    >
      <script :type={Phoenix.LiveView.ColocatedHook} name=".FromBag">
        export default {
          mounted() {
            const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches
            const chips = [...this.el.querySelectorAll("[data-pool-chip]")]
            const bag = () => document.querySelector("[data-role=bag-button]")
            const away = c => {
              const b = bag()
              if (reduce || !b) return {opacity: 0}
              const r = c.getBoundingClientRect(), s = b.getBoundingClientRect()
              const dx = s.x + s.width / 2 - r.x - r.width / 2, dy = s.y + s.height / 2 - r.y - r.height / 2
              return {translate: `${dx}px ${dy}px`, scale: 0.35, opacity: 0}
            }
            chips.forEach((c, i) => c.animate([away(c), {translate: "0 0", scale: 1, opacity: 1}],
              {duration: reduce ? 200 : 420, delay: i * 140, easing: "cubic-bezier(0.22, 1, 0.36, 1)", fill: "backwards"}))
            this.el.addEventListener("click", e => {
              const hit = e.target.closest("[data-pool-chip]:not(:disabled), [data-crow-skip]")
              if (!hit) return
              if (hit.matches("[data-pool-chip]")) hit.animate([{opacity: 1}, {opacity: 0}], {duration: 220, fill: "forwards"})
              chips.filter(c => c !== hit).forEach((c, i) => c.animate([{translate: "0 0", scale: 1, opacity: 1}, away(c)],
                {duration: reduce ? 200 : 360, delay: i * 50, easing: "cubic-bezier(0.55, 0, 1, 0.45)", fill: "forwards"}))
            })
          }
        }
      </script>
      <.info_row id={"info-blue-#{@game.round}"}>
        <:icon>
          <span class="grid size-7 place-items-center" title="Crow skull" data-role="blue-book">
            <.chip chip={{:blue, nil}} size={:sm} />
          </span>
        </:icon>
        <span class="block truncate" data-role="blue-hint">Add a chip to the pot</span>
        <span class="block truncate text-xs font-normal text-parchment-dim">
          Or skip: they all go back in the bag
        </span>
      </.info_row>
      <div class="flex h-12 items-center gap-2" data-role="blue-row">
        <div class="relative flex h-12 min-w-0 items-center px-1" data-role="blue-tray">
          <span
            class="blue-cloth absolute inset-0 rounded-xl"
            aria-hidden="true"
            data-role="blue-cloth"
          />
          <button
            :for={c <- @chips}
            id={"blue-chip-#{@game.round}-#{c.id}"}
            type="button"
            phx-click={c.action && "action"}
            phx-value-action={c.action && encode(c.action)}
            disabled={is_nil(c.action)}
            class="pool-chip relative z-10 grid size-11 shrink-0 place-items-center rounded-full touch-manipulation transition-transform duration-100 ease-out active:scale-95 disabled:opacity-40"
            aria-label={c.label}
            title={c.label}
            data-pool-chip
          >
            <.chip chip={c.chip} size={:md} />
          </button>
        </div>
        <.button
          :if={@skip?}
          phx-click="action"
          phx-value-action={encode(:return_all)}
          variant={:secondary}
          class="ml-auto h-12 shrink-0 touch-manipulation px-3"
          aria-label={action_label(:return_all, @game, @me)}
          data-role="blue-skip"
          data-crow-skip
        >
          Skip
        </.button>
      </div>
    </section>
    """
  end

  # Round 33 (sweep): the other small choices of a turn, the same way: an info row
  # and the options as buttons (`pick_spec/4`).
  def bar_choice(%{choice: choice} = assigns) when choice in @pick_choices do
    spec = pick_spec(choice, assigns.actions, assigns.game, assigns.me)
    assigns = assign(assigns, spec: spec)

    ~H"""
    <section
      id={"bar-pick-#{@choice}"}
      class="bar-choice flex flex-col gap-1.5"
      aria-label={phase_name(@choice)}
      data-role="bar-pick"
      data-choice={@choice}
    >
      <.info_row id={"info-#{@choice}"}>
        <:icon :if={@spec.chip}><.chip chip={@spec.chip} size={:sm} /></:icon>
        <span class="block truncate" data-role="info-title">{@spec.title}</span>
        <span :if={@spec.text} class="block truncate text-xs font-normal text-parchment-dim">
          {@spec.text}
        </span>
      </.info_row>
      <.chip_row :if={@spec[:options]} options={@spec.options}>
        <.choice_button
          :for={item <- @spec.items}
          action={item.action}
          variant={item[:variant] || :primary}
          label={item.label}
          title={item.title}
          hint={item.hint}
          class="min-h-12 min-w-16 flex-1"
          data-role="pick-action"
        />
      </.chip_row>
      <.choice_grid :if={!@spec[:options]} count={length(@spec.items)}>
        <.choice_button
          :for={item <- @spec.items}
          action={item.action}
          variant={item[:variant] || :primary}
          label={item.label}
          title={item.title}
          hint={item.hint}
          data-role="pick-action"
        >
          <:icon :if={item.icon}><.chip_item_icon icon={item.icon} /></:icon>
        </.choice_button>
      </.choice_grid>
    </section>
    """
  end

  @doc """
  Round 33: the buttons of a choice in the bar as a grid, never a sideways scroll:
  up to 4 in one row, 5 to 8 in two rows (3 or 4 per row), all of one width. Two
  rows only while choosing: the bar keeps its height and the second row rises over
  the pot's lower band (`.game-bar` sets the buttons at its foot), so the pot never
  moves. `data-rows` says how many rows.
  """
  attr :count, :integer, required: true
  slot :inner_block, required: true

  def choice_grid(assigns) do
    assigns = assign(assigns, rows: if(assigns.count > 4, do: 2, else: 1))

    ~H"""
    <div
      class={[
        "grid gap-1.5 *:min-w-0 *:touch-manipulation",
        if(@rows == 2, do: "*:min-h-11", else: "*:min-h-12"),
        grid_cols(@count)
      ]}
      data-role="choice-grid"
      data-rows={@rows}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp grid_cols(n) when n <= 1, do: "grid-cols-1"
  defp grid_cols(2), do: "grid-cols-2"
  defp grid_cols(n) when n in [3, 5, 6], do: "grid-cols-3"
  defp grid_cols(_n), do: "grid-cols-4"

  @doc """
  Round 33: one button of a bar choice: its picture (a chip, a piece) then a short
  title on one line, and a hint line under it. The picture has its own box, so a
  chip's value badge never covers the text. `action` nil or `disabled` greys it;
  `label` is the full text (screen readers, the tooltip).
  """
  attr :action, :any, default: nil
  attr :variant, :atom, default: :primary
  attr :disabled, :boolean, default: false
  attr :label, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :icon

  def choice_button(assigns) do
    ~H"""
    <.button
      phx-click={@action && "action"}
      phx-value-action={@action && encode(@action)}
      disabled={@disabled or is_nil(@action)}
      variant={@variant}
      class={["flex-col gap-0! px-1! py-1! leading-tight", @class]}
      aria-label={@label}
      title={@label}
      data-choice-button
      {@rest}
    >
      <span class="flex max-w-full items-center gap-1 text-sm font-bold tabular-nums">
        <span
          :if={@icon != []}
          class="inline-flex shrink-0 items-center pr-1"
          data-role="choice-icon"
        >
          {render_slot(@icon)}
        </span>
        <span class="truncate">{@title}</span>
      </span>
      <span :if={@hint} class="max-w-full truncate text-[11px] font-normal opacity-80">
        {@hint}
      </span>
    </.button>
    """
  end

  @doc """
  Round 36: a choice among chips as the chips themselves, to tap (the crow skull's
  and Choices, Choices' way): one round button per option, its chip big (`:md`
  from 7 options), the action's label to read on hover and for screen readers.
  An upgrade shows the chip it turns into, small, on its edge (`to`). An option
  without an action is greyed. The inner block (Skip, Done, a ladder) follows the
  chips in the same row; the row wraps into a second row while choosing (it
  rises over the pot's lower band, as `choice_grid/1` does).
  """
  attr :options, :list, required: true, doc: "`%{chip, action, label}`, optional `to`"
  slot :inner_block

  def chip_row(assigns) do
    assigns = assign(assigns, size: if(length(assigns.options) > 6, do: :md, else: :lg))

    ~H"""
    <div
      class="flex min-h-12 flex-wrap items-center justify-center gap-x-2 gap-y-1.5"
      data-role="chip-row"
    >
      <button
        :for={o <- @options}
        type="button"
        phx-click={o.action && "action"}
        phx-value-action={o.action && encode(o.action)}
        disabled={is_nil(o.action)}
        class={[
          "relative grid shrink-0 place-items-center rounded-full touch-manipulation",
          "transition-transform duration-100 ease-out hover:scale-105 active:scale-95",
          "focus-visible:outline-3 focus-visible:outline-droplet disabled:opacity-40"
        ]}
        aria-label={o.label}
        title={o.label}
        data-role="chip-option"
        data-chip={chip_name(o.chip)}
        data-choice={o[:kind]}
      >
        <.chip chip={o.chip} size={@size} />
        <span
          :if={o[:to]}
          class="absolute -right-2 -bottom-1 flex items-center rounded-full bg-iron-dark/90 py-0.5 pr-0.5 shadow"
          data-role="chip-option-to"
        >
          <.icon name="hero-arrow-right-mini" class="size-3 text-parchment" />
          <.chip chip={o.to} size={:xs} />
        </span>
      </button>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # A chip action as a `chip_row/1` option: the chip it brings (an upgrade: the
  # bigger chip, the pot chip is already chosen).
  defp chip_option(action, game, me) do
    %{chip: option_chip(action), action: action, label: action_label(action, game, me)}
  end

  defp option_chip({:chip, {:upgrade, _from, to}}), do: to
  defp option_chip(action), do: hd(pick_chips(action))

  @doc """
  Round 36: the choices about a chip already in the pot: the player taps that
  chip (`pot_targets/1`). P4 swaps a pot chip, locoweed V returns one, an
  Alchemists bonus swaps a 1-chip for a bigger one.
  """
  def pot_action?({:chip, {:upgrade, _from, _to}}), do: true
  def pot_action?({:chip, {:return, _chip}}), do: true
  def pot_action?({:essence, {:swap, _chip}}), do: true
  def pot_action?(_action), do: false

  @doc false
  def pot_chip({:chip, {:upgrade, from, _to}}), do: from
  def pot_chip({_kind, {_verb, chip}}), do: chip

  @doc """
  Round 33: the info row, the bar's second context row. It sits where the white
  track is while brewing (the fuse row), over the step's buttons: what the step is
  (a chip, the die) and a short text. In the evaluation and the shop the white
  track is not needed there.
  """
  attr :id, :string, default: nil
  attr :rest, :global
  slot :icon
  slot :inner_block, required: true

  def info_row(assigns) do
    ~H"""
    <div
      id={@id}
      class="flex min-h-9 min-w-0 items-center gap-2 rounded-lg bg-iron-dark/90 px-2 py-1 text-sm leading-tight font-semibold text-parchment shadow-lg"
      aria-live="polite"
      data-role="info-row"
      {@rest}
    >
      <span :if={@icon != []} class="flex shrink-0 items-center gap-1" data-role="info-icon">
        {render_slot(@icon)}
      </span>
      <span class="min-w-0 flex-1">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  # What the info row says and the buttons of a sweep choice (`@pick_choices`).
  defp pick_spec(:yellow_choice, actions, game, me) do
    %{
      chip: {:white, 1},
      title: "Mandrake: a white chip came after it",
      text: "Put it back in the bag, or keep it in the pot",
      items: Enum.map(actions, &text_item(&1, game, me))
    }
  end

  defp pick_spec(:blue_choice, actions, game, me) do
    %{
      chip: {:blue, 1},
      title: "Crow skull: place one in the pot",
      text: "Or return them all to the bag",
      items: pool_items(me.pending, actions, game, me, "Place")
    }
  end

  defp pick_spec(:witch_offer, actions, game, me) do
    picks = Enum.filter(actions, &(pick_chips(&1) != []))

    %{
      chip: nil,
      title: "The silver witch drew:",
      text: "Tap them one by one, in any order, or return the rest",
      options:
        for chip <- me.witch_offer do
          action = pool_pick(picks, chip)

          %{
            chip: chip,
            action: action,
            label: if(action, do: action_label(action, game, me), else: chip_name(chip))
          }
        end,
      items: Enum.map(text_actions(actions), &text_item(&1, game, me))
    }
  end

  # The Toadstools one at a time: the first chip that waits, then the next.
  defp pick_spec(:red_choice, actions, game, me) do
    chip = Enum.find(me.pending, &Enum.any?(actions, fn a -> pick_chips(a) == [&1] end))
    n = length(me.pending)

    %{
      chip: chip,
      title: "Toadstool: #{chip && chip_name(chip)}#{if n > 1, do: " (#{n} waiting)"}",
      text: "Place it now, keep it beside the pot, or return it to the bag",
      items:
        for(
          kind <- [:place, :keep, :return],
          action = {:red, {kind, chip}},
          action in actions,
          do: %{
            action: action,
            label: action_label(action, game, me),
            title: red_title(kind),
            hint: red_hint(kind),
            icon: nil
          }
        )
    }
  end

  defp pick_spec(:essence_offer, actions, game, me) do
    %{
      chip: offer_chip(me.essence_pending),
      title: offer_hint(me.essence_pending) || "Patient offer",
      text: "Your essence: #{me.essence}",
      items: Enum.map(actions, &text_item(&1, game, me))
    }
  end

  defp red_title(:place), do: "Place"
  defp red_title(:keep), do: "Keep"
  defp red_title(:return), do: "Return"

  defp red_hint(:place), do: "After your last chip"
  defp red_hint(:keep), do: "Beside the pot"
  defp red_hint(:return), do: "To the bag"

  # Every chip of a pool (duplicates too) as a button; one without an action is
  # greyed. Then the text actions ("Return all").
  defp pool_items(pool, actions, game, me, verb) do
    picks = Enum.filter(actions, &(pick_chips(&1) != []))

    chips =
      for chip <- pool do
        action = pool_pick(picks, chip)

        %{
          action: action,
          label: if(action, do: action_label(action, game, me), else: chip_name(chip)),
          title: verb,
          hint: chip_name(chip),
          icon: {:chips, [chip], false}
        }
      end

    chips ++ Enum.map(text_actions(actions), &text_item(&1, game, me))
  end

  # An action without a chip as a bar button: its label after the book's name,
  # the first part as the title and the rest as the hint ("Pay 1 ruby" / "move 3
  # more"). "No"/"Pass" is the secondary one.
  defp text_item(action, game, me) do
    label = action_label(action, game, me)
    rest = label |> String.split(": ", parts: 2) |> List.last()
    {title, hint} = short_words(action, label, rest)

    %{
      action: action,
      label: label,
      title: title,
      hint: hint,
      icon: nil,
      variant: if(action in [{:essence, :pass}, :keep], do: :secondary, else: :primary)
    }
  end

  defp short_words(:return_white, _label, _rest), do: {"Back to bag", "The white chip"}
  defp short_words(:keep, _label, _rest), do: {"Keep", "In the pot"}
  defp short_words(:return_all, _label, _rest), do: {"Return all", "To the bag"}

  defp short_words({:witch, :silver, :return_all}, _label, _rest),
    do: {"Return the rest", "To the bag"}

  # A patient offer: the cost is the title ("Spend 2 essence"), what it does the hint.
  defp short_words({:essence, kind}, label, _rest) when kind != :pass do
    case String.split(label, ": ", parts: 2) do
      [cost, what] -> {cost, what}
      [label] -> {label, nil}
    end
  end

  defp short_words(_action, _label, rest) do
    case String.split(rest, ", ", parts: 2) do
      [title, hint] -> {String.capitalize(title, :ascii), hint}
      [title] -> {String.capitalize(title, :ascii), nil}
    end
  end

  defp tube_hint(%Player{tube: tube}) do
    if tube < TestTubes.last(),
      do: "Bonus: #{tube_bonus(TestTubes.bonus(tube + 1))}",
      else: "Tubes full"
  end

  # A ladder rung (`ladder/3`) as a bar button; a rung out of reach is greyed with
  # its reason as the hint.
  defp rung_item(%{action: action, label: label, reason: reason}, _game, _me) do
    {title, hint, icon} = rung_words(action, label)

    %{
      action: action,
      label: label,
      title: title,
      hint: if(reason, do: reason |> String.split(",") |> hd(), else: hint),
      reason: reason,
      icon: icon
    }
  end

  defp rung_words({:chip, {:purple_trade, t}}, label),
    do:
      {"Trade #{t}", label |> String.split(" for ") |> List.last(),
       {:chips, [{:purple, 1}], false}}

  defp rung_words({:chip, {:pay_ruby_move, k}}, _label),
    do: {"Pay #{k}", "droplet +#{k}", {:piece, :ruby}}

  defp rung_words(nil, label),
    do: {"Swap", label |> String.split(": ") |> List.last(), {:chips, [{:purple, 1}], false}}

  defp rung_title(%{action: {:chip, {:purple_trade, _}}}), do: "Ghost's breath: trade purple"
  defp rung_title(%{action: {:chip, {:pay_ruby_move, _}}}), do: "Garden spider: pay rubies"
  defp rung_title(%{action: nil}), do: "Ghost's breath: swap"

  attr :icon, :any, required: true

  defp chip_item_icon(%{icon: {:piece, name}} = assigns) do
    assigns = assign(assigns, name: name)

    ~H"""
    <.piece_icon name={@name} class="size-5" />
    """
  end

  defp chip_item_icon(%{icon: {:chips, chips, arrow?}} = assigns) do
    assigns = assign(assigns, chips: Enum.with_index(chips), arrow?: arrow?)

    ~H"""
    <span class="inline-flex items-center gap-0.5 pb-1">
      <%= for {chip, i} <- @chips do %>
        <.icon :if={i > 0 and @arrow?} name="hero-arrow-right" class="size-3" />
        <.chip chip={chip} size={if length(@chips) > 1, do: :xs, else: :sm} />
      <% end %>
    </span>
    """
  end

  attr :choice, :any, required: true

  defp card_choice_icon(%{choice: {kind, _chip}} = assigns) when kind in [:take, :place],
    do: ~H"""
    <span class="inline-flex pb-1"><.chip chip={elem(@choice, 1)} size={:sm} /></span>
    """

  defp card_choice_icon(%{choice: {:upgrade, chip}} = assigns) do
    assigns = assign(assigns, from: chip, to: Fortune.upgrade(chip))

    ~H"""
    <span class="inline-flex items-center gap-0.5">
      <.chip chip={@from} size={:xs} /><.icon name="hero-arrow-right" class="size-3" /><.chip
        :if={@to}
        chip={@to}
        size={:xs}
      />
    </span>
    """
  end

  defp card_choice_icon(%{choice: choice} = assigns) do
    assigns = assign(assigns, name: card_choice_piece(choice))

    ~H"""
    <.piece_icon :if={@name} name={@name} class="size-5" />
    """
  end

  defp card_choice_piece(:droplet), do: :droplet
  defp card_choice_piece(:rubies), do: :ruby
  defp card_choice_piece(:vp), do: :vp
  defp card_choice_piece({:rats_back, _n}), do: :rat
  defp card_choice_piece(:remove_white), do: :bag
  defp card_choice_piece(:return_all), do: :bag
  defp card_choice_piece(_choice), do: nil

  defp card_choice_kind({kind, _}), do: kind
  defp card_choice_kind(kind), do: kind

  # The big line on a card choice button: short, the hint says the rest.
  defp card_choice_title({:take, _chip}, :p3), do: "Trade"
  defp card_choice_title({:take, _chip}, _card), do: "Take"
  defp card_choice_title({:upgrade, _chip}, _card), do: ""
  defp card_choice_title(:droplet, :p11), do: "Droplet +2"
  defp card_choice_title(:droplet, _card), do: "Droplet +1"
  defp card_choice_title(:rubies, _card), do: "+3"
  defp card_choice_title(:vp, :p6), do: "+4"
  defp card_choice_title(:vp, _card), do: "VP"
  defp card_choice_title(:remove_white, _card), do: "Remove"
  defp card_choice_title({:rats_back, n}, _card), do: "Back #{n}"
  defp card_choice_title(:skip, _card), do: "No thanks"
  defp card_choice_title({:place, _chip}, _card), do: "Place"
  defp card_choice_title(:return_all, _card), do: "Return all"
  defp card_choice_title(_choice, _card), do: ""

  # The small line under it.
  defp card_choice_hint({:take, chip}, :p3, _me), do: "1 ruby: #{chip_name(chip)}"
  defp card_choice_hint({:take, chip}, _card, _me), do: chip_name(chip)
  defp card_choice_hint({:upgrade, _chip}, _card, _me), do: "Trade up"
  defp card_choice_hint(:droplet, _card, _me), do: "Move your droplet"
  defp card_choice_hint(:rubies, _card, _me), do: "Take 3 rubies"
  defp card_choice_hint(:vp, :p10, _me), do: "1 per rat tail"
  defp card_choice_hint(:vp, _card, _me), do: "Score now"
  defp card_choice_hint(:remove_white, _card, _me), do: "A white 1 from the bag"

  defp card_choice_hint({:rats_back, n}, _card, _me),
    do: "+#{n} #{if n == 1, do: "ruby", else: "rubies"}"

  defp card_choice_hint(:skip, _card, _me), do: "Keep as is"
  defp card_choice_hint({:place, _chip}, _card, _me), do: "Safe, last in pot"
  defp card_choice_hint(:return_all, _card, _me), do: "All to the bag"
  defp card_choice_hint(_choice, _card, _me), do: ""

  # The ruby uses in the bar: the test tube is on the reverse pot side only. Round
  # 37: round 9 (reverse side) offers the tube beside 2 rubies -> 1 VP.
  defp ruby_uses(%Game{round: 9}), do: [:tube, :vp]
  defp ruby_uses(%Game{rules: %{pot_side: :back}}), do: [:tube, :flask, :droplet]
  defp ruby_uses(_game), do: [:flask, :droplet]

  defp ruby_icon(:tube), do: :tube
  defp ruby_icon(:flask), do: :flask
  defp ruby_icon(:droplet), do: :pot
  defp ruby_icon(:vp), do: :vp

  @doc """
  Round 37: the gold witch G4 ("Cheap rubies") can be called in the rubies step.
  """
  def g4_call?(%Game{witches: %{gold: :g4}}, actions), do: {:witch, :gold} in actions
  def g4_call?(_game, _actions), do: false

  # What a ruby use costs now: 2 rubies -> 1 VP is always 2.
  defp ruby_cost(:vp, _me), do: 2
  defp ruby_cost(_use, me), do: me.ruby_price

  # The small line on a ruby button: what it does, or why it cannot.
  defp ruby_why(use, me, actions) do
    cond do
      {:rubies, use} in actions -> ruby_what(use)
      use == :flask and me.flask -> "Flask full"
      use == :tube and me.tube >= TestTubes.last() -> "Tubes full"
      me.rubies >= 1 and {:witch, :gold} in actions -> "Witch: 1 ruby"
      true -> "Too few rubies"
    end
  end

  defp ruby_what(:tube), do: "Test tube"
  defp ruby_what(:flask), do: "Refill flask"
  defp ruby_what(:droplet), do: "Droplet +1"
  defp ruby_what(:vp), do: "1 VP"

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

  # Round 28: under a Flea Market chip that cannot go up, the reason.
  defp blocked_reason(%Game{fortune_card: :p13} = game, [chip]) do
    case Quacks.Game.Fortune.flea_block(game, chip) do
      nil -> nil
      reason -> flea_reason(reason)
    end
  end

  defp blocked_reason(_game, _chips), do: nil

  @doc """
  The chips of a choice as its controls: each chip is a button that sends its
  action. With `pool` (the chips a crow skull, the silver witch, the toadstools or a
  fortune card drew, duplicates included) every pool chip shows, and one without an
  action is dimmed; the toadstool's keep and return are small buttons under the
  chip. Without `pool`, one button per chip action ("any 2-value chip": one chip
  per colour), in the shop's row order, under a title per kind. Actions without a
  chip are not here (`text_actions/1`).
  """
  attr :actions, :list, required: true, doc: "the seat's legal actions"
  attr :pool, :list, default: nil
  attr :game, Game, required: true
  attr :me, Player, required: true
  attr :click, :any, default: "action", doc: "the `phx-click` of each chip"

  def chip_picks(assigns) do
    picks = Enum.filter(assigns.actions, &(pick_chips(&1) != []))

    groups =
      case assigns.pool do
        nil ->
          title = &pick_title(&1, assigns.game.fortune_card)

          for t <- picks |> Enum.map(title) |> Enum.uniq() do
            tiles =
              picks
              |> Enum.filter(&(title.(&1) == t))
              |> Enum.sort_by(&chip_order/1)
              |> Enum.map(&{pick_chips(&1), &1})

            {t, tiles}
          end

        pool ->
          [
            {nil, for(chip <- pool, do: {[chip], pool_pick(picks, chip)})}
          ]
      end

    limit = white_limit(assigns.game, assigns.me)

    groups =
      for {title, tiles} <- groups, tiles != [] do
        {title,
         for(
           {chips, action} <- tiles,
           do: {chips, action, action && over_limit(action, assigns.me, limit)}
         )}
      end

    assigns = assign(assigns, groups: groups, limit: limit)

    ~H"""
    <div :for={{title, tiles} <- @groups} class="space-y-1" data-role="chip-picks">
      <p :if={title} class="text-sm font-semibold">{title}</p>
      <ul class="flex flex-wrap items-start gap-2">
        <li :for={{chips, action, over} <- tiles} class="flex flex-col items-center">
          <button
            :if={action}
            type="button"
            phx-click={@click}
            phx-value-action={encode(action)}
            aria-label={pick_label(action_label(action, @game, @me), over, @limit)}
            title={pick_label(action_label(action, @game, @me), over, @limit)}
            data-role="chip-pick"
            data-over={over && to_string(over)}
            class={[
              "inline-flex min-h-11 min-w-11 cursor-pointer items-center justify-center gap-1 rounded-full p-1",
              "bg-parchment-light shadow-sm touch-manipulation select-none",
              "transition-[scale,box-shadow] duration-150 ease-out hover:ring-2 hover:ring-ink/60",
              "active:scale-[0.94] focus-visible:outline-3 focus-visible:outline-droplet",
              if(over == :explodes, do: "ring-2 ring-ruby", else: "ring-1 ring-ink/25")
            ]}
          >
            <%= for {chip, i} <- Enum.with_index(chips) do %>
              <.icon :if={i > 0 and upgrade?(action)} name="hero-arrow-right" class="size-4" />
              <.chip chip={chip} data-role={if @pool, do: "offer-chip"} />
            <% end %>
          </button>
          <span
            :if={!action}
            class="inline-flex size-11 items-center justify-center opacity-40"
            title={blocked_reason(@game, chips) || "Not playable"}
          >
            <.chip :for={chip <- chips} chip={chip} data-role="offer-chip" />
          </span>
          <span
            :if={!action && blocked_reason(@game, chips)}
            class="mt-0.5 w-16 text-center text-tag leading-4 font-semibold text-ink-soft"
            data-role="pick-blocked"
          >
            {blocked_reason(@game, chips)}
          </span>
          <span
            :if={over}
            class={[
              "mt-0.5 rounded-full px-1.5 text-tag leading-4 font-bold",
              if(over == :explodes, do: "bg-ruby text-white", else: "bg-gold text-ink")
            ]}
            data-role="explode-warning"
          >
            {if over == :explodes, do: "explodes!", else: "over #{@limit}, safe"}
          </span>
          <span
            :if={(!over and @pool) && pick_verb(action)}
            class="mt-0.5 text-tag leading-4 font-semibold text-ink-soft"
            data-role="pick-verb"
          >
            {pick_verb(action)}
          </span>
          <%!-- Without a pool (a card's or a chip action's "take one"), the colour
               word under the chip, so a pick does not read as only its value. --%>
          <span
            :if={action && !@pool && !over}
            class="mt-0.5 text-tag leading-4 font-semibold text-ink-soft"
            data-role="pick-colour"
          >
            {chips |> List.last() |> elem(0)}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  @doc "The chips an action shows as its control; [] for an action without a chip."
  def pick_chips({:place, chip}), do: [chip]
  def pick_chips({:red, {_kind, chip}}), do: [chip]
  def pick_chips({:witch, :silver, {:place, chip}}), do: [chip]
  def pick_chips({:fortune, {kind, chip}}) when kind in [:take, :place, :upgrade], do: [chip]
  def pick_chips({:chip, {kind, chip}}) when kind in [:gain, :starter, :return], do: [chip]
  def pick_chips({:chip, {:upgrade, from, to}}), do: [from, to]
  def pick_chips({:chip, {:buy, chips}}), do: chips
  def pick_chips({:essence, {kind, chip}}) when kind in [:swap, :buy], do: [chip]
  def pick_chips(_action), do: []

  # The highest white sum that does not explode, for `me` (the rule, B5, Wing ears…).
  defp white_limit(game, me),
    do: Enum.max([game.rules.explode_above, me.mods.explode_above, Fortune.explode_above(game)])

  # A white chip whose placing takes the pot over the limit: `:explodes`, or `:safe`
  # for Safety Procedure (B7: a placed chip cannot explode the pot).
  defp over_limit(action, me, limit) do
    case place_chip(action) do
      {:white, v} when is_integer(v) ->
        if Player.white_sum(me) + v > limit, do: over_kind(action)

      _ ->
        nil
    end
  end

  defp over_kind({:fortune, {:place, _chip}}), do: :safe
  defp over_kind(_action), do: :explodes

  defp place_chip({:place, chip}), do: chip
  defp place_chip({:fortune, {:place, chip}}), do: chip
  defp place_chip({:witch, :silver, {:place, chip}}), do: chip
  defp place_chip(_action), do: nil

  defp pick_label(label, :explodes, _limit), do: "#{label}: explodes the pot"
  defp pick_label(label, :safe, limit), do: "#{label}: over #{limit}, cannot explode"
  defp pick_label(label, _over, _limit), do: label

  # The word under an offered chip, so a pick says what it does.
  defp pick_verb(action) do
    cond do
      place_chip(action) -> "Place"
      match?({:fortune, {:upgrade, _}}, action) -> "Trade up"
      true -> nil
    end
  end

  defp pool_pick(picks, chip), do: Enum.find(picks, &(pick_chips(&1) == [chip]))

  defp upgrade?({:chip, {:upgrade, _from, _to}}), do: true
  defp upgrade?(_action), do: false

  @doc """
  The buttons of a choice that are not chips ("Return all", "Done", "3 rubies").
  """
  def text_actions(actions), do: Enum.filter(actions, &(pick_chips(&1) == []))

  # The rungs of this seat's open ladder choices (`me.chip_choices`, the engine's
  # data); the legal ones come from `legal_actions/2`, the rest from the book.
  defp ladder(%Player{} = me, actions, game) do
    purple = Enum.count(Player.pot_chips(me), &match?({:purple, _}, &1))
    label = &action_label(&1, game, me)
    Enum.flat_map(me.chip_choices, &rungs(&1, me, purple, actions, label))
  end

  defp ladder(_me, _actions, _game), do: []

  defp rungs({:purple_trade, _tier}, _me, purple, actions, label) do
    for t <- 1..3 do
      action = {:chip, {:purple_trade, t}}

      %{
        action: action,
        label: label.(action),
        reason: if(action not in actions, do: "needs #{t} purple, you have #{purple}")
      }
    end
  end

  # Garden spider IV: one ruby per green chip on the last two spaces.
  defp rungs({:ruby_move, greens}, me, _purple, actions, label) do
    for k <- 1..2 do
      action = {:chip, {:pay_ruby_move, k}}

      %{
        action: action,
        label: label.(action),
        reason: ruby_reason(action in actions, k, greens, me)
      }
    end
  end

  # Ghost's breath IV: the swaps are chip picks; the tiers above the pot's purple
  # chips show here, greyed.
  defp rungs({:upgrade, tier}, _me, purple, _actions, _label) do
    book = Books.get({:purple, 4})

    for {{_label, text}, t} <- Enum.with_index(book.tiers, 1), t > tier do
      %{
        action: nil,
        label: "Ghost's breath: swap #{text}",
        reason: "needs #{t} purple, you have #{purple}"
      }
    end
  end

  defp rungs(_choice, _me, _purple, _actions, _label), do: []

  defp ruby_reason(true = _legal, _k, _greens, _me), do: nil

  defp ruby_reason(_legal, k, greens, _me) when k > greens,
    do: "needs #{k} green chips on the last two spaces, you have #{greens}"

  defp ruby_reason(_legal, k, _greens, me),
    do: "needs #{k} #{if k == 1, do: "ruby", else: "rubies"}, you have #{me.rubies}"

  # The board's colour order (`Chips.order/0`, white first), then value.
  defp chip_order(action), do: Enum.map(pick_chips(action), &Chips.sort_key/1)

  defp pick_title({:chip, {:gain, _chip}}, _card), do: "Garden spider: take one"

  defp pick_title({:chip, {:starter, _chip}}, _card),
    do: "Garden spider: start the next round with"

  defp pick_title({:chip, {:buy, _chips}}, _card), do: "Ghost's breath: take"
  defp pick_title({:chip, {:upgrade, _from, _to}}, _card), do: "Ghost's breath: swap"
  defp pick_title({:chip, {:return, _chip}}, _card), do: "Locoweed: return one to your bag"
  defp pick_title({:fortune, {:take, _chip}}, :p3), do: "Trade 1 ruby for one"
  defp pick_title({:fortune, {:take, _chip}}, _card), do: "Take one"
  defp pick_title({:essence, {:swap, _chip}}, _card), do: "Swap one"
  defp pick_title({:essence, {:buy, _chip}}, _card), do: "Buy one"
  defp pick_title(_action, _card), do: nil

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

  # Why the waiting droplet moves came (reverse pot side): this seat's log events that
  # moved its droplet since its last droplet choice (or the round's start).
  defp droplet_sources(log, seat) do
    log
    |> Enum.take_while(
      &(not match?({^seat, {:droplet, _}}, &1) and not match?({:round_end, _}, &1))
    )
    |> Enum.filter(fn
      {^seat, {:black, _}} -> true
      {^seat, {:bonus_die, :droplet}} -> true
      {^seat, {:purple, 3, _}} -> true
      {^seat, {:fortune, _id, :droplet}} -> true
      {^seat, {:essence_bonus, {:droplet, _}}} -> true
      _entry -> false
    end)
    |> Enum.reverse()
    |> Enum.map(fn {_seat, event} -> {cause(event), label(event)} end)
  end

  # What moved the droplet, as a picture: the chip of the book (a black chip for the
  # hawkmoth), the die, the card or the flask.
  defp cause({:black, _}), do: {:chip, {:black, 1}}
  defp cause({:purple, 3, _}), do: {:chip, {:purple, 1}}
  defp cause({:bonus_die, face}), do: {:die, face}
  defp cause({:fortune, _id, _outcome}), do: :card
  defp cause(_event), do: :essence

  attr :cause, :any, required: true

  defp droplet_cause(%{cause: {:chip, _chip}} = assigns),
    do: ~H"""
    <.chip chip={elem(@cause, 1)} data-role="droplet-cause" />
    """

  defp droplet_cause(%{cause: {:die, _face}} = assigns),
    do: ~H"""
    <span data-role="droplet-cause"><.die face={elem(@cause, 1)} /></span>
    """

  defp droplet_cause(assigns),
    do: ~H"""
    <span
      class="grid size-9 shrink-0 place-items-center rounded-full bg-parchment-deep"
      data-role="droplet-cause"
    >
      <.icon name="hero-sparkles" class="size-5" />
    </span>
    """

  @doc "What a Chicken eyes or Vampirism bonus asks for."
  def bonus_hint({:swap, 1, to}),
    do: "Chicken eyes: swap a 1-chip in your pot for a #{to}-chip of the same colour."

  def bonus_hint({:buy, coins}), do: "Vampirism: buy 1 chip for up to #{coins} coins."
  def bonus_hint(_pending), do: nil

  # The patient offer waiting now, for its dialog.
  defp offer_hint({:offers, [{:carrot, _} | _]}), do: "Carrot nose: you drew a pumpkin."

  defp offer_hint({:offers, [{kind, _} | _]}) when kind in [:wing, :wing_bowl],
    do: "Wing ears: you drew a white chip."

  defp offer_hint({:offers, [{:hump, chip} | _]}),
    do: "Witch's hump: a chip on a ruby space. Bonus: #{term_text(Alchemists.hump_bonus(chip))}."

  defp offer_hint(_pending), do: nil

  defp offer_chip({:offers, [{_kind, chip} | _]}), do: chip
  defp offer_chip(_pending), do: nil

  @doc "The witches that `actions` can call, for the decision dialog."
  @spec witches_acting(Game.t(), [Game.action()]) :: list
  def witches_acting(%{witches: nil}, _actions), do: []

  def witches_acting(game, actions) do
    for {colour, id} <- witches(game), calls(actions, colour) != [], do: id
  end

  @doc """
  A button label; G4 makes the rubies phase cost 1 ruby. The reverse pot side
  names the droplet ("pot droplet") and the next glass's bonus.
  """
  @spec action_label(Game.action(), Game.t(), Player.t()) :: String.t()
  def action_label({:rubies, what}, game, me) when what in [:droplet, :tube, :flask],
    do:
      "Spend #{if me.ruby_price == 1, do: "1 ruby", else: "2 rubies"}: #{ruby_use(what, game, me)}"

  def action_label({:droplet, :tube}, _game, me), do: "Test tube (#{next_glass(me)})"

  def action_label({:essence, :hump}, _game, %{essence_pending: {:offers, [{:hump, c} | _]}}),
    do: "Spend 2 essence: #{term_text(Alchemists.hump_bonus(c))}"

  def action_label({:essence, :pass}, _game, %{phase: :essence_offer}), do: "No"

  # The explosion's two answers, with what the scoring space pays.
  def action_label({:explosion_choice, :vp}, _game, me),
    do: "Take VP (+#{PotTrack.at(Player.scoring_index(me)).vp})"

  # Round 9 has no shop: the coins stay and convert to VP at the end (5 for 1).
  def action_label({:explosion_choice, :buy}, %Game{round: 9}, me),
    do: "Take coins (#{PotTrack.at(Player.scoring_index(me)).coins}, converted to VP at the end)"

  def action_label({:explosion_choice, :buy}, _game, me),
    do: "Take coins (#{PotTrack.at(Player.scoring_index(me)).coins} to spend)"

  def action_label(action, game, _me), do: label(action, game.fortune_card)

  defp ruby_use(:droplet, %{rules: %{pot_side: :back}}, _me), do: "pot droplet +1"
  defp ruby_use(:droplet, _game, _me), do: "droplet +1"
  defp ruby_use(:flask, _game, _me), do: "refill flask"

  defp ruby_use(:tube, _game, me), do: "test tube (#{next_glass(me)})"

  defp next_glass(me), do: "bonus: #{tube_bonus(TestTubes.bonus(me.tube + 1))}"
end
