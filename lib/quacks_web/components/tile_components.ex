defmodule QuacksWeb.TileComponents do
  @moduledoc """
  The players: the players row as a ledger (players_ledger/1) with one row per
  seat (player_chip/1), a player's sheet (player_card/1, the row's tap view), the
  bot badge, the round leader's crown, what each seat does now (seat_state/2) and
  the results table (result_lines/1).
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
  One player at the table, read-only, for the player sheet (a tap on the player's
  row; round 48: the tap view of the round 46 study). The head: the seat colour,
  the initial, the full name (cut with an ellipsis), you, bot, then what they do
  now in words, the crown (rolls the bonus die) and the start player. Then the
  numbers in a grid: VP, rubies, droplet, flask, pot space, white sum, the black
  chips (black book I only), and rat tails, test tube, essence and witch pennies
  while their rule or expansion is on. Then their patient with its glasses (The
  Alchemists), their pot drawn small, their test-tube rack (reverse pot side),
  the bowl and what is in their bag (counts only).
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :name, :string, required: true
  attr :you, :boolean, default: false, doc: "this browser's own seat"
  attr :bot, :boolean, default: false

  def player_card(assigns) do
    %{game: game, seat: seat} = assigns
    p = game.players[seat]
    index = Player.scoring_index(p)

    assigns =
      assign(assigns,
        p: p,
        state: seat_state(game, seat),
        lead: seat in round_leaders(game),
        first: length(game.seats) > 1 and Game.start_seat(game) == seat,
        coins: PotTrack.at(index).coins,
        white: Game.white_sum(game, seat),
        limit: Potions.explode_above(game, seat),
        black: Enum.count(Player.pot_chips(p), &match?({:black, _}, &1)),
        pennies: Enum.count([:copper, :silver, :gold], &p.pennies[&1])
      )

    ~H"""
    <article
      class={["paper space-y-2 rounded-lg border-t-4 p-2 text-sm text-ink", seat_border(@seat)]}
      style={"--seat: var(--color-player-#{@seat});"}
      data-seat={@seat}
      data-role="player-card"
    >
      <header class="sheet-head flex min-w-0 items-center gap-1.5 pr-8">
        <span
          class="grid size-6 shrink-0 place-items-center rounded-full bg-(--seat) font-hand text-label font-bold ring-1 ring-black/40"
          aria-hidden="true"
        >
          {initial(@name)}
        </span>
        <span class="min-w-0 flex-1 truncate font-hand text-big font-bold" data-role="player-name">
          {@name}
        </span>
        <span
          :if={@you}
          class="shrink-0 rounded bg-gold-deep px-1 text-tag font-bold text-parchment-light uppercase"
        >
          you
        </span>
        <.bot_badge :if={@bot} class="shrink-0 bg-ink/10 text-ink-soft" />
        <.player_state game={@game} seat={@seat} />
      </header>
      <p class="flex flex-wrap items-center gap-x-2 text-tag text-ink-soft">
        <span
          :if={@p.exploded?}
          class="rounded bg-ruby px-1.5 font-bold text-white"
          data-role="exploded-badge"
        >
          {exploded_text(@p)}
        </span>
        <span :if={!@p.exploded?} class="font-semibold text-ink" data-role="peek-state">
          {state_words(@state, @p)}
        </span>
        <span :if={@lead} class="flex items-center gap-0.5">
          <.crown class="size-3.5" />rolls the bonus die
        </span>
        <span :if={@first} class="flex items-center gap-0.5">
          <span class="hero-flag-micro size-3.5" aria-hidden="true" />start player
        </span>
      </p>
      <dl class="grid grid-cols-4 gap-1 text-center">
        <.sheet_stat label="VP" value={@p.vp} icon={:vp} />
        <.sheet_stat label="Rubies" value={@p.rubies} icon={:ruby} />
        <.sheet_stat label="Droplet" value={@p.droplet} icon={:droplet} />
        <.sheet_stat label="Flask" value={flask_word(@p.flask)} icon={:flask} />
        <.sheet_stat label="Pot space" value={"#{@coins} coins"} />
        <.sheet_stat label="White" value={"#{@white} / #{@limit}"} />
        <.sheet_stat :if={black_counts?(@game)} label="Black" value={@black} />
        <.sheet_stat :if={@game.rules.rats} label="Rat tails" value={@p.rat_stone} icon={:rat} />
        <.sheet_stat
          :if={@game.rules.pot_side == :back}
          label="Test tube"
          value={@p.tube}
          icon={:tube}
        />
        <.sheet_stat :if={Game.expansion?(@game, :alchemists)} label="Essence" value={@p.essence} />
        <.sheet_stat :if={@game.witches} label="Pennies" value={@pennies} icon={:penny} />
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
        <h3 class="text-xs font-semibold text-ink-soft">
          In the bag: {length(shown_bag(@game, @seat))}
        </h3>
        <.chip_counts chips={shown_bag(@game, @seat)} id={"bag-counts-#{@seat}"} />
      </section>
    </article>
    """
  end

  defp state_words("brewing", %Player{drawn: []}), do: "Has not drawn yet"
  defp state_words("brewing", %Player{drawn: d}), do: "Brewing: #{length(d)} chips in the pot"
  defp state_words("stopped", _p), do: "Stopped"
  defp state_words("deciding", _p), do: "Deciding: draw or stop"
  defp state_words("chosen", _p), do: "Chose"
  defp state_words("droplet", _p), do: "Moving the droplet"
  defp state_words("shopping", _p), do: "In the shop"
  defp state_words("ready", _p), do: "Ready"
  defp state_words(nil, _p), do: "Game over"
  defp state_words(state, _p), do: String.capitalize(state)

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
  Round 48: the players row is a ledger (option A of the round 46 study): a
  parchment score sheet with one row per player (`player_chip/1`), in seat order,
  column by column (first half on the left). Columns: on a phone one up to 4
  players, two from 5; from 48rem two from 3 players; from 80rem three from 5
  (`ledger_columns/2`).
  """
  attr :count, :integer, required: true, doc: "the number of seats"
  attr :id, :string, default: "players-row"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def players_ledger(assigns) do
    ~H"""
    <nav
      id={@id}
      class={[
        "paper grid auto-cols-fr grid-flow-col gap-x-1 gap-y-0.5 rounded-lg p-1 text-ink shadow-[0_2px_8px_rgb(0_0_0/0.45)]",
        "grid-rows-(--rows) md:grid-rows-(--rows-md) xl:grid-rows-(--rows-xl)",
        @class
      ]}
      style={
        "--rows: #{ledger_rows(@count, :phone)}; --rows-md: #{ledger_rows(@count, :md)}; --rows-xl: #{ledger_rows(@count, :xl)}"
      }
      aria-label="Players"
      data-role="players-row"
      data-columns={ledger_columns(@count, :phone)}
      {@rest}
    >
      {render_slot(@inner_block)}
    </nav>
    """
  end

  @doc """
  The ledger's column count for `n` seats at a width: `:phone`, `:md` (48rem) or
  `:xl` (80rem).

      iex> for n <- [1, 2, 3, 4, 5, 8], do: QuacksWeb.TileComponents.ledger_columns(n, :phone)
      [1, 1, 1, 1, 2, 2]
      iex> for n <- [2, 3, 5, 8], do: QuacksWeb.TileComponents.ledger_columns(n, :xl)
      [1, 2, 3, 3]
  """
  @spec ledger_columns(pos_integer, :phone | :md | :xl) :: pos_integer
  def ledger_columns(n, :phone) when n <= 4, do: 1
  def ledger_columns(_n, :phone), do: 2
  def ledger_columns(n, _wide) when n <= 2, do: 1
  def ledger_columns(n, :md) when n > 2, do: 2
  def ledger_columns(n, :xl) when n <= 4, do: 2
  def ledger_columns(_n, :xl), do: 3

  defp ledger_rows(n, width) do
    cols = ledger_columns(n, width)
    "repeat(#{div(n + cols - 1, cols)}, auto)"
  end

  @doc """
  One player's row in the ledger (`players_ledger/1`), a button that opens the
  player's sheet (`sheet-player-N`). Left to right: the seat colour stripe, the
  crown (the round leader, `round_leaders/1`), the name (one line, cut with an
  ellipsis), YOU, the bot mark, the start player's flag, the patient (The
  Alchemists), this round's die faces (`rolls`), the live slot (`tile-line`), the
  state mark (`player_state/1`) and the VP.

  The live slot: while the round brews the seat's last draws (`news` with `hold`,
  `:sm` chips, as many as the row's width lets show, app.css `.tile-draw`) and
  the white sum against the limit; else the pot space's coins. A results step's
  news or the shop's buys swap in over the coins and back (app.css `.tile-line`).
  The tap view (the sheet) has the rubies, droplet, flask and the pieces of the
  expansions.

  A row of less than 15rem (two columns on a phone) has a smaller name and no YOU,
  bot, flag or patient marks (the title and screen-reader text keep them). An
  exploded seat: red stripes (`.tile-boom`); stopped: faded; yours: gold. During
  the replay the VP ticks on its beat (`updates`, `QuacksWeb.Replay.updates/2`).
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :name, :string, required: true
  attr :you, :boolean, default: false
  attr :bot, :boolean, default: false
  attr :lead, :boolean, default: false, doc: "the round leader: the crown"
  attr :updates, :list, default: [], doc: "the round's results, `Replay.updates/2`"

  attr :ticks, :boolean,
    default: false,
    doc: "while the replay runs: the VP ticks on its beat"

  attr :totals, :any,
    default: nil,
    doc: "`%{vp:, vp_from:}` in place of the seat's own, while the evaluation plays on the tiles"

  attr :news, :any, default: nil, doc: "`%{key:, items:}` for the live slot, or nil"
  attr :rolls, :list, default: [], doc: "this round's bonus die faces"

  def player_chip(assigns) do
    %{game: game, seat: seat} = assigns
    p = game.players[seat]
    state = seat_state(game, seat)
    white = Game.white_sum(game, seat)
    limit = Potions.explode_above(game, seat)

    assigns =
      assign(assigns,
        p: p,
        state: state,
        boom: p.exploded? and p.drawn != [],
        stopped: state == "stopped",
        brewing: game.phase == :potions,
        index: Player.scoring_index(p),
        white: white,
        limit: limit,
        level: white_level(p, white, limit),
        first: length(game.seats) > 1 and Game.start_seat(game) == seat,
        vp_tick: assigns.ticks && card_ticks(game, seat, assigns.updates)[:vp]
      )

    ~H"""
    <button
      type="button"
      popovertarget={"sheet-player-#{@seat}"}
      phx-click={JS.push("open_player", value: %{seat: @seat})}
      class={[
        "player-tile @container/row relative block w-full min-w-0 cursor-pointer rounded-md text-left touch-manipulation",
        "transition-[scale,background-color,opacity] duration-150 ease-out active:scale-[0.98]",
        cond do
          @boom -> "tile-boom ring-1 ring-ruby/60"
          @you -> "bg-gold/30 ring-1 ring-gold-deep/60"
          true -> "bg-parchment-deep/50 hover:bg-parchment-deep"
        end,
        @stopped && "opacity-55"
      ]}
      title={@name}
      data-seat={@seat}
      data-state={@state}
      data-role="player-chip"
      data-you={@you && "true"}
      data-lead={@lead && "true"}
      data-boom={@boom && "true"}
      data-stopped={@stopped && "true"}
    >
      <span class="sr-only" data-role="player-name">
        {@name}{if @you, do: " (you)"}{if @bot, do: ", bot"}
      </span>
      <span class="flex h-8 min-w-0 items-center gap-1 pr-1 @min-[15rem]/row:h-9">
        <span
          class={["w-1.5 shrink-0 self-stretch rounded-l-md", seat_bg(@seat)]}
          aria-hidden="true"
          data-role="seat-stripe"
        />
        <span class="flex min-w-6 flex-1 items-center gap-1" aria-hidden="true">
          <span
            :if={@lead}
            class="flex shrink-0"
            title="Round leader: rolls the bonus die"
            data-role="crown"
          >
            <.crown class="size-3.5" />
          </span>
          <span
            class={[
              "truncate text-tag leading-tight @min-[15rem]/row:text-label",
              if(@you, do: "font-bold", else: "font-semibold")
            ]}
            data-role="tile-name"
          >
            {@name}
          </span>
          <span
            :if={@you}
            class="hidden shrink-0 rounded bg-gold-deep px-1 text-tag leading-4 font-bold text-parchment-light uppercase @min-[15rem]/row:inline"
          >
            you
          </span>
          <span
            :if={@bot}
            class="hero-cpu-chip-micro hidden size-3 shrink-0 text-ink-soft @min-[15rem]/row:block"
            title="bot"
            data-role="bot-badge"
          />
          <span
            :if={@first}
            class="hero-flag-micro hidden size-3 shrink-0 text-ink-soft @min-[15rem]/row:block"
            title="Start player"
            data-role="tile-start"
          />
          <span
            :if={@p.patient}
            class="hidden size-4 shrink-0 place-items-center rounded-full bg-parchment text-ink ring-1 ring-ink/30 @min-[15rem]/row:grid"
            title={Alchemists.get(@p.patient).name}
            data-role="player-patient"
          >
            <.patient_icon id={@p.patient} class="size-3" />
          </span>
          <%!-- On the die step the faces come in as the news goes (`data-late`). --%>
          <span
            :if={@rolls != []}
            class="flex shrink-0 gap-px"
            data-role="tile-die"
            data-late={@news && Enum.any?(@news.items, &match?({:die, _}, &1)) && "true"}
          >
            <.die_face :for={face <- @rolls} face={face} class="size-3.5" />
          </span>
        </span>
        <span class="flex min-w-0 shrink items-center gap-1.5">
          <%!-- The news and the coins in one grid cell: the slot is as wide as the
               wider of the two, and the swap (app.css `.tile-line`) does not move
               the row. --%>
          <span
            id={"tile-line-#{@seat}" <> if(@news, do: "-" <> (@news[:line] || @news.key), else: "")}
            class="tile-line grid min-w-0 grid-cols-[minmax(0,auto)] items-center justify-items-end *:col-start-1 *:row-start-1"
            data-role="tile-line"
            data-news={@news && "true"}
            data-hold={@news && @news[:hold] && "true"}
          >
            <span class="tile-totals flex items-center" data-role="player-stats">
              <b
                :if={!@brewing}
                class="flex items-center gap-0.5 text-tag leading-none font-bold text-ink-soft tabular-nums"
                title="Pot space (coins)"
                data-role="player-space"
                data-index={@index}
              >
                <.piece_icon name={:coin} class="size-3.5 shrink-0" /><span
                  id={"tile-space-#{@seat}-#{@index}"}
                  class="tile-space"
                >{PotTrack.at(@index).coins}</span><span class="sr-only"> coins (pot space)</span>
              </b>
            </span>
            <span
              :if={@news}
              class={[
                "tile-news flex min-w-0 max-w-full items-center whitespace-nowrap text-tag font-bold tabular-nums",
                if(@news[:hold],
                  do: "gap-0",
                  else:
                    "gap-1.5 overflow-x-clip rounded bg-iron-dark/90 py-0.5 pr-1.5 pl-1 leading-5 text-parchment-light"
                )
              ]}
              data-role="tile-news"
            >
              <QuacksWeb.TileRevealComponents.tile_news items={@news.items} />
            </span>
          </span>
          <span
            :if={@brewing}
            class="flex shrink-0 items-center text-tag font-bold tabular-nums"
            data-role="tile-brew"
          >
            <span
              class={["leading-none whitespace-nowrap", white_text(@level)]}
              title={"White #{@white} of #{@limit}"}
              data-role="tile-white"
              data-level={@level}
            >
              {@white}<span class="opacity-60">/</span>{@limit}<span class="sr-only"> white</span>
            </span>
          </span>
        </span>
        <.player_state game={@game} seat={@seat} tile class="shrink-0" />
        <span
          class="flex min-w-[1.75rem] shrink-0 items-center justify-end gap-px font-hand text-num leading-none font-bold text-gold-deep tabular-nums @min-[15rem]/row:min-w-[3.25rem] @min-[15rem]/row:text-big"
          title="VP"
          data-role="player-vp"
        >
          <.piece_icon name={:vp} class="hidden size-3.5 shrink-0 @min-[15rem]/row:block" /><span data-role="vp-number"><.card_count
            :if={!@totals}
            value={@p.vp}
            tick={@vp_tick}
          /><span
            :if={@totals}
            id={"tile-vp-#{@seat}-#{@totals.vp}"}
            class="tile-count"
            style={"--n: #{@totals.vp}; --from: #{@totals.vp_from}"}
          ><span class="sr-only">{@totals.vp}</span></span></span><span class="sr-only">VP</span>
        </span>
      </span>
    </button>
    """
  end

  # The white sum's level: amber one point before the limit, red at it or after an
  # explosion (as the bar's fuse).
  defp white_level(%Player{exploded?: true}, _white, _limit), do: "danger"
  defp white_level(_p, white, limit) when white >= limit, do: "danger"
  defp white_level(_p, white, limit) when white == limit - 1, do: "warn"
  defp white_level(_p, _white, _limit), do: "safe"

  defp white_text("danger"), do: "text-ruby"
  defp white_text("warn"), do: "text-[#b4580c]"
  defp white_text("safe"), do: "text-ink-soft"

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

  @doc """
  Whether the black chips in a pot matter at the table: black book I (the base
  book) compares them, with the neighbours or (house rule) the standings. Black
  books II and III (The Herb Witches) do not compare pot counts.
  """
  @spec black_counts?(Game.t()) :: boolean
  def black_counts?(%Game{sets: sets}), do: Map.get(sets, :black, 1) == 1

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
