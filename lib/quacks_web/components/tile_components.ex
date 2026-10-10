defmodule QuacksWeb.TileComponents do
  @moduledoc """
  The players: one tile per seat in the players row (player_chip/1) in a fixed
  seat loop (seat_loop/1), a player's sheet (player_card/1), the bot badge, the
  round leader's crown, what each seat does now (seat_state/2) and the results
  table (result_lines/1).
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Quacks.{Game, Player}
  alias Quacks.Game.Potions
  alias Quacks.Rules.{Alchemists, PotTrack}
  alias QuacksWeb.{AlchemistsComponents, Replay}

  import QuacksWeb.ChipComponents
  import QuacksWeb.GameText
  import QuacksWeb.Icons
  import QuacksWeb.PotComponents

  @doc """
  Round 30: your ruby total as a small badge by the pot (top right). The scoring
  sequence's rubies fly to it (`PotMotion` in app.js, `#stat-rubies`) and it ticks
  on their beat. Round 30 removed the stats strip over the tiles: VP is on your tile
  and the rat track, the flask is drawn at the pot.
  """
  attr :rubies, :integer, required: true

  attr :beats, :map,
    default: %{},
    doc: "while the replay plays: `%{rubies: beat, from: %{rubies: n}}`"

  attr :class, :any, default: nil

  def ruby_badge(assigns) do
    ~H"""
    <dl
      class={[
        "flex h-8 items-center gap-0.5 rounded-full bg-iron-dark/85 py-0.5 pr-2.5 pl-1.5 text-parchment-light shadow-md ring-1 ring-parchment/20",
        @class
      ]}
      data-role="ruby-badge"
    >
      <.stat
        label="Rubies"
        value={@rubies}
        id="stat-rubies"
        icon={:ruby}
        beat={@beats[:rubies]}
        from={@beats[:rubies] && get_in(@beats, [:from, :rubies])}
      />
    </dl>
    """
  end

  defp flask_word(true), do: "full"
  defp flask_word(_empty), do: "empty"

  # B2: the crow skull protected the explosion. No explosion choice is made then.
  # S4: the silver witch took the penalty away.
  defp exploded_text(%Player{explosion_choice: :witch}), do: "Exploded (silver witch)"

  defp exploded_text(%Player{} = p) do
    if p.explosion_choice == nil and p.phase != :explosion_choice,
      do: "Exploded (protected)",
      else: "Exploded!"
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :atom, default: nil

  # A stat in a player sheet: a small label (with its icon) over the value.
  defp sheet_stat(assigns) do
    ~H"""
    <div class="rounded-md bg-parchment-deep/70 px-2 py-0.5">
      <.stat_label label={@label} icon={@icon} />
      <dd class="font-semibold leading-tight tabular-nums">{@value}</dd>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :icon, :atom, default: nil

  defp stat_label(assigns) do
    ~H"""
    <dt class="flex items-center gap-1 text-tag leading-tight text-ink-soft">
      <.piece_icon
        :if={@icon}
        name={@icon}
        class={["size-3.5", if(@icon == :ruby, do: "text-ruby", else: "text-ink-soft")]}
      />{@label}
    </dt>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :id, :string, required: true
  attr :icon, :atom, required: true, doc: "a `QuacksWeb.Icons.piece_icon/1` name"
  attr :beat, :integer, default: nil, doc: "the replay beat it ticks on (app.css)"
  attr :from, :integer, default: nil, doc: "with `beat`: the value it shows until then"

  # A number ticker: `--n` is a registered integer (app.css), so CSS counts it from
  # the old value to the new one and shows it with `counter(n)`. The inner span's id
  # holds the value: a new value is a new node, so it pops. Screen readers get the
  # word and the plain number.
  defp stat(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5" title={@label}>
      <dt class="flex">
        <.piece_icon name={@icon} class="size-5 text-ruby-light drop-shadow-sm" />
        <span class="sr-only">{@label}</span>
      </dt>
      <dd
        id={@id}
        class="stat-tick min-w-[1.2em] text-center font-hand text-num leading-none font-bold tabular-nums"
        style={"--n: #{@value}" <> beat_style(@beat, @from)}
        data-beat={@beat}
        data-from={@from}
      >
        <span class="sr-only">{@value}</span>
        <span id={"#{@id}-#{@value}"} class="stat-pop" aria-hidden="true"></span>
      </dd>
    </div>
    """
  end

  defp beat_style(nil, _from), do: ""
  defp beat_style(beat, nil), do: "; --beat: #{beat}"
  defp beat_style(beat, from), do: "; --beat: #{beat}; --from: #{from}"

  @doc """
  One player at the table, read-only, for the player detail sheet: name and VP up
  front (with a band in the seat colour), what they do now, rubies, flask, white
  sum, their patient with its glasses and essence (The Alchemists), their pot drawn small, their test-tube
  rack (reverse pot side), the bowl and what is in their bag (counts only).
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :name, :string, required: true
  attr :you, :boolean, default: false, doc: "this browser's own seat"

  def player_card(assigns) do
    assigns =
      assign(assigns, p: assigns.game.players[assigns.seat], border: seat_border(assigns.seat))

    ~H"""
    <article
      class={["paper space-y-2 rounded-lg border-t-4 p-2 text-sm", @border]}
      data-seat={@seat}
      data-role="player-card"
    >
      <header class="sheet-head flex flex-wrap items-center gap-1.5 pr-8">
        <.seat_dot seat={@seat} />
        <span class="font-hand text-lg font-bold" data-role="player-name">{@name}</span>
        <span :if={@you} class="text-xs font-semibold text-ink-soft">you</span>
        <.player_state game={@game} seat={@seat} />
        <span
          :if={@p.exploded?}
          class="rounded bg-ruby px-1.5 text-xs font-bold text-white"
          data-role="exploded-badge"
        >
          {exploded_text(@p)}
        </span>
      </header>
      <dl class="grid grid-cols-4 gap-1 text-center">
        <.sheet_stat label="VP" value={@p.vp} icon={:vp} />
        <.sheet_stat label="Rubies" value={@p.rubies} icon={:ruby} />
        <.sheet_stat label="Flask" value={if @p.flask, do: "full", else: "empty"} />
        <.sheet_stat
          label="White"
          value={"#{Game.white_sum(@game, @seat)} / #{Potions.explode_above(@game, @seat)}"}
        />
      </dl>
      <AlchemistsComponents.patient_panel
        :if={@p.patient}
        game={@game}
        seat={@seat}
        preview={@you}
      />
      <.pot game={@game} seat={@seat} size={:sm} class="mx-auto block h-auto w-full max-w-64" />
      <.test_tubes
        :if={@game.rules.pot_side == :back}
        id={"tubes-player-#{@seat}"}
        tube={@p.tube}
        class="mx-auto block h-auto w-full max-w-64"
      />
      <.bowl :if={@p.bowl != []} chips={@p.bowl} />
      <section aria-label="Bag" data-role="player-bag">
        <h3 class="text-xs font-semibold text-ink-soft">In the bag: {length(@p.bag)}</h3>
        <.chip_counts chips={@p.bag} />
      </section>
    </article>
    """
  end

  @doc """
  The small "bot" tag next to a bot's name. `compact` shows a chip icon instead of
  the word, for the tight players row.
  """
  attr :class, :any, default: "bg-ink/10 text-ink-soft"
  attr :compact, :any, default: false, doc: "true, or `:phone` for phones only"

  def bot_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center rounded px-1 text-tag leading-4 font-bold uppercase tracking-wide",
        @class
      ]}
      title="bot"
      data-role="bot-badge"
    >
      <%= case @compact do %>
        <% true -> %>
          <span class="hero-cpu-chip-micro size-3" aria-hidden="true"></span><span class="sr-only">bot</span>
        <% :phone -> %>
          <span class="hero-cpu-chip-micro size-3 sm:hidden" aria-hidden="true"></span><span class="max-sm:sr-only">bot</span>
        <% _ -> %>
          bot
      <% end %>
    </span>
    """
  end

  @doc """
  One player's tile in the players row (round 27, design B; slimmer in round 28),
  a button that opens the player's detail sheet (`sheet-player-N`). No name text:
  the seat disc has the initial (and a small bot icon), the full name is the
  tile's title and screen-reader text. Top line: the disc, this round's die faces
  (`rolls`), the pot space (its coins) and the VP, large. Bottom line
  (`tile-line`): rubies, the droplet, the flask (full or used), the black chips in
  the pot (only while black book I compares black chips, `black_counts?/1`), then
  rat tails, essence, test tube, patient or witch pennies while they fit (the line
  wraps into hidden overflow, so the tile never grows). With `news`
  (`QuacksWeb.TileReveal.news/3`) the bottom line swaps to the news and back.

  Badges, all absolute, so the tile never changes size: the state badge
  (`player_state/1`) on the top right corner, a **crown** on the disc for the
  round leader (`round_leaders/1`, the bonus die roller). States: exploded = red
  stripes (`.tile-boom`), stopped = faded, leader = a gold glow (`.tile-lead`).
  Your own tile has the gold border. `row` and `col` place the tile in the seat
  loop (`seat_loop/1`). During the replay VP and rubies tick on their beats
  (`updates`, `QuacksWeb.Replay.updates/2`).
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :name, :string, required: true
  attr :you, :boolean, default: false
  attr :bot, :boolean, default: false
  attr :lead, :boolean, default: false, doc: "the round leader: the crown"
  attr :row, :integer, default: 1
  attr :col, :integer, default: nil

  attr :start, :integer,
    default: nil,
    doc: "round 36: the first of the tile's 2 half columns (`loop_start/3`)"

  attr :updates, :list, default: [], doc: "the round's results, `Replay.updates/2`"

  attr :ticks, :boolean,
    default: false,
    doc: "while the replay runs: the counters tick on their beats"

  attr :totals, :any,
    default: nil,
    doc:
      "`%{vp:, rubies:, droplet:, vp_from:, rubies_from:}` in place of the seat's own, while the evaluation plays on the tiles"

  attr :news, :any, default: nil, doc: "`%{key:, items:}` for the bottom line, or nil"
  attr :rolls, :list, default: [], doc: "this round's bonus die faces, by the disc"

  def player_chip(assigns) do
    p = assigns.game.players[assigns.seat]
    state = seat_state(assigns.game, assigns.seat)

    assigns =
      assign(assigns,
        p: p,
        bg: seat_bg(assigns.seat),
        state: state,
        boom: p.exploded? and p.drawn != [],
        stopped: state == "stopped",
        brewing: assigns.game.phase == :potions
      )

    ~H"""
    <button
      type="button"
      popovertarget={"sheet-player-#{@seat}"}
      phx-click={JS.push("open_player", value: %{seat: @seat})}
      class={[
        "player-tile @container/tile relative flex h-[3.25rem] w-full min-w-0 cursor-pointer flex-col justify-center gap-0.5 rounded-[9px] px-1 text-left max-sm:px-0.5 touch-manipulation",
        "transition-[scale,background-color,opacity] duration-150 ease-out active:scale-[0.97]",
        if(@you,
          do: "border-2 border-gold bg-gold/15",
          else: "border border-parchment/12 bg-black/25 hover:bg-black/35"
        ),
        @boom && "tile-boom",
        @stopped && "opacity-55",
        @lead && "tile-lead"
      ]}
      style={"grid-row: #{@row}" <> if(@start, do: "; grid-column: #{@start} / span 2", else: "")}
      title={@name}
      data-seat={@seat}
      data-role="player-chip"
      data-you={@you && "true"}
      data-lead={@lead && "true"}
      data-boom={@boom && "true"}
      data-stopped={@stopped && "true"}
      data-row={@row}
      data-col={@col}
    >
      <span class="sr-only" data-role="player-name">
        {@name}{if @you, do: " (you)"}{if @bot, do: ", bot"}
      </span>
      <%!-- Round 28: no name text (the initial in the disc; the name is the
           tile's aria-label and title). Top line: the disc, the die faces this
           round (tiles mode), the pot space and the VP, large. --%>
      <span class="flex w-full min-w-0 items-center gap-0.5" data-role="tile-top">
        <span class="relative shrink-0">
          <span
            class={[
              "grid size-[18px] place-items-center rounded-full text-tag leading-none font-extrabold text-ink ring-1 ring-black/40",
              @bg
            ]}
            aria-hidden="true"
            data-role="seat-disc"
          >
            {initial(@name)}
          </span>
          <span
            :if={@lead}
            class="absolute -top-3 left-1/2 -translate-x-1/2 drop-shadow-[0_0_3px_var(--color-gold)]"
            title="Round leader: rolls the bonus die"
            data-role="crown"
          >
            <.crown class="size-3.5" />
            <span class="sr-only">round leader</span>
          </span>
          <span
            :if={@bot}
            class="hero-cpu-chip-micro absolute -right-1.5 -bottom-1 size-2.5 text-parchment-dim"
            aria-hidden="true"
            data-role="bot-badge"
          />
          <%!-- The die faces sit by the crown, on the tile's top edge, so the top
               line keeps its room. On the die step they come in as the news goes
               (`data-late`). --%>
          <span
            :if={@rolls != []}
            class="absolute -top-3 left-[calc(50%+0.4rem)] z-10 flex gap-px drop-shadow-[0_1px_2px_rgb(0_0_0/0.6)]"
            data-role="tile-die"
            data-late={@news && Enum.any?(@news.items, &match?({:die, _}, &1)) && "true"}
          >
            <.die_face :for={face <- @rolls} face={face} class="size-3.5" />
          </span>
        </span>
        <.chip_score
          p={@p}
          seat={@seat}
          ticks={@ticks && card_ticks(@game, @seat, @updates)}
          totals={@totals}
        />
      </span>
      <%!-- R2: the bottom line swaps to the step's news and back (app.css
           `.tile-line`); a new `news.key` plays the swap again. --%>
      <%!-- Round 31: while the round brews, the pot's black chips and white
           sum stay on the line's right end, beside the last draws. --%>
      <span
        id={"tile-line-#{@seat}" <> if(@news, do: "-" <> (@news[:line] || @news.key), else: "")}
        class="tile-line relative flex h-[18px] w-full min-w-0 items-center gap-[3px]"
        data-role="tile-line"
        data-news={@news && "true"}
        data-hold={@news && @news[:hold] && "true"}
      >
        <span class="relative h-full min-w-0 flex-1">
          <.chip_stats
            game={@game}
            p={@p}
            seat={@seat}
            totals={@totals}
            ticks={@ticks && card_ticks(@game, @seat, @updates)}
            show_black={!@brewing}
          />
          <span
            :if={@news}
            class="tile-news absolute inset-0 flex items-center gap-1 overflow-hidden text-tag font-bold whitespace-nowrap tabular-nums"
            data-role="tile-news"
          >
            <QuacksWeb.TileRevealComponents.tile_news items={@news.items} />
          </span>
        </span>
        <.tile_brew :if={@brewing} game={@game} p={@p} seat={@seat} />
      </span>
      <.player_state game={@game} seat={@seat} tile class="absolute -top-2.5 -right-1.5" />
    </button>
    """
  end

  @doc "The crown of the round leader (the bonus die roller), in gold."
  attr :class, :any, default: "size-3"

  def crown(assigns) do
    ~H"""
    <svg viewBox="0 0 12 12" class={@class} aria-hidden="true" data-icon="crown">
      <path
        d="M1 9.5h10L10 3 7.6 6 6 2 4.4 6 2 3z"
        fill="var(--color-gold)"
        stroke="var(--color-wood-dark)"
        stroke-width=".7"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  @doc """
  The round leaders: the seats with the furthest pot this round among the seats
  that did not explode (or whose explosion the silver witch took away), the seats
  that roll the bonus die (`Quacks.Game.Evaluation`). Empty before anyone has
  drawn a chip this round, and with one player.
  """
  @spec round_leaders(Game.t()) :: [Game.seat()]
  def round_leaders(%Game{seats: [_]}), do: []

  def round_leaders(%Game{seats: seats} = game) do
    candidates =
      Enum.filter(seats, fn seat ->
        p = Game.player(game, seat)
        not p.exploded? or p.explosion_choice == :witch
      end)

    if candidates == [] or Enum.all?(seats, &(Game.player(game, &1).drawn == [])) do
      []
    else
      best = candidates |> Enum.map(&Game.scoring_index(game, &1)) |> Enum.max()
      Enum.filter(candidates, &(Game.scoring_index(game, &1) == best))
    end
  end

  @doc """
  Where each seat's tile sits: `[{seat, row, col}]`, in seat order. The tiles form
  a fixed loop and never re-order. 2 to 4 seats: one row. 5 to 8 seats: two rows of
  `ceil(n / 2)` columns; the second row runs backwards and ends under the first
  row's last tile, so neighbours touch (8: `1 2 3 4 / 8 7 6 5`; 5: `1 2 3 / _ 5 4`).

      iex> QuacksWeb.TileComponents.seat_loop([0, 1, 2, 3, 4])
      [{0, 1, 1}, {1, 1, 2}, {2, 1, 3}, {3, 2, 3}, {4, 2, 2}]
  """
  @spec seat_loop([Game.seat()]) :: [{Game.seat(), pos_integer, pos_integer}]
  def seat_loop(seats) do
    cols = loop_columns(length(seats))

    seats
    |> Enum.with_index()
    |> Enum.map(fn
      {seat, i} when i < cols -> {seat, 1, i + 1}
      {seat, i} -> {seat, 2, 2 * cols - i}
    end)
  end

  @doc """
  Round 36: the players row has 2 half columns per column and each tile spans 2,
  so a short second row (5 or 7 seats) moves half a column to the left: it is
  centred under the first row, its tiles as wide as the first row's. This is the
  half column where the tile at `row`, `col` (`seat_loop/1`) of `n` seats starts.

      iex> for {_seat, row, col} <- QuacksWeb.TileComponents.seat_loop([0, 1, 2, 3, 4]),
      ...>     do: QuacksWeb.TileComponents.loop_start(5, row, col)
      [1, 3, 5, 4, 2]
  """
  @spec loop_start(pos_integer, pos_integer, pos_integer) :: pos_integer
  def loop_start(n, 2, col) when rem(n, 2) == 1, do: 2 * col - 2
  def loop_start(_n, _row, col), do: 2 * col - 1

  @doc "The players row's column count for `n` seats (`seat_loop/1`)."
  @spec loop_columns(pos_integer) :: pos_integer
  def loop_columns(n) when n <= 4, do: n
  def loop_columns(n), do: div(n + 1, 2)

  # While the replay runs: on which beat the card's VP and rubies tick, and from what.
  defp card_ticks(game, seat, updates) do
    from = Replay.before(game, seat)

    for %{kind: kind, beat: beat} <- updates,
        kind in [:vp, :rubies],
        into: %{},
        do: {kind, {beat, from[kind]}}
  end

  defp initial(name),
    do: name |> String.trim() |> String.first() |> Kernel.||("?") |> String.upcase()

  attr :value, :integer, required: true
  attr :tick, :any, default: nil, doc: "`{beat, from}` while the replay runs"

  # A count on a tile: a plain number, or during the replay a ticker that shows
  # the old value until its beat (the same CSS as the stats strip, `stat/1`).
  defp card_count(%{tick: {beat, from}} = assigns) do
    assigns = assign(assigns, beat: beat, from: from)

    ~H"""
    <span
      class="stat-tick"
      style={"--n: #{@value}; --beat: #{@beat}; --from: #{@from}"}
      data-beat={@beat}
      data-from={@from}
    ><span class="sr-only">{@value}</span><span class="stat-pop" aria-hidden="true"></span></span>
    """
  end

  defp card_count(assigns), do: ~H"{@value}"

  attr :p, Player, required: true
  attr :seat, :integer, required: true
  attr :ticks, :any, default: nil, doc: "`%{vp: {beat, from}, rubies: {beat, from}}`"
  attr :totals, :any, default: nil, doc: "see `player_chip/1`"

  # The tile's top line, right of the disc: the pot space (its coins) and the VP,
  # large (round 28).
  defp chip_score(assigns) do
    assigns = assign(assigns, index: Player.scoring_index(assigns.p))

    ~H"""
    <span
      class="flex min-w-0 flex-1 items-center justify-between gap-0.5 font-hand leading-none font-bold tabular-nums"
      data-role="player-score"
    >
      <b
        id={"tile-space-#{@seat}-#{@index}"}
        class="tile-space min-w-[1.2em] text-num leading-none text-parchment-light @max-[5.75rem]/tile:text-label"
        title="Pot space (coins)"
        data-role="player-space"
        data-index={@index}
      >
        {PotTrack.at(@index).coins}<span class="sr-only"> pot space</span>
      </b>
      <span
        class={[
          "flex items-center gap-px text-num leading-none tracking-tight text-gold @max-[5.75rem]/tile:text-label",
          @p.vp >= 100 && "max-sm:text-label"
        ]}
        title="VP"
        data-role="player-vp"
      >
        <.piece_icon name={:vp} class="size-3 shrink-0 text-gold" /><span
          class="min-w-[1.2em] pr-px text-right"
          data-role="vp-number"
        ><.card_count
          :if={!@totals}
          value={@p.vp}
          tick={@ticks && @ticks[:vp]}
        /><span
          :if={@totals}
          id={"tile-vp-#{@seat}-#{@totals.vp}"}
          class="tile-count"
          style={"--n: #{@totals.vp}; --from: #{@totals.vp_from}"}
        ><span class="sr-only">{@totals.vp}</span></span></span>
        <span class="sr-only">VP</span>
      </span>
    </span>
    """
  end

  attr :game, Game, required: true
  attr :p, Player, required: true
  attr :seat, :integer, required: true

  # Round 31 (item 8): while the round brews, the right end of a tile's bottom
  # line: the black chips in the pot and the white sum against the limit ("4/7",
  # `Potions.explode_above/2`; amber one point before the limit, red at it or
  # after an explosion, like `fuse_meter/1`). Compact, so 8 tiles fit at 360 px.
  defp tile_brew(assigns) do
    white = Game.white_sum(assigns.game, assigns.seat)
    limit = Potions.explode_above(assigns.game, assigns.seat)

    assigns =
      assign(assigns,
        black: Enum.count(Player.pot_chips(assigns.p), &match?({:black, _}, &1)),
        white: white,
        limit: limit,
        level:
          cond do
            assigns.p.exploded? or white >= limit -> "danger"
            white == limit - 1 -> "warn"
            true -> "safe"
          end
      )

    ~H"""
    <span
      class="flex shrink-0 items-center gap-[3px] text-tag font-semibold tabular-nums"
      data-role="tile-brew"
    >
      <span class="flex items-center gap-px" title="Black chips in the pot" data-role="tile-black">
        <span class="size-2 rounded-full bg-chip-black ring-1 ring-penny-silver" aria-hidden="true" />{@black}
        <span class="sr-only">black chips in the pot</span>
      </span>
      <span
        class={[
          "leading-none",
          case @level do
            "danger" -> "font-bold text-ruby-light"
            "warn" -> "font-bold text-[#f0892a]"
            "safe" -> "text-parchment-light"
          end
        ]}
        title={"White #{@white} of #{@limit}"}
        data-role="tile-white"
        data-level={@level}
      >
        {@white}<span class="text-parchment-dim">/</span>{@limit}<span class="sr-only"> white</span>
      </span>
    </span>
    """
  end

  @doc """
  Whether the black chips in a pot matter at the table: black book I (the base
  book) compares them, with the neighbours or (house rule) the standings. Black
  books II and III (The Herb Witches) do not compare pot counts.
  """
  @spec black_counts?(Game.t()) :: boolean
  def black_counts?(%Game{sets: sets}), do: Map.get(sets, :black, 1) == 1

  attr :game, Game, required: true
  attr :p, Player, required: true
  attr :seat, :integer, required: true
  attr :ticks, :any, default: nil, doc: "`%{vp: {beat, from}, rubies: {beat, from}}`"
  attr :totals, :any, default: nil, doc: "see `player_chip/1`"

  attr :show_black, :boolean,
    default: true,
    doc: "the black count (`tile_brew/1` has it while brewing)"

  # The tile's bottom line: rubies, the droplet, the flask (full or used), the black
  # chips in the pot (black book I only), this round's rat tails (rats on),
  # essence (The Alchemists), the test tube (reverse pot side), the patient or the
  # witch pennies (spent ones dim). One line high: what does not fit wraps into the
  # hidden overflow, the sheet has it all.
  defp chip_stats(assigns) do
    assigns =
      assign(assigns,
        black: Enum.count(Player.pot_chips(assigns.p), &match?({:black, _}, &1)),
        droplet: if(assigns.totals, do: assigns.totals.droplet, else: assigns.p.droplet)
      )

    ~H"""
    <span
      class="tile-totals flex h-[18px] w-full min-w-0 flex-wrap items-center gap-x-[3px] overflow-hidden text-tag font-semibold tabular-nums"
      data-role="player-stats"
    >
      <span class="flex items-center gap-px" title="Rubies" data-role="player-rubies">
        <.piece_icon name={:ruby} class="size-2.5 text-ruby-light" /><.card_count
          :if={!@totals}
          value={@p.rubies}
          tick={@ticks && @ticks[:rubies]}
        /><span
          :if={@totals}
          id={"tile-rubies-#{@seat}-#{@totals.rubies}"}
          class="tile-count"
          style={"--n: #{@totals.rubies}; --from: #{@totals.rubies_from}"}
        ><span class="sr-only">{@totals.rubies}</span></span>
        <span class="sr-only">rubies</span>
      </span>
      <span class="flex items-center gap-px" title="Droplet" data-role="player-droplet">
        <.piece_icon name={:droplet} class="size-2.5 text-droplet" />{@droplet}
        <span class="sr-only">droplet</span>
      </span>
      <span
        class="flex items-center"
        title={"Flask #{flask_word(@p.flask)}"}
        data-role="player-flask"
        data-flask={flask_word(@p.flask)}
      >
        <.piece_icon
          name={:flask}
          class={["size-2.5", if(@p.flask, do: "text-potion-light", else: "text-parchment-dim/50")]}
        />
        <span class="sr-only">flask {flask_word(@p.flask)}</span>
      </span>
      <span
        :if={@show_black and black_counts?(@game)}
        class="flex items-center gap-px"
        title="Black chips in the pot"
        data-role="player-black"
      >
        <span class="size-2 rounded-full bg-chip-black ring-1 ring-penny-silver" aria-hidden="true" />{@black}
        <span class="sr-only">black chips in the pot</span>
      </span>
      <span
        :if={@game.rules.rats and @p.rat_stone > 0}
        class="flex items-center gap-px"
        title="Rat tails"
        data-role="player-rats"
      >
        <.piece_icon name={:rat} class="size-3 text-parchment-dim" />{@p.rat_stone}
        <span class="sr-only">rat tails</span>
      </span>
      <span
        :if={Game.expansion?(@game, :alchemists)}
        class="flex items-center gap-px"
        title="Essence"
        data-role="player-essence"
      >
        <span class="hero-beaker-micro size-3 text-gold" aria-hidden="true" />{@p.essence}
        <span class="sr-only">essence</span>
      </span>
      <span
        :if={@game.rules.pot_side == :back}
        class="flex items-center gap-px"
        title="Test tube"
        data-role="player-tube"
      >
        <.piece_icon name={:tube} class="size-3 text-droplet" />{@p.tube}
        <span class="sr-only">test tube</span>
      </span>
      <span
        :if={@p.patient}
        class="grid size-4 place-items-center rounded-full bg-parchment text-ink"
        title={Alchemists.get(@p.patient).name}
        data-role="player-patient"
      >
        <.patient_icon id={@p.patient} class="size-3" />
        <span class="sr-only">patient {Alchemists.get(@p.patient).name}</span>
      </span>
      <span :if={@game.witches && !@p.patient} class="flex -space-x-1" data-role="player-pennies">
        <.piece_icon
          :for={colour <- [:copper, :silver, :gold]}
          name={:penny}
          class={["size-3", penny_text(colour), !@p.pennies[colour] && "opacity-30"]}
        />
        <span class="sr-only">
          witch pennies left: {Enum.count([:copper, :silver, :gold], &@p.pennies[&1])}
        </span>
      </span>
    </span>
    """
  end

  defp penny_text(:silver), do: "text-penny-silver"
  defp penny_text(:copper), do: "text-penny-copper"
  defp penny_text(:gold), do: "text-penny-gold"

  @doc """
  Round 30: "explosion" is one red icon, the same in the bar's risk and on an
  exploded tile.
  """
  attr :class, :any, default: nil

  def explosion_icon(assigns) do
    ~H"""
    <.piece_icon name={:explosion} class={["text-ruby", @class]} />
    """
  end

  # The status graphic (see `seat_state/2`): a steam wisp while brewing, a lid once
  # stopped, the 💥 explosion icon after an explosion, three dots while choosing, a tick when
  # ready. No word on screen: the word is for screen readers only. Everyone shops at
  # once, so the shop shows nothing. On a tile (`tile`, round 27, design B): nothing
  # while brewing, a check once stopped and the red explosion icon (round 30: the
  # same as the bar's risk, `explosion_icon/1`) after an explosion.
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :class, :any, default: nil
  attr :tile, :boolean, default: false
  attr :graphic, :atom, default: nil, doc: "a graphic in place of the state's own"

  defp player_state(%{tile: true} = assigns) do
    assigns = assign(assigns, state: seat_state(assigns.game, assigns.seat))

    ~H"""
    <span
      :if={@state == "exploded"}
      class={["grid size-4 shrink-0 place-items-center", @class]}
      title={exploded_text(@game.players[@seat])}
      data-role="player-state"
      data-state={@state}
    >
      <.explosion_icon class="size-4 drop-shadow-[0_0_2px_rgb(0_0_0/0.9)]" />
      <span class="sr-only">{@state}</span>
    </span>
    <.player_state
      :if={@state not in ["exploded", "brewing"]}
      game={@game}
      seat={@seat}
      class={@class}
      graphic={if(@state == "stopped", do: :tick)}
    />
    """
  end

  defp player_state(assigns) do
    assigns = assign(assigns, state: seat_state(assigns.game, assigns.seat))

    ~H"""
    <%!-- Round 31: an explosion is the 💥 burst here too, not a star in a dot. --%>
    <span
      :if={@state == "exploded"}
      class={["grid size-3.5 shrink-0 place-items-center sm:size-4", @class]}
      title={@state}
      data-role="player-state"
      data-state={@state}
    >
      <.explosion_icon class="size-full drop-shadow-[0_0_1px_rgb(0_0_0/0.9)]" />
    </span>
    <span
      :if={@state && @state not in ["shopping", "exploded"]}
      class={[
        "grid size-3.5 shrink-0 place-items-center rounded-full ring-[1.5px] ring-iron-dark sm:size-4",
        state_class(@state),
        @class
      ]}
      title={@state}
      data-role="player-state"
      data-state={@state}
    >
      <svg
        viewBox="0 0 16 16"
        class="size-2.5 sm:size-3"
        aria-hidden="true"
        fill="none"
        stroke="currentColor"
        stroke-width="1.6"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <%= case @graphic || state_graphic(@state) do %>
          <% :steam -> %>
            <path d="M5 14c-1.6-1.8 1.6-2.7 0-4.5S6.6 6.8 5 5M8.5 13c-1.6-1.8 1.6-2.7 0-4.5S10.1 5.8 8.5 4M12 14c-1.6-1.8 1.6-2.7 0-4.5" />
          <% :lid -> %>
            <path d="M2 12h12M3.2 12a4.8 4.4 0 0 1 9.6 0" /><circle
              cx="8"
              cy="6"
              r="1.3"
              fill="currentColor"
            />
          <% :dots -> %>
            <circle cx="3.5" cy="8" r="1.3" fill="currentColor" stroke="none" /><circle
              cx="8"
              cy="8"
              r="1.3"
              fill="currentColor"
              stroke="none"
            /><circle cx="12.5" cy="8" r="1.3" fill="currentColor" stroke="none" />
          <% :tick -> %>
            <path d="M3 8.5l3.2 3L13 4.5" />
        <% end %>
      </svg>
      <span class="sr-only">{@state}</span>
    </span>
    """
  end

  defp state_graphic("brewing"), do: :steam
  defp state_graphic("stopped"), do: :lid
  defp state_graphic(state) when state in ["ready", "chosen"], do: :tick
  defp state_graphic(_choosing), do: :dots

  @doc """
  What `seat` does now, in one word: "brewing", "stopped" or "exploded" while
  everyone brews (round 9 with 2+ players: "deciding" until the seat picks Draw or
  Stop, then "chosen"; "droplet" while it moves a droplet); "shopping" or "ready" in the shop; "choosing" or "ready"
  while seats answer a card, chip or witch choice; with The Alchemists "choosing
  patient" before round 1 and "essence" in the essence phase. `nil` once the game
  is over.
  """
  @spec seat_state(Game.t(), Game.seat()) :: String.t() | nil
  def seat_state(%Game{phase: :potions, players: players} = game, seat) do
    case players[seat] do
      %Player{droplet_moves: n} when n > 0 -> "droplet"
      %Player{exploded?: true} -> "exploded"
      %Player{phase: phase} when phase in [:stopped, :done] -> "stopped"
      %Player{phase: :waiting_stir} -> "chosen"
      _brewing when game.round == 9 and length(game.seats) > 1 -> "deciding"
      _brewing -> "brewing"
    end
  end

  def seat_state(%Game{phase: :shopping, players: players}, seat),
    do: if(players[seat].phase == :ready, do: "ready", else: "shopping")

  def seat_state(%Game{phase: :over}, _seat), do: nil

  def seat_state(%Game{phase: :patient_choice, players: players}, seat),
    do: if(players[seat].patient, do: "ready", else: "choosing patient")

  def seat_state(%Game{phase: :essence} = game, seat),
    do: if(Game.legal_actions(game, seat) == [], do: "ready", else: "essence")

  def seat_state(%Game{} = game, seat),
    do: if(Game.legal_actions(game, seat) == [], do: "ready", else: "choosing")

  defp state_class("brewing"), do: "bg-potion-deep text-parchment"
  defp state_class("exploded"), do: "bg-ruby text-white"

  defp state_class(state) when state in ["stopped", "ready", "chosen"],
    do: "bg-iron text-parchment"

  defp state_class(_state), do: "bg-parchment-deep text-ink"

  @doc """
  What `seat` gained this round, for its player sheet (the name card's update
  chips in full): every log entry since the round began that gave VP or rubies,
  plus the bonus die (its face) and the Fortune Teller card's outcome, then the
  totals. In round 9 also the final buying power (coins and rubies → VP; from the
  log once the seat is done, else from what it has now).
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true

  def result_lines(assigns) do
    assigns = assign(assigns, lines: Replay.beats(assigns.game, assigns.seat))

    ~H"""
    <section
      class="space-y-1 rounded-md bg-parchment-deep/60 px-2 py-1.5"
      aria-label="Round results"
      data-role="round-results"
      data-seat={@seat}
    >
      <h3 class="font-hand text-base font-bold">Round {@game.round} results</h3>
      <ul class="space-y-0.5 text-sm">
        <li
          :for={line <- @lines}
          data-role="result-line"
          data-kind={line.kind}
          class={line.face && "flex items-center gap-2"}
        >
          <.die :if={line.face} face={line.face} />
          <span>{line.text}</span>
        </li>
        <li :if={@lines == []} class="text-ink-soft">Nothing gained this round.</li>
      </ul>
      <p class="font-semibold" data-role="result-total">
        Total: +{total(@lines, :vp)} VP, +{total(@lines, :rubies)} {plural(
          total(@lines, :rubies),
          "ruby",
          "rubies"
        )}
      </p>
      <p
        :if={power = final_power(@game, @seat)}
        class="text-sm font-semibold"
        data-role="result-buying-power"
      >
        {power}
      </p>
    </section>
    """
  end

  defp total(lines, key), do: lines |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

  # Round 9: "Final buying power: ..." from the seat's conversion entry, or what its
  # coins and rubies will give now.
  defp final_power(%{round: 9} = game, seat) do
    entry =
      Enum.find_value(game.log, fn
        {^seat, {:final_conversion, _, _, _, _} = entry} -> entry
        _entry -> nil
      end)

    %{coins: coins, rubies: rubies} = game.players[seat]
    {_, coins, cvp, rubies, rvp} = entry || {nil, coins, div(coins, 5), rubies, div(rubies, 2)}

    "Final buying power: #{coins} coins → #{cvp} VP, #{rubies} #{plural(rubies, "ruby", "rubies")} → #{rvp} VP"
  end

  defp final_power(_game, _seat), do: nil
end
