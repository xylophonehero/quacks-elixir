defmodule QuacksWeb.RevealComponents do
  @moduledoc """
  The reveal overlay (round 14): one modal `<dialog>` (full screen on phones since
  round 20, a bottom sheet on tablets, centred from 64rem) that shows the slides of `QuacksWeb.Reveal`, one at a time,
  with Skip and Next in a bar at its foot. A tap on the slide, Enter or Space also
  advance; Esc or × end the reveal. Rendering only: `QuacksWeb.GameLive` keeps the
  slide index (`reveal`) and answers `reveal_next`, `reveal_skip` and
  `reveal_close`.

  Also the menu's two reveal settings (`reveal_settings/1`): Step or Auto, and the
  speed. They live in this browser (`RevealSettings` in app.js).
  """
  use Phoenix.Component

  import QuacksWeb.CoreComponents, only: [button: 1, dialog_sheet: 1, kbd: 1]
  import QuacksWeb.Icons, only: [ingredient_icon: 1, piece_icon: 1]

  import QuacksWeb.GameComponents, only: [book_info: 2, book_ink: 1, chip: 1, die: 1, seat_dot: 1]

  import QuacksWeb.GameText, only: [card_outcome: 2]

  import QuacksWeb.CardRevealComponents, only: [card_reveals: 1]
  alias Phoenix.LiveView.JS
  alias Quacks.Rules.Fortune
  alias QuacksWeb.Reveal

  @doc """
  The overlay for `reveal` (`%{key, slides, index}`). Its id names the moment, so
  a new moment is a new dialog that opens itself; each slide has its own id, so
  its entrance plays once. In Auto mode a thin bar runs for the slide's time.
  """
  attr :reveal, :map, required: true
  attr :names, :map, required: true
  attr :seat, :integer, required: true
  attr :auto_ms, :integer, default: nil, doc: "the slide's time in Auto mode, nil in Step mode"
  attr :close_label, :string, default: "Close"

  def reveal_overlay(assigns) do
    %{key: {kind, round}, slides: slides, index: index} = assigns.reveal

    assigns =
      assign(assigns,
        id: "reveal-#{kind}-#{round}",
        slide: Enum.at(slides, index),
        count: length(slides),
        last?: index == length(slides) - 1,
        card?: kind == :card
      )

    ~H"""
    <.dialog_sheet
      id={@id}
      label={title(@reveal.key)}
      on_close={JS.push("reveal_close")}
      class={["reveal-sheet", @card? && "reveal-card-sheet"]}
    >
      <div class="flex min-h-full flex-col" data-role="reveal" data-kind={elem(@reveal.key, 0)}>
        <header class="flex items-center gap-2 pr-10">
          <p class="text-xs font-bold tracking-[0.14em] text-ink-soft uppercase">
            {title(@reveal.key)}
          </p>
          <p
            :if={@count > 1}
            class="ml-auto text-xs font-semibold text-ink-soft tabular-nums"
            data-role="reveal-count"
          >
            {@reveal.index + 1} / {@count}
          </p>
        </header>
        <ol :if={@count > 1} class="mt-1.5 flex gap-1" aria-hidden="true">
          <li
            :for={i <- 0..(@count - 1)}
            class={[
              "h-1 flex-1 rounded-full transition-colors duration-300",
              if(i <= @reveal.index, do: "bg-ink/70", else: "bg-ink/15")
            ]}
          />
        </ol>
        <.strip
          :if={
            @slide[:standings] not in [nil, []] and
              @slide.kind not in [:card, :standings]
          }
          rows={@slide.standings}
          names={@names}
          seat={@seat}
          index={@reveal.index}
        />
        <span
          :if={@auto_ms}
          id={"reveal-timer-#{@reveal.index}"}
          class="reveal-timer mt-1 block h-0.5 origin-left rounded-full bg-gold"
          style={"--slide-ms: #{@auto_ms}ms"}
          data-role="reveal-timer"
          aria-hidden="true"
        />
        <%!-- A tap anywhere on the slide is Next. --%>
        <div
          id="reveal-stage"
          class="reveal-stage flex flex-1 cursor-pointer flex-col justify-center py-3"
          phx-click="reveal_next"
          data-role="reveal-stage"
          aria-live="polite"
        >
          <div
            id={"reveal-slide-#{@reveal.index}"}
            class="reveal-slide"
            data-role="reveal-slide"
            data-kind={@slide.kind}
          >
            <.slide
              slide={@slide}
              names={@names}
              seat={@seat}
              settled={Map.get(@reveal, :settled, true)}
            />
          </div>
        </div>
        <footer class="flex gap-2 *:min-h-12" data-role="reveal-bar">
          <.button
            :if={not @last?}
            id="reveal-skip"
            phx-click="reveal_skip"
            variant={:secondary}
            class="flex-none"
          >
            Skip
          </.button>
          <.button
            id="reveal-next"
            phx-click="reveal_next"
            variant={:primary}
            class="flex-1 text-base"
            autofocus
          >
            {if @last?, do: @close_label, else: "Next"}
            <.kbd>Enter</.kbd>
          </.button>
        </footer>
      </div>
    </.dialog_sheet>
    """
  end

  defp title({:card, round}), do: "Round #{round}: the fortune teller"
  defp title({:results, round}), do: "Round #{round}: evaluation"

  attr :slide, :map, required: true
  attr :names, :map, required: true
  attr :seat, :integer, required: true
  attr :settled, :boolean, default: true, doc: "the standings show the new ranks"

  # Round 22: the card itself hovers over the pot (`GameLive`, `.pot-card`); the
  # sheet names it, and holds its text for screen readers (the page behind the
  # modal sheet is inert). Round 24: the sheet shows only after a tap, for a card
  # that did something to this seat: the list says what (`Reveal.card_outcomes/2`).
  defp slide(%{slide: %{kind: :card}} = assigns) do
    assigns =
      assign(assigns,
        info: Fortune.card(assigns.slide.card),
        outcomes: Map.get(assigns.slide, :outcomes, []),
        reveals: Map.get(assigns.slide, :reveals, %{})
      )

    ~H"""
    <div class="text-center" data-role="reveal-card-name">
      <h2 class="font-hand text-2xl leading-tight font-bold">{@info.name}</h2>
      <p class="sr-only">{@info.text}</p>
      <.card_reveals
        :if={@reveals != %{}}
        id={"reveal-card-reveals-#{@slide.round}"}
        card={@slide.card}
        reveals={@reveals}
        order={@slide.order}
        seat={@seat}
        names={@names}
        class="mt-2"
      />
      <ul
        :if={@outcomes != [] and @reveals == %{}}
        class="mt-2 space-y-1"
        data-role="card-outcomes"
      >
        <li
          :for={outcome <- @outcomes}
          class="mx-auto flex w-fit items-center gap-1.5 rounded-full bg-ink/10 px-3 py-1 text-base font-semibold"
          data-role="card-outcome"
        >
          <%!-- Round 30: a chip the card gave shows as its chip image too. --%>
          <.chip :if={match?({:take, _}, outcome)} chip={elem(outcome, 1)} size={:sm} />
          {card_outcome(outcome, @slide.card)}
        </li>
      </ul>
      <p class="mt-2 text-sm text-ink-soft" aria-hidden="true">
        It stays in the pot's corner: tap it to see it again.
      </p>
    </div>
    """
  end

  # Round 20: the evaluation's steps, one slide each with every seat on it, one row
  # per seat in VP order (`step_rows/1`). The bonus die: each seat's rolls side by
  # side, every die with its reward under it.
  defp slide(%{slide: %{kind: :die}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <.step_title>
        <:icon><.piece_icon name={:die} class="size-6" /></:icon>
        Bonus die
      </.step_title>
      <.step_rows :let={row} rows={@slide.rows} names={@names} seat={@seat} scored={&(&1.rolls != [])}>
        <span :if={row.rolls == []} class="text-ink-soft">–</span>
        <span :if={row.rolls != []} class="reveal-dice flex flex-wrap gap-2" data-role="reveal-dice">
          <span
            :for={{roll, n} <- Enum.with_index(row.rolls)}
            class="flex flex-col items-center gap-0.5"
            data-role="reveal-roll"
            title={roll.text}
          >
            <.die face={roll.face} />
            <span class="reveal-after flex"><.face_reward face={roll.face} /></span>
            <span class="sr-only">{roll.text}</span>
            <span :if={n > 2} class="sr-only">and more</span>
          </span>
        </span>
      </.step_rows>
    </div>
    """
  end

  # One book (black, green, purple, or another that paid): the chips that count as
  # small chips, black's targets ("vs" their black chips), the reward as tags.
  defp slide(%{slide: %{kind: :book}} = assigns) do
    assigns = assign(assigns, book: book_info(assigns.slide.book, assigns.slide.set))

    ~H"""
    <div class="space-y-2">
      <.step_title>
        <:icon>
          <.ingredient_icon colour={@slide.book} class={["size-6", book_ink(@slide.book)]} />
        </:icon>
        {@book.name}
      </.step_title>
      <.step_rows :let={row} rows={@slide.rows} names={@names} seat={@seat} scored={& &1.scored}>
        <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span
            class="inline-flex items-center gap-1.5 text-xs font-bold tabular-nums"
            aria-label={"#{length(row.chips)} counted"}
            data-role="reveal-chips"
          >
            <span
              :for={{chip, i} <- Enum.with_index(row.chips)}
              class="reveal-chip inline-flex"
              style={"--i: #{i}"}
            ><.chip chip={chip} size={:sm} /></span>
            <span :if={row.chips == []} class="text-ink-soft">0</span>
          </span>
          <span
            :if={row.compare != []}
            class="inline-flex items-center gap-1 text-xs text-ink-soft"
            aria-label="Compared with"
            data-role="reveal-compare"
          >
            vs
            <span :for={{s, n} <- row.compare} class="inline-flex items-center gap-0.5 font-semibold">
              <.seat_dot seat={s} />{n}
            </span>
          </span>
        </span>
        <:reward :let={row}>
          <.rewards vp={row.vp} rubies={row.rubies} droplet={row.droplet} small />
        </:reward>
        <:lines :let={row}>{Enum.join(row.lines, " · ")}</:lines>
      </.step_rows>
    </div>
    """
  end

  # The scoring space: coins, VP, and a ruby on the rows that landed on one.
  defp slide(%{slide: %{kind: :space}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <.step_title>
        <:icon><.piece_icon name={:cauldron} class="size-6" /></:icon>
        Scoring space
      </.step_title>
      <.step_rows :let={row} rows={@slide.rows} names={@names} seat={@seat} scored={fn _ -> true end}>
        <span
          class="inline-flex items-center gap-1 text-sm font-bold tabular-nums"
          data-role="reveal-coins"
        >
          <.piece_icon name={:coin} class="size-4 text-gold drop-shadow-[0_0_0.75px_#7a5a10]" />{row.coins}
          <span class="sr-only">coins</span>
          <span
            :if={row.exploded and row.choice in [:vp, :buy]}
            class="ml-1 rounded-full bg-ruby/15 px-1.5 text-[10px] leading-4 font-bold text-ruby"
          >
            exploded: {choice(row.choice)}
          </span>
        </span>
        <:reward :let={row}>
          <span class="inline-flex items-center gap-1">
            <span
              :if={row.rubies > 0}
              class="inline-flex items-center gap-1 rounded-full bg-ruby/15 px-1.5 text-xs font-bold text-ruby"
              data-role="reveal-ruby-landing"
            >
              <.piece_icon name={:ruby} class="size-3.5" /> +{row.rubies}
            </span>
            <.rewards vp={row.vp} small />
          </span>
        </:reward>
      </.step_rows>
    </div>
    """
  end

  # Round 18: the totals after the round. The rows stay in seat order in the DOM; each
  # row's `--rank` puts it in its slot (`transform`, app.css `.standings-row`). The
  # first render uses the old ranks and VP; the server's settle tick (GameLive,
  # 300 ms) sets the new ones, and CSS glides the rows and ticks the counters.
  defp slide(%{slide: %{kind: :standings}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <h2 class="text-center font-hand text-3xl leading-tight font-bold">Standings</h2>
      <div
        class="standings relative text-sm"
        style={"--rows: #{length(@slide.rows)}"}
        data-role="reveal-standings"
        data-settled={to_string(@settled)}
      >
        <ol class="absolute inset-y-0 left-0 w-5" aria-hidden="true">
          <li
            :for={i <- 1..length(@slide.rows)}
            class="standings-slot font-hand text-lg text-ink-soft"
          >
            {i}
          </li>
        </ol>
        <div
          :for={row <- @slide.rows}
          id={"standings-row-#{row.seat}"}
          class={["standings-row", row.seat == @seat && "ring-1 ring-gold"]}
          style={"--rank: #{if @settled, do: row.rank, else: row.from_rank}"}
          data-seat={row.seat}
          data-rank={if @settled, do: row.rank, else: row.from_rank}
          data-role="standings-row"
        >
          <.seat_dot seat={row.seat} />
          <span class="min-w-0 flex-1 truncate font-semibold">
            {short_name(@names, row.seat, @seat)}
          </span>
          <span
            :if={row.vp > row.from_vp}
            class="shrink-0 rounded-full bg-gold/50 px-1.5 text-xs font-bold tabular-nums"
          >
            +{row.vp - row.from_vp}
          </span>
          <span class="flex w-14 shrink-0 items-center justify-end gap-1 font-hand text-xl font-bold">
            <.piece_icon name={:vp} class="size-4 text-gold" /><.ticker value={
              if @settled, do: row.vp, else: row.from_vp
            } />
            <span class="sr-only">VP</span>
          </span>
          <span class="flex w-11 shrink-0 items-center justify-end gap-1 font-hand text-lg font-bold">
            <.piece_icon name={:ruby} class="size-3.5 text-ruby" /><.ticker value={
              if @settled, do: row.rubies, else: row.from_rubies
            } />
            <span class="sr-only">rubies</span>
          </span>
        </div>
      </div>
      <p :if={@slide.last} class="text-center text-sm text-ink-soft">
        Next: the final scoring.
      </p>
    </div>
    """
  end

  # The running results (round 16): one chip per seat in VP order, its VP so far and
  # what this slide added. A fixed height, so the slide does not move. Each slide
  # has its own ids, so the gain pops in once per slide.
  attr :rows, :list, required: true
  attr :names, :map, required: true
  attr :seat, :integer, required: true
  attr :index, :integer, required: true

  defp strip(assigns) do
    assigns = assign(assigns, compact: length(assigns.rows) > 4)

    ~H"""
    <ol
      class="mt-1.5 flex h-7 gap-1 overflow-hidden"
      aria-label="Results so far"
      data-role="reveal-strip"
    >
      <li
        :for={row <- @rows}
        id={"reveal-strip-#{@index}-#{row.seat}"}
        class={[
          "flex min-w-0 flex-1 items-center gap-1 rounded-full px-1.5 text-xs transition-colors",
          if(row.gain > 0, do: "bg-gold/45 ring-1 ring-gold", else: "bg-parchment-deep/70"),
          row.seat == @seat && "font-semibold"
        ]}
        data-seat={row.seat}
        data-vp={row.vp}
      >
        <.seat_dot seat={row.seat} />
        <span :if={!@compact} class="min-w-0 truncate">{short_name(@names, row.seat, @seat)}</span>
        <span class="ml-auto shrink-0 font-bold tabular-nums">{row.vp}</span>
        <span
          :if={row.gain > 0}
          class="reveal-gain shrink-0 font-bold text-ink tabular-nums"
          data-role="reveal-gain"
        >
          +{row.gain}
        </span>
      </li>
    </ol>
    """
  end

  # A step slide's title: the step's icon in a parchment disc, then its name.
  slot :icon, required: true
  slot :inner_block, required: true

  defp step_title(assigns) do
    ~H"""
    <h2 class="flex items-center justify-center gap-2 font-hand text-3xl leading-tight font-bold">
      <span class="grid size-10 shrink-0 place-items-center rounded-full bg-parchment-deep/70">
        {render_slot(@icon)}
      </span>
      {render_slot(@inner_block)}
    </h2>
    """
  end

  # The rows of a step slide (round 20), one per seat in the slide's order: the
  # name, the step's content (the inner block, given the row), the reward on the
  # right (or "–"). A seat that did not score in the step is dimmed.
  attr :rows, :list, required: true
  attr :names, :map, required: true
  attr :seat, :integer, required: true
  attr :scored, :any, required: true, doc: "row -> whether the seat scored in this step"
  slot :inner_block, required: true
  slot :reward
  slot :lines, doc: "the result lines, for screen readers and the row's title"

  defp step_rows(assigns) do
    ~H"""
    <ol class="space-y-1.5" data-role="reveal-step">
      <li
        :for={{row, i} <- Enum.with_index(@rows)}
        class={[
          "reveal-row flex min-h-11 items-center gap-2 rounded-md px-2 py-1.5",
          if(@scored.(row), do: "bg-parchment-deep/55", else: "bg-parchment-deep/25 text-ink-soft"),
          row.seat == @seat && "ring-1 ring-gold"
        ]}
        style={"--i: #{i}"}
        data-seat={row.seat}
        data-scored={to_string(@scored.(row))}
        data-role="reveal-step-row"
      >
        <span class="flex w-[5.5rem] shrink-0 items-center gap-1.5 text-sm font-semibold sm:w-28">
          <.seat_dot seat={row.seat} />
          <span class="min-w-0 truncate">{short_name(@names, row.seat, @seat)}</span>
        </span>
        <span class="min-w-0 flex-1">{render_slot(@inner_block, row)}</span>
        <span :if={@reward != []} class="reveal-after shrink-0" data-role="reveal-step-reward">
          <%= if @scored.(row) do %>
            {render_slot(@reward, row)}
          <% else %>
            <span class="px-1 text-ink-soft">–</span>
          <% end %>
        </span>
        <span :if={@lines != []} class="sr-only">{render_slot(@lines, row)}</span>
      </li>
    </ol>
    """
  end

  # The reward of one bonus die face, as a small tag.
  attr :face, :any, required: true

  defp face_reward(%{face: {:vp, n}} = assigns) do
    assigns = assign(assigns, n: n)

    ~H"""
    <span class={[tag(true), "bg-gold/60"]} data-reward="vp">+{@n} VP</span>
    """
  end

  defp face_reward(%{face: :ruby} = assigns) do
    ~H"""
    <span class={[tag(true), "bg-ruby/15 text-ruby"]} data-reward="rubies">
      <.piece_icon name={:ruby} class="size-3" />+1
    </span>
    """
  end

  defp face_reward(%{face: :droplet} = assigns) do
    ~H"""
    <span class={[tag(true), "bg-droplet/20"]} data-reward="droplet">
      <.piece_icon name={:droplet} class="size-3" />+1
    </span>
    """
  end

  defp face_reward(%{face: colour} = assigns) when is_atom(colour) do
    ~H"""
    <span class={[tag(true), "bg-parchment-deep"]} data-reward="chip">
      <.ingredient_icon colour={@face} class={["size-3", book_ink(@face)]} />+1
    </span>
    """
  end

  # A counter that ticks to its new value (`.stat-tick`, app.css: `--n` is a
  # registered integer, so a change of `--n` transitions and `counter()` shows it).
  attr :value, :integer, required: true

  defp ticker(assigns) do
    ~H"""
    <span class="stat-tick" style={"--n: #{@value}"} data-value={@value}><span class="sr-only">{@value}</span><span
      class="stat-pop"
      aria-hidden="true"
    ></span></span>
    """
  end

  # The gains of a slide as tags: VP, rubies, droplet steps. Nothing gained: "No reward".
  attr :vp, :integer, default: 0
  attr :rubies, :integer, default: 0
  attr :droplet, :integer, default: 0
  attr :small, :boolean, default: false
  attr :quiet, :boolean, default: false, doc: "no \"No reward\" when nothing is gained"
  attr :class, :any, default: nil

  defp rewards(assigns) do
    ~H"""
    <p
      class={["flex flex-wrap justify-center gap-1.5", @class]}
      data-role="reveal-rewards"
    >
      <span :if={@vp > 0} class={[tag(@small), "bg-gold/60"]} data-reward="vp">
        <.piece_icon name={:vp} class={icon(@small)} /> +{@vp} VP
      </span>
      <span :if={@rubies > 0} class={[tag(@small), "bg-ruby/15 text-ruby"]} data-reward="rubies">
        <.piece_icon name={:ruby} class={icon(@small)} />
        +{@rubies} {if @rubies == 1,
          do: "ruby",
          else: "rubies"}
      </span>
      <span :if={@droplet > 0} class={[tag(@small), "bg-droplet/20"]} data-reward="droplet">
        <.piece_icon name={:droplet} class={icon(@small)} /> droplet +{@droplet}
      </span>
      <span
        :if={@vp == 0 and @rubies == 0 and @droplet == 0 and not @small and not @quiet}
        class="text-sm text-ink-soft"
      >
        No reward
      </span>
    </p>
    """
  end

  defp tag(true), do: "inline-flex items-center gap-1 rounded-full px-1.5 text-xs font-bold"

  defp tag(false),
    do: "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-base font-bold"

  defp icon(true), do: "size-3.5"
  defp icon(false), do: "size-5"

  defp choice(:vp), do: "VP"
  defp choice(:buy), do: "coins"

  defp short_name(_names, seat, seat), do: "You"
  defp short_name(names, seat, _me), do: Map.get(names, seat, "Player #{seat + 1}")

  @doc """
  The menu's reveal settings, a form (`#reveal-settings`, event
  `"reveal_settings"`): Step or Auto, the speed, the risk beside the white meter
  (round 29: Off, Percent or Chips). `RevealSettings` (app.js)
  keeps them in this browser and sends them on mount. With reduced motion only
  Step.
  """
  attr :mode, :atom, required: true, values: [:step, :auto]
  attr :speed, :atom, required: true, values: Reveal.speeds()
  attr :reduced, :boolean, default: false

  attr :risk, :atom,
    default: :percent,
    values: [:off, :percent, :chips],
    doc: "round 29: the explosion risk beside the white meter"

  def reveal_settings(assigns) do
    ~H"""
    <form
      id="reveal-settings"
      class="space-y-2"
      phx-change="reveal_settings"
      phx-hook="RevealSettings"
      aria-label="Reveal settings"
    >
      <.segments
        name="mode"
        legend="Reveal"
        value={@mode}
        options={[step: "Step", auto: "Auto"]}
        disabled={if @reduced, do: [:auto], else: []}
      />
      <p :if={@reduced} class="text-xs text-ink-soft">Reduced motion: Step only.</p>
      <.segments
        name="speed"
        legend="Speed"
        value={@speed}
        options={[normal: "Normal", slow: "Slow", slower: "Slower"]}
      />
      <.segments
        name="risk"
        legend="Risk"
        value={@risk}
        options={[off: "Off", percent: "Percent", chips: "Chips"]}
      />
    </form>
    """
  end

  attr :name, :string, required: true
  attr :legend, :string, required: true
  attr :value, :atom, required: true
  attr :options, :list, required: true
  attr :disabled, :list, default: []

  defp segments(assigns) do
    ~H"""
    <fieldset class="text-sm">
      <legend class="mb-1 font-semibold">{@legend}</legend>
      <div class="segmented flex gap-1 rounded-lg bg-parchment-deep p-1">
        <label
          :for={{value, label} <- @options}
          class="relative flex min-h-10 flex-1 cursor-pointer items-center justify-center px-2 py-1 text-center leading-tight has-disabled:cursor-not-allowed has-disabled:opacity-50"
        >
          <input
            type="radio"
            id={"reveal-#{@name}-#{value}"}
            name={@name}
            value={value}
            checked={@value == value}
            disabled={value in @disabled}
            class="segment"
          />
          <span class="relative">{label}</span>
        </label>
      </div>
    </fieldset>
    """
  end
end
