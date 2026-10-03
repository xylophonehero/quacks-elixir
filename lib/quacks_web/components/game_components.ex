defmodule QuacksWeb.GameComponents do
  @moduledoc """
  Function components that draw a `Quacks.Game` struct. Rendering only: nothing in
  here changes game state. The LiveView passes the struct in; each component reads
  the fields it needs.
  """
  use Phoenix.Component

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Game.Potions
  alias Quacks.Rules.{Books, Chips, PotTrack}
  alias Quacks.Rules.Fortune
  alias Quacks.Rules.Witches

  @colours %{
    white: "bg-chip-white text-ink border-2 border-zinc-400",
    orange: "bg-chip-orange text-ink",
    green: "bg-chip-green text-ink",
    blue: "bg-chip-blue text-white",
    red: "bg-chip-red text-white",
    yellow: "bg-chip-yellow text-ink",
    purple: "bg-chip-purple text-white",
    black: "bg-chip-black text-white border border-iron",
    locoweed: "bg-chip-locoweed text-white"
  }

  # The witch penny colours, as background classes.
  @pennies %{silver: "bg-penny-silver", copper: "bg-penny-copper", gold: "bg-penny-gold"}

  # Seat colours (theme tokens `--color-seat-N`), as full class names so Tailwind
  # finds them in the source.
  @seat_bg %{
    0 => "bg-seat-0",
    1 => "bg-seat-1",
    2 => "bg-seat-2",
    3 => "bg-seat-3",
    4 => "bg-seat-4"
  }
  @seat_border %{
    0 => "border-seat-0",
    1 => "border-seat-1",
    2 => "border-seat-2",
    3 => "border-seat-3",
    4 => "border-seat-4"
  }

  # Chips with a light face get dark ink for their value (contrast >= 4.5:1).
  @light_chips [:white, :orange, :green, :yellow]

  # The spiral pot, laid out once at compile time. Space 0 sits in the centre;
  # spaces 1..53 sit `step` apart (arc length) on the Archimedean spiral
  # r = a + b·θ, which turns anticlockwise on screen like the board. The whole
  # spiral is then turned so space 53 ends at the upper right, by the spoon.
  # `b` gives 52 units between turns, enough for two 22-unit bubbles.
  spiral_a = 46
  spiral_b = 52 / (2 * :math.pi())
  step = 50
  d_theta = 0.001

  next_theta = fn theta ->
    {theta, 0.0}
    |> Stream.iterate(fn {t, len} ->
      r = spiral_a + spiral_b * t
      {t + d_theta, len + d_theta * :math.sqrt(r * r + spiral_b * spiral_b)}
    end)
    |> Enum.find(fn {_t, len} -> len >= step end)
    |> elem(0)
  end

  thetas = Enum.scan(2..PotTrack.last(), 0.0, fn _space, theta -> next_theta.(theta) end)
  turn = :math.pi() / 12 - List.last(thetas)

  positions =
    Enum.map([0.0 | thetas], fn theta ->
      r = spiral_a + spiral_b * theta
      {Float.round(r * :math.cos(theta + turn), 1), Float.round(-r * :math.sin(theta + turn), 1)}
    end)

  @positions List.to_tuple([{0.0, 0.0} | positions])
  @groove Enum.map_join([{0.0, 0.0} | positions], " ", fn {x, y} -> "#{x},#{y}" end)

  @doc """
  One chip: a coloured disc that shows its value.

  ## Examples

      <.chip chip={{:green, 2}} />
      <.chip chip={{:white, 1}} size={:sm} />
  """
  attr :chip, :any, required: true, doc: "a `{colour, value}` tuple"
  attr :size, :atom, default: :md, values: [:xs, :sm, :md]
  attr :rest, :global

  def chip(assigns) do
    {colour, value} = assigns.chip

    assigns =
      assign(assigns,
        colour: colour,
        value: value,
        colour_class: Map.get(@colours, colour, "bg-zinc-400 text-white")
      )

    ~H"""
    <span
      class={[
        "inline-flex shrink-0 items-center justify-center rounded-full font-bold tabular-nums",
        @size == :xs && "size-4 text-[9px]",
        @size == :sm && "size-6 text-xs",
        @size == :md && "size-9 text-sm",
        @colour_class
      ]}
      aria-label={"#{@colour} #{@value}"}
      {@rest}
    >
      {face(@chip)}
    </span>
    """
  end

  @doc """
  One seat's 54-space pot track, drawn as the board's cauldron: an inline SVG with
  the spaces on a spiral from the centre (space 0) out to the rim (space 53).

  `size={:lg}` (your own pot) shows each space's coins (top tag), victory points
  (lower tag) and a ruby gem. `size={:sm}` (another player's pot) shows only the
  chips. In both, the droplet is a blue drop on its space, placed chips sit on their
  spaces and the rat stone, when the player has one, is a grey pebble on its space.

  Scoring spaces (the space directly after the last chip) are rings in the seat
  colours. `rings` maps seat => scoring space; by default only this seat's ring
  shows. When seats share a space, the ring splits into one arc per seat.

  An exploded pot gets a red, cracked rim. `flask` (`:full` or `:empty`) draws the
  flask in the corner; with `flask_click` set it glows and a click sends it as the
  `"action"` event's value.

  The SVG scales to its box and keeps its shape, so `class="block size-full"` fits
  the whole pot into whatever space the page gives it. On phones the VP tags are too
  small to read and are left out; each space's `<title>` still names its VP.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0
  attr :size, :atom, default: :lg, values: [:sm, :lg]
  attr :class, :string, default: "block h-auto w-full"
  attr :rings, :map, default: nil, doc: "`%{seat => scoring index}`; nil: this seat only"
  attr :flask, :atom, default: nil, values: [nil, :full, :empty]
  attr :flask_click, :string, default: nil, doc: "the encoded `:use_flask` when legal"

  def pot(assigns) do
    player = assigns.game.players[assigns.seat]
    rings = assigns.rings || %{assigns.seat => Game.scoring_index(assigns.game, assigns.seat)}

    assigns =
      assign(assigns,
        me: player,
        chips_by_index: chips_by_index(player),
        rings_by_index: rings |> Enum.sort() |> Enum.group_by(&elem(&1, 1), &elem(&1, 0)),
        rat_index: if(player.rat_stone > 0, do: Player.start_index(player)),
        spaces: 0..PotTrack.last(),
        groove: @groove
      )

    ~H"""
    <svg
      viewBox="-268 -268 536 536"
      preserveAspectRatio="xMidYMid meet"
      class={[@class, "select-none"]}
      role="group"
      aria-label="Pot track"
      data-exploded={to_string(@me.exploded?)}
    >
      <defs>
        <radialGradient id={"brew-#{@seat}-#{@size}"}>
          <stop offset="0%" stop-color="var(--color-potion-light)" stop-opacity="0.55" />
          <stop offset="70%" stop-color="var(--color-potion)" />
          <stop offset="100%" stop-color="var(--color-potion-deep)" />
        </radialGradient>
      </defs>
      <%!-- the table under the pot --%>
      <rect x="-268" y="-10" width="536" height="278" rx="14" fill="var(--color-wood)" />
      <%!-- iron rim and the brew --%>
      <circle r="262" fill={if @me.exploded?, do: "#4a1210", else: "var(--color-iron-dark)"} />
      <circle
        r="250"
        fill={"url(#brew-#{@seat}-#{@size})"}
        stroke={if @me.exploded?, do: "var(--color-ruby)", else: "var(--color-iron)"}
        stroke-width="12"
      />
      <g :if={@me.exploded?} data-role="cracked-rim">
        <circle r="244" fill="var(--color-ruby)" fill-opacity="0.18" />
        <polyline
          points="-176,-190 -150,-168 -162,-146 -128,-124 -136,-104"
          fill="none"
          stroke="#2a0806"
          stroke-width="5"
          stroke-linejoin="round"
        />
        <polyline
          points="196,150 170,138 178,112 150,100"
          fill="none"
          stroke="#2a0806"
          stroke-width="4"
          stroke-linejoin="round"
        />
      </g>
      <%!-- the spiral groove the spaces sit in --%>
      <polyline
        points={@groove}
        fill="none"
        stroke="var(--color-potion-deep)"
        stroke-opacity="0.45"
        stroke-width="46"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <g :for={index <- @spaces} data-space={index} transform={translate(index)}>
        <title :if={@size == :lg}>{space_title(index)}</title>
        <circle
          r="22"
          fill="var(--color-potion-light)"
          stroke="var(--color-potion-deep)"
          stroke-width="2"
        />
        <g :if={@size == :lg}>
          <rect
            x="-13"
            y="-19"
            width="26"
            height="17"
            rx="2"
            fill="var(--color-parchment)"
            stroke="var(--color-ink-soft)"
            stroke-width="0.75"
          />
          <text
            y="-5.5"
            text-anchor="middle"
            font-size="14"
            font-weight="700"
            font-family="var(--font-hand)"
            fill="var(--color-ink)"
          >
            {PotTrack.at(index).coins}
          </text>
          <g :if={PotTrack.at(index).vp > 0} class="hidden sm:inline">
            <rect
              x="-9"
              y="1"
              width="18"
              height="15"
              rx="2"
              fill="var(--color-parchment-deep)"
              stroke="var(--color-ink-soft)"
              stroke-width="0.75"
            />
            <text
              y="13"
              text-anchor="middle"
              font-size="12.5"
              font-weight="700"
              fill="var(--color-ink)"
            >
              {PotTrack.at(index).vp}
            </text>
          </g>
          <path
            :if={PotTrack.at(index).ruby?}
            d="M14 -22 l6 4 -2 7 h-8 l-2 -7 z"
            fill="var(--color-ruby)"
            stroke="#7a1410"
            stroke-width="1"
            aria-label="ruby"
          />
        </g>
        <.pot_chip
          :if={Map.has_key?(@chips_by_index, index)}
          chip={@chips_by_index[index]}
          size={@size}
        />
        <.scoring_ring :if={@rings_by_index[index]} seats={@rings_by_index[index]} />
        <path
          :if={index == @me.droplet}
          d="M0 -11 C8 -1 8 7 0 7 C-8 7 -8 -1 0 -11 Z"
          transform="translate(-20 -13)"
          fill="var(--color-droplet)"
          stroke="white"
          stroke-width="1.5"
          aria-label="droplet"
        />
        <ellipse
          :if={index == @rat_index}
          cx="17"
          cy="16"
          rx="8"
          ry="6"
          fill="#8b9097"
          stroke="var(--color-iron-dark)"
          stroke-width="1.5"
          aria-label="rat stone"
          data-role="rat-stone"
        />
      </g>
      <.flask :if={@flask} full={@flask == :full} click={@flask_click} />
    </svg>
    """
  end

  # A scoring ring: one full circle, or one arc per seat when seats share the space.
  # `pathLength="100"` lets each arc be "100 / n" long whatever the radius.
  attr :seats, :list, required: true

  defp scoring_ring(assigns) do
    assigns = assign(assigns, arc: 100 / length(assigns.seats))

    ~H"""
    <circle
      :for={{seat, i} <- Enum.with_index(@seats)}
      r="26"
      fill="none"
      stroke={seat_colour(seat)}
      stroke-width="5"
      pathLength="100"
      stroke-dasharray={if length(@seats) > 1, do: "#{@arc - 3} #{103 - @arc}"}
      stroke-dashoffset={-@arc * i}
      transform="rotate(-90)"
      aria-label="scoring space"
      data-role="scoring-ring"
      data-seat={seat}
    />
    """
  end

  # The flask, in the free corner to the upper right of the cauldron. Parchment when
  # full, grey when empty. Usable: it glows and is a button (click or Enter).
  attr :full, :boolean, required: true
  attr :click, :string, default: nil

  defp flask(assigns) do
    ~H"""
    <g
      transform="translate(220 -212)"
      data-role="flask"
      data-usable={to_string(@click != nil)}
      class={@click && "flask-usable"}
      role={if @click, do: "button", else: "img"}
      tabindex={@click && "0"}
      aria-label={
        if @click,
          do: "Use flask: put the last white chip back in the bag",
          else: "Flask #{if @full, do: "full", else: "empty"}"
      }
      phx-click={@click && "action"}
      phx-keydown={@click && "action"}
      phx-key={@click && "Enter"}
      phx-value-action={@click}
    >
      <rect x="-32" y="-54" width="64" height="88" fill="transparent" />
      <rect x="-9" y="-50" width="18" height="10" rx="2" fill="var(--color-wood)" />
      <path
        d="M-7 -41 h14 v16 A25 25 0 1 1 -7 -25 Z"
        fill={if @full, do: "var(--color-parchment)", else: "#7d8288"}
        stroke="var(--color-iron-dark)"
        stroke-width="3"
        stroke-linejoin="round"
      />
      <ellipse cx="-9" cy="-4" rx="5" ry="9" fill="white" fill-opacity="0.35" />
    </g>
    """
  end

  @doc ~s{The CSS colour of a seat, e.g. "var(--color-seat-1)", for SVG fills.}
  @spec seat_colour(Game.seat()) :: String.t()
  def seat_colour(seat), do: "var(--color-seat-#{seat})"

  @doc "A small dot in the seat's colour, before a player's name."
  attr :seat, :integer, required: true

  def seat_dot(assigns) do
    assigns = assign(assigns, bg: @seat_bg[assigns.seat])

    ~H"""
    <span
      class={["inline-block size-2.5 shrink-0 rounded-full ring-1 ring-black/30", @bg]}
      data-role="seat-dot"
      data-seat={@seat}
    />
    """
  end

  attr :chip, :any, required: true
  attr :size, :atom, required: true

  defp pot_chip(assigns) do
    {colour, value} = assigns.chip
    ink = if colour in @light_chips, do: "var(--color-ink)", else: "white"
    assigns = assign(assigns, colour: colour, value: value, ink: ink)

    ~H"""
    <g data-role="pot-chip" aria-label={"#{@colour} #{@value}"}>
      <circle
        r="19"
        fill={"var(--color-chip-#{@colour})"}
        stroke={if @colour == :white, do: "#9a9a94", else: "rgb(0 0 0 / 0.4)"}
        stroke-width="2.5"
      />
      <text
        dy="0.35em"
        text-anchor="middle"
        font-size={if @size == :lg, do: "17", else: "24"}
        font-weight="700"
        fill={@ink}
      >
        {face(@chip)}
      </text>
    </g>
    """
  end

  # What a chip shows: its value. Locoweed has no printed value: an "L".
  defp face({:locoweed, _}), do: "L"
  defp face({_colour, value}), do: value

  defp translate(index) do
    {x, y} = elem(@positions, index)
    "translate(#{x} #{y})"
  end

  defp space_title(index) do
    space = PotTrack.at(index)
    ruby = if space.ruby?, do: ", ruby", else: ""
    "Space #{index}: #{space.coins} coins, #{space.vp} VP#{ruby}"
  end

  # Each chip remembers the space it landed on, so the pot just reads it back.
  defp chips_by_index(%{drawn: drawn}),
    do: Map.new(drawn, fn {chip, index} -> {index, chip} end)

  @doc """
  What is left in the bag, as a count per kind of chip. The bag's order is hidden:
  only counts are shown, so the next draw stays a surprise.
  """
  attr :bag, :list, required: true, doc: "list of `{colour, value}` chips"

  def bag(assigns) do
    assigns = assign(assigns, counts: assigns.bag |> Enum.frequencies() |> Enum.sort())

    ~H"""
    <div class="paper rounded-lg p-3">
      <h2 class="text-lg font-bold">Bag ({length(@bag)} chips)</h2>
      <ul class="mt-1 flex flex-wrap gap-2" aria-label="Chips in the bag">
        <li :for={{chip, count} <- @counts} class="flex items-center gap-1 text-sm">
          <.chip chip={chip} /> <span class="text-ink-soft">x{count}</span>
        </li>
      </ul>
    </div>
    """
  end

  @doc "The round and this seat's phase, for the page header."
  attr :game, Game, required: true
  attr :seat, :integer, default: 0

  def round_phase(assigns) do
    ~H"""
    <dl class="flex items-center gap-2 text-sm">
      <div class="flex items-baseline gap-1">
        <dt class="text-parchment-dim">Round</dt>
        <dd class="font-semibold tabular-nums">{@game.round} / 9</dd>
      </div>
      <div>
        <dt class="sr-only">Phase</dt>
        <dd class="rounded-full bg-parchment/15 px-2 py-0.5 font-semibold">
          {phase_name(Game.phase(@game, @seat))}
        </dd>
      </div>
    </dl>
    """
  end

  @doc """
  One seat's score and resources in one row, plus a badge while it buys (its coins)
  or after an explosion.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0

  def status(assigns) do
    assigns = assign(assigns, me: assigns.game.players[assigns.seat])

    ~H"""
    <dl class="paper grid grid-cols-4 gap-1 rounded-lg p-1 text-sm">
      <.stat label="VP" value={@me.vp} />
      <.stat label="Rubies" value={@me.rubies} />
      <.stat label="Flask" value={if @me.flask, do: "full", else: "empty"} />
      <.stat
        label="White"
        value={"#{Game.white_sum(@game, @seat)} / #{Potions.explode_above(@game, @seat)}"}
      />
      <div
        :if={Game.phase(@game, @seat) == :buy or @me.exploded?}
        class="col-span-4 flex flex-wrap gap-1"
      >
        <span
          :if={Game.phase(@game, @seat) == :buy}
          class="rounded-md bg-gold px-2 font-semibold text-ink"
        >
          {@me.coins} coins to spend
        </span>
        <span
          :if={@me.exploded?}
          class="rounded-md bg-ruby px-2 font-semibold text-white"
          data-role="exploded"
        >
          {exploded_text(@me)}
        </span>
      </div>
    </dl>
    """
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

  defp stat(assigns) do
    ~H"""
    <div class="rounded-md bg-parchment-deep/70 px-2 py-0.5">
      <dt class="text-xs leading-tight text-ink-soft">{@label}</dt>
      <dd class="font-semibold leading-tight tabular-nums">{@value}</dd>
    </div>
    """
  end

  @doc """
  Another player at the table, read-only: name and VP up front (with a band in the
  seat colour), rubies, flask, whether they are still brewing, whose turn it is, an
  "Exploded" badge, and their pot drawn small.
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :name, :string, required: true

  def player_card(assigns) do
    assigns =
      assign(assigns, p: assigns.game.players[assigns.seat], border: @seat_border[assigns.seat])

    ~H"""
    <article
      class={["paper space-y-2 rounded-lg border-t-4 p-2 text-xs", @border]}
      data-seat={@seat}
      data-role="player-card"
    >
      <header class="flex flex-wrap items-center gap-1">
        <.seat_dot seat={@seat} />
        <span class="font-hand text-sm font-bold" data-role="player-name">{@name}</span>
        <span class="ml-auto text-sm font-bold tabular-nums" data-role="player-vp">{@p.vp} VP</span>
      </header>
      <div class="flex flex-wrap items-center gap-1">
        <.player_state game={@game} seat={@seat} />
      </div>
      <p class="text-ink-soft">
        {@p.rubies} {plural(@p.rubies, "ruby", "rubies")} · flask {if @p.flask,
          do: "full",
          else: "empty"} · white {Game.white_sum(@game, @seat)} / {Potions.explode_above(
          @game,
          @seat
        )}
      </p>
      <.pot game={@game} seat={@seat} size={:sm} />
      <.bowl :if={@p.bowl != []} chips={@p.bowl} />
    </article>
    """
  end

  @doc """
  Another player in one line, for phones: colour dot, name, VP, rubies and state.
  The whole line opens the players sheet with the full card.
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :name, :string, required: true

  def player_line(assigns) do
    assigns = assign(assigns, p: assigns.game.players[assigns.seat])

    ~H"""
    <button
      type="button"
      popovertarget="sheet-players"
      class="flex min-h-7 w-full min-w-0 items-center gap-1.5 rounded-md bg-iron-dark/80 px-2 text-xs ring-1 ring-iron"
      data-seat={@seat}
      data-role="player-line"
    >
      <.seat_dot seat={@seat} />
      <span class="truncate font-semibold" data-role="player-name">{@name}</span>
      <span class="font-semibold tabular-nums" data-role="player-vp">{@p.vp} VP</span>
      <span class="tabular-nums text-parchment-dim">{@p.rubies}<span class="text-ruby">◆</span></span>
      <span class="ml-auto flex shrink-0 gap-1"><.player_state game={@game} seat={@seat} /></span>
    </button>
    """
  end

  # The small badges after a name: exploded, done or waiting, their turn.
  attr :game, Game, required: true
  attr :seat, :integer, required: true

  defp player_state(assigns) do
    assigns = assign(assigns, p: assigns.game.players[assigns.seat])

    ~H"""
    <span
      :if={@p.exploded?}
      class="rounded bg-ruby px-1.5 font-bold text-white"
      data-role="exploded-badge"
    >
      Exploded
    </span>
    <span
      :if={@game.phase == :potions and not @p.exploded?}
      class="rounded bg-parchment-deep px-1 text-ink"
    >
      {if @p.done?, do: "done", else: "waiting"}
    </span>
    <span :if={@game.turn == @seat} class="rounded bg-gold px-1 text-ink">their turn</span>
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
        Enum.filter(
          [:orange, :green, :blue, :red, :yellow, :purple, :black, :locoweed],
          &Map.has_key?(@sets, &1)
        ),
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

  def book_text(assigns) do
    ~H"""
    <p class="text-xs text-ink-soft" data-role="book-text">
      <span class="font-semibold text-ink">{@book.name}</span>
      · {trigger_label(@book.trigger)} · {@book.text}
    </p>
    """
  end

  @doc """
  A list of books, each with its colour, set and text, e.g. for the menu's "Books"
  sheet. `books` is a list of `{colour, set}` (`Quacks.Rules.Books.in_play/2`).
  """
  attr :books, :list, required: true

  def book_list(assigns) do
    assigns = assign(assigns, :colours, @colours)

    ~H"""
    <dl class="space-y-2" data-role="book-list">
      <div :for={{colour, set} <- @books} data-book={"#{colour}-#{set}"}>
        <dt class="flex items-center gap-1.5 text-sm font-semibold">
          <span class={["inline-block size-3 rounded-full", @colours[colour]]} />
          {String.capitalize(to_string(colour))} {book_set_name(colour, set)}
        </dt>
        <dd><.book_text book={Books.get({colour, set})} /></dd>
      </div>
    </dl>
    """
  end

  defp book_set_name(:white, _set), do: ""
  defp book_set_name(:black, 1), do: "(base)"
  defp book_set_name(_colour, set), do: "Set #{set}"

  @doc ~s[When a book acts, as a label: "On draw", "Evaluation (step B)", ...]
  @spec trigger_label(Books.trigger()) :: String.t()
  def trigger_label(:on_draw), do: "On draw"
  def trigger_label(:step_b), do: "Evaluation (step B)"
  def trigger_label(:passive), do: "All round"
  def trigger_label(:none), do: "No action"

  @doc """
  The game's house rules that differ from the rulebook game, e.g. "House rules:
  explodes above 9 · no rats". Renders nothing with the default rules.
  """
  attr :rules, :map, required: true, doc: "`game.rules`"

  def house_rules(assigns) do
    %{rules: rules} = assigns
    default = Game.default_rules()
    # A fixed order: map keys have no order to rely on.
    keys = [:explode_above, :starting_rubies, :round6_white, :fortune, :rats, :black_solo, :die]
    changed = for key <- keys, rules[key] != default[key], do: {key, rules[key]}
    assigns = assign(assigns, changed: changed)

    ~H"""
    <p :if={@changed != []} class="text-xs text-zinc-500" data-role="house-rules">
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
  defp rule_label({:die, :no_orange}), do: "die: ruby instead of orange"

  @doc "Red Set 2 chips waiting beside the pot (not in the bag)."
  attr :chips, :list, required: true, doc: "the player's `aside` chips"

  def aside(assigns) do
    ~H"""
    <div
      class="paper flex flex-wrap items-center gap-2 rounded-md border-l-4 border-ruby p-2 text-sm"
      aria-label="Beside the pot"
    >
      <span class="font-semibold">Beside the pot:</span>
      <.chip :for={chip <- @chips} chip={chip} size={:sm} data-role="aside-chip" />
    </div>
    """
  end

  @doc """
  The overflow bowl (The Herb Witches): chips drawn after a chip reached the last
  space. Half their values, rounded down, are VP in the evaluation.
  """
  attr :chips, :list, required: true, doc: "the player's `bowl` chips, newest first"

  def bowl(assigns) do
    ~H"""
    <div
      class="flex min-h-10 flex-wrap items-center gap-1 rounded-b-full border-4 border-t-0 border-iron bg-iron-dark/90 px-3 py-1 text-xs text-parchment"
      aria-label="Overflow bowl"
      data-role="bowl"
    >
      <span class="font-semibold">Bowl</span>
      <.chip :for={chip <- @chips} chip={chip} size={:xs} data-role="bowl-chip" />
      <span :if={@chips == []} class="text-parchment-dim">empty</span>
    </div>
    """
  end

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
        {@card.colour} witch
        <span class="ml-auto normal-case">{if @spent, do: "penny spent", else: "1 penny"}</span>
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
  The chips a blue chip drew, duplicates included, so two identical offers are both
  visible. The action buttons below it show one button per distinct chip.
  `title` and `hint` let the fortune cards B7 and P13 reuse the strip.
  """
  attr :pending, :list, required: true, doc: "the player's `pending` chips"
  attr :title, :string, default: "Crow skull drew:"
  attr :hint, :string, default: "Place one of them, or return them all."
  attr :label, :string, default: "Crow skull offer"
  attr :accent, :string, default: "border-droplet", doc: "left border colour class"

  def blue_offer(assigns) do
    ~H"""
    <div
      class={[
        "paper flex flex-wrap items-center gap-2 rounded-md border-l-4 p-2 text-sm",
        @accent
      ]}
      aria-label={@label}
    >
      <span class="font-semibold">{@title}</span>
      <.chip :for={chip <- @pending} chip={chip} data-role="offer-chip" />
      <span class="text-ink-soft">{@hint}</span>
    </div>
    """
  end

  @doc """
  The chips a fortune card drew from the bag: B7 Safety Procedure (place one) or
  P13 Flea Market (trade one up). Same strip as the crow skull offer.
  """
  attr :card, :atom, required: true, doc: "`game.fortune_card`"
  attr :pending, :list, required: true, doc: "the player's `pending` chips"

  def fortune_offer(%{card: :p13} = assigns) do
    ~H"""
    <.blue_offer
      pending={@pending}
      title="Flea Market drew:"
      hint="Trade one in for the next value up, or skip."
      label="Fortune teller offer"
      accent="border-chip-purple"
    />
    """
  end

  def fortune_offer(assigns) do
    ~H"""
    <.blue_offer
      pending={@pending}
      title="Safety Procedure drew:"
      hint="Place one of them, or return them all."
      label="Fortune teller offer"
      accent="border-chip-purple"
    />
    """
  end

  @doc """
  The Fortune Teller card of this round: a colour band (blue = a rule for the whole
  round, purple = resolved once at the start), its name and its full text.

  ## Examples

      <.fortune_card id={:b7} />
  """
  attr :id, :atom, required: true, doc: "a card id from `Quacks.Rules.Fortune`"

  def fortune_card(assigns) do
    assigns = assign(assigns, card: Fortune.card(assigns.id))

    ~H"""
    <section
      class="paper overflow-hidden rounded-lg text-sm"
      aria-label="Fortune teller card"
      data-role="fortune-card"
      data-colour={@card.colour}
    >
      <div class={[
        "px-3 py-1 text-xs font-semibold uppercase tracking-wide text-white",
        @card.colour == :blue && "bg-chip-blue",
        @card.colour == :purple && "bg-chip-purple"
      ]}>
        Fortune teller · {if @card.colour == :blue, do: "this round", else: "now"}
      </div>
      <div class="px-3 py-2">
        <h2 class="text-lg font-bold">{@card.name}</h2>
        <p class="text-ink-soft">{@card.text}</p>
      </div>
    </section>
    """
  end

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
    entries =
      assigns.log
      |> Enum.reject(&(&1 |> untag() |> narrated_by_event?()))
      |> Enum.take(assigns.limit)
      |> Enum.map(&log_line(&1, assigns.names))

    assigns = assign(assigns, entries: entries)

    ~H"""
    <div class="paper rounded-lg p-3">
      <h2 class="text-lg font-bold">Log</h2>
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

  # `{seat, text}`; seat is nil when no dot shows (solo, or an untagged entry).
  defp log_line({seat, entry}, names) when is_integer(seat) and is_map(names),
    do: {seat, "#{Map.get(names, seat, GameServer.default_name(seat))}: #{label(entry)}"}

  defp log_line(entry, _names), do: {nil, entry |> untag() |> label()}

  defp untag({seat, entry}) when is_integer(seat), do: entry
  defp untag(entry), do: entry

  defp narrated_by_event?(:draw), do: true
  defp narrated_by_event?({:buy, [_ | _]}), do: true
  defp narrated_by_event?({:rubies, _}), do: true
  defp narrated_by_event?(:end_round), do: true
  # Every card choice logs its outcome right after, as `{:fortune, id, outcome}`.
  defp narrated_by_event?({:fortune, _choice}), do: true
  # Every chip choice logs its `{:effect, ...}` right after.
  defp narrated_by_event?({:chip, _choice}), do: true
  defp narrated_by_event?(_entry), do: false

  @doc """
  What each player gained this round: every log entry since the round began that
  gave VP or rubies, plus the bonus die, then the totals. Read from the log only.
  With `names` (multiplayer) there is one block per seat, headed by its name.
  """
  attr :game, Game, required: true
  attr :names, :map, default: nil, doc: "`%{seat => name}`; nil for solo"

  def round_results(assigns) do
    assigns = assign(assigns, results: round_gains(assigns.game))

    ~H"""
    <section class="space-y-3" aria-label="Round results" data-role="round-results">
      <h2 class="text-xl font-bold">Round {@game.round} results</h2>
      <div
        :for={seat <- @game.seats}
        class={["space-y-1", @names && ["border-l-4 pl-2", seat_border(seat)]]}
        data-seat={seat}
      >
        <h3 :if={@names} class="flex items-center gap-1.5 font-hand text-base font-bold">
          <.seat_dot seat={seat} />
          {Map.get(@names, seat, GameServer.default_name(seat))}
        </h3>
        <ul class="space-y-0.5 text-sm">
          <li :for={{text, _vp, _rubies} <- @results[seat] || []} data-role="result-line">{text}</li>
          <li :if={(@results[seat] || []) == []} class="text-ink-soft">Nothing gained this round.</li>
        </ul>
        <p class="font-semibold" data-role="result-total">
          Total: +{total(@results[seat], 1)} VP, +{total(@results[seat], 2)} {plural(
            total(@results[seat], 2),
            "ruby",
            "rubies"
          )}
        </p>
      </div>
    </section>
    """
  end

  defp seat_border(seat), do: @seat_border[seat]

  defp total(nil, _pos), do: 0
  defp total(lines, pos), do: lines |> Enum.map(&elem(&1, pos)) |> Enum.sum()

  # `%{seat => [{text, vp, rubies}]}`, oldest first, for the entries since the last
  # `{:round_end, _}`.
  defp round_gains(game) do
    game.log
    |> Enum.take_while(&(not match?({:round_end, _}, &1)))
    |> Enum.reverse()
    |> Enum.flat_map(fn
      {seat, entry} when is_integer(seat) ->
        case gain(entry) do
          {vp, rubies} -> [{seat, {label(entry), vp, rubies}}]
          nil -> []
        end

      _untagged ->
        []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # `{vp, rubies}` a log entry gave, or nil when it is not a result. The bonus die
  # always counts as a result, whatever its face.
  defp gain({:bonus_die, {:vp, n}}), do: {n, 0}
  defp gain({:bonus_die, :ruby}), do: {0, 1}
  defp gain({:bonus_die, _face}), do: {0, 0}
  defp gain({:green_rubies, n}), do: {0, n}
  defp gain({:purple, 1, _}), do: {1, 0}
  defp gain({:purple, 2, _}), do: {1, 1}
  defp gain({:purple, 3, _}), do: {2, 0}
  defp gain({:black, :droplet_ruby}), do: {0, 1}
  defp gain({:pot_ruby, _index}), do: {0, 1}
  defp gain({:pot_vp, vp, _index}), do: {vp, 0}
  defp gain({:bowl, _chips, vp}), do: {vp, 0}
  defp gain({:effect, {:green, 6}, {:bonus_die, face}}), do: gain({:bonus_die, face})
  defp gain({:effect, {:purple, 2}, {:trade, 1}}), do: {1, 1}
  defp gain({:effect, {:purple, 2}, {:trade, 2}}), do: {3, 0}
  defp gain({:effect, {:purple, 2}, {:trade, 3}}), do: {6, 1}
  defp gain({:effect, _book, {:vp, n}}), do: {n, 0}
  defp gain({:effect, _book, {:rubies, n}}), do: {0, n}
  defp gain({:effect, _book, :ruby}), do: {0, 1}
  defp gain({:effect, _book, :droplet_ruby}), do: {0, 1}
  defp gain({:witch, _id, {:vp, n}}), do: {n, 0}
  defp gain({:witch, _id, {:rubies, n}}), do: {0, n}
  defp gain({:fortune, _id, {:vp, n}}), do: {n, 0}
  defp gain({:fortune, _id, :ruby}), do: {0, 1}
  defp gain({:fortune, _id, :rubies}), do: {0, 3}
  defp gain({:fortune, _id, {:rats_back, n}}), do: {0, n}
  defp gain(_entry), do: nil

  @doc """
  Like `label/1`, but a fortune card choice is worded for `card` (the current
  `game.fortune_card`): the same `{:fortune, :vp}` means 4 VP on P6 and VP per rat
  tail on P10.
  """
  @spec label(term, Fortune.id() | nil) :: String.t()
  def label({:fortune, choice}, card), do: fortune_choice(choice, card)
  def label(action, _card), do: label(action)

  @doc """
  Human label for an action or a log entry. Unknown shapes fall back to `inspect/1`,
  so a new engine action never crashes the page.
  """
  @spec label(term) :: String.t()
  def label(:draw), do: "Draw a chip"
  def label(:stop), do: "Stop"
  def label(:resume), do: "Resume brewing"
  def label(:stopped), do: "Stopped (may resume while others brew)"
  def label(:resumed), do: "Resumed brewing"
  def label(:use_flask), do: "Use flask"
  def label(:end_round), do: "End round"
  def label({:explosion_choice, :vp}), do: "Exploded: take the victory points"
  def label({:explosion_choice, :buy}), do: "Exploded: buy chips instead"
  def label({:rubies, :droplet}), do: "Spend 2 rubies: droplet +1"
  def label({:rubies, :flask}), do: "Spend 2 rubies: refill flask"
  def label({:buy, []}), do: "Buy nothing"

  # No price here: it depends on the game's books. The shop shows the prices.
  def label({:buy, chips}) when is_list(chips),
    do: "Buy #{Enum.map_join(chips, " + ", &chip_name/1)}"

  def label(:return_white), do: "Mandrake: put the white chip back in the bag"
  def label(:keep), do: "Mandrake: keep the white chip"
  def label({:place, {colour, value}}), do: "Crow skull: place #{colour} #{value}"
  def label(:return_all), do: "Crow skull: return all drawn chips to the bag"
  def label({:bonus_die, {:vp, n}}), do: "Bonus die: #{n} VP"
  def label({:bonus_die, :ruby}), do: "Bonus die: ruby"
  def label({:bonus_die, :droplet}), do: "Bonus die: droplet +1"
  def label({:bonus_die, :orange}), do: "Bonus die: orange 1 chip"
  def label({:drew, chip, index}), do: "Drew #{chip_name(chip)} → space #{index}"
  def label({:returned, chip}), do: "Returned #{chip_name(chip)} to the bag"
  def label({:exploded, white_sum}), do: "Exploded (white #{white_sum})"
  def label({:bought, chips}), do: "Bought #{Enum.map_join(chips, " + ", &chip_name/1)}"
  def label({:rubies_spent, :droplet}), do: "Spent 2 rubies: droplet +1"
  def label({:rubies_spent, :flask}), do: "Spent 2 rubies: flask refilled"
  def label({:green_rubies, n}), do: "Garden spider: +#{n} #{plural(n, "ruby", "rubies")}"
  def label({:purple, 1, :vp1}), do: "Ghost's breath (tier 1): +1 VP"
  def label({:purple, 2, :vp1_ruby}), do: "Ghost's breath (tier 2): +1 VP, +1 ruby"
  def label({:purple, 3, :vp2_droplet}), do: "Ghost's breath (tier 3): +2 VP, droplet +1"
  def label({:black, :droplet}), do: "Hawkmoth: droplet +1"
  def label({:black, :droplet_ruby}), do: "Hawkmoth: droplet +1, +1 ruby"
  def label({:rats, tails}), do: "Rats: #{tails} #{plural(tails, "tail", "tails")}"
  def label({:pot_ruby, index}), do: "Scoring space #{index}: +1 ruby"
  def label({:pot_vp, vp, index}), do: "Scoring space #{index}: +#{vp} VP"
  def label({:round_end, round}), do: "— Round #{round} over —"

  def label({:final_conversion, coins_vp, rubies_vp}),
    do: "Final: coins → #{coins_vp} VP, rubies → #{rubies_vp} VP"

  def label({:fortune, choice}), do: fortune_choice(choice, nil)
  def label({:fortune_drawn, id}), do: "Fortune teller: #{Fortune.card(id).name}"

  def label({:fortune_skipped, id}),
    do: "Fortune teller: #{Fortune.card(id).name} (skipped in solo)"

  def label({:fortune, id, outcome}),
    do: "#{Fortune.card(id).name}: #{fortune_outcome(outcome, id)}"

  def label({:chip, {:gain, chip}}), do: "Garden spider: take #{chip_name(chip)}"

  def label({:chip, {:pay_ruby_move, n}}),
    do: "Garden spider: pay #{n} #{plural(n, "ruby", "rubies")}, droplet +#{n}"

  def label({:chip, {:purple_trade, tier}}),
    do: "Ghost's breath: trade #{tier} purple for #{purple_trade(tier)}"

  def label({:chip, {:upgrade, from, to}}),
    do: "Ghost's breath: swap #{chip_name(from)} for #{chip_name(to)}"

  def label(:chip_done), do: "Done with chip actions"

  def label({:red, {:place, chip}}),
    do: "Toadstool: place #{chip_name(chip)} after your last chip"

  def label({:red, {:keep, chip}}), do: "Toadstool: keep #{chip_name(chip)} beside the pot"
  def label({:red, {:return, chip}}), do: "Toadstool: return #{chip_name(chip)} to the bag"
  def label({:rubies_spent, :droplet, 1}), do: "Spent 1 ruby: droplet +1"
  def label({:rubies_spent, :flask, 1}), do: "Spent 1 ruby: flask refilled"
  def label({:overflow, chip}), do: "#{chip_name(chip)} went in the overflow bowl"
  def label({:bowl, _chips, vp}), do: "Overflow bowl: +#{vp} VP"
  def label({:pennies, vp}), do: "Unused witch pennies: +#{vp} VP"
  def label({:expansion, :herb_witches}), do: "Playing with The Herb Witches"
  def label({:witch, colour}), do: "Call the #{colour} witch"

  def label({:witch, :silver, n}) when is_integer(n),
    do: "Silver witch: return the last #{plural(n, "white chip", "#{n} white chips")}"

  def label({:witch, :silver, {:place, chip}}), do: "Silver witch: place #{chip_name(chip)}"
  def label({:witch, :silver, :return_all}), do: "Silver witch: return the rest to the bag"

  def label({:witch, :copper, {:upgrade, chips}}),
    do: "Copper witch: upgrade #{Enum.map_join(chips, " + ", &chip_name/1)}"

  def label({:witch, :copper, {:buy, chips, copy}}),
    do: "Copper witch: buy #{Enum.map_join(chips, " + ", &chip_name/1)}, free #{chip_name(copy)}"

  def label({:witch, id, outcome}), do: "#{Witches.card(id).title}: #{witch_outcome(outcome, id)}"
  def label(:witch_done), do: "Keep the gold penny"
  def label({:chip, :yellow_ruby}), do: "Mandrake: pay 1 ruby, move 3 more"

  def label({:chip, {:starter, chip}}),
    do: "Garden spider: start the next round with #{chip_name(chip)}"

  def label({:chip, {:buy, chips}}),
    do: "Ghost's breath: take #{Enum.map_join(chips, " + ", &chip_name/1)}"

  def label({:effect, book, detail}), do: effect(book, detail)
  def label({seat, {:effect, _, _} = entry}) when is_integer(seat), do: label(entry)
  def label(other), do: inspect(other)

  # A Set 2–4 chip effect, for the log. One head per `{:effect, {colour, set}, detail}`
  # shape in the Log table of `docs/CONTEXT.md`.
  defp effect({:green, 2}, {:gain, chip}), do: "Garden spider: took #{chip_name(chip)}"

  defp effect({:green, 3}, {:moved_last, n}),
    do: "Garden spider: exactly 7 white, last chip moved #{n} #{plural(n, "space", "spaces")}"

  defp effect({:green, 4}, {:droplet, n}),
    do: "Garden spider: paid #{n} #{plural(n, "ruby", "rubies")}, droplet +#{n}"

  defp effect({:blue, 2}, {:protect, n}),
    do: "Crow skull: the next #{n} #{plural(n, "chip is", "chips are")} protected"

  defp effect({:blue, 2}, :protected_explosion),
    do: "Crow skull: protected, you keep VP and coins"

  defp effect({:blue, 3}, :ruby), do: "Crow skull: on a ruby space, +1 ruby"
  defp effect({:blue, 4}, {:vp, n}), do: "Crow skull: on a ruby space, +#{n} VP"
  defp effect({:red, 2}, {:aside, chip}), do: "Toadstool: #{chip_name(chip)} beside the pot"
  defp effect({:red, 3}, {:extra, n}), do: "Toadstool: +#{n} after a white chip"
  defp effect({:red, 4}, :white_plus1), do: "Toadstool: white 1 moved 2"
  defp effect({:yellow, 2}, {:doubled, n}), do: "Mandrake: moved double (#{n} spaces)"
  defp effect({:yellow, 3}, {:limit, n}), do: "Mandrake: white limit now #{n}"
  defp effect({:yellow, 4}, {:extra, n}), do: "Mandrake: +#{n} #{plural(n, "space", "spaces")}"

  defp effect({:purple, 2}, {:trade, tier}),
    do: "Ghost's breath: traded for #{purple_trade(tier)}"

  defp effect({:purple, 3}, {:vp, n}), do: "Ghost's breath: +#{n} VP from pot fields"

  defp effect({:purple, 4}, {:upgrade, from, to}),
    do: "Ghost's breath: swapped #{chip_name(from)} for #{chip_name(to)} (into the bag)"

  # The Herb Witches books (Sets 5 and 6, black, locoweed).
  defp effect({:red, 5}, {:extra, n}), do: "Toadstool: +#{n}, a higher red is in the pot"
  defp effect({:red, 6}, {:aside, chip}), do: "Toadstool: #{chip_name(chip)} set aside"
  defp effect({:yellow, 5}, {:peek, chip}), do: "Mandrake: peeked at #{chip_name(chip)}, moved on"
  defp effect({:yellow, 6}, {:extra, n}), do: "Mandrake: paid 1 ruby, +#{n} spaces"
  defp effect({:blue, 5}, {:vp, n}), do: "Crow skull: +#{n} VP for the pumpkins"

  defp effect({:blue, 6}, {:rubies, n}),
    do: "Crow skull: +#{n} #{plural(n, "ruby", "rubies")} for white 1-chips"

  defp effect({:green, 5}, {:starter, chip}),
    do: "Garden spider: #{chip_name(chip)} starts the next round"

  defp effect({:green, 5}, {:first, chip}), do: "Garden spider: #{chip_name(chip)} placed first"
  defp effect({:green, 6}, {:bonus_die, face}), do: "Garden spider: " <> label({:bonus_die, face})

  defp effect({:purple, 5}, {:bought, chips}),
    do: "Ghost's breath: took #{Enum.map_join(chips, " + ", &chip_name/1)}"

  defp effect({:purple, 5}, {:vp, n}), do: "Ghost's breath: +#{n} VP from the purple spaces"
  defp effect({:purple, 6}, {:vp, n}), do: "Ghost's breath: +#{n} VP from the chips after purple"

  defp effect({:black, 5}, {:to_left, _seat}),
    do: "Hawkmoth: black chip into the left player's bag, droplet +1"

  defp effect({:black, 5}, :to_supply), do: "Hawkmoth: black chip back to the supply, droplet +1"

  defp effect({:black, 5}, {:rubies, n}),
    do: "Hawkmoth: +#{n} #{plural(n, "ruby", "rubies")}"

  defp effect({:black, 6}, :droplet), do: "Hawkmoth: furthest black chip, droplet +1"
  defp effect({:black, 6}, :ruby), do: "Hawkmoth: second furthest black chip, +1 ruby"
  defp effect({:black, 6}, :droplet_ruby), do: "Hawkmoth: droplet +1, +1 ruby"
  defp effect({:locoweed, 5}, {:moves, n}), do: "Locoweed: moved #{n}"
  defp effect({:locoweed, 6}, {:copied, chip}), do: "Locoweed: acted as #{chip_name(chip)}"
  defp effect(book, detail), do: inspect({:effect, book, detail})

  # What a witch did, for the log.
  defp witch_outcome(:flask, _id), do: "the flask took the white chip back"
  defp witch_outcome({:offer, n}, _id), do: "drew #{n} #{plural(n, "chip", "chips")}"

  defp witch_outcome({:return_white, n}, _id),
    do: "#{n} white #{plural(n, "chip", "chips")} back in the bag"

  defp witch_outcome(:no_penalty, _id), do: "no explosion penalty"

  defp witch_outcome({:upgrade, chips}, _id),
    do: "upgraded #{Enum.map_join(chips, " + ", &chip_name/1)}"

  defp witch_outcome({:coins, n}, :c2), do: "coins doubled to #{n}"
  defp witch_outcome({:coins, n}, _id), do: "+#{n} coins"
  defp witch_outcome({:copy, chip}, _id), do: "free #{chip_name(chip)}"
  defp witch_outcome({:vp, n}, _id), do: "+#{n} VP"
  defp witch_outcome({:rubies, n}, _id), do: "+#{n} #{plural(n, "ruby", "rubies")}"
  defp witch_outcome(:ruby_price, _id), do: "droplet and flask cost 1 ruby"
  defp witch_outcome(other, _id), do: inspect(other)

  defp purple_trade(1), do: "black 1, 1 VP, 1 ruby"
  defp purple_trade(2), do: "green 1, blue 2, 3 VP, droplet +1"
  defp purple_trade(3), do: "yellow 4, 6 VP, 1 ruby, droplet +2"

  # A `{:fortune, choice}` button. `card` is the current card; nil means unknown.
  defp fortune_choice({:take, chip}, :p3), do: "Trade 1 ruby for #{chip_name(chip)}"
  defp fortune_choice({:take, chip}, _card), do: "Take #{chip_name(chip)}"
  defp fortune_choice(:rubies, _card), do: "Take 3 rubies"
  defp fortune_choice(:vp, :p6), do: "Score 4 VP"
  defp fortune_choice(:vp, :p10), do: "Score 1 VP per rat tail behind the leader"
  defp fortune_choice(:vp, _card), do: "Score victory points"
  defp fortune_choice(:remove_white, _card), do: "Remove a white 1 from your bag"

  defp fortune_choice({:rats_back, n}, _card),
    do: "Rat stone back #{n}, take #{n} #{plural(n, "ruby", "rubies")}"

  defp fortune_choice(:droplet, :p11), do: "Droplet 2 forward"
  defp fortune_choice(:droplet, _card), do: "Droplet forward"

  defp fortune_choice({:upgrade, chip}, _card),
    do: "Trade #{chip_name(chip)} for the next value up"

  defp fortune_choice(:skip, _card), do: "No thanks"
  defp fortune_choice(:restart_round, _card), do: "Second Chances: start the round again"
  defp fortune_choice(:return_white, _card), do: "Cauldron Bubble: put the white chip back"
  defp fortune_choice({:place, chip}, _card), do: "Safety Procedure: place #{chip_name(chip)}"
  defp fortune_choice(:return_all, _card), do: "Safety Procedure: return all to the bag"
  defp fortune_choice(other, _card), do: inspect({:fortune, other})

  # What a card did for a player, for the log.
  defp fortune_outcome(:droplet, :p11), do: "droplet +2"
  defp fortune_outcome(:droplet, _id), do: "droplet +1"
  defp fortune_outcome({:take, chip}, _id), do: "took #{chip_name(chip)}"
  defp fortune_outcome(:restart_round, _id), do: "started the round again"
  defp fortune_outcome({:place, chip}, _id), do: "placed #{chip_name(chip)}"
  defp fortune_outcome(:return_all, _id), do: "returned all chips to the bag"
  defp fortune_outcome({:vp, n}, _id), do: "+#{n} VP"
  defp fortune_outcome(:flask, _id), do: "flask refilled"
  defp fortune_outcome(:return_white, _id), do: "white chip back in the bag"
  defp fortune_outcome(:ruby, _id), do: "+1 ruby"
  defp fortune_outcome(:rubies, _id), do: "+3 rubies"
  defp fortune_outcome(:skip, _id), do: "no thanks"
  defp fortune_outcome(:remove_white, _id), do: "removed a white 1 from the bag"
  defp fortune_outcome({:rats, n}, _id), do: "rat stone +#{n}"

  defp fortune_outcome({:rats_back, n}, _id),
    do: "rat stone back #{n}, +#{n} #{plural(n, "ruby", "rubies")}"

  defp fortune_outcome({:upgrade, chip}, _id), do: "traded #{chip_name(chip)} up"
  defp fortune_outcome(:orange, _id), do: "orange 1 chip"
  defp fortune_outcome(other, _id), do: inspect(other)

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many

  @doc ~s("green 2" for `{:green, 2}`; locoweed has no value: "locoweed".)
  @spec chip_name(Chips.chip()) :: String.t()
  def chip_name({:locoweed, _}), do: "locoweed"
  def chip_name({colour, value}), do: "#{colour} #{value}"

  @doc "The name of a phase, as the header shows it."
  @spec phase_name(atom) :: String.t()
  def phase_name(:potions), do: "Brewing"
  def phase_name(:explosion_choice), do: "Explosion"
  def phase_name(:yellow_choice), do: "Mandrake"
  def phase_name(:blue_choice), do: "Crow skull"
  def phase_name(:fortune_choice), do: "Fortune teller"
  def phase_name(:chip_choice), do: "Chip actions"
  def phase_name(:witch_choice), do: "Gold witch"
  def phase_name(:witch_offer), do: "Silver witch"
  def phase_name(:red_choice), do: "Toadstool"
  def phase_name(:stopped), do: "Stopped"
  def phase_name(:buy), do: "Shop"
  def phase_name(:rubies), do: "Rubies"
  def phase_name(:ready), do: "Ready"
  def phase_name(:done), do: "Done"
  def phase_name(:over), do: "Over"
  def phase_name(other), do: inspect(other)
end
