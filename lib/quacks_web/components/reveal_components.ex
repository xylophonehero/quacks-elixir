defmodule QuacksWeb.RevealComponents do
  @moduledoc """
  The reveal overlay (round 14): one modal `<dialog>` (a bottom sheet on phones,
  centred from 64rem) that shows the slides of `QuacksWeb.Reveal`, one at a time,
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
    only: [book_info: 2, book_ink: 1, chip: 1, die: 1, fortune_card: 1, seat_bg: 1, seat_dot: 1]

  alias Phoenix.LiveView.JS
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
        last?: index == length(slides) - 1
      )

    ~H"""
    <.dialog_sheet
      id={@id}
      label={title(@reveal.key)}
      on_close={JS.push("reveal_close")}
      class="reveal-sheet"
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
            <.slide slide={@slide} names={@names} seat={@seat} />
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
  defp title({:final, _}), do: "Final scoring"

  attr :slide, :map, required: true
  attr :names, :map, required: true
  attr :seat, :integer, required: true

  defp slide(%{slide: %{kind: :card}} = assigns) do
    ~H"""
    <div class="space-y-3 text-center">
      <h2 class="font-hand text-3xl leading-tight font-bold">A new card</h2>
      <div class="reveal-card mx-auto w-full max-w-72">
        <.fortune_card id={@slide.card} flip />
      </div>
    </div>
    """
  end

  defp slide(%{slide: %{kind: :die}} = assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-3 text-center">
      <.who seat={@slide.seat} names={@names} me={@seat} />
      <h2 class="font-hand text-3xl leading-tight font-bold">Bonus die</h2>
      <div class="reveal-die" data-role="reveal-die"><.die face={@slide.face} /></div>
      <p class="reveal-after text-lg font-semibold">{@slide.text}</p>
      <%!-- A chip or droplet face says its reward in the line above. --%>
      <.rewards class="reveal-after" vp={@slide.vp} rubies={@slide.rubies} quiet />
    </div>
    """
  end

  defp slide(%{slide: %{kind: :book}} = assigns) do
    assigns = assign(assigns, book: book_info(assigns.slide.book, assigns.slide.set))

    ~H"""
    <div class="flex flex-col items-center gap-3 text-center">
      <.who seat={@slide.seat} names={@names} me={@seat} />
      <h2 class="flex items-center gap-2 font-hand text-3xl leading-tight font-bold">
        <span class="grid size-11 place-items-center rounded-full bg-parchment-deep/70">
          <.ingredient_icon colour={@slide.book} class={["size-7", book_ink(@slide.book)]} />
        </span>
        {@book.name}
      </h2>
      <ul
        :if={@slide.chips != []}
        class="flex flex-wrap justify-center gap-1.5"
        aria-label="The chips that count"
        data-role="reveal-chips"
      >
        <li
          :for={{chip, i} <- Enum.with_index(@slide.chips)}
          class="reveal-chip"
          style={"--i: #{i}"}
        >
          <.chip chip={chip} />
        </li>
      </ul>
      <ul
        :if={@slide.compare != []}
        class="flex flex-wrap justify-center gap-2 text-sm"
        aria-label="Black chips at the table"
        data-role="reveal-compare"
      >
        <li
          :for={{s, n} <- @slide.compare}
          class={[
            "flex items-center gap-1.5 rounded-full px-2.5 py-1 font-semibold",
            if(s == @slide.seat, do: "bg-ink text-parchment", else: "bg-parchment-deep/70")
          ]}
        >
          <.seat_dot seat={s} />{short_name(@names, s, @seat)}
          <span class="tabular-nums">{n}</span>
          <.ingredient_icon colour={:black} class="size-4" />
        </li>
      </ul>
      <p :for={line <- @slide.lines} class="reveal-after text-base font-semibold text-balance">
        {line}
      </p>
      <.rewards
        class="reveal-after"
        vp={@slide.vp}
        rubies={@slide.rubies}
        droplet={@slide.droplet}
      />
    </div>
    """
  end

  defp slide(%{slide: %{kind: :scoring}} = assigns) do
    ~H"""
    <div class="space-y-3">
      <h2 class="text-center font-hand text-3xl leading-tight font-bold">Scoring space</h2>
      <table class="w-full text-sm" data-role="reveal-scoring">
        <thead class="text-xs text-ink-soft">
          <tr>
            <th class="text-left font-semibold">Player</th>
            <th class="font-semibold">Space</th>
            <th class="font-semibold">Coins</th>
            <th class="font-semibold">VP</th>
            <th class="font-semibold">Ruby</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={{row, i} <- Enum.with_index(@slide.rows)}
            class="reveal-row border-t border-ink/10"
            style={"--i: #{i}"}
            data-seat={row.seat}
          >
            <td class="py-1.5">
              <span class="flex min-w-0 items-center gap-1.5 font-semibold">
                <.seat_dot seat={row.seat} />
                <span class="truncate">{short_name(@names, row.seat, @seat)}</span>
              </span>
              <span :if={row.exploded} class="text-xs text-ruby">
                exploded{if row.choice, do: ": took the #{choice(row.choice)}"}
              </span>
            </td>
            <td class="text-center tabular-nums">{row.space}</td>
            <td class="text-center font-bold tabular-nums">{row.coins}</td>
            <td class="text-center font-bold tabular-nums">{row.vp}</td>
            <td class="text-center">
              <.piece_icon :if={row.ruby} name={:ruby} class="inline size-5 text-ruby" />
              <span :if={!row.ruby} class="text-ink-soft">–</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp slide(%{slide: %{kind: :more}} = assigns) do
    ~H"""
    <div class="space-y-3">
      <h2 class="text-center font-hand text-3xl leading-tight font-bold">Also this round</h2>
      <ul class="space-y-1.5 text-sm">
        <li
          :for={{row, i} <- Enum.with_index(@slide.rows)}
          class="reveal-row flex items-center gap-2 rounded-md bg-parchment-deep/50 px-2 py-1.5"
          style={"--i: #{i}"}
          data-seat={row.seat}
        >
          <.seat_dot seat={row.seat} />
          <span class="min-w-0 flex-1 font-semibold">{row.text}</span>
          <.rewards vp={row.vp} rubies={row.rubies} small />
        </li>
      </ul>
    </div>
    """
  end

  defp slide(%{slide: %{kind: :summary}} = assigns) do
    ~H"""
    <div class="space-y-3">
      <h2 class="text-center font-hand text-3xl leading-tight font-bold">
        Round {@slide.round} summary
      </h2>
      <ul class="space-y-1.5 text-sm" data-role="reveal-summary">
        <li
          :for={{row, i} <- Enum.with_index(@slide.rows)}
          class="reveal-row flex flex-wrap items-center gap-1.5 rounded-md bg-parchment-deep/50 px-2 py-1.5"
          style={"--i: #{i}"}
          data-seat={row.seat}
        >
          <span class="flex min-w-0 flex-1 items-center gap-1.5 font-semibold">
            <.seat_dot seat={row.seat} />
            <span class="truncate">{short_name(@names, row.seat, @seat)}</span>
          </span>
          <span
            :for={update <- row.updates}
            class={[
              "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-bold",
              update_class(update.kind)
            ]}
            data-kind={update.kind}
          >
            <.piece_icon
              :if={update.kind in [:rubies, :droplet]}
              name={if update.kind == :rubies, do: :ruby, else: :droplet}
              class="size-3.5"
            />
            {update.text}
          </span>
        </li>
      </ul>
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

  # Whose slide it is: the seat dot and the name ("You" for this browser).
  attr :seat, :integer, required: true
  attr :names, :map, required: true
  attr :me, :integer, required: true

  defp who(assigns) do
    ~H"""
    <p class="flex items-center gap-1.5 text-sm font-semibold" data-role="reveal-who">
      <.seat_dot seat={@seat} />{short_name(@names, @seat, @me)}
    </p>
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

  defp update_class(:exploded), do: "bg-ruby/15 text-ruby"
  defp update_class(:stopped), do: "bg-ink/10 text-ink-soft"
  defp update_class(:vp), do: "bg-gold/60"
  defp update_class(:rubies), do: "bg-ruby/15 text-ruby"
  defp update_class(:droplet), do: "bg-droplet/20"

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
  `"reveal_settings"`): Step or Auto, and the speed. `RevealSettings` (app.js)
  keeps them in this browser and sends them on mount. With reduced motion only
  Step.
  """
  attr :mode, :atom, required: true, values: [:step, :auto]
  attr :speed, :atom, required: true, values: Reveal.speeds()
  attr :reduced, :boolean, default: false

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
