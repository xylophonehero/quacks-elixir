defmodule QuacksWeb.TileDesignComponents do
  @moduledoc """
  The player tile redesign study: three options for the players row, gallery only
  (`/dev/gallery/tiles/redesign?option=a|b|c`). The game page does not use them.
  Each option draws the facts of `QuacksWeb.TileDesign.facts/3`, one map per seat.

  - **A, Ledger** (`ledger/1`): a parchment score sheet, one row per player with
    the name, what the player does now and the VP. One column up to 4 players, two
    from 5.
  - **B, Tokens** (`tokens/1`): one round token per player, always in one row: the
    initial on the seat colour, a fuse ring for the white sum, the last chip as a
    badge and the VP in a pill under it (a results step's news takes the pill's place). Names under the tokens up to 4 players.
  - **C, Race** (`lanes/1`): one lane per player: the name, the pot as a bar of the
    drawn chips (each chip as long as it moved the pot), the white sum and the VP.

  `peek/1` is the tap view for every option: one player's other facts, with words.
  """
  use Phoenix.Component

  import QuacksWeb.ChipComponents, only: [chip: 1]
  import QuacksWeb.Icons, only: [piece_icon: 1, patient_icon: 1]
  import QuacksWeb.TileComponents, only: [crown: 1, explosion_icon: 1]

  alias QuacksWeb.{TileDesign, TileRevealComponents}

  # -- A: the ledger -------------------------------------------------------------------

  @doc """
  Option A: a parchment score sheet, in seat order (from 5 players two columns, the
  first half left). A row: the seat colour stripe, the crown (round
  leader), the name (one line, cut with an ellipsis), the live slot (the last draws
  and the white sum while the round brews; else the news, or the pot space's coins),
  the state mark and the VP.
  """
  attr :facts, :list, required: true

  def ledger(assigns) do
    n = length(assigns.facts)
    cols = if n <= 4, do: 1, else: 2
    rows = div(n + cols - 1, cols)

    placed =
      assigns.facts
      |> Enum.with_index()
      |> Enum.map(fn {f, i} -> {f, rem(i, rows) + 1, div(i, rows) + 1} end)

    assigns = assign(assigns, placed: placed, cols: cols, wide: cols == 1)

    ~H"""
    <nav
      class="paper rounded-lg p-1 text-ink shadow-[0_2px_8px_rgb(0_0_0/0.45)]"
      aria-label="Players"
      data-role="tiles-a"
      data-columns={@cols}
    >
      <div
        class="grid gap-x-1 gap-y-0.5"
        style={"grid-template-columns: repeat(#{@cols}, minmax(0, 1fr))"}
      >
        <button
          :for={{f, row, col} <- @placed}
          type="button"
          class={[
            "relative flex min-w-0 items-center rounded-md pr-1 text-left touch-manipulation",
            if(@wide, do: "gap-1", else: "gap-0.5"),
            "transition-[background-color,scale] duration-150 ease-out active:scale-[0.98]",
            if(@wide, do: "h-9", else: "h-8"),
            row_bg(f),
            f.state == "stopped" && "opacity-60"
          ]}
          style={"grid-row: #{row}; grid-column: #{col}; " <> seat_var(f.seat)}
          title={f.name}
          data-role="tile"
          data-seat={f.seat}
          data-state={f.state}
          data-you={f.you && "true"}
        >
          <span
            class="relative w-1.5 shrink-0 self-stretch rounded-l-md bg-(--seat)"
            aria-hidden="true"
          >
            <span
              :if={f.bot and not @wide}
              class="hero-cpu-chip-micro absolute -bottom-0.5 -left-0.5 size-3 rounded-full bg-parchment text-ink-soft"
            />
          </span>
          <.crown
            :if={f.lead and not @wide}
            class="absolute -top-1.5 -left-1 size-3.5 drop-shadow-[0_0_2px_var(--color-gold)]"
          />
          <span class="flex min-w-0 flex-1 items-center gap-1">
            <.crown :if={f.lead and @wide} class="size-3.5 shrink-0" />
            <span
              class={[
                "truncate leading-tight",
                if(@wide, do: "text-label", else: "text-tag"),
                if(f.you, do: "font-bold", else: "font-semibold")
              ]}
              data-role="tile-name"
            >
              {f.name}
            </span>
            <span
              :if={f.you and @wide}
              class="shrink-0 rounded bg-gold-deep px-1 text-tag leading-4 font-bold text-parchment-light uppercase"
            >
              you
            </span>
            <span
              :if={f.bot and @wide}
              class="hero-cpu-chip-micro size-3 shrink-0 text-ink-soft"
              title="bot"
            />
            <.patient_mark :if={@wide && f.patient} patient={f.patient} />
            <span :if={f.you} class="sr-only">(you)</span>
          </span>
          <.live_slot f={f} max={if(@wide, do: 5, else: 1)} tone={:ink} />
          <.state_mark f={f} class="size-4" />
          <span
            class={[
              "flex shrink-0 items-center justify-end gap-px font-hand leading-none font-bold text-gold-deep tabular-nums",
              if(@wide, do: "min-w-[3.25rem] text-big", else: "min-w-[1.75rem] text-num")
            ]}
            title="VP"
            data-role="tile-vp"
          >
            <.piece_icon :if={@wide} name={:vp} class="size-3.5 shrink-0" />{f.vp}<span class="sr-only">VP</span>
          </span>
        </button>
      </div>
    </nav>
    """
  end

  defp row_bg(%{exploded: true}),
    do:
      "bg-[repeating-linear-gradient(135deg,rgb(216_50_43/0.24)_0_6px,rgb(216_50_43/0.12)_6px_12px)] ring-1 ring-ruby/60"

  defp row_bg(%{you: true}), do: "bg-gold/30 ring-1 ring-gold-deep/60"
  defp row_bg(_f), do: "bg-parchment-deep/50 hover:bg-parchment-deep"

  # -- B: the tokens -------------------------------------------------------------------

  @doc """
  Option B: one token per player in one row, at any player count. The disc has the
  initial on the seat colour; while the round brews a ring around it fills with the
  white sum against the limit (amber one before, red at it). The last chip drawn is a
  badge on the disc, the state mark on its top right, the crown over it. The VP is a
  gold pill under the disc; a results step's news (the shop's buys) takes its place. Up to 4 players the name is under it.
  """
  attr :facts, :list, required: true

  def tokens(assigns) do
    n = length(assigns.facts)
    assigns = assign(assigns, n: n, big: n <= 4)

    ~H"""
    <nav
      class="grid items-start justify-items-center gap-x-1 pt-2"
      style={"grid-template-columns: repeat(#{@n}, minmax(0, 1fr))"}
      aria-label="Players"
      data-role="tiles-b"
    >
      <button
        :for={f <- @facts}
        type="button"
        class={[
          "relative flex w-full min-w-0 flex-col items-center rounded-xl pt-1.5 pb-1 touch-manipulation",
          "transition-[background-color,scale,opacity] duration-150 ease-out active:scale-[0.96]",
          cond do
            f.exploded -> "bg-ruby/20 ring-1 ring-ruby/70"
            f.you -> "bg-gold/15 ring-1 ring-gold/80"
            true -> "hover:bg-black/20"
          end,
          f.state == "stopped" && "opacity-55"
        ]}
        style={seat_var(f.seat)}
        title={f.name}
        data-role="tile"
        data-seat={f.seat}
        data-state={f.state}
        data-you={f.you && "true"}
      >
        <span class="sr-only">{f.name}{if f.you, do: " (you)"}{if f.bot, do: ", bot"}</span>
        <span class={[
          "relative grid shrink-0 place-items-center",
          if(@big, do: "size-13", else: "size-[38px]")
        ]}>
          <svg viewBox="0 0 40 40" class="absolute inset-0 size-full -rotate-90" aria-hidden="true">
            <circle cx="20" cy="20" r="18" fill="none" stroke="rgb(0 0 0 / 0.45)" stroke-width="3.5" />
            <circle
              :if={f.brewing and (f.white > 0 or f.exploded)}
              cx="20"
              cy="20"
              r="18"
              fill="none"
              stroke={level_colour(f.level)}
              stroke-width="3.5"
              stroke-linecap="round"
              pathLength="100"
              stroke-dasharray={"#{fuse(f)} 100"}
              data-role="tile-fuse"
            />
          </svg>
          <span
            class={[
              "grid place-items-center rounded-full bg-(--seat) font-hand leading-none font-bold text-ink ring-1 ring-black/50",
              if(@big, do: "size-10 text-big", else: "size-7 text-num"),
              f.exploded && "grayscale-[0.7] brightness-75"
            ]}
            aria-hidden="true"
          >
            {f.initial}
          </span>
          <.crown
            :if={f.lead}
            class="absolute -top-2.5 left-1/2 size-4 -translate-x-1/2 drop-shadow-[0_0_3px_var(--color-gold)]"
          />
          <span
            :if={f.bot}
            class="absolute -top-0.5 -left-1 grid size-4 place-items-center rounded-full bg-iron-dark ring-1 ring-parchment/30"
            title="bot"
          >
            <span class="hero-cpu-chip-micro size-3 text-parchment-dim" />
          </span>
          <.state_mark f={f} class="absolute -top-1 -right-1 size-4" />
          <span class="absolute -right-1.5 -bottom-1 z-10 flex" data-role="tile-badge">
            <.live_badge f={f} />
          </span>
        </span>
        <span
          class={[
            "relative z-10 -mt-1 flex items-center gap-px rounded-full bg-iron-dark px-1.5 leading-tight tabular-nums ring-1",
            if(f.news,
              do: "text-tag font-bold text-parchment-light ring-parchment/50",
              else: "font-hand font-bold text-gold ring-gold/40"
            ),
            if(@big, do: "text-num", else: "text-label")
          ]}
          title="VP"
          data-role="tile-vp"
        >
          <%= if f.news do %>
            <TileRevealComponents.tile_news items={Enum.take(f.news.items, if(@big, do: 2, else: 1))} />
          <% else %>
            <.piece_icon :if={@big} name={:vp} class="size-3 shrink-0" />{f.vp}<span class="sr-only">VP</span>
          <% end %>
        </span>
        <span
          :if={@big}
          class={[
            "mt-0.5 max-w-full truncate px-1 text-tag leading-4",
            if(f.you, do: "font-bold text-gold", else: "text-parchment")
          ]}
          aria-hidden="true"
          data-role="tile-name"
        >
          {f.name}
        </span>
      </button>
    </nav>
    """
  end

  defp fuse(%{exploded: true}), do: 100
  defp fuse(%{white: white, limit: limit}), do: round(min(white / max(limit, 1), 1) * 100)

  defp level_colour("danger"), do: "var(--color-ruby)"
  defp level_colour("warn"), do: "#f0892a"
  defp level_colour("safe"), do: "var(--color-parchment-light)"

  attr :f, :map, required: true

  # Option B's badge: the newest pot chip while brewing (the news goes in the VP pill).
  defp live_badge(%{f: %{brewing: true, exploded: false, draws: [chip | _]}} = assigns) do
    assigns = assign(assigns, chip: chip)

    ~H"""
    <span class="rounded-full ring-1 ring-black/60" title="Last chip drawn">
      <.chip chip={@chip} size={:xs} />
    </span>
    """
  end

  defp live_badge(assigns), do: ~H""

  # -- C: the race ---------------------------------------------------------------------

  @doc """
  Option C: one lane per player, the round as a race. The name column, then the pot
  as a bar from the droplet: one segment per pot chip in the chip's colour, as long as
  the chip moved the pot (white chips pale), with the newest chip at the head. The
  furthest pot wears the crown (the bonus die). Then the white sum (while brewing;
  else the pot space's coins) and the VP. An exploded pot greys out, its head bursts.
  """
  attr :facts, :list, required: true

  def lanes(assigns) do
    n = length(assigns.facts)
    assigns = assign(assigns, big: n <= 4, scale: TileDesign.race_scale(assigns.facts))

    ~H"""
    <nav
      class="rounded-lg bg-black/30 p-1 ring-1 ring-parchment/10"
      aria-label="Players"
      data-role="tiles-c"
    >
      <ol class="space-y-0.5">
        <li :for={f <- @facts}>
          <button
            type="button"
            class={[
              "grid w-full items-center gap-1.5 rounded-md px-1 text-left touch-manipulation",
              "transition-[background-color,opacity] duration-150 ease-out",
              if(@big, do: "h-8", else: "h-[22px]"),
              cond do
                f.exploded -> "bg-ruby/15"
                f.you -> "bg-gold/15 ring-1 ring-gold/60"
                true -> "hover:bg-black/25"
              end,
              f.state == "stopped" && "opacity-55"
            ]}
            style={
              "grid-template-columns: #{if @big, do: "6.5rem", else: "5.25rem"} minmax(0, 1fr) 2rem 2.25rem; " <>
                seat_var(f.seat)
            }
            title={f.name}
            data-role="tile"
            data-seat={f.seat}
            data-state={f.state}
            data-you={f.you && "true"}
          >
            <span class="flex min-w-0 items-center gap-1">
              <.crown :if={f.lead} class="size-3 shrink-0" />
              <span
                :if={!f.lead}
                class="size-2.5 shrink-0 rounded-full bg-(--seat) ring-1 ring-black/40"
              />
              <span
                class={[
                  "truncate text-tag leading-4",
                  if(f.you, do: "font-bold text-gold", else: "font-semibold text-parchment-light")
                ]}
                data-role="tile-name"
              >
                {f.name}
              </span>
              <span
                :if={f.bot}
                class="hero-cpu-chip-micro size-3 shrink-0 text-parchment-dim"
                title="bot"
              />
              <.patient_mark :if={@big && f.patient} patient={f.patient} />
              <span :if={f.you} class="sr-only">(you)</span>
            </span>
            <span class="relative flex h-full min-w-0 items-center" data-role="tile-race">
              <span class={[
                "relative w-full rounded-full bg-parchment/10 ring-1 ring-black/40",
                if(@big, do: "h-2.5", else: "h-2")
              ]}>
                <span
                  :for={{chip, from, to} <- f.segments}
                  class={[
                    "absolute inset-y-0 border-r border-black/50",
                    segment_bg(chip),
                    f.exploded && "grayscale brightness-75"
                  ]}
                  style={"left: #{TileDesign.percent(from, @scale)}; width: calc(#{TileDesign.percent(to, @scale)} - #{TileDesign.percent(from, @scale)})"}
                />
                <span
                  class="absolute top-1/2 z-10 -translate-x-1/2 -translate-y-1/2"
                  style={"left: clamp(9px, #{TileDesign.percent(f.index - 1, @scale)}, calc(100% - 9px))"}
                  data-role="tile-head"
                >
                  <.race_head f={f} />
                </span>
              </span>
              <span
                :if={f.news}
                class="absolute inset-y-0 right-0 z-20 flex items-center gap-1 rounded bg-iron-dark/95 px-1 text-tag font-bold whitespace-nowrap tabular-nums"
              >
                <TileRevealComponents.tile_news items={
                  Enum.take(f.news.items, if(@big, do: 4, else: 2))
                } />
              </span>
            </span>
            <span class="flex justify-end">
              <.white_count :if={f.brewing} f={f} />
              <.state_mark :if={!f.brewing and f.state not in [nil, "shopping"]} f={f} class="size-4" />
              <.coins :if={!f.brewing and f.state in [nil, "shopping"]} n={f.coins} />
            </span>
            <span
              class="flex items-center justify-end font-hand text-num leading-none font-bold text-gold tabular-nums"
              title="VP"
              data-role="tile-vp"
            >
              {f.vp}<span class="sr-only">VP</span>
            </span>
          </button>
        </li>
      </ol>
    </nav>
    """
  end

  attr :f, :map, required: true

  defp race_head(%{f: %{exploded: true}} = assigns) do
    ~H"""
    <.explosion_icon class="size-5 drop-shadow-[0_0_2px_rgb(0_0_0/0.9)]" />
    """
  end

  defp race_head(%{f: %{draws: [chip | _]}} = assigns) do
    assigns = assign(assigns, chip: chip)

    ~H"""
    <span class={[
      "flex rounded-full ring-1 ring-black/60",
      @f.lead && "shadow-[0_0_6px_var(--color-gold)]"
    ]}>
      <.chip chip={@chip} size={:xs} />
    </span>
    """
  end

  defp race_head(assigns), do: ~H""

  defp segment_bg({:white, _}), do: "bg-chip-white/70"
  defp segment_bg({:orange, _}), do: "bg-chip-orange"
  defp segment_bg({:green, _}), do: "bg-chip-green"
  defp segment_bg({:blue, _}), do: "bg-chip-blue"
  defp segment_bg({:red, _}), do: "bg-chip-red"
  defp segment_bg({:yellow, _}), do: "bg-chip-yellow"
  defp segment_bg({:purple, _}), do: "bg-chip-purple"
  defp segment_bg({:black, _}), do: "bg-chip-black ring-1 ring-inset ring-penny-silver/70"
  defp segment_bg({:locoweed, _}), do: "bg-chip-locoweed"

  # -- the tap view --------------------------------------------------------------------

  @doc """
  The tap view of every option: one player's facts with words, on parchment. The
  head: the seat colour, the full name (cut with an ellipsis), you, bot, the start
  player and the state in words. Then the numbers in a grid; the pieces of the
  expansions and house rules only when they are on.
  """
  attr :f, :map, required: true

  def peek(assigns) do
    ~H"""
    <article
      class="paper space-y-1.5 rounded-lg border-t-4 border-(--seat) p-2 text-ink shadow-[0_2px_8px_rgb(0_0_0/0.45)]"
      style={seat_var(@f.seat)}
      data-role="tile-peek"
      data-seat={@f.seat}
    >
      <header class="flex min-w-0 items-center gap-1.5">
        <span class="grid size-6 shrink-0 place-items-center rounded-full bg-(--seat) font-hand text-label font-bold ring-1 ring-black/40">
          {@f.initial}
        </span>
        <span class="min-w-0 flex-1 truncate font-hand text-big font-bold">{@f.name}</span>
        <span
          :if={@f.you}
          class="shrink-0 rounded bg-gold-deep px-1 text-tag font-bold text-parchment-light uppercase"
        >
          you
        </span>
        <span
          :if={@f.bot}
          class="shrink-0 rounded bg-ink/10 px-1 text-tag font-bold text-ink-soft uppercase"
        >bot</span>
      </header>
      <p class="flex flex-wrap items-center gap-x-2 text-tag text-ink-soft">
        <span class="font-semibold text-ink" data-role="peek-state">{state_words(@f)}</span>
        <span :if={@f.lead} class="flex items-center gap-0.5"><.crown class="size-3.5" />rolls the bonus die</span>
        <span :if={@f.start} class="flex items-center gap-0.5">
          <span class="hero-flag-micro size-3.5" aria-hidden="true" />start player
        </span>
      </p>
      <dl class="grid grid-cols-4 gap-1 text-center">
        <.fact label="VP" value={@f.vp} icon={:vp} />
        <.fact label="Rubies" value={@f.rubies} icon={:ruby} />
        <.fact label="Droplet" value={@f.droplet} icon={:droplet} />
        <.fact label="Flask" value={if(@f.flask, do: "full", else: "used")} icon={:flask} />
        <.fact label="Pot space" value={"#{@f.coins} coins"} />
        <.fact label="White" value={"#{@f.white} / #{@f.limit}"} />
        <.fact :if={@f.show_black} label="Black" value={@f.black} />
        <.fact :if={@f.rats} label="Rat tails" value={@f.rats} icon={:rat} />
        <.fact :if={@f.tube} label="Test tube" value={@f.tube} icon={:tube} />
        <.fact :if={@f.essence} label="Essence" value={@f.essence} />
        <.fact :if={@f.pennies} label="Pennies" value={length(@f.pennies)} icon={:penny} />
      </dl>
      <p :if={@f.patient} class="flex items-center gap-1.5 text-tag" data-role="peek-patient">
        <span class="grid size-6 place-items-center rounded-full bg-parchment-deep ring-1 ring-ink/20">
          <.patient_icon id={@f.patient.id} class="size-4" />
        </span>
        Patient: <b>{@f.patient.name}</b>
      </p>
    </article>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :atom, default: nil

  defp fact(assigns) do
    ~H"""
    <div class="rounded-md bg-parchment-deep/70 px-1 py-0.5">
      <dt class="flex items-center justify-center gap-0.5 text-tag leading-tight text-ink-soft">
        <.piece_icon :if={@icon} name={@icon} class="size-3 shrink-0" />{@label}
      </dt>
      <dd class="truncate text-label font-semibold tabular-nums">{@value}</dd>
    </div>
    """
  end

  defp state_words(%{state: "brewing", draws: []}), do: "Has not drawn yet"
  defp state_words(%{state: "brewing", draws: d}), do: "Brewing: #{length(d)} chips in the pot"
  defp state_words(%{state: "exploded"}), do: "Exploded"
  defp state_words(%{state: "stopped"}), do: "Stopped"
  defp state_words(%{state: "shopping"}), do: "In the shop"
  defp state_words(%{state: "ready"}), do: "Ready"
  defp state_words(%{state: nil}), do: "Game over"
  defp state_words(%{state: state}), do: String.capitalize(state)

  # -- shared --------------------------------------------------------------------------

  attr :patient, :map, required: true

  # The Alchemists: the patient's face, small, after the name (where it fits).
  defp patient_mark(assigns) do
    ~H"""
    <span
      class="grid size-4 shrink-0 place-items-center rounded-full bg-parchment text-ink ring-1 ring-ink/30"
      title={@patient.name}
    >
      <.patient_icon id={@patient.id} class="size-3" />
      <span class="sr-only">patient {@patient.name}</span>
    </span>
    """
  end

  defp seat_var(seat), do: "--seat: var(--color-player-#{seat});"

  attr :f, :map, required: true
  attr :max, :integer, required: true, doc: "how many draws fit"
  attr :tone, :atom, default: :wood, doc: "`:ink` on parchment, `:wood` on the board"

  # The live slot: the news (a results step, the shop's buys) or, while the round
  # brews, the newest draws (newest first, the older ones dimmer) and the white sum;
  # else the pot space's coins.
  defp live_slot(%{f: %{news: %{items: items}}} = assigns) do
    assigns = assign(assigns, items: Enum.take(items, assigns.max + 1))

    ~H"""
    <span class="flex shrink-0 items-center gap-1 rounded bg-iron-dark/90 px-1 text-tag font-bold text-parchment-light tabular-nums">
      <TileRevealComponents.tile_news items={@items} />
    </span>
    """
  end

  defp live_slot(%{f: %{brewing: true}} = assigns) do
    assigns = assign(assigns, shown: Enum.take(assigns.f.draws, assigns.max))

    ~H"""
    <span class="flex shrink-0 items-center gap-1.5">
      <span
        :if={!@f.exploded}
        class="flex items-center gap-0.5"
        title="Last chips drawn, newest first"
      >
        <span
          :for={{chip, i} <- Enum.with_index(@shown)}
          class={["flex rounded-full ring-1 ring-black/40", i > 0 && "opacity-70"]}
        >
          <.chip chip={chip} size={:xs} />
        </span>
      </span>
      <.white_count f={@f} tone={@tone} />
    </span>
    """
  end

  defp live_slot(assigns) do
    ~H"""
    <.coins n={@f.coins} tone={@tone} />
    """
  end

  attr :f, :map, required: true
  attr :tone, :atom, default: :wood

  # The white sum against the limit ("4/7"), amber one point before, red at it.
  defp white_count(assigns) do
    ~H"""
    <span
      class={[
        "text-tag leading-none font-bold whitespace-nowrap tabular-nums",
        level_text(@f.level, @tone)
      ]}
      title={"White #{@f.white} of #{@f.limit}"}
      data-role="tile-white"
      data-level={@f.level}
    >
      {@f.white}<span class="opacity-60">/</span>{@f.limit}
    </span>
    """
  end

  defp level_text("danger", :ink), do: "text-ruby"
  defp level_text("danger", _wood), do: "text-ruby-light"
  defp level_text("warn", :ink), do: "text-[#b4580c]"
  defp level_text("warn", _wood), do: "text-[#f0892a]"
  defp level_text("safe", :ink), do: "text-ink-soft"
  defp level_text("safe", _wood), do: "text-parchment-light"

  attr :n, :integer, required: true
  attr :tone, :atom, default: :wood

  defp coins(assigns) do
    ~H"""
    <span
      class={[
        "flex items-center gap-0.5 text-tag leading-none font-bold tabular-nums",
        if(@tone == :ink, do: "text-ink-soft", else: "text-parchment-light")
      ]}
      title="Pot space: coins"
    >
      <.piece_icon name={:coin} class="size-3.5 shrink-0" />{@n}
    </span>
    """
  end

  attr :f, :map, required: true
  attr :class, :any, default: nil

  # The state mark: the burst after an explosion, a tick once stopped or ready, three
  # dots while choosing. Nothing while brewing (the live slot moves) or shopping.
  defp state_mark(%{f: %{state: "exploded"}} = assigns) do
    ~H"""
    <span class={["grid shrink-0 place-items-center", @class]} title="Exploded" data-role="tile-state">
      <.explosion_icon class="size-full drop-shadow-[0_0_2px_rgb(0_0_0/0.9)]" />
      <span class="sr-only">exploded</span>
    </span>
    """
  end

  defp state_mark(%{f: %{state: state}} = assigns) when state in ["stopped", "ready", "chosen"] do
    ~H"""
    <span
      class={[
        "grid shrink-0 place-items-center rounded-full bg-iron text-parchment ring-[1.5px] ring-iron-dark",
        @class
      ]}
      title={@f.state}
      data-role="tile-state"
    >
      <span class="hero-check-micro size-3" aria-hidden="true" />
      <span class="sr-only">{@f.state}</span>
    </span>
    """
  end

  defp state_mark(%{f: %{state: state}} = assigns)
       when state in [nil, "brewing", "shopping", "deciding"],
       do: ~H""

  defp state_mark(assigns) do
    ~H"""
    <span
      class={[
        "grid shrink-0 place-items-center rounded-full bg-parchment-deep text-ink ring-[1.5px] ring-iron-dark",
        @class
      ]}
      title={@f.state}
      data-role="tile-state"
    >
      <span class="hero-ellipsis-horizontal-micro size-3" aria-hidden="true" />
      <span class="sr-only">{@f.state}</span>
    </span>
    """
  end
end
