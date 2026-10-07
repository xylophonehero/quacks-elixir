defmodule QuacksWeb.GameComponents do
  @moduledoc """
  Function components that draw a `Quacks.Game` struct. Rendering only: nothing in
  here changes game state. The LiveView passes the struct in; each component reads
  the fields it needs.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Quacks.AI.Odds
  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Game.Potions
  alias Quacks.Rules.{Alchemists, Books, Chips, PotTrack, ScoringTrack, TestTubes}
  alias Quacks.Rules.Fortune
  alias Quacks.Rules.Witches
  alias QuacksWeb.{AlchemistsComponents, Replay}

  import QuacksWeb.Icons

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

  # Seat colours (theme tokens `--color-player-N`, see `seat_style/1`), as full class
  # names so Tailwind finds them in the source.
  @seat_bg %{
    0 => "bg-player-0",
    1 => "bg-player-1",
    2 => "bg-player-2",
    3 => "bg-player-3",
    4 => "bg-player-4",
    5 => "bg-player-5",
    6 => "bg-player-6",
    7 => "bg-player-7"
  }
  @seat_border %{
    0 => "border-player-0",
    1 => "border-player-1",
    2 => "border-player-2",
    3 => "border-player-3",
    4 => "border-player-4",
    5 => "border-player-5",
    6 => "border-player-6",
    7 => "border-player-7"
  }

  # A ring in the seat colour (the "You" name pill).
  @seat_ring %{
    0 => "ring-player-0",
    1 => "ring-player-1",
    2 => "ring-player-2",
    3 => "ring-player-3",
    4 => "ring-player-4",
    5 => "ring-player-5",
    6 => "ring-player-6",
    7 => "ring-player-7"
  }

  # The palette itself (`--color-seat-N`), for the colour picker.
  @palette_bg %{
    0 => "bg-seat-0",
    1 => "bg-seat-1",
    2 => "bg-seat-2",
    3 => "bg-seat-3",
    4 => "bg-seat-4",
    5 => "bg-seat-5",
    6 => "bg-seat-6",
    7 => "bg-seat-7"
  }

  # Chips with a light face get dark ink for their value (contrast >= 4.5:1).
  @light_chips [:white, :orange, :green, :yellow]

  # Chips whose icon is ink; the icon is white on every other chip.
  @ink_icon_chips [:white, :yellow, :orange, :green]

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
  One chip: a disc in the chip colour with the ingredient icon and the value in a
  parchment badge. `size={:xs}` is too small for the icon: it shows only the value.

  ## Examples

      <.chip chip={{:green, 2}} />
      <.chip chip={{:white, 1}} size={:sm} />
  """
  attr :chip, :any, required: true, doc: "a `{colour, value}` tuple"
  attr :size, :atom, default: :md, values: [:xs, :sm, :md, :lg]
  attr :rest, :global

  def chip(assigns) do
    {colour, value} = assigns.chip

    assigns =
      assign(assigns,
        colour: colour,
        value: value,
        colour_class: Map.get(@colours, colour, "bg-zinc-400 text-white"),
        icon_class: if(colour in @ink_icon_chips, do: "text-ink", else: "text-white")
      )

    ~H"""
    <span
      :if={@size == :xs}
      class={[
        "inline-flex size-4 shrink-0 items-center justify-center rounded-full text-[9px] font-bold tabular-nums",
        @colour_class
      ]}
      aria-label={"#{@colour} #{@value}"}
      {@rest}
    >
      {face(@chip)}
    </span>
    <span
      :if={@size != :xs}
      class={[
        "chip-token relative inline-flex shrink-0 items-center justify-center rounded-full",
        @size == :sm && "size-6",
        @size == :md && "size-9",
        @size == :lg && "size-12",
        @colour_class
      ]}
      aria-label={"#{@colour} #{@value}"}
      data-chip-icon={@colour}
      {@rest}
    >
      <.ingredient_icon
        colour={@colour}
        class={[
          "size-[58%]",
          @icon_class,
          @colour != :locoweed && "-translate-x-[8%] -translate-y-[8%]"
        ]}
      />
      <span
        :if={@colour != :locoweed}
        class={[
          "absolute inline-flex items-center justify-center rounded-full bg-parchment-light font-hand leading-none font-bold text-ink tabular-nums ring-ink",
          @size == :sm && "-right-1 -bottom-1 size-3.5 text-[9px] ring-1",
          @size == :md && "-right-1 -bottom-1 size-[18px] text-[11px] ring-2"
        ]}
        data-role="chip-value"
      >
        {@value}
      </span>
    </span>
    """
  end

  @doc """
  One seat's 54-space pot track, drawn as the board's cauldron: an inline SVG with
  the spaces on a spiral from the centre (space 0) out to the rim (space 53).

  `size={:lg}` (your own pot) shows each space's coins (a plain numeral), its
  victory points (a small gold seal, only where VP > 0) and a ruby gem. Spaces
  before the scoring space are dimmed; the scoring space glows gold. `size={:sm}`
  (another player's pot) shows only the chips. In both, the droplet is a full blue
  piece on its space, each rat tail is a grey rat piece on its own space after it
  (`data-role="rat"`, in the `rat-stone` group), and placed chips sit on their spaces.

  Scoring spaces (the space directly after the last chip) are rings in the seat
  colours. `rings` maps seat => scoring space; by default only this seat's ring
  shows. When seats share a space, the ring splits into one arc per seat.

  An exploded pot gets a red, cracked rim. `flask` (`:full` or `:empty`) draws the
  flask in the lower-left corner; with `flask_click` set it glows and a click sends it as the
  `"action"` event's value.

  The SVG scales to its box and keeps its shape, so `class="block size-full"` fits
  the whole pot into whatever space the page gives it. Each space's `<title>` also
  names its coins and VP.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0
  attr :size, :atom, default: :lg, values: [:sm, :lg]
  attr :class, :string, default: "block h-auto w-full"
  attr :rings, :map, default: nil, doc: "`%{seat => scoring index}`; nil: this seat only"
  attr :flask, :atom, default: nil, values: [nil, :full, :empty]
  attr :flask_click, :string, default: nil, doc: "the encoded `:use_flask` when legal"

  attr :beats, :map,
    default: %{},
    doc: "`QuacksWeb.Replay.highlights/1`: the chips, droplet and scoring ring to light up"

  attr :effects, :list,
    default: [],
    doc: "while the replay plays: `QuacksWeb.Replay.pot_effects/1` (flying rubies, VP tags)"

  def pot(assigns) do
    player = assigns.game.players[assigns.seat]
    scoring = Game.scoring_index(assigns.game, assigns.seat)
    rings = assigns.rings || %{assigns.seat => scoring}

    assigns =
      assign(assigns,
        me: player,
        chips_by_index: chips_by_index(player),
        placed: placements(assigns.game.log, assigns.seat),
        positions: @positions,
        rings_by_index: rings |> Enum.sort() |> Enum.group_by(&elem(&1, 1), &elem(&1, 0)),
        rat_index: if(player.rat_stone > 0, do: Player.start_index(player)),
        scoring: scoring,
        ring_index: scoring,
        fx: Enum.map(assigns.effects, &Map.put(&1, :xy, fx_at(&1, player.droplet, scoring))),
        spaces: 0..PotTrack.last(),
        groove: @groove
      )

    ~H"""
    <svg
      id={"pot-#{@seat}-#{@size}"}
      viewBox="-268 -268 536 536"
      preserveAspectRatio="xMidYMid meet"
      class={[@class, "pot-#{@size} select-none"]}
      role="group"
      aria-label="Pot track"
      data-exploded={to_string(@me.exploded?)}
      phx-hook={@size == :lg && "PotMotion"}
      data-round={@size == :lg && @game.round}
      data-slide-beat={@effects != [] && @beats[:droplet]}
      style={@effects != [] && @beats[:droplet] && "--slide-beat: #{@beats[:droplet]}"}
    >
      <defs>
        <%!-- The brew; an exploded pot's brew turns a dull, spoiled olive. --%>
        <radialGradient
          id={"brew-#{@seat}-#{@size}"}
          data-role="brew"
          data-spoiled={@me.exploded? && "true"}
        >
          <stop
            offset="0%"
            stop-color={if @me.exploded?, do: "#8a9560", else: "var(--color-potion-light)"}
            stop-opacity="0.55"
          />
          <stop
            offset="70%"
            stop-color={if @me.exploded?, do: "#5b6b3a", else: "var(--color-potion)"}
          />
          <stop
            offset="100%"
            stop-color={if @me.exploded?, do: "#3b4526", else: "var(--color-potion-deep)"}
          />
        </radialGradient>
        <radialGradient :if={@size == :lg} id={"vp-gold-#{@seat}"} cx="35%" cy="30%">
          <stop offset="0%" stop-color="#fff1bf" />
          <stop offset="50%" stop-color="var(--color-gold)" />
          <stop offset="100%" stop-color="#a97d17" />
        </radialGradient>
        <radialGradient id={"drop-#{@seat}-#{@size}"} cx="35%" cy="55%" r="70%">
          <stop offset="0%" stop-color="#7fb0ff" />
          <stop offset="55%" stop-color="var(--color-droplet)" />
          <stop offset="100%" stop-color="#1f4fb0" />
        </radialGradient>
      </defs>
      <%!-- iron rim and the brew --%>
      <circle r="262" fill={if @me.exploded?, do: "#4a1210", else: "var(--color-iron-dark)"} />
      <circle
        r="250"
        fill={"url(#brew-#{@seat}-#{@size})"}
        stroke={if @me.exploded?, do: "var(--color-ruby)", else: "var(--color-iron)"}
        stroke-width="12"
      />
      <g :if={@me.exploded?} id={"cracked-rim-#{@seat}-#{@size}"} data-role="cracked-rim">
        <circle r="244" fill="var(--color-ruby)" fill-opacity="0.18" />
        <circle r="250" fill="var(--color-parchment)" opacity="0" data-role="puff" />
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
        stroke={if @me.exploded?, do: "#2f3820", else: "var(--color-potion-deep)"}
        stroke-opacity="0.7"
        stroke-width="46"
        stroke-linecap="round"
        stroke-linejoin="round"
        data-role="groove"
      />
      <%!-- a thin highlight along the groove, so the spiral reads at a glance --%>
      <polyline
        points={@groove}
        fill="none"
        stroke="var(--color-potion-light)"
        stroke-opacity="0.35"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        transform="translate(0 -1)"
      />
      <g
        :for={index <- @spaces}
        data-space={index}
        data-x={@size == :lg && elem(elem(@positions, index), 0)}
        data-y={@size == :lg && elem(elem(@positions, index), 1)}
        transform={translate(index)}
      >
        <title :if={@size == :lg}>{space_title(index)}</title>
        <circle
          r="22"
          fill="var(--color-potion-light)"
          stroke="var(--color-potion-deep)"
          stroke-width="2"
        />
        <circle
          :if={@size == :lg and index == @scoring}
          r="22"
          fill="var(--color-gold)"
          fill-opacity="0.35"
          data-role="next-space"
        />
        <g
          :if={@size == :lg}
          opacity={if index < @scoring, do: "0.45"}
          data-passed={index < @scoring && "true"}
        >
          <text
            dy="0.35em"
            text-anchor="middle"
            font-size="17"
            font-weight="600"
            fill="var(--color-ink)"
            fill-opacity="0.75"
            class="tabular-nums"
          >
            {PotTrack.at(index).coins}
          </text>
          <g :if={PotTrack.at(index).vp > 0} transform="translate(14 14)" data-role="vp-tag">
            <circle
              r="9"
              fill={"url(#vp-gold-#{@seat})"}
              stroke="#7a5a10"
              stroke-width="1"
            />
            <text
              dy="0.35em"
              text-anchor="middle"
              font-size="12"
              font-weight="700"
              fill="#3a2508"
            >
              {PotTrack.at(index).vp}
            </text>
          </g>
          <%!-- Lower left, mirroring the VP tag: inside a scoring ring it stays in
               view (round 12; it sat on the top edge, under the ring). --%>
          <.piece_icon
            :if={PotTrack.at(index).ruby?}
            name={:ruby}
            x="-21.5"
            y="6.5"
            width="15"
            height="15"
            class="text-ruby"
            style="filter: drop-shadow(0 0 1px #4a0d0a)"
          />
        </g>
        <.pot_chip
          :if={Map.has_key?(@chips_by_index, index)}
          chip={elem(@chips_by_index[index], 0)}
          order={elem(@chips_by_index[index], 1)}
          seat={@seat}
          index={index}
          placed={Map.get(@placed, index, 0)}
          size={@size}
          beat={@beats[index]}
        />
        <.scoring_ring :if={@rings_by_index[index]} seats={@rings_by_index[index]} />
        <.beat_ring :if={index == @ring_index} beat={@beats[:ring]} r="32" />
      </g>
      <%!-- The droplet and the rats are full pieces, like chips: the droplet on its
           space, then one rat per rat tail on each space after it, so the first chip
           lands after the last rat. Fixed ids: when the droplet moves, only `translate`
           changes and CSS slides them. --%>
      <g
        id={"droplet-#{@seat}-#{@size}"}
        data-role="droplet"
        data-index={@me.droplet}
        style={translate_style(@me.droplet)}
        aria-label="droplet"
      >
        <circle
          r="19"
          fill={"url(#drop-#{@seat}-#{@size})"}
          stroke="#1f3f8a"
          stroke-width="2.5"
        />
        <path
          d="M0 -13 L6.2 -2.6 A7 7 0 1 1 -6.2 -2.6 Z"
          fill="var(--color-parchment-light)"
          fill-opacity="0.92"
          stroke="#1f3f8a"
          stroke-width="1.5"
          stroke-linejoin="round"
          transform="translate(0 3)"
        />
        <.beat_ring beat={@beats[:droplet]} r="24" />
      </g>
      <g
        :if={@rat_index}
        id={"rat-#{@seat}-#{@size}"}
        data-role="rat-stone"
        data-index={@rat_index}
        data-tails={@me.rat_stone}
      >
        <g
          :for={tail <- 1..@me.rat_stone//1}
          id={"rat-#{@seat}-#{@size}-#{tail}"}
          data-role="rat"
          data-index={@me.droplet + tail}
          style={translate_style(@me.droplet + tail)}
          aria-label="rat"
        >
          <g class="rat-pebble">
            <circle r="19" fill="#8b9097" stroke="var(--color-iron-dark)" stroke-width="2.5" />
            <.piece_icon
              name={:rat}
              x="-12"
              y="-12"
              width="24"
              height="24"
              class="text-parchment-light"
            />
          </g>
        </g>
      </g>
      <.flask
        :if={@flask}
        id={"flask-#{@seat}"}
        full={@flask == :full}
        click={@flask_click}
        uid={"#{@seat}-#{@size}"}
      />
      <%!-- The scoring sequence: on its line's beat a ruby lifts and flies to the ruby
           counter (app.js `PotMotion`), a VP tag floats up (app.css `vp-float`). --%>
      <g
        :for={fx <- @fx}
        id={"beat-fx-#{@seat}-#{@game.round}-#{fx.kind}-#{fx.beat}-#{fx.n}"}
        data-role={if fx.kind == :ruby, do: "ruby-flight", else: "vp-float"}
        data-beat={fx.beat}
        data-n={fx.n}
        data-wait={if fx.at == :droplet, do: "300", else: "0"}
        data-x={elem(fx.xy, 0)}
        data-y={elem(fx.xy, 1)}
        style={"--beat: #{fx.beat}"}
        transform={"translate(#{elem(fx.xy, 0)} #{elem(fx.xy, 1)})"}
        aria-hidden="true"
      >
        <g class="beat-fx">
          <.piece_icon
            :if={fx.kind == :ruby}
            name={:ruby}
            x="-10"
            y="-10"
            width="20"
            height="20"
            class="text-ruby"
            style="filter: drop-shadow(0 0 3px var(--color-gold))"
          />
          <g :if={fx.kind == :vp} transform="translate(0 -26)">
            <rect
              x="-27"
              y="-11"
              width="54"
              height="22"
              rx="11"
              fill="var(--color-gold)"
              stroke="#7a5a10"
            />
            <text dy="0.35em" text-anchor="middle" font-size="14" font-weight="700" fill="#3a2508">
              {fx.text}
            </text>
          </g>
        </g>
      </g>
      <%!-- The chip flight's ghosts (app.js `PotMotion`) live here, out of LiveView's way. --%>
      <g :if={@size == :lg} id={"pot-fx-#{@seat}"} phx-update="ignore" data-role="pot-fx" />
    </svg>
    """
  end

  @doc """
  The test-tube rack of the reverse pot side: glass 0 (the start) and the 12 bonus
  glasses, each with its bonus (a ruby, the VP, or the chip). The droplet sits above
  the glass the player reached; glasses already paid are dimmed.
  """
  attr :tube, :integer, required: true, doc: "the player's `tube` (0..12)"
  attr :class, :any, default: "block h-auto w-full"

  def test_tubes(assigns) do
    assigns = assign(assigns, glasses: 0..TestTubes.last(), last: TestTubes.last())

    ~H"""
    <svg
      viewBox="0 -18 364 84"
      class={[@class, "select-none"]}
      role="img"
      aria-label={"Test tubes: glass #{@tube} of #{@last}"}
      data-role="test-tubes"
      data-tube={@tube}
    >
      <rect x="2" y="54" width="360" height="9" rx="3" fill="var(--color-wood)" />
      <rect x="2" y="54" width="360" height="3" rx="1.5" fill="var(--color-wood-dark)" opacity="0.5" />
      <g
        :for={glass <- @glasses}
        transform={"translate(#{14 + 28 * glass} 0)"}
        data-role="glass"
        data-filled={to_string(glass > 0 and glass <= @tube)}
        opacity={if glass > 0 and glass <= @tube, do: "0.4"}
        class="transition-opacity duration-300 motion-reduce:transition-none"
      >
        <title>{glass_title(glass)}</title>
        <path
          d={
            if glass == 0,
              do: "M-7 22 v20 a7 7 0 0 0 14 0 v-20",
              else: "M-10 6 v38 a10 10 0 0 0 20 0 v-38"
          }
          fill="var(--color-parchment-light)"
          fill-opacity="0.85"
          stroke="var(--color-iron)"
          stroke-width="2"
        />
        <line
          x1={if glass == 0, do: "-9", else: "-12"}
          x2={if glass == 0, do: "9", else: "12"}
          y1={if glass == 0, do: "22", else: "6"}
          y2={if glass == 0, do: "22", else: "6"}
          stroke="var(--color-iron)"
          stroke-width="3"
          stroke-linecap="round"
        />
        <.glass_bonus :if={glass > 0} bonus={TestTubes.bonus(glass)} />
        <path
          :if={glass == @tube}
          d="M0 -11 C8 -1 8 7 0 7 C-8 7 -8 -1 0 -11 Z"
          transform="translate(0 -4)"
          fill="var(--color-droplet)"
          stroke="white"
          stroke-width="1.5"
          aria-label="test-tube droplet"
          data-role="tube-droplet"
        />
      </g>
    </svg>
    """
  end

  attr :bonus, :any, required: true

  defp glass_bonus(%{bonus: :ruby} = assigns) do
    ~H"""
    <path
      d="M0 22 l7 5 -2.5 8 h-9 l-2.5 -8 z"
      fill="var(--color-ruby)"
      stroke="#7a1410"
      stroke-width="1"
    />
    """
  end

  defp glass_bonus(%{bonus: {:vp, n}} = assigns) do
    assigns = assign(assigns, n: n)

    ~H"""
    <text y="31" text-anchor="middle" font-size="15" font-weight="800" fill="var(--color-ink)">
      {@n}
    </text>
    <text y="42" text-anchor="middle" font-size="7" font-weight="700" fill="var(--color-ink-soft)">
      VP
    </text>
    """
  end

  defp glass_bonus(%{bonus: {:chip, {colour, value}}} = assigns) do
    ink = if colour in @light_chips, do: "var(--color-ink)", else: "white"
    assigns = assign(assigns, colour: colour, value: value, ink: ink)

    ~H"""
    <circle
      cy="30"
      r="8"
      fill={"var(--color-chip-#{@colour})"}
      stroke="rgb(0 0 0 / 0.4)"
      stroke-width="1.5"
    />
    <text y="33.5" text-anchor="middle" font-size="10" font-weight="700" fill={@ink}>
      {@value}
    </text>
    """
  end

  defp glass_title(0), do: "Start"
  defp glass_title(glass), do: "Glass #{glass}: #{tube_bonus(TestTubes.bonus(glass))}"

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

  # The flask, in the free corner to the lower left of the cauldron (the page puts
  # the bag in the lower right and the fortune card in the upper right). Parchment when
  # full, grey when empty. Usable: it glows and is a button (click or Enter).
  attr :id, :string, required: true
  attr :full, :boolean, required: true
  attr :click, :string, default: nil
  attr :uid, :string, required: true, doc: "makes the gradient and clip ids unique"

  defp flask(assigns) do
    ~H"""
    <g
      id={@id}
      transform="translate(-222 214)"
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
      <title :if={@click}>Tap the flask to put the white chip back in the bag</title>
      <defs>
        <clipPath id={"flask-body-#{@uid}"}>
          <path d="M-7 -41 h14 v16 A25 25 0 1 1 -7 -25 Z" />
        </clipPath>
        <linearGradient id={"flask-brew-#{@uid}"} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="var(--color-potion-light)" />
          <stop offset="100%" stop-color="var(--color-potion-deep)" />
        </linearGradient>
      </defs>
      <rect x="-32" y="-54" width="64" height="88" fill="transparent" />
      <rect x="-9" y="-50" width="18" height="10" rx="2" fill="var(--color-wood)" />
      <rect x="-9" y="-50" width="18" height="3" rx="1.5" fill="white" fill-opacity="0.18" />
      <path
        class="flask-body"
        d="M-7 -41 h14 v16 A25 25 0 1 1 -7 -25 Z"
        fill={if @full, do: "#dfe6e2", else: "#7d8288"}
        fill-opacity={if @full, do: "0.55", else: "1"}
      />
      <path
        :if={@full}
        clip-path={"url(#flask-body-#{@uid})"}
        d="M-30 -8 q7.5 -4 15 0 t15 0 t15 0 t15 0 V30 H-30 Z"
        fill={"url(#flask-brew-#{@uid})"}
        data-role="flask-brew"
      />
      <path
        d="M-7 -41 h14 v16 A25 25 0 1 1 -7 -25 Z"
        fill="none"
        stroke="var(--color-iron-dark)"
        stroke-width="3"
        stroke-linejoin="round"
      />
      <ellipse cx="-9" cy="-4" rx="5" ry="9" fill="white" fill-opacity="0.35" />
      <path
        d="M17 -10 A20 20 0 0 1 14 14"
        fill="none"
        stroke="white"
        stroke-opacity="0.2"
        stroke-width="2"
        stroke-linecap="round"
      />
    </g>
    """
  end

  @doc ~s{The CSS colour of a seat, e.g. "var(--color-player-1)", for SVG fills.}
  @spec seat_colour(Game.seat()) :: String.t()
  def seat_colour(seat), do: "var(--color-player-#{seat})"

  @doc """
  The inline style that gives each seat its chosen colour: `colours` is
  `%{seat => 0..7}` (`GameServer` table), e.g. `%{0 => 5}` gives
  `"--color-player-0: var(--color-seat-5);"`. Put it on an element around the page.
  """
  @spec seat_style(%{Game.seat() => 0..7}) :: String.t()
  def seat_style(colours),
    do:
      Enum.map_join(colours, " ", fn {seat, c} ->
        "--color-player-#{seat}: var(--color-seat-#{c});"
      end)

  @doc "The background class of palette colour `colour` (0..7), e.g. `\"bg-seat-5\"`."
  @spec palette_bg(0..7) :: String.t()
  def palette_bg(colour), do: @palette_bg[colour]

  @doc """
  The rat track (round 16; equal steps since round 22): a slim strip between the
  name cards and the pot. Not to scale: one step per rat tail
  (`ScoringTrack.tails/0`) between the last player and the leader, the leader on
  the left. Every seat's dot sits in the step of its rats
  (`ScoringTrack.rat_tails/2`: the leader's step has none, each tail to the right
  adds one); seats in one step stack. Under each rat tail its VP; above the
  leader's dot (round 24) the leader's VP, once for a tie. A fixed height; nothing
  to tap.
  """
  attr :game, :map, required: true
  attr :seat, :any, default: nil, doc: "this browser's seat, nil for a spectator"
  attr :names, :map, required: true
  attr :class, :any, default: nil

  def rat_track(assigns) do
    game = assigns.game
    vps = for s <- game.seats, do: {s, Game.player(game, s).vp}
    {low, leader} = vps |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    # The tails from the leader's side: a seat behind tail `t` (VP <= t) gets its rat.
    tails = for t <- Enum.reverse(ScoringTrack.tails()), low <= t and t < leader, do: t
    steps = length(tails) + 1

    dots =
      vps
      |> Enum.map(fn {s, vp} -> {s, vp, ScoringTrack.rat_tails(vp, leader)} end)
      |> Enum.sort_by(fn {s, vp, step} -> {step, -vp, s} end)
      |> Enum.chunk_by(&elem(&1, 2))
      |> Enum.flat_map(fn same ->
        for {{s, vp, step}, i} <- Enum.with_index(same),
            do: %{
              seat: s,
              vp: vp,
              step: step,
              bg: @seat_bg[s],
              x: (step + 0.5) / steps,
              shift: i - (length(same) - 1) / 2
            }
      end)

    rats = for {t, j} <- Enum.with_index(tails), do: %{vp: t, x: (j + 1) / steps}

    label =
      Enum.map_join(vps, "; ", fn {s, vp} ->
        n = ScoringTrack.rat_tails(vp, leader)

        "#{Map.get(assigns.names, s, "Player #{s + 1}")} #{vp} VP, #{n} #{if n == 1, do: "rat", else: "rats"}"
      end)

    assigns =
      assign(assigns, dots: dots, rats: rats, steps: steps, leader: leader, label: label)

    ~H"""
    <div
      id="rat-track"
      class={["relative h-8 select-none", @class]}
      role="img"
      aria-label={"Rat track, leader first: " <> @label}
      data-role="rat-track"
      data-steps={@steps}
    >
      <span
        class="absolute top-3.5 h-px rounded-full bg-parchment/35"
        style={"left: #{pos(0.5 / @steps)}; right: #{pos(0.5 / @steps)}"}
      />
      <span
        :for={rat <- @rats}
        class="absolute top-3.5 flex -translate-x-1/2 -translate-y-1/2 flex-col items-center text-parchment-dim"
        style={"left: #{pos(rat.x)}"}
        data-role="track-rat"
        data-vp={rat.vp}
      >
        <.piece_icon name={:rat} class="size-3" />
        <span class="absolute top-full text-[9px] leading-none font-semibold tabular-nums">
          {rat.vp}
        </span>
      </span>
      <span
        :for={dot <- @dots}
        class="absolute top-3.5 -translate-x-1/2 -translate-y-1/2 transition-[left] duration-500 ease-out motion-reduce:transition-none"
        style={"left: calc(#{pos(dot.x)} + #{dot.shift * 7}px)"}
        title={"#{Map.get(@names, dot.seat, "Player #{dot.seat + 1}")}: #{dot.vp} VP"}
        data-role="track-dot"
        data-seat={dot.seat}
        data-vp={dot.vp}
        data-step={dot.step}
      >
        <span class={[
          "block rounded-full",
          dot.bg,
          if(dot.seat == @seat,
            do: "size-3 ring-2 ring-parchment/80",
            else: "size-2.5 ring-1 ring-black/40"
          )
        ]} />
      </span>
      <span
        class="absolute top-3.5 -translate-x-1/2 -translate-y-[calc(100%+0.4rem)] text-[10px] leading-none font-bold text-parchment tabular-nums"
        style={"left: #{pos(0.5 / @steps)}"}
        aria-hidden="true"
        data-role="leader-vp"
      >
        {@leader}
      </span>
    </div>
    """
  end

  # A position on the track, 0..1, as a CSS length inside an 0.5rem inset.
  defp pos(x), do: "calc(0.5rem + (100% - 1rem) * #{Float.round(x * 1.0, 4)})"

  @doc "A small dot in the seat's colour, before a player's name."
  attr :seat, :integer, required: true
  attr :class, :any, default: nil

  def seat_dot(assigns) do
    assigns = assign(assigns, bg: @seat_bg[assigns.seat])

    ~H"""
    <span
      class={["inline-block size-2.5 shrink-0 rounded-full ring-1 ring-black/30", @bg, @class]}
      data-role="seat-dot"
      data-seat={@seat}
    />
    """
  end

  attr :chip, :any, required: true
  attr :order, :integer, required: true, doc: "position in `player.drawn` (0 = newest)"
  attr :seat, :integer, required: true
  attr :index, :integer, required: true, doc: "the space the chip sits on"
  attr :placed, :integer, required: true, doc: "how many chips were placed on this space"
  attr :size, :atom, required: true
  attr :beat, :integer, default: nil, doc: "the replay beat this chip lights up on"

  defp pot_chip(assigns) do
    {colour, value} = assigns.chip
    icon = if colour in @ink_icon_chips, do: "text-ink", else: "text-white"
    # The other players' pots are drawn small: a bigger badge keeps the value legible.
    badge = if assigns.size == :lg, do: {9, 9, 10.5, 16}, else: {8, 8, 12.5, 20}
    assigns = assign(assigns, colour: colour, value: value, icon: icon, badge: badge)

    ~H"""
    <g
      id={pot_chip_id(@seat, @index, @placed, @size)}
      data-role="pot-chip"
      data-order={@order}
      data-index={@index}
      aria-label={"#{@colour} #{@value}"}
    >
      <circle
        r="19"
        fill={"var(--color-chip-#{@colour})"}
        stroke={if @colour == :white, do: "#9a9a94", else: "rgb(0 0 0 / 0.4)"}
        stroke-width="2.5"
      />
      <path
        d="M-15 -9 A17 17 0 0 1 9 -15"
        fill="none"
        stroke="white"
        stroke-opacity="0.35"
        stroke-width="2"
      />
      <.ingredient_icon
        colour={@colour}
        x={if @colour == :locoweed, do: "-12", else: "-14"}
        y={if @colour == :locoweed, do: "-12", else: "-14"}
        width={if @colour == :locoweed, do: "24", else: "22"}
        height={if @colour == :locoweed, do: "24", else: "22"}
        class={@icon}
      />
      <g :if={@colour != :locoweed} data-role="chip-value">
        <circle
          cx={elem(@badge, 0)}
          cy={elem(@badge, 1)}
          r={elem(@badge, 2)}
          fill="var(--color-parchment-light)"
          stroke="var(--color-ink)"
          stroke-width="2"
        />
        <text
          x={elem(@badge, 0)}
          y={elem(@badge, 1)}
          dy="0.36em"
          text-anchor="middle"
          font-size={elem(@badge, 3)}
          font-weight="700"
          font-family="var(--font-hand)"
          fill="var(--color-ink)"
        >
          {@value}
        </text>
      </g>
      <.beat_ring beat={@beat} r="24" />
    </g>
    """
  end

  # A gold ring that flashes on its replay beat (app.css, `beat-ring`); nothing
  # without a beat.
  attr :beat, :integer, default: nil
  attr :r, :string, required: true
  attr :cx, :string, default: "0"
  attr :cy, :string, default: "0"

  defp beat_ring(assigns) do
    ~H"""
    <circle
      :if={@beat}
      r={@r}
      cx={@cx}
      cy={@cy}
      fill="none"
      stroke="var(--color-gold)"
      stroke-width="5"
      data-role="beat-ring"
      data-beat={@beat}
      style={"--beat: #{@beat}"}
    />
    """
  end

  # What a chip shows: its value. Locoweed has no printed value: an "L".
  defp face({:locoweed, _}), do: "L"
  defp face({_colour, value}), do: value

  defp translate(index) do
    {x, y} = elem(@positions, index)
    "translate(#{x} #{y})"
  end

  # Where a scoring effect starts, in pot units: its chip's space, the droplet, or
  # the scoring space's own ruby (for a ruby) or VP seal (for a VP tag).
  defp fx_at(%{at: :droplet}, droplet, _ring), do: elem(@positions, droplet)
  defp fx_at(%{at: :ring, kind: kind}, _droplet, ring), do: offset(elem(@positions, ring), kind)
  defp fx_at(%{at: index}, _droplet, _ring), do: elem(@positions, index)

  defp offset({x, y}, :ruby), do: {x + 15, y - 20}
  defp offset({x, y}, :vp), do: {x + 14, y + 14}

  # The same place as a CSS `translate`, so a change can transition (SVG user units = px).
  defp translate_style(index) do
    {x, y} = elem(@positions, index)
    "translate: #{x}px #{y}px"
  end

  # Fixed per seat, space and placement, so LiveView patches the same node and a new
  # chip is a new node (its landing plays once), also on a space a returned chip
  # left. Your own pot, the first chip on space 5: `pot-chip-0-5-1`.
  defp pot_chip_id(seat, index, placed, :lg), do: "pot-chip-#{seat}-#{index}-#{placed}"
  defp pot_chip_id(seat, index, placed, size), do: "pot-chip-#{seat}-#{index}-#{placed}-#{size}"

  # `%{index => n}`: how many chips `seat` placed on each space this game (the log's
  # `{:drew, chip, index}` events).
  defp placements(log, seat) do
    Enum.reduce(log, %{}, fn
      {^seat, {:drew, _chip, index}}, acc -> Map.update(acc, index, 1, &(&1 + 1))
      _entry, acc -> acc
    end)
  end

  defp space_title(index) do
    space = PotTrack.at(index)
    ruby = if space.ruby?, do: ", ruby", else: ""
    "Space #{index}: #{space.coins} coins, #{space.vp} VP#{ruby}"
  end

  # Each chip remembers the space it landed on, so the pot just reads it back.
  # The value is `{chip, order}`: `order` is the chip's position in `drawn`.
  defp chips_by_index(%{drawn: drawn}),
    do:
      drawn
      |> Enum.with_index()
      |> Map.new(fn {{chip, index}, order} -> {index, {chip, order}} end)

  @doc """
  What is left in the bag, as a count per kind of chip. The bag's order is hidden:
  only counts are shown, so the next draw stays a surprise.
  """
  attr :bag, :list, required: true, doc: "list of `{colour, value}` chips"

  def bag(assigns) do
    ~H"""
    <div class="paper rounded-lg p-3">
      <h2 class="text-lg font-bold">Bag ({length(@bag)} chips)</h2>
      <.chip_counts chips={@bag} size={:md} />
    </div>
    """
  end

  @doc """
  Chips as a count per kind, e.g. white 1 ×4, in the board's colour order
  (`Chips.order/0`), then by value. Shows no
  order, so it is safe for a bag.
  """
  attr :chips, :list, required: true, doc: "list of `{colour, value}` chips"
  attr :size, :atom, default: :sm, values: [:sm, :md]

  def chip_counts(assigns) do
    counts = assigns.chips |> Enum.frequencies() |> Enum.sort_by(&Chips.sort_key(elem(&1, 0)))
    assigns = assign(assigns, counts: counts)

    ~H"""
    <ul class={["mt-1 flex flex-wrap", if(@size == :md, do: "gap-2", else: "gap-x-2 gap-y-1")]}>
      <li :for={{chip, count} <- @counts} class="flex items-center gap-0.5 text-sm">
        <.chip chip={chip} size={@size} />
        <span class="ml-1 text-ink-soft tabular-nums" data-role="chip-count">×{count}</span>
      </li>
      <li :if={@counts == []} class="text-ink-soft">empty</li>
    </ul>
    """
  end

  @doc """
  The bag beside the pot: a pouch with the number of chips in it and a small
  magnifying glass. It opens the `sheet-bag` sheet with the counts per kind.
  """
  attr :count, :integer, required: true
  attr :class, :any, default: "relative", doc: "must position it (the glass sits in its corner)"

  def bag_button(assigns) do
    ~H"""
    <button
      type="button"
      popovertarget="sheet-bag"
      class={[
        "size-14 touch-manipulation drop-shadow-[0_2px_3px_rgb(0_0_0/0.5)]",
        "transition-transform duration-100 ease-out active:scale-95",
        @class
      ]}
      aria-label={"Bag: #{@count} chips. Show what is in it"}
      aria-keyshortcuts="b"
      title="Bag (b)"
      data-role="bag-button"
    >
      <svg viewBox="0 0 48 48" class="size-full" aria-hidden="true">
        <defs>
          <linearGradient id="bag-cloth" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#a87444" />
            <stop offset="55%" stop-color="var(--color-wood)" />
            <stop offset="100%" stop-color="var(--color-wood-dark)" />
          </linearGradient>
        </defs>
        <%!-- the ruffled top above the drawstring --%>
        <path
          d="M17 4 q2 2 3.5 0 q2 2 3.5 0 q2 2 3.5 0 q2 2 3.5 0 L28.5 14 h-9 Z"
          fill="#a87444"
          stroke="var(--color-wood-dark)"
          stroke-width="1.5"
          stroke-linejoin="round"
        />
        <%!-- the sack: a wide round bottom under a pinched neck --%>
        <path
          d="M19.5 14 C9 18 4 30 6 38 C8 45 16 46 24 46 C32 46 40 45 42 38 C44 30 39 18 28.5 14 Z"
          fill="url(#bag-cloth)"
          stroke="var(--color-wood-dark)"
          stroke-width="2"
          stroke-linejoin="round"
        />
        <%!-- cloth folds --%>
        <g
          fill="none"
          stroke="#c99a66"
          stroke-opacity="0.55"
          stroke-width="1.3"
          stroke-linecap="round"
        >
          <path d="M17 19 q-5 8 -6 16" />
          <path d="M31 19 q5 8 6 16" />
          <path d="M22 17 q-1 4 -2 6" />
          <path d="M27 17 q1 4 2 6" />
        </g>
        <%!-- the drawstring and its knot --%>
        <path
          d="M17.5 14.5 q6.5 2.5 13 0"
          fill="none"
          stroke="var(--color-parchment-dim)"
          stroke-width="2"
          stroke-linecap="round"
        />
        <path
          d="M30 15 q3 3 1 6 M30 15 q5 1 6 5"
          fill="none"
          stroke="var(--color-parchment-dim)"
          stroke-width="1.5"
          stroke-linecap="round"
        />
        <circle cx="30" cy="15" r="1.8" fill="var(--color-parchment-dim)" />
        <text
          x="24"
          y="36"
          text-anchor="middle"
          font-size="15"
          font-weight="700"
          fill="var(--color-parchment-light)"
        >
          {@count}
        </text>
      </svg>
      <span class="absolute -right-1 -bottom-1 inline-flex size-6 items-center justify-center rounded-full bg-parchment text-ink ring-1 ring-ink-soft">
        <span class="hero-magnifying-glass-mini size-4"></span>
      </span>
    </button>
    """
  end

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
        <dd class="block max-w-[7.5rem] truncate rounded-full bg-parchment/15 px-2 py-0.5 font-semibold max-sm:text-xs sm:max-w-none">
          {round_phase_name(@game, Game.phase(@game, @seat))}
        </dd>
      </div>
    </dl>
    """
  end

  @doc """
  One seat's score and resources in one row of icons with numbers: VP (laurel),
  rubies, the flask (full or empty glass), the essence with The Alchemists, and the
  coins while it buys. Each pair is a `dt` (the word, for screen readers) and a
  `dd`. A badge shows after an explosion. The white total is the fuse
  (`fuse_meter/1`) above the action bar.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0

  attr :beats, :map,
    default: %{},
    doc: "while the replay plays: `%{vp: beat, rubies: beat}`, when each counter ticks"

  def status(assigns) do
    assigns =
      assign(assigns,
        me: assigns.game.players[assigns.seat],
        shop?: Game.phase(assigns.game, assigns.seat) == :shop,
        alchemists?: Game.expansion?(assigns.game, :alchemists)
      )

    ~H"""
    <dl
      class="paper flex min-h-10 flex-wrap items-center justify-around gap-x-3 gap-y-1 rounded-lg px-2 py-1"
      data-role="stats"
    >
      <.stat
        label="VP"
        value={@me.vp}
        id="stat-vp"
        icon={:vp}
        beat={@beats[:vp]}
        from={@beats[:vp] && get_in(@beats, [:from, :vp])}
      />
      <.stat
        label="Rubies"
        value={@me.rubies}
        id="stat-rubies"
        icon={:ruby}
        beat={@beats[:rubies]}
        from={@beats[:rubies] && get_in(@beats, [:from, :rubies])}
      />
      <div class="flex items-center gap-1" title={"Flask #{flask_word(@me.flask)}"}>
        <dt class="flex">
          <.piece_icon
            name={:flask}
            class={["size-6", if(@me.flask, do: "text-potion", else: "text-ink-soft/40")]}
          />
          <span class="sr-only">Flask</span>
        </dt>
        <dd class="text-xs font-semibold text-ink-soft" data-role="flask-state">
          {flask_word(@me.flask)}
        </dd>
      </div>
      <div :if={@alchemists?} class="flex items-center gap-1" title="Essence">
        <dt class="flex">
          <span class="size-4 rounded-full bg-potion ring-2 ring-potion-deep/60" aria-hidden="true" />
          <span class="sr-only">Essence</span>
        </dt>
        <dd class="font-hand text-xl leading-none font-bold tabular-nums" data-role="stat-essence">
          {@me.essence}
        </dd>
      </div>
      <%!-- The id holds the value: a new value is a new node, so it pops. --%>
      <div :if={@shop?} class="flex items-center gap-1" title="Coins to spend">
        <dt class="flex">
          <span class="book-coin text-xl" aria-hidden="true" /><span class="sr-only">Coins</span>
        </dt>
        <dd
          id={"stat-coins-#{@me.coins}"}
          class="stat-pop font-hand text-xl leading-none font-bold tabular-nums"
          data-role="coins"
        >
          {@me.coins}<span class="sr-only"> coins to spend</span>
        </dd>
      </div>
      <span
        :if={@me.exploded?}
        id="status-exploded"
        class="rounded-md bg-ruby px-2 text-sm font-semibold text-white"
        data-role="exploded"
      >
        {exploded_text(@me)}
      </span>
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
  The line above the draw strip: what the scoring space pays ("Reward: 8 coins ·
  0 VP · ruby") and, on the right, the chance that the next draw explodes
  (`Quacks.AI.Odds.next_draw/2`, whole percent; 0% for a seat that stopped or
  exploded). One fixed-height line, so a draw never moves the layout.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0

  def reward_line(assigns) do
    assigns =
      assign(assigns,
        space: PotTrack.at(Game.scoring_index(assigns.game, assigns.seat)),
        final?: assigns.game.round == 9,
        explode: explode_percent(assigns.game, assigns.seat)
      )

    # Round 9 has no shop: the line names the VP, not coins to spend.
    ~H"""
    <p
      class="flex h-4 min-w-0 items-center justify-between gap-2 overflow-hidden text-xs leading-4 whitespace-nowrap text-parchment-dim"
      data-role="reward-line"
    >
      <span class="min-w-0 truncate" data-role="next-reward">
        Reward:
        <span :if={!@final?} class="font-semibold text-parchment">{@space.coins} {plural(
          @space.coins,
          "coin",
          "coins"
        )} ·</span>
        <span class="font-semibold text-gold">{@space.vp} VP</span><span :if={@space.ruby?}> · <span class="font-semibold text-ruby-light">ruby</span></span>
      </span>
      <span class="shrink-0" data-role="explode-chance" data-percent={@explode}>
        Explode: <span class="font-semibold text-parchment tabular-nums">{@explode}%</span>
      </span>
    </p>
    """
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
    <dt class="flex items-center gap-1 text-xs leading-tight text-ink-soft">
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
    <div class="flex items-center gap-1" title={@label}>
      <dt class="flex">
        <.piece_icon
          name={@icon}
          class={["size-6", if(@icon == :ruby, do: "text-ruby", else: "text-gold drop-shadow-sm")]}
        />
        <span class="sr-only">{@label}</span>
      </dt>
      <dd
        id={@id}
        class="stat-tick font-hand text-xl leading-none font-bold tabular-nums"
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
      assign(assigns, p: assigns.game.players[assigns.seat], border: @seat_border[assigns.seat])

    ~H"""
    <article
      class={["paper space-y-2 rounded-lg border-t-4 p-2 text-sm", @border]}
      data-seat={@seat}
      data-role="player-card"
    >
      <header class="flex flex-wrap items-center gap-1.5 pr-8">
        <.seat_dot seat={@seat} />
        <span class="font-hand text-lg font-bold" data-role="player-name">{@name}</span>
        <span :if={@you} class="text-xs font-semibold text-ink-soft">you</span>
        <.player_state game={@game} seat={@seat} />
        <span
          :if={@p.exploded?}
          class="rounded bg-ruby px-1.5 text-xs font-bold text-white"
          data-role="exploded-badge"
        >
          Exploded
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
        "inline-flex items-center rounded px-1 text-[10px] leading-4 font-bold uppercase tracking-wide",
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
  One player's tile in the players row (round 27, design B), a button that opens
  the player's detail sheet (`sheet-player-N`). Line 1: the seat disc with the
  initial, the name (one line, a long one ends in an ellipsis) and the bot icon.
  Line 2: this round's pot space (its coins, large) and VP. Line 3: rubies, the
  black chips in the pot, then the flask, rat tails, essence, test tube, patient or
  witch pennies while they fit (the line wraps into hidden overflow, so the tile
  never grows).

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
  attr :updates, :list, default: [], doc: "the round's results, `Replay.updates/2`"

  attr :ticks, :boolean,
    default: false,
    doc: "while the replay runs: the counters tick on their beats"

  slot :inner_block, doc: "extra badges on the tile (the evaluation on the tiles)"

  def player_chip(assigns) do
    p = assigns.game.players[assigns.seat]
    state = seat_state(assigns.game, assigns.seat)

    assigns =
      assign(assigns,
        p: p,
        bg: @seat_bg[assigns.seat],
        state: state,
        boom: p.exploded? and p.drawn != [],
        stopped: state == "stopped"
      )

    ~H"""
    <button
      type="button"
      popovertarget={"sheet-player-#{@seat}"}
      phx-click={JS.push("open_player", value: %{seat: @seat})}
      class={[
        "player-tile relative flex h-[3.25rem] w-full min-w-0 cursor-pointer flex-col justify-center rounded-[9px] px-1.5 text-left touch-manipulation",
        "transition-[scale,background-color,opacity] duration-150 ease-out active:scale-[0.97]",
        if(@you,
          do: "border-2 border-gold bg-gold/15",
          else: "border border-parchment/12 bg-black/25 hover:bg-black/35"
        ),
        @boom && "tile-boom",
        @stopped && "opacity-55",
        @lead && "tile-lead"
      ]}
      style={"grid-row: #{@row}" <> if(@col, do: "; grid-column: #{@col}", else: "")}
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
      <span class="flex w-full min-w-0 items-center gap-1">
        <span class="relative shrink-0">
          <span
            class={[
              "grid size-4 place-items-center rounded-full text-[10px] leading-none font-extrabold text-ink ring-1 ring-black/40",
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
        </span>
        <%!-- One line: a long name ends in an ellipsis, the BOT badge stays whole
             beside it (round 14: "Wilhelmina" wrapped as "Wilhelmin / a"). --%>
        <span
          class="flex min-w-0 items-center gap-1 text-[11px] leading-tight font-semibold"
          data-role="player-name"
        >
          <span class="min-w-0 truncate" data-role="player-name-text">
            {@name}<span :if={@you} class="sr-only"> (you)</span>
          </span>
          <%!-- Phones: the chip icon, so "Septimus BOT" does not wrap. --%>
          <.bot_badge
            :if={@bot}
            compact={:phone}
            class="shrink-0 bg-transparent px-0! text-parchment-dim"
          />
        </span>
      </span>
      <.chip_stats game={@game} p={@p} ticks={@ticks && card_ticks(@game, @seat, @updates)} />
      <.player_state game={@game} seat={@seat} tile class="absolute -top-1.5 -right-1.5" />
      {render_slot(@inner_block)}
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

  attr :game, Game, required: true
  attr :p, Player, required: true
  attr :ticks, :any, default: nil, doc: "`%{vp: {beat, from}, rubies: {beat, from}}`"

  # The tile's lines 2 and 3: the pot space (its coins, large) and VP; rubies, the
  # black chips in the pot, then the flask (full or empty), this round's rat tails (rats
  # on), essence (The Alchemists), the test tube (reverse pot side), the patient or
  # the witch pennies (spent ones dim). One line high: what does not fit wraps into
  # the hidden overflow, the sheet has it all.
  defp chip_stats(assigns) do
    assigns =
      assign(assigns,
        index: Player.scoring_index(assigns.p),
        black: Enum.count(Player.pot_chips(assigns.p), &match?({:black, _}, &1))
      )

    ~H"""
    <span
      class="flex h-[1.125rem] w-full min-w-0 items-end justify-between gap-1 font-hand leading-none font-bold tabular-nums"
      data-role="player-score"
    >
      <b
        class="text-lg leading-none text-parchment-light"
        title="Pot space (coins)"
        data-role="player-space"
        data-index={@index}
      >
        {PotTrack.at(@index).coins}<span class="sr-only"> pot space</span>
      </b>
      <span class="flex items-center gap-px text-[15px] text-gold" title="VP" data-role="player-vp">
        <.piece_icon name={:vp} class="size-3 text-gold" /><.card_count
          value={@p.vp}
          tick={@ticks && @ticks[:vp]}
        />
        <span class="sr-only">VP</span>
      </span>
    </span>
    <span
      class="flex h-3.5 w-full min-w-0 flex-wrap items-center gap-x-1.5 overflow-hidden text-[11px] leading-3.5 font-semibold tabular-nums"
      data-role="player-stats"
    >
      <span class="flex items-center gap-px" title="Rubies" data-role="player-rubies">
        <.piece_icon name={:ruby} class="size-2.5 text-ruby-light" /><.card_count
          value={@p.rubies}
          tick={@ticks && @ticks[:rubies]}
        />
        <span class="sr-only">rubies</span>
      </span>
      <span class="flex items-center gap-0.5" title="Black chips in the pot" data-role="player-black">
        <span class="size-2 rounded-full bg-chip-black ring-1 ring-penny-silver" aria-hidden="true" />{@black}
        <span class="sr-only">black chips in the pot</span>
      </span>
      <span
        class="flex items-center"
        title={"Flask #{flask_word(@p.flask)}"}
        data-role="player-flask"
        data-flask={flask_word(@p.flask)}
      >
        <.piece_icon
          name={:flask}
          class={["size-3", if(@p.flask, do: "text-potion-light", else: "text-parchment-dim/50")]}
        />
        <span class="sr-only">flask {flask_word(@p.flask)}</span>
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

  # The status graphic (see `seat_state/2`): a steam wisp while brewing, a lid once
  # stopped, a burst after an explosion, three dots while choosing, a tick when
  # ready. No word on screen: the word is for screen readers only. Everyone shops at
  # once, so the shop shows nothing. On a tile (`tile`, round 27, design B): nothing
  # while brewing, a check once stopped and a large red burst after an explosion.
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
      class={["grid size-5 shrink-0 place-items-center", @class]}
      title={@state}
      data-role="player-state"
      data-state={@state}
    >
      <svg viewBox="0 0 24 24" class="size-5" aria-hidden="true">
        <path
          d="M12 1l2.6 6.2 6.4-2.6-2.9 6.1L24 13l-6.4 1.6 2 6.4-5.7-3.4L12 23l-1.9-5.4-5.7 3.4 2-6.4L0 13l5.9-2.3L3 4.6l6.4 2.6z"
          fill="var(--color-ruby)"
          stroke="#ffd25a"
          stroke-width="1.2"
        />
      </svg>
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
    <span
      :if={@state && @state not in ["shopping"]}
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
          <% :burst -> %>
            <path
              d="M8 1.5l1.3 3.6 3.7-1.4-1.6 3.5 3.1 2-3.7.6.3 3.8L8 11.4 4.9 13.6l.3-3.8-3.7-.6 3.1-2L3 3.7l3.7 1.4z"
              fill="currentColor"
              stroke-width="0.8"
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
  defp state_graphic("exploded"), do: :burst
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
    assigns = assign(assigns, :colours, @colours)

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
  the desktop books column (80rem). Each tile: the icon, the
  name, the book number, when it acts and its rule; tiered books show their tiers
  inline, only the rows for this table size. `beats` (`%{colour => beat}`) lights a
  book up on the replay beat of its line (app.css `.book-beat`).
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
    <section
      id={@id}
      class={["min-h-0 flex-col gap-1.5", @class]}
      aria-label="Ingredient books"
      {@rest}
    >
      <h2 class="flex items-baseline gap-2 px-1 font-hand text-lg font-bold text-parchment">
        <QuacksWeb.CoreComponents.icon name="hero-book-open" class="size-4 self-center" />
        Books in play
        <span class="ml-auto font-sans text-xs font-normal text-parchment-dim">
          {@players} {if @players == 1, do: "player", else: "players"}
        </span>
      </h2>
      <ol class="min-h-0 space-y-1.5 overflow-y-auto pb-1" data-role="books-in-play">
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
    </section>
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
  Red Set 2 chips waiting beside the pot (not in the bag): a small pill of chips
  for the pot's top right corner (round 22). The chips overlap a little, so four
  still fit the corner; the label is for screen readers only.
  """
  attr :chips, :list, required: true, doc: "the player's `aside` chips"
  attr :class, :any, default: nil

  def aside(assigns) do
    ~H"""
    <div
      class={[
        "paper flex items-center -space-x-1.5 rounded-full p-1 shadow-md ring-2 ring-ruby/70",
        @class
      ]}
      role="group"
      aria-label={"Beside the pot: #{Enum.map_join(@chips, ", ", fn {c, v} -> "#{c} #{v}" end)}"}
      title="Toadstool chips beside the pot"
      data-role="beside-pot"
    >
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
  The newest `limit` lines of `log` in the words of `action_log/1`, newest first
  (a bug report's log). `names` as in `action_log/1`.
  """
  @spec log_text(list, pos_integer, map | nil) :: [String.t()]
  def log_text(log, limit, names),
    do: for({_seat, line} <- log_lines(log, limit, names), do: line)

  defp log_lines(log, limit, names) do
    log
    |> drop_stop_before_stopped()
    |> Enum.reject(&(&1 |> untag() |> narrated_by_event?()))
    |> Enum.take(limit)
    |> Enum.map(&log_line(&1, names))
  end

  # `{seat, text}`; seat is nil when no dot shows (solo, or an untagged entry).
  defp log_line({seat, entry}, names) when is_integer(seat) and is_map(names),
    do: {seat, "#{Map.get(names, seat, GameServer.default_name(seat))}: #{log_label(entry)}"}

  defp log_line(entry, _names), do: {nil, entry |> untag() |> log_label()}

  # The `:stop` action and the `:stopped` event are one stop, and `:resume` and
  # `:resumed` are one resume: keep the event only.
  defp drop_stop_before_stopped(log) do
    [nil | log]
    |> Enum.zip(log)
    |> Enum.reject(fn {newer, entry} -> echo?(newer, entry) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp echo?({seat, :stopped}, {seat, :stop}), do: true
  defp echo?({seat, :resumed}, {seat, :resume}), do: true
  defp echo?(_newer, _entry), do: false

  defp untag({seat, entry}) when is_integer(seat), do: entry
  defp untag(entry), do: entry

  # The log tells what happened, in the past tense: an action the player took reads
  # "Bought nothing", not the button's "Buy nothing". Events already read so.
  defp log_label(:stop), do: "Stopped"
  defp log_label(:resume), do: "Resumed brewing"
  defp log_label({:explosion_choice, :vp}), do: "Exploded: took the VP"
  defp log_label({:explosion_choice, :buy}), do: "Exploded: took the coins"
  defp log_label({:buy, []}), do: "Bought nothing"
  defp log_label(:keep), do: "Mandrake: kept the white chip"
  defp log_label({:place, chip}), do: "Crow skull: placed #{chip_name(chip)}"
  defp log_label(:return_all), do: "Crow skull: returned all drawn chips to the bag"
  defp log_label(:chip_done), do: "Finished the chip actions"

  defp log_label({:red, {:place, chip}}),
    do: "Toadstool: placed #{chip_name(chip)} after the last chip"

  defp log_label({:red, {:keep, chip}}), do: "Toadstool: kept #{chip_name(chip)} beside the pot"
  defp log_label({:red, {:return, chip}}), do: "Toadstool: returned #{chip_name(chip)} to the bag"
  defp log_label({:essence, {:space, n}}), do: "Essence: took space #{n}"
  defp log_label({:essence, {:swap, chip}}), do: "Chicken eyes: swapped #{chip_name(chip)}"
  defp log_label({:essence, {:place, chip}}), do: "Nervousness: placed #{chip_name(chip)}"
  defp log_label({:essence, :pass}), do: "Essence: passed"
  defp log_label({:witch, colour}), do: "Called the #{colour} witch"

  defp log_label({:witch, :silver, {:place, chip}}),
    do: "Silver witch: placed #{chip_name(chip)}"

  defp log_label({:witch, :silver, :return_all}), do: "Silver witch: returned the rest to the bag"
  defp log_label(:witch_done), do: "Kept the gold penny"
  defp log_label(entry), do: label(entry)

  defp narrated_by_event?(:draw), do: true
  # The event right after says it: `{:returned, chip}`, `{:bought, chips}` or the
  # witch's `{:witch, id, outcome}`.
  defp narrated_by_event?(:use_flask), do: true
  defp narrated_by_event?(:return_white), do: true
  defp narrated_by_event?({:essence, {:buy, _chip}}), do: true
  defp narrated_by_event?({:witch, :silver, n}) when is_integer(n), do: true
  defp narrated_by_event?({:witch, :copper, _choice}), do: true
  defp narrated_by_event?({:buy, [_ | _]}), do: true
  defp narrated_by_event?({:rubies, _}), do: true
  defp narrated_by_event?({:droplet, :tube}), do: true
  defp narrated_by_event?(:end_round), do: true
  # Every card choice logs its outcome right after, as `{:fortune, id, outcome}`.
  defp narrated_by_event?({:fortune, _choice}), do: true
  # Every chip choice logs its `{:effect, ...}` right after.
  defp narrated_by_event?({:chip, _choice}), do: true
  # Every essence spend logs `{:essence_spent, n, what}` right after.
  defp narrated_by_event?({:essence, what}) when what in [:carrot, :double, :return, :hump],
    do: true

  defp narrated_by_event?({:essence, {:forget, _chip}}), do: true
  defp narrated_by_event?(_entry), do: false

  # One face of the bonus die in a 48 × 48 frame: a parchment square with its glyph
  # (the VP number on a laurel, a ruby, a droplet or an orange chip).
  attr :face, :any, required: true, doc: "`{:vp, n}`, `:ruby`, `:droplet` or `:orange`"

  defp die_art(assigns) do
    ~H"""
    <rect
      x="2"
      y="2"
      width="44"
      height="44"
      rx="6"
      fill="var(--color-parchment-light)"
      stroke="var(--color-ink)"
      stroke-width="2.5"
    />
    <%= case @face do %>
      <% {:vp, n} -> %>
        <.piece_icon name={:vp} x="7" y="7" width="34" height="34" class="text-gold" />
        <text
          x="24"
          y="25"
          dy="0.36em"
          text-anchor="middle"
          font-size="20"
          font-weight="700"
          font-family="var(--font-hand)"
          fill="var(--color-ink)"
        >
          {n}
        </text>
      <% :ruby -> %>
        <.piece_icon name={:ruby} x="9" y="9" width="30" height="30" class="text-ruby" />
      <% :droplet -> %>
        <path
          d="M24 6 L35.7 21.4 A13 13 0 1 1 12.3 21.4 Z"
          fill="var(--color-droplet)"
          stroke="#1f3f8a"
          stroke-width="2"
          stroke-linejoin="round"
        />
      <% _orange -> %>
        <circle
          cx="24"
          cy="24"
          r="15"
          fill="var(--color-chip-orange)"
          stroke="rgb(0 0 0 / 0.4)"
          stroke-width="2"
        />
        <.ingredient_icon colour={:orange} x="15" y="15" width="18" height="18" class="text-ink" />
    <% end %>
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

  @die_faces [{:vp, 1}, {:vp, 1}, {:vp, 2}, :ruby, :droplet, :orange]

  @doc """
  The bonus die while the replay plays (scoring sequence): it shows on its beat,
  rolls through its strip, lands, and its line ("Bonus die: +1 VP") fades in after.
  Phones show it in the bar's tray; from 64rem the results panel in the context
  column rolls it (`results_panel/1` in game_live.ex).
  """
  attr :lines, :list, required: true, doc: "the replay's `:die` lines (`Replay.beats/3`)"
  attr :class, :any, default: nil

  def replay_die(assigns) do
    ~H"""
    <div
      :for={line <- @lines}
      class={["replay-die items-center gap-2 rounded-lg bg-iron-dark/70 px-2 py-1", @class]}
      data-role="replay-die"
      data-beat={line.beat}
      style={"--beat: #{line.beat}"}
    >
      <.die face={line.face} />
      <span class="replay-die-text text-sm font-semibold text-parchment">{line.text}</span>
    </div>
    """
  end

  @doc """
  The bonus die for a result line: a strip of seven frames (the six faces in a
  fixed rotated order, no RNG, then `face`), which CSS steps through and lands on
  the last. Without motion only the last frame shows. `data-face` names the face.
  """
  attr :face, :any, required: true, doc: "a die face from the log: `{:vp, n}`, `:ruby`, ..."

  def die(assigns) do
    i = Enum.find_index(@die_faces, &(&1 == assigns.face)) || 0
    {a, b} = Enum.split(@die_faces, rem(i + 3, 6))
    assigns = assign(assigns, frames: Enum.with_index(b ++ a ++ [assigns.face]))

    ~H"""
    <span class="die" data-role="die" data-face={die_key(@face)} aria-hidden="true">
      <svg class="die-strip" viewBox="0 0 48 336">
        <g :for={{face, n} <- @frames} transform={"translate(0 #{n * 48})"}>
          <.die_art face={face} />
        </g>
      </svg>
    </span>
    """
  end

  @doc "One bonus die face, still (round 18: the results table's die column)."
  attr :face, :any, required: true
  attr :class, :any, default: "size-5"

  def die_face(assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 48 48" data-role="die-face" data-face={die_key(@face)}>
      <.die_art face={@face} />
    </svg>
    """
  end

  defp die_key({:vp, n}), do: "vp#{n}"
  defp die_key(face) when is_atom(face), do: Atom.to_string(face)

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

  @doc "The border class of a seat's colour, e.g. `\"border-player-1\"`."
  @spec seat_border(Game.seat()) :: String.t()
  def seat_border(seat), do: @seat_border[seat]

  @doc "The background class of a seat's colour, e.g. `\"bg-player-1\"`."
  @spec seat_bg(Game.seat()) :: String.t()
  def seat_bg(seat), do: @seat_bg[seat]

  @doc "The ring class of seat `seat`'s colour, e.g. `\"ring-player-1\"`."
  @spec seat_ring(Game.seat()) :: String.t()
  def seat_ring(seat), do: @seat_ring[seat]

  @doc """
  The VP `seat` got from the last round's coins and rubies (the round 9
  conversion), or nil when the log has no such entry yet. Reads both log shapes,
  `{:final_conversion, coins_vp, rubies_vp}` and
  `{:final_conversion, coins, coins_vp, rubies, rubies_vp}`.
  """
  @spec buying_power([term], Game.seat()) :: non_neg_integer | nil
  def buying_power(log, seat) do
    Enum.find_value(log, fn
      {^seat, {:final_conversion, cvp, rvp}} -> cvp + rvp
      {^seat, {:final_conversion, _coins, cvp, _rubies, rvp}} -> cvp + rvp
      _entry -> nil
    end)
  end

  @doc """
  Where `seat`'s `total` VP came from, read from the log, as `[{part, vp}]` in a
  fixed order, parts with 0 VP left out. The parts: `:brewing` (scoring spaces,
  overflow bowl, test tubes), `:die` (bonus die), `:chips` (chip and book
  actions), `:rubies` (2 rubies for 1 VP), `:final` (the round 9 conversion),
  `:essence` (The Alchemists), `:witches` (witch calls), `:cards` (fortune teller
  cards), `:pennies` (unused witch pennies at the end) and `:other`, the rest of
  `total`, so the parts always add up to `total`.
  """
  @spec vp_breakdown([term], Game.seat(), integer) :: [{atom, integer}]
  def vp_breakdown(log, seat, total) do
    known =
      for({^seat, entry} <- log, {part, vp} = vp_part(entry), vp != 0, do: {part, vp})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {part, vps} -> {part, Enum.sum(vps)} end)

    other = total - (known |> Map.values() |> Enum.sum())
    parts = Map.put(known, :other, other)

    for part <- [
          :brewing,
          :die,
          :chips,
          :rubies,
          :final,
          :essence,
          :witches,
          :cards,
          :pennies,
          :other
        ],
        vp = Map.get(parts, part, 0),
        vp != 0,
        do: {part, vp}
  end

  @doc "The name of a `vp_breakdown/3` part."
  @spec vp_part_name(atom) :: String.t()
  def vp_part_name(:brewing), do: "Brewing"
  def vp_part_name(:die), do: "Bonus die"
  def vp_part_name(:chips), do: "Chip actions"
  def vp_part_name(:rubies), do: "Rubies"
  def vp_part_name(:final), do: "Final coins and rubies"
  def vp_part_name(:essence), do: "Essence"
  def vp_part_name(:witches), do: "Witches"
  def vp_part_name(:cards), do: "Fortune cards"
  def vp_part_name(:pennies), do: "Unused pennies"
  def vp_part_name(:other), do: "Other"

  @doc "What a `vp_breakdown/3` part counts, for its tooltip."
  @spec vp_part_hint(atom) :: String.t()
  def vp_part_hint(:brewing), do: "Victory points of your scoring spaces"
  def vp_part_hint(:die), do: "The bonus die"
  def vp_part_hint(:chips), do: "Purple, green, black and other chip actions"
  def vp_part_hint(:rubies), do: "2 rubies for 1 victory point"
  def vp_part_hint(:final), do: "Round 9: coins and rubies turned into victory points"
  def vp_part_hint(:essence), do: "The Alchemists: essence and the patient's glasses"
  def vp_part_hint(:witches), do: "Victory points from the witches you called"
  def vp_part_hint(:cards), do: "Victory points from fortune teller cards"
  def vp_part_hint(:pennies), do: "2 victory points for each witch penny you did not use"
  def vp_part_hint(:other), do: "Points that no other part shows, for example rat tails"

  defp vp_part({:pot_vp, vp, _index}), do: {:brewing, vp}
  defp vp_part({:bowl, _chips, vp}), do: {:brewing, vp}
  defp vp_part({:tube, _glass, {:vp, n}}), do: {:brewing, n}
  defp vp_part({:bonus_die, face}), do: {:die, die_vp(face)}
  defp vp_part({:effect, {:green, 6}, {:bonus_die, face}}), do: {:die, die_vp(face)}
  defp vp_part({:rubies_spent, :vp}), do: {:rubies, 1}
  defp vp_part({:final_conversion, cvp, rvp}), do: {:final, cvp + rvp}
  defp vp_part({:final_conversion, _coins, cvp, _rubies, rvp}), do: {:final, cvp + rvp}
  defp vp_part({:essence_vp, n}), do: {:essence, n}
  defp vp_part({:essence_bonus, {:vp, n}}), do: {:essence, n}
  defp vp_part({:witch, _id, {:vp, n}}), do: {:witches, n}
  defp vp_part({:fortune, _id, {:vp, n}}), do: {:cards, n}
  defp vp_part({:pennies, n}), do: {:pennies, n}

  defp vp_part({:purple, _, _} = entry), do: {:chips, gain_vp(entry)}
  defp vp_part({:effect, _, _} = entry), do: {:chips, gain_vp(entry)}
  defp vp_part(_entry), do: {:other, 0}

  defp gain_vp(entry) do
    case Replay.gain(entry) do
      {vp, _rubies} -> vp
      nil -> 0
    end
  end

  defp die_vp({:vp, n}), do: n
  defp die_vp(_face), do: 0

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
  def label(:stopped), do: "Stopped"
  def label(:resumed), do: "Resumed brewing"
  def label(:use_flask), do: "Use flask"
  def label(:end_round), do: "End round"
  def label({:explosion_choice, :vp}), do: "Exploded: take the victory points"
  def label({:explosion_choice, :buy}), do: "Exploded: buy chips instead"
  def label({:rubies, :droplet}), do: "Spend 2 rubies: droplet +1"
  def label({:rubies, :flask}), do: "Spend 2 rubies: refill flask"
  def label({:rubies, :vp}), do: "2 rubies → 1 VP"
  def label({:rubies, :tube}), do: "Spend 2 rubies: test tube +1"
  def label({:droplet, :pot}), do: "Pot droplet +1"
  def label({:droplet, :tube}), do: "Test tube +1"
  def label({:tube, glass, bonus}), do: "Test tube #{glass}: #{tube_bonus(bonus)}"
  def label({:buy, []}), do: "Buy nothing"

  # No price here: it depends on the game's books. The shop shows the prices.
  def label({:buy, chips}) when is_list(chips),
    do: "Buy #{Enum.map_join(chips, " + ", &chip_name/1)}"

  def label(:return_white), do: "Mandrake: put the white chip back in the bag"
  def label(:keep), do: "Mandrake: keep the white chip"
  def label({:place, {colour, value}}), do: "Crow skull: place #{colour} #{value}"
  def label(:return_all), do: "Crow skull: return all drawn chips to the bag"
  def label({:bonus_die, face}), do: "Bonus die: #{die_text(face)}"
  def label({:drew, chip, index}), do: "Drew #{chip_name(chip)} → space #{index}"
  def label({:returned, chip}), do: "Returned #{chip_name(chip)} to the bag"
  def label({:exploded, white_sum}), do: "Exploded (white #{white_sum})"
  def label({:bought, chips}), do: "Bought #{Enum.map_join(chips, " + ", &chip_name/1)}"
  def label({:rubies_spent, :droplet}), do: "Spent 2 rubies: droplet +1"
  def label({:rubies_spent, :flask}), do: "Spent 2 rubies: flask refilled"
  def label({:rubies_spent, :vp}), do: "Spent 2 rubies: +1 VP"
  def label({:rubies_spent, :tube}), do: "Spent 2 rubies: test tube +1"
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

  def label({:final_conversion, coins, coins_vp, rubies, rubies_vp}),
    do:
      "Final: #{coins} coins → #{coins_vp} VP, #{rubies} #{plural(rubies, "ruby", "rubies")} → #{rubies_vp} VP"

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
  def label({:rubies_spent, :tube, 1}), do: "Spent 1 ruby: test tube +1"
  def label({:overflow, chip}), do: "#{chip_name(chip)} went in the overflow bowl"
  def label({:bowl, _chips, vp}), do: "Overflow bowl: +#{vp} VP"
  def label({:pennies, vp}), do: "Unused witch pennies: +#{vp} VP"
  def label({:expansion, :herb_witches}), do: "Playing with The Herb Witches"
  def label({:expansion, :alchemists}), do: "Playing with The Alchemists"

  def label({:patients, ids}),
    do: "Patients dealt: #{Enum.map_join(ids, ", ", &Alchemists.get(&1).name)}"

  def label({:patient, id}), do: "Patient: #{Alchemists.get(id).name}"

  def label({:essence, space, parts}) when is_map(parts),
    do: "Essence: space #{space} (#{Enum.join(AlchemistsComponents.parts_text(parts), ", ")})"

  def label({:essence, {:space, n}}), do: "Essence: take space #{n}"
  def label({:essence, {:swap, chip}}), do: "Chicken eyes: swap #{chip_name(chip)}"
  def label({:essence, {:buy, chip}}), do: "Vampirism: buy #{chip_name(chip)}"
  def label({:essence, {:place, chip}}), do: "Nervousness: place #{chip_name(chip)}"
  def label({:essence, {:forget, chip}}), do: "Forgetfulness: return #{chip_name(chip)}"
  def label({:essence, :pass}), do: "No thanks"
  def label({:essence, :carrot}), do: "Spend 2 essence: pumpkin to the next ruby space"
  def label({:essence, :double}), do: "Spend 2 essence: move the white chip double"
  def label({:essence, :return}), do: "Spend 3 essence: white chip back to the bag"
  def label({:essence, :hump}), do: "Spend 2 essence: Witch's hump bonus"

  def label({:essence_bonus, term}),
    do: "Essence bonus: #{AlchemistsComponents.term_text(term)}"

  def label({:essence_vp, n}), do: "Final essence: +#{n} VP"
  def label({:essence_rat, n}), do: "Essence: rat stone +#{n}"

  def label({:essence_spent, n, what}), do: "Spent #{n} essence: #{essence_use(what)}"

  def label({:display, chips}), do: "Nervousness: laid out #{chip_list(chips)}"
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
  def label({:chip, {:return, chip}}), do: "Locoweed: return #{chip_name(chip)} to the bag"

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
    do: "Crow skull: protected, kept VP and coins"

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

  defp effect({:black, 2}, {:to_left, _seat}),
    do: "Hawkmoth: black chip into the left player's bag, droplet +1"

  defp effect({:black, 2}, :to_supply), do: "Hawkmoth: black chip back to the supply, droplet +1"

  defp effect({:black, 2}, {:rubies, n}),
    do: "Hawkmoth: +#{n} #{plural(n, "ruby", "rubies")}"

  defp effect({:black, 3}, :droplet), do: "Hawkmoth: furthest black chip, droplet +1"
  defp effect({:black, 3}, :ruby), do: "Hawkmoth: second furthest black chip, +1 ruby"
  defp effect({:black, 3}, :droplet_ruby), do: "Hawkmoth: droplet +1, +1 ruby"
  defp effect({:locoweed, _}, {:moves, n}), do: "Locoweed: moved #{n}"

  defp effect({:locoweed, 5}, {:returned, chip}),
    do: "Locoweed: #{chip_name(chip)} back to the bag"

  defp effect({:locoweed, 2}, {:copied, chip}), do: "Locoweed: acted as #{chip_name(chip)}"
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

  @doc "Round 24: what card `id` did for a player (`outcome` of its log entry), as text."
  @spec card_outcome(term, atom) :: String.t()
  def card_outcome(outcome, id), do: outcome |> fortune_outcome(id) |> String.capitalize()

  # What a card did for a player, for the log.
  defp fortune_outcome({:drew, chips}, :p8),
    do: "drew #{chip_list(chips)} (sum #{chips |> Enum.map(&elem(&1, 1)) |> Enum.sum()})"

  defp fortune_outcome({:drew, chips}, :b3), do: "put back #{chip_list(chips)}"
  defp fortune_outcome({:drew, chips}, _id), do: "drew #{chip_list(chips)}"
  defp fortune_outcome(face, :p12), do: "rolled the die: #{die_text(face)}"
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
  defp fortune_outcome(:skip, _id), do: "passed"
  defp fortune_outcome(:remove_white, _id), do: "removed a white 1 from the bag"
  defp fortune_outcome({:rats, n}, _id), do: "rat stone +#{n}"

  defp fortune_outcome({:rats_back, n}, _id),
    do: "rat stone back #{n}, +#{n} #{plural(n, "ruby", "rubies")}"

  defp fortune_outcome({:upgrade, chip}, _id), do: "traded #{chip_name(chip)} up"
  defp fortune_outcome(:orange, _id), do: "took orange 1"
  defp fortune_outcome(other, _id), do: inspect(other)

  defp chip_list(chips), do: Enum.map_join(chips, ", ", &chip_name/1)

  defp essence_use(:carrot), do: "pumpkin to the next ruby space"
  defp essence_use(:double), do: "white chip moved double"
  defp essence_use(:return), do: "white chip back to the bag"
  defp essence_use(:hump), do: "Witch's hump"
  defp essence_use({:forget, chip}), do: "#{chip_name(chip)} back to the bag"

  @doc ~s(A bonus die face in words: "2 VP", "ruby", "droplet +1", "orange 1 chip".)
  def die_text({:vp, n}), do: "#{n} VP"
  def die_text(:ruby), do: "ruby"
  def die_text(:droplet), do: "droplet +1"
  def die_text(:orange), do: "orange 1 chip"
  def die_text(other), do: inspect(other)

  @doc ~s(A test-tube glass bonus in words: "1 ruby", "2 VP", "blue 1 chip".)
  @spec tube_bonus(Quacks.Rules.TestTubes.bonus()) :: String.t()
  def tube_bonus(:ruby), do: "1 ruby"
  def tube_bonus({:vp, n}), do: "#{n} VP"
  def tube_bonus({:chip, chip}), do: "#{chip_name(chip)} chip"

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many

  @doc ~s("green 2" for `{:green, 2}`; locoweed has no value: "locoweed".)
  @spec chip_name(Chips.chip()) :: String.t()
  def chip_name({:locoweed, _}), do: "locoweed"
  def chip_name({colour, value}), do: "#{colour} #{value}"

  # Round 9 has no shop: its shopping phase is the final scoring (rubies, Done).
  defp round_phase_name(%Game{round: 9}, :shop), do: "Final scoring"
  defp round_phase_name(_game, phase), do: phase_name(phase)

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
  def phase_name(:shop), do: "Shop"
  def phase_name(:rubies), do: "Spend rubies"
  def phase_name(:droplet_choice), do: "Droplet"
  def phase_name(:waiting_stir), do: "Stir!"
  def phase_name(:ready), do: "Ready"
  def phase_name(:done), do: "Done"
  def phase_name(:over), do: "Over"
  def phase_name(:patient_choice), do: "Patient"
  def phase_name(:essence), do: "Essence"
  def phase_name(:essence_choice), do: "Essence"
  def phase_name(:essence_bonus), do: "Essence bonus"
  def phase_name(:ear_worm), do: "Ear worm"
  def phase_name(:essence_offer), do: "Essence"
  def phase_name(other), do: inspect(other)
end
