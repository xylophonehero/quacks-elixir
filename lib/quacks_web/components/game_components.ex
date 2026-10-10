defmodule QuacksWeb.GameComponents do
  @moduledoc """
  Function components that draw a `Quacks.Game` struct. Rendering only: nothing in
  here changes game state. The LiveView passes the struct in; each component reads
  the fields it needs.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Quacks.AI.Odds
  alias Quacks.{Game, Player}
  alias Quacks.Game.Potions
  alias Quacks.Rules.{Alchemists, Books, Chips, PotTrack}
  alias Quacks.Rules.Fortune
  alias Quacks.Rules.Witches
  alias QuacksWeb.{AlchemistsComponents, Replay}

  import QuacksWeb.ChipComponents
  import QuacksWeb.GameText
  import QuacksWeb.PotComponents
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

      iex> QuacksWeb.GameComponents.seat_loop([0, 1, 2, 3, 4])
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

      iex> for {_seat, row, col} <- QuacksWeb.GameComponents.seat_loop([0, 1, 2, 3, 4]),
      ...>     do: QuacksWeb.GameComponents.loop_start(5, row, col)
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

  attr :class, :any, default: nil

  # Round 30: "explosion" is one red icon, the same in the bar's risk and on an
  # exploded tile.
  defp explosion_icon(assigns) do
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

  # Round 9 has no shop: its shopping phase is the final scoring (rubies, Done).
  defp round_phase_name(%Game{round: 9}, :shop), do: "Final scoring"
  defp round_phase_name(_game, phase), do: phase_name(phase)
end
