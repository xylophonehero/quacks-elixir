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

  import QuacksWeb.GameComponents,
    only: [
      book_info: 2,
      book_ink: 1,
      card_outcome: 2,
      chip: 1,
      die: 1,
      die_face: 1,
      seat_bg: 1,
      seat_dot: 1
    ]

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

  slot :podium,
    doc: "round 22: the game-over screen (podium, results, Play again) on the final podium slide"

  def reveal_overlay(assigns) do
    %{key: {kind, round}, slides: slides, index: index} = assigns.reveal

    assigns =
      assign(assigns,
        id: "reveal-#{kind}-#{round}",
        slide: Enum.at(slides, index),
        count: length(slides),
        last?: index == length(slides) - 1,
        card?: kind == :card,
        # Round 22: the game's last slide holds the game-over actions: no Next.
        actions?: kind == :final and index == length(slides) - 1 and assigns.podium != []
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
            @slide[:standings] not in [nil, []] and @slide.kind not in [:card, :podium, :standings]
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
        <%!-- A tap anywhere on the slide is Next (not on the game's last slide). --%>
        <div
          id="reveal-stage"
          class={[
            "reveal-stage flex flex-1 flex-col justify-center py-3",
            not @actions? && "cursor-pointer"
          ]}
          phx-click={not @actions? && "reveal_next"}
          data-role="reveal-stage"
          aria-live="polite"
        >
          <div
            id={"reveal-slide-#{@reveal.index}"}
            class="reveal-slide"
            data-role="reveal-slide"
            data-kind={@slide.kind}
          >
            {if @actions?, do: render_slot(@podium)}
            <.slide
              :if={not @actions?}
              slide={@slide}
              names={@names}
              seat={@seat}
              settled={Map.get(@reveal, :settled, true)}
            />
          </div>
        </div>
        <footer :if={not @actions?} class="flex gap-2 *:min-h-12" data-role="reveal-bar">
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
  defp title({:final, _}), do: "Final scoring"

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
        outcomes: Map.get(assigns.slide, :outcomes, [])
      )

    ~H"""
    <div class="text-center" data-role="reveal-card-name">
      <h2 class="font-hand text-2xl leading-tight font-bold">{@info.name}</h2>
      <p class="sr-only">{@info.text}</p>
      <ul :if={@outcomes != []} class="mt-2 space-y-1" data-role="card-outcomes">
        <li
          :for={outcome <- @outcomes}
          class="mx-auto w-fit rounded-full bg-ink/10 px-3 py-1 text-base font-semibold"
          data-role="card-outcome"
        >
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
            class="inline-flex items-center gap-1 text-xs font-bold tabular-nums"
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

  # Round 18: a real <table> (columns hold even without a utility class, see the
  # guide), the rows in VP order. The name may wrap; the update chips sit small
  # under it. The card, essence and witch lines wait in a closed "Details".
  defp slide(%{slide: %{kind: :results}} = assigns) do
    assigns =
      assign(assigns,
        colours: assigns.slide.rows |> List.first(%{pot: []}) |> Map.get(:pot) |> Keyword.keys(),
        extras: for(row <- assigns.slide.rows, line <- row.extra, do: {row.seat, line})
      )

    ~H"""
    <div class="space-y-2">
      <h2 class="text-center font-hand text-3xl leading-tight font-bold">
        Round {@slide.round} results
      </h2>
      <div class="max-h-[min(54dvh,30rem)] overflow-y-auto overscroll-contain">
        <table
          class="reveal-table w-full table-fixed border-collapse text-sm"
          data-role="reveal-results"
        >
          <colgroup>
            <col class="w-4" />
            <col />
            <col class="w-9" />
            <col class="w-7" />
            <col class="w-6" />
            <col class="w-7" />
            <col class={if length(@colours) > 3, do: "w-[6.5rem]", else: "w-20"} />
          </colgroup>
          <thead class="text-[10px] font-semibold tracking-tight text-ink-soft">
            <tr>
              <th scope="col"><span class="sr-only">Rank</span></th>
              <th scope="col" class="text-left">Player</th>
              <th scope="col" title="Coins">
                <.piece_icon
                  name={:coin}
                  class="inline size-4 text-gold drop-shadow-[0_0_0.75px_#7a5a10]"
                /><span class="sr-only">Coins</span>
              </th>
              <th scope="col" title="VP">
                <.piece_icon name={:vp} class="inline size-4 text-gold" /><span class="sr-only">VP</span>
              </th>
              <th scope="col" title="Ruby">
                <.piece_icon name={:ruby} class="inline size-3.5 text-ruby" /><span class="sr-only">Ruby</span>
              </th>
              <th scope="col" title="Bonus die">
                <.piece_icon name={:die} class="inline size-4" /><span class="sr-only">Bonus die</span>
              </th>
              <th scope="col" title="Chips in the pot">
                <span class="sr-only">Chips in the pot</span>
                <span class="inline-flex gap-2" aria-hidden="true">
                  <.ingredient_icon
                    :for={c <- @colours}
                    colour={c}
                    class={["size-3.5", book_ink(c)]}
                  />
                </span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={{row, i} <- Enum.with_index(@slide.rows)}
              class="reveal-row border-t border-ink/10 align-top"
              style={"--i: #{i}"}
              data-seat={row.seat}
              data-role="reveal-result"
            >
              <td class="py-1.5 font-hand text-base leading-5 text-ink-soft">{i + 1}</td>
              <td class="py-1.5 pr-1 text-left">
                <span class="flex items-start gap-1.5 leading-5 font-semibold">
                  <.seat_dot seat={row.seat} class="mt-1" />
                  <span class="min-w-0 break-words">{short_name(@names, row.seat, @seat)}</span>
                </span>
                <span :if={row.updates != []} class="mt-0.5 flex flex-wrap gap-0.5">
                  <span
                    :for={update <- row.updates}
                    class={[
                      "inline-flex items-center gap-0.5 rounded-full px-1 text-[10px] leading-4 font-bold",
                      update_class(update.kind)
                    ]}
                    data-kind={update.kind}
                  >
                    <.piece_icon
                      :if={update.kind in [:rubies, :droplet]}
                      name={if update.kind == :rubies, do: :ruby, else: :droplet}
                      class="size-2.5"
                    />
                    {short_update_text(update, row)}
                  </span>
                </span>
              </td>
              <td class="py-1.5 text-center leading-5 font-bold tabular-nums">{row.coins}</td>
              <td class="py-1.5 text-center leading-5 font-bold tabular-nums">{row.vp}</td>
              <td class="py-1.5 text-center leading-5">
                <.piece_icon :if={row.ruby} name={:ruby} class="inline size-3.5 text-ruby" />
                <span :if={!row.ruby} class="text-ink-soft">–</span>
              </td>
              <td class="py-1.5 text-center leading-5" data-role="reveal-die-cell">
                <%!-- Up to three faces in a column, no taller than two lines. --%>
                <span :if={row.die != []} class="inline-flex flex-col items-center gap-px">
                  <.die_face :for={face <- row.die} face={face} class={die_size(length(row.die))} />
                </span>
                <span :if={row.die == []} class="text-ink-soft">–</span>
              </td>
              <td class="py-1.5 text-center leading-5">
                <.pot_counts counts={row.pot} small />
              </td>
            </tr>
          </tbody>
        </table>
        <details :if={@extras != []} class="reveal-details mt-2 text-xs" data-role="reveal-details">
          <summary class="cursor-pointer py-1 font-semibold text-ink-soft">
            Details ({length(@extras)})
          </summary>
          <ul class="space-y-0.5 pb-1">
            <li
              :for={{s, line} <- @extras}
              class="flex items-start gap-1.5 leading-snug"
              data-role="reveal-extra"
            >
              <.seat_dot seat={s} class="mt-0.5" /><span>{line.text}</span>
            </li>
          </ul>
        </details>
      </div>
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

  defp slide(%{slide: %{kind: :final}} = assigns) do
    ~H"""
    <div class="space-y-3">
      <h2 class="text-center font-hand text-3xl leading-tight font-bold">Coins, rubies, pennies</h2>
      <ul class="space-y-1.5 text-sm" data-role="reveal-final">
        <li
          :for={{row, i} <- Enum.with_index(@slide.rows)}
          class="reveal-row space-y-0.5 rounded-md bg-parchment-deep/50 px-2 py-1.5"
          style={"--i: #{i}"}
          data-seat={row.seat}
        >
          <p class="flex items-center gap-1.5 font-semibold">
            <.seat_dot seat={row.seat} />
            <span class="min-w-0 flex-1 truncate">{short_name(@names, row.seat, @seat)}</span>
            <span class="font-hand text-lg tabular-nums">{row.vp} VP</span>
          </p>
          <p class="text-xs text-ink-soft">
            {row.coins} coins → {row.coins_vp} VP · {row.rubies} {if row.rubies == 1,
              do: "ruby",
              else: "rubies"} → {row.rubies_vp} VP<span :if={row.pennies_vp > 0}> · pennies {row.pennies_vp} VP</span>
          </p>
        </li>
      </ul>
    </div>
    """
  end

  defp slide(%{slide: %{kind: :podium}} = assigns) do
    ~H"""
    <div class="space-y-3 text-center">
      <h2 class="win-shimmer font-hand text-3xl leading-tight font-bold">
        {winner(@slide.ranked, @names, @seat)}
      </h2>
      <ol class="space-y-1.5 text-left" data-role="reveal-podium">
        <li
          :for={{{seat, vp, place}, i} <- Enum.with_index(@slide.ranked)}
          class={[
            "reveal-row flex items-center gap-2 rounded-md px-2 py-1.5",
            if(place == 1, do: "bg-gold/40 ring-1 ring-gold", else: "bg-parchment-deep/50")
          ]}
          style={"--i: #{length(@slide.ranked) - 1 - i}"}
          data-seat={seat}
          data-place={place}
        >
          <span class="w-5 font-hand text-lg font-bold">{place}</span>
          <span class={[
            "grid size-7 place-items-center rounded-full font-hand font-bold text-ink ring-1 ring-black/25",
            seat_bg(seat)
          ]}>
            {String.first(short_name(@names, seat, nil))}
          </span>
          <span class="min-w-0 flex-1 truncate font-semibold">
            {short_name(@names, seat, @seat)}
          </span>
          <.piece_icon :if={place == 1} name={:vp} class="size-5 text-gold" />
          <span class="font-hand text-xl font-bold tabular-nums">{vp} VP</span>
        </li>
      </ol>
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

  # The black, green and purple chips in a pot: an icon and a number each.
  attr :counts, :list, required: true, doc: "`[{colour, n}]`"
  attr :class, :any, default: nil
  attr :small, :boolean, default: false, doc: "the results table: tight, small icons"

  defp pot_counts(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1.5 text-xs font-semibold tabular-nums",
        @class
      ]}
      aria-label={Enum.map_join(@counts, ", ", fn {c, n} -> "#{n} #{c}" end)}
      data-role="reveal-pot"
    >
      <span
        :for={{colour, n} <- @counts}
        class={[
          "inline-flex items-center",
          if(@small, do: "gap-px", else: "gap-0.5"),
          n == 0 && "opacity-45"
        ]}
      >
        <.ingredient_icon
          colour={colour}
          class={[if(@small, do: "size-3", else: "size-4"), book_ink(colour)]}
        />{n}
      </span>
    </span>
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

  defp die_size(1), do: "size-5"
  defp die_size(2), do: "size-4"
  defp die_size(_n), do: "size-3"

  defp update_class(:exploded), do: "bg-ruby/15 text-ruby"
  defp update_class(:stopped), do: "bg-ink/10 text-ink-soft"
  defp update_class(:vp), do: "bg-gold/60"
  defp update_class(:rubies), do: "bg-ruby/15 text-ruby"
  defp update_class(:droplet), do: "bg-droplet/20"

  # An exploded seat's chip also says what it took.
  defp update_text(%{kind: :exploded}, %{choice: choice}) when choice in [:vp, :buy],
    do: "exploded: took the #{choice(choice)}"

  defp update_text(update, _row), do: update.text

  # The results table's chips are small: "exploded: coins".
  defp short_update_text(%{kind: :exploded}, %{choice: choice}) when choice in [:vp, :buy],
    do: "exploded: #{choice(choice)}"

  defp short_update_text(update, row), do: update_text(update, row)

  defp choice(:vp), do: "VP"
  defp choice(:buy), do: "coins"

  defp short_name(_names, seat, seat), do: "You"
  defp short_name(names, seat, _me), do: Map.get(names, seat, "Player #{seat + 1}")

  defp winner(ranked, names, me) do
    case for({seat, _vp, 1} <- ranked, do: seat) do
      [^me] -> "You win!"
      [seat] -> "#{short_name(names, seat, nil)} wins!"
      seats -> "#{Enum.map_join(seats, " and ", &short_name(names, &1, me))} share the win!"
    end
  end

  @doc """
  The menu's reveal settings, a form (`#reveal-settings`, event
  `"reveal_settings"`): Step or Auto, the speed and (not on a phone) where the
  results play. `RevealSettings` (app.js)
  keeps them in this browser and sends them on mount. With reduced motion only
  Step.
  """
  attr :mode, :atom, required: true, values: [:step, :auto]
  attr :speed, :atom, required: true, values: Reveal.speeds()
  attr :reduced, :boolean, default: false

  attr :show, :atom,
    default: :overlay,
    values: [:overlay, :tiles],
    doc: "round 27: the results in the overlay, or played on the tiles"

  attr :phone, :boolean,
    default: false,
    doc: "round 28: a phone always plays the results on the tiles; the Results choice hides"

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
      <input type="hidden" name="phone" value={to_string(@phone)} />
      <div :if={!@phone} data-role="reveal-show">
        <.segments
          name="show"
          legend="Results"
          value={@show}
          options={[overlay: "Overlay", tiles: "On tiles"]}
        />
      </div>
      <p :if={@phone} class="text-xs text-ink-soft" data-role="reveal-show-phone">
        Results: on the player tiles (phone).
      </p>
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
