defmodule QuacksWeb.GameComponents do
  @moduledoc """
  Function components that draw a `Quacks.Game` struct. Rendering only: nothing in
  here changes game state. The LiveView passes the struct in; each component reads
  the fields it needs.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
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

  # Your own chip in the players row: a ring and a wash in your seat colour.
  @seat_you %{
    0 => "ring-player-0 bg-player-0/20",
    1 => "ring-player-1 bg-player-1/20",
    2 => "ring-player-2 bg-player-2/20",
    3 => "ring-player-3 bg-player-3/20",
    4 => "ring-player-4 bg-player-4/20",
    5 => "ring-player-5 bg-player-5/20",
    6 => "ring-player-6 bg-player-6/20",
    7 => "ring-player-7 bg-player-7/20"
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
  @ink_icon_chips [:white, :yellow]

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
  attr :size, :atom, default: :md, values: [:xs, :sm, :md]
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
  (another player's pot) shows only the chips. In both, the droplet is a blue drop
  with a dark outline on its space, placed chips sit on their spaces and the rat
  stone, when the player has one, is a grey pebble on its space.

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

  def pot(assigns) do
    player = assigns.game.players[assigns.seat]
    rings = assigns.rings || %{assigns.seat => Game.scoring_index(assigns.game, assigns.seat)}

    assigns =
      assign(assigns,
        me: player,
        chips_by_index: chips_by_index(player),
        placed: placements(assigns.game.log, assigns.seat),
        positions: @positions,
        rings_by_index: rings |> Enum.sort() |> Enum.group_by(&elem(&1, 1), &elem(&1, 0)),
        rat_index: if(player.rat_stone > 0, do: Player.start_index(player)),
        scoring: Game.scoring_index(assigns.game, assigns.seat),
        ring_index: Game.scoring_index(assigns.game, assigns.seat),
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
    >
      <defs>
        <radialGradient id={"brew-#{@seat}-#{@size}"}>
          <stop offset="0%" stop-color="var(--color-potion-light)" stop-opacity="0.55" />
          <stop offset="70%" stop-color="var(--color-potion)" />
          <stop offset="100%" stop-color="var(--color-potion-deep)" />
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
        stroke="var(--color-potion-deep)"
        stroke-opacity="0.45"
        stroke-width="46"
        stroke-linecap="round"
        stroke-linejoin="round"
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
          <.piece_icon
            :if={PotTrack.at(index).ruby?}
            name={:ruby}
            x="8"
            y="-27"
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
      <%!-- The droplet and the rat stone sit above the spaces, each in one group with a
           fixed id: when the space changes, only `translate` changes and CSS slides it. --%>
      <g
        id={"droplet-#{@seat}-#{@size}"}
        data-role="droplet"
        data-index={@me.droplet}
        style={translate_style(@me.droplet)}
      >
        <g transform="translate(-20 -9) scale(0.62)" aria-label="droplet">
          <path
            d="M0 -22 L8.91 -4.55 A10 10 0 1 1 -8.91 -4.55 Z"
            fill={"url(#drop-#{@seat}-#{@size})"}
            stroke="#1f3f8a"
            stroke-width="2.4"
            stroke-linejoin="round"
          />
          <path
            d="M-5.5 -5 Q-6 0 -3 3.5"
            fill="none"
            stroke="white"
            stroke-opacity="0.6"
            stroke-width="2.4"
            stroke-linecap="round"
          />
        </g>
        <.beat_ring beat={@beats[:droplet]} r="14" cx="-20" cy="-15" />
      </g>
      <g
        :if={@rat_index}
        id={"rat-#{@seat}-#{@size}"}
        data-role="rat-stone"
        data-index={@rat_index}
        style={translate_style(@rat_index)}
      >
        <ellipse
          class="rat-pebble"
          cx="17"
          cy="16"
          rx="8"
          ry="6"
          fill="#8b9097"
          stroke="var(--color-iron-dark)"
          stroke-width="1.5"
          aria-label="rat stone"
        />
        <.piece_icon
          name={:rat}
          x="10"
          y="9"
          width="14"
          height="14"
          class="text-parchment-light"
        />
      </g>
      <.flask
        :if={@flask}
        id={"flask-#{@seat}"}
        full={@flask == :full}
        click={@flask_click}
        uid={"#{@seat}-#{@size}"}
      />
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
  Chips as a count per kind, e.g. white 1 ×4, sorted by colour and value. Shows no
  order, so it is safe for a bag.
  """
  attr :chips, :list, required: true, doc: "list of `{colour, value}` chips"
  attr :size, :atom, default: :sm, values: [:sm, :md]

  def chip_counts(assigns) do
    assigns = assign(assigns, counts: assigns.chips |> Enum.frequencies() |> Enum.sort())

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

  @doc """
  This round's Fortune Teller card as a small parchment card beside the pot: the
  colour band and the name. It opens the `sheet-fortune` sheet with the full text.
  """
  attr :id, :atom, required: true, doc: "`game.fortune_card`"
  attr :class, :any, default: nil

  def fortune_tile(assigns) do
    assigns = assign(assigns, card: Fortune.card(assigns.id))

    ~H"""
    <button
      type="button"
      popovertarget="sheet-fortune"
      class={[
        "paper flex w-22 rotate-3 flex-col overflow-hidden rounded-md text-left touch-manipulation",
        "transition-transform duration-100 ease-out active:scale-95",
        @class
      ]}
      aria-label={"Fortune teller card: #{@card.name}. Show the text"}
      data-role="fortune-tile"
      data-colour={@card.colour}
    >
      <span class={[
        "h-2 w-full",
        @card.colour == :blue && "bg-chip-blue",
        @card.colour == :purple && "bg-chip-purple"
      ]} />
      <span class="line-clamp-2 px-1.5 py-1 font-hand text-xs leading-tight font-bold">
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
        <dt class="text-parchment-dim">Round</dt>
        <dd class="round-counter font-semibold tabular-nums" data-role="round-counter">
          {@game.round} / 9
        </dd>
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
  One seat's score and resources in one row of icons with numbers: VP (laurel),
  rubies, the flask (full or empty glass), the essence with The Alchemists, and the
  coins while it buys. Each pair is a `dt` (the word, for screen readers) and a
  `dd`. A badge shows after an explosion. The white total is the fuse
  (`fuse_meter/1`) above the action bar.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0

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
      <.stat label="VP" value={@me.vp} id="stat-vp" icon={:vp} />
      <.stat label="Rubies" value={@me.rubies} id="stat-rubies" icon={:ruby} />
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

  @doc ~s{What the scoring space pays, for the bar: "Next: 8 coins · 2 VP · ruby".}
  attr :game, Game, required: true
  attr :seat, :integer, default: 0

  def next_reward(assigns) do
    assigns = assign(assigns, space: PotTrack.at(Game.scoring_index(assigns.game, assigns.seat)))

    ~H"""
    <p class="shrink-0 text-right text-xs leading-tight text-parchment-dim" data-role="next-reward">
      Next:
      <span class="font-semibold text-parchment">{@space.coins} coins</span><span :if={@space.vp > 0}> · <span class="font-semibold text-gold">{@space.vp} VP</span></span><span :if={
        @space.ruby?
      }> · <span class="font-semibold text-ruby">ruby</span></span>
    </p>
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
        style={"--n: #{@value}"}
      >
        <span class="sr-only">{@value}</span>
        <span id={"#{@id}-#{@value}"} class="stat-pop" aria-hidden="true"></span>
      </dd>
    </div>
    """
  end

  @doc """
  One player at the table, read-only, for the player detail sheet: name and VP up
  front (with a band in the seat colour), what they do now, rubies, flask, white
  sum, their pot drawn small, the bowl and what is in their bag (counts only).
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
      <AlchemistsComponents.flask_strip :if={@p.patient} game={@game} seat={@seat} size={:sm} />
      <.pot game={@game} seat={@seat} size={:sm} class="mx-auto block h-auto w-full max-w-64" />
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
  attr :compact, :boolean, default: false

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
      <%= if @compact do %>
        <span class="hero-cpu-chip-micro size-3" aria-hidden="true"></span><span class="sr-only">bot</span>
      <% else %>
        bot
      <% end %>
    </span>
    """
  end

  @doc """
  One player in the players row under the status strip: colour dot, name, VP and
  what they do now. A tap opens that player's detail sheet (`sheet-player-N`).
  Your own chip says "you" and wears your seat colour as a ring.
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :name, :string, required: true
  attr :you, :boolean, default: false
  attr :bot, :boolean, default: false

  def player_chip(assigns) do
    assigns =
      assign(assigns, p: assigns.game.players[assigns.seat], you_class: @seat_you[assigns.seat])

    ~H"""
    <button
      type="button"
      popovertarget={"sheet-player-#{@seat}"}
      class={[
        "flex min-h-11 w-full min-w-0 cursor-pointer flex-col justify-center gap-0.5 rounded-lg px-1.5 py-1 text-left text-xs touch-manipulation",
        "transition-[scale,background-color] duration-150 ease-out active:scale-[0.97]",
        if(@you,
          do: ["ring-2", @you_class],
          else: "bg-iron-dark/80 ring-1 ring-iron hover:bg-iron-dark"
        )
      ]}
      title={@name}
      data-seat={@seat}
      data-role="player-chip"
      data-you={@you && "true"}
    >
      <span class="flex w-full min-w-0 items-center gap-1">
        <.seat_dot seat={@seat} />
        <span class="min-w-0 truncate font-semibold" data-role="player-name">{@name}</span>
        <.bot_badge :if={@bot} compact class="shrink-0 bg-parchment/15 text-parchment-dim" />
      </span>
      <span class="flex w-full min-w-0 items-center gap-1">
        <span class="shrink-0 font-semibold tabular-nums" data-role="player-vp">{@p.vp} VP</span>
        <span :if={@you} class="sr-only">you</span>
        <span class="ml-auto min-w-0 truncate"><.player_state game={@game} seat={@seat} /></span>
      </span>
    </button>
    """
  end

  # The badge with what the seat does now (see `seat_state/2`).
  attr :game, Game, required: true
  attr :seat, :integer, required: true

  defp player_state(assigns) do
    assigns = assign(assigns, state: seat_state(assigns.game, assigns.seat))

    ~H"""
    <span
      :if={@state}
      class={["shrink-0 rounded px-1 text-[11px] leading-4", state_class(@state)]}
      data-role="player-state"
      data-state={@state}
    >
      {@state}
    </span>
    """
  end

  @doc """
  What `seat` does now, in one word: "brewing", "stopped" or "exploded" while
  everyone brews (round 9 with 2+ players: "deciding" until the seat picks Draw or
  Stop, then "chosen"); "shopping" or "ready" in the shop; "choosing" or "ready"
  while seats answer a card, chip or witch choice; with The Alchemists "choosing
  patient" before round 1 and "essence" in the essence phase. `nil` once the game
  is over.
  """
  @spec seat_state(Game.t(), Game.seat()) :: String.t() | nil
  def seat_state(%Game{phase: :potions, players: players} = game, seat) do
    case players[seat] do
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

  defp state_class(state) when state in ["stopped", "ready", "chosen"],
    do: "bg-iron text-parchment"

  defp state_class("exploded"), do: "bg-ruby font-bold text-white"
  defp state_class(_state), do: "bg-parchment-deep text-ink"

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

  def book_list(assigns) do
    assigns = assign(assigns, :colours, @colours)

    ~H"""
    <dl class="space-y-2" data-role="book-list">
      <div :for={{colour, set} <- @books} data-book={"#{colour}-#{set}"}>
        <dt class="flex items-center gap-1.5 text-sm font-semibold">
          <.ingredient_icon colour={colour} class={["size-4", book_ink(colour)]} />
          {String.capitalize(to_string(colour))} {book_set_name(colour, set)}
        </dt>
        <dd><.book_text book={Books.get({colour, set})} players={@players} /></dd>
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
  The book `{colour, set}` for display: `Books.get/1` plus `chips`, each buyable
  chip of the colour with its price. Locoweed nil is "not in play"; locoweed III
  (The Alchemists' A) acts in the essence phase.
  """
  @spec book_info(Chips.colour(), 1..6 | nil) :: map
  def book_info(:locoweed, nil) do
    %{
      Books.get({:locoweed, 1})
      | text: "No locoweed chips in the shop this game.",
        prices: []
    }
    |> Map.put(:chips, [])
  end

  def book_info(:locoweed, 3) do
    %{
      Books.get({:locoweed, 1})
      | text:
          "Moves 1; in the essence phase your essence marker moves 1 more space for each locoweed in your pot.",
        prices: [Chips.price({:locoweed, 1}, %{locoweed: 3})]
    }
    |> Map.put(:chips, [{{:locoweed, 1}, Chips.price({:locoweed, 1}, %{locoweed: 3})}])
  end

  def book_info(colour, set) do
    sets = %{colour => set}
    chips = for {^colour, _} = chip <- Chips.shop(:herb_witches, sets), do: chip
    Map.put(Books.get({colour, set}), :chips, Enum.map(chips, &{&1, Chips.price(&1, sets)}))
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
      :die,
      :supply,
      :pot_side
    ]

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
  defp rule_label({:supply, :limited}), do: "limited chip supply"
  defp rule_label({:pot_side, :back}), do: "reverse pot side (test tubes)"

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
      hint="Tap a chip to place it, or return them all."
      label="Fortune teller offer"
      accent="border-chip-purple"
    >
      {render_slot(@inner_block)}
    </.blue_offer>
    """
  end

  @doc """
  The Fortune Teller card of this round: a colour band (blue = a rule for the whole
  round, purple = resolved once at the start), its name and its full text.

  ## Examples

      <.fortune_card id={:b7} />
  """
  attr :id, :atom, required: true, doc: "a card id from `Quacks.Rules.Fortune`"
  attr :choice, :boolean, default: false, doc: "the card asks this player a choice now"

  attr :flip, :boolean,
    default: false,
    doc:
      "turn the card over (back, then front) when it enters the page: the new card of the round"

  def fortune_card(%{flip: true} = assigns) do
    ~H"""
    <div id={"card-flip-#{@id}"} class="card-flip" data-role="card-flip">
      <div class="card-flip-inner">
        <div class="card-back" aria-hidden="true">
          <span class="flex flex-col items-center gap-1 font-hand font-bold text-gold">
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
        {band_text(@card.colour, @choice)}
      </div>
      <div class="px-3 py-2">
        <h2 class="text-lg font-bold">{@card.name}</h2>
        <p class="text-ink-soft">{@card.text}</p>
      </div>
    </section>
    """
  end

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
        <.ingredient_icon colour={:orange} x="15" y="15" width="18" height="18" class="text-white" />
    <% end %>
    """
  end

  @doc """
  What each player gained this round: every log entry since the round began that
  gave VP or rubies, plus the bonus die and the Fortune Teller card's outcome, then
  the totals. Below the totals: the rat tails for the next round (2+ players, rats
  on) and, in round 9, the final buying power (coins and rubies → VP; from the log
  once the seat is done, else from what it has now). With `names` (multiplayer)
  there is one block per seat, headed by its name; `me` comes first.

  The step-B replay (`QuacksWeb.Replay`): `me`'s lines carry `data-beat` and
  `--beat`, and CSS reveals them one by one; a die line shows the rolling `die/1`.
  Every other seat's block is one beat after `me`'s total. "Skip" adds
  `replay-done` to the dialog, which shows everything at once.
  """
  attr :game, Game, required: true
  attr :names, :map, default: nil, doc: "`%{seat => name}`; nil for solo"
  attr :me, :integer, default: 0, doc: "the seat whose lines replay beat by beat"
  attr :dialog, :string, default: "round-results", doc: "the dialog id Skip finishes"

  def round_results(assigns) do
    assigns = assign(assigns, blocks: result_blocks(assigns.game, assigns.me))

    ~H"""
    <section class="space-y-3" aria-label="Round results" data-role="round-results">
      <div class="flex items-baseline gap-3">
        <h2 class="text-xl font-bold">Round {@game.round} results</h2>
        <button
          type="button"
          id={"#{@dialog}-skip"}
          data-role="replay-skip"
          phx-click={JS.add_class("replay-done", to: "##{@dialog}")}
          class="min-h-9 rounded-full px-2 text-sm font-semibold text-ink-soft underline underline-offset-2 transition-colors duration-150 hover:text-ink"
        >
          Skip
        </button>
      </div>
      <div
        :for={block <- @blocks}
        class={["space-y-1", @names && ["border-l-4 pl-2", seat_border(block.seat)]]}
        data-seat={block.seat}
        data-beat={block.beat}
        style={beat_style(block.beat)}
      >
        <h3 :if={@names} class="flex items-center gap-1.5 font-hand text-base font-bold">
          <.seat_dot seat={block.seat} />
          {Map.get(@names, block.seat, GameServer.default_name(block.seat))}
        </h3>
        <ul class="space-y-0.5 text-sm">
          <li
            :for={line <- block.lines}
            data-role="result-line"
            data-kind={line.kind}
            data-beat={block.own? && line.beat}
            style={block.own? && beat_style(line.beat)}
            class={line.face && "flex items-center gap-2"}
          >
            <.die :if={line.face} face={line.face} />
            <span class={line.face && "die-text"}>{line.text}</span>
          </li>
          <li
            :if={block.lines == []}
            class="text-ink-soft"
            data-beat={block.own? && 0}
            style={block.own? && beat_style(0)}
          >
            Nothing gained this round.
          </li>
        </ul>
        <p
          class="font-semibold"
          data-role="result-total"
          data-beat={block.own? && block.total}
          style={block.own? && beat_style(block.total)}
        >
          Total: +{total(block.lines, :vp)} VP, +{total(block.lines, :rubies)} {plural(
            total(block.lines, :rubies),
            "ruby",
            "rubies"
          )}
        </p>
        <p
          :if={tails = rat_tails(@game, block.seat)}
          class="flex items-center gap-1 text-sm"
          data-role="result-rats"
          data-beat={block.own? && block.total}
          style={block.own? && beat_style(block.total)}
        >
          <.piece_icon name={:rat} class="size-4 text-ink-soft" />
          Rats next round: {tails} {plural(tails, "tail", "tails")}
        </p>
        <p
          :if={power = final_power(@game, block.seat)}
          class="text-sm font-semibold"
          data-role="result-buying-power"
          data-beat={block.own? && block.total}
          style={block.own? && beat_style(block.total)}
        >
          {power}
        </p>
      </div>
    </section>
    """
  end

  # `me`'s block first, its lines on their own beats and the total one beat after
  # (one after "Nothing gained" when there is nothing); then every other seat as
  # one block, one beat each.
  defp result_blocks(game, me) do
    me = if me in game.seats, do: me, else: hd(game.seats)
    lines = Replay.beats(game, me)
    total = max(Replay.next_beat(lines), 1)

    others =
      (game.seats -- [me])
      |> Enum.with_index(total + 1)
      |> Enum.map(fn {seat, beat} ->
        %{seat: seat, own?: false, beat: beat, total: nil, lines: Replay.beats(game, seat)}
      end)

    [%{seat: me, own?: true, beat: nil, total: total, lines: lines} | others]
  end

  defp beat_style(nil), do: nil
  defp beat_style(beat), do: "--beat: #{beat}"

  defp total(lines, key), do: lines |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

  @die_faces [{:vp, 1}, {:vp, 1}, {:vp, 2}, :ruby, :droplet, :orange]

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

  defp die_key({:vp, n}), do: "vp#{n}"
  defp die_key(face) when is_atom(face), do: Atom.to_string(face)

  # The rat tails `seat` gets at the start of the next round, as the VP stand now;
  # nil when no rats come (solo, house rule off, round 9).
  defp rat_tails(%{seats: [_]}, _seat), do: nil
  defp rat_tails(%{rules: %{rats: false}}, _seat), do: nil
  defp rat_tails(%{round: 9}, _seat), do: nil

  defp rat_tails(game, seat) do
    leader = game.players |> Map.values() |> Enum.map(& &1.vp) |> Enum.max()
    ScoringTrack.rat_tails(game.players[seat].vp, leader)
  end

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
  `:essence` (The Alchemists) and `:other`, the rest of `total` (witches, fortune
  cards, pennies, patient actions), so the parts always add up to `total`.
  """
  @spec vp_breakdown([term], Game.seat(), integer) :: [{atom, integer}]
  def vp_breakdown(log, seat, total) do
    known =
      for({^seat, entry} <- log, {part, vp} = vp_part(entry), vp != 0, do: {part, vp})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {part, vps} -> {part, Enum.sum(vps)} end)

    other = total - (known |> Map.values() |> Enum.sum())
    parts = Map.put(known, :other, other)

    for part <- [:brewing, :die, :chips, :rubies, :final, :essence, :other],
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
  def vp_part_name(:other), do: "Other"

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
  def label(:stopped), do: "Stopped (may resume while others brew)"
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

  # What a card did for a player, for the log.
  defp fortune_outcome({:drew, chips}, :p8),
    do: "drew #{chip_list(chips)} (sum #{chips |> Enum.map(&elem(&1, 1)) |> Enum.sum()})"

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
  defp fortune_outcome(:skip, _id), do: "no thanks"
  defp fortune_outcome(:remove_white, _id), do: "removed a white 1 from the bag"
  defp fortune_outcome({:rats, n}, _id), do: "rat stone +#{n}"

  defp fortune_outcome({:rats_back, n}, _id),
    do: "rat stone back #{n}, +#{n} #{plural(n, "ruby", "rubies")}"

  defp fortune_outcome({:upgrade, chip}, _id), do: "traded #{chip_name(chip)} up"
  defp fortune_outcome(:orange, _id), do: "orange 1 chip"
  defp fortune_outcome(other, _id), do: inspect(other)

  defp chip_list(chips), do: Enum.map_join(chips, ", ", &chip_name/1)

  defp essence_use(:carrot), do: "pumpkin to the next ruby space"
  defp essence_use(:double), do: "white chip moved double"
  defp essence_use(:return), do: "white chip back to the bag"
  defp essence_use(:hump), do: "Witch's hump"
  defp essence_use({:forget, chip}), do: "#{chip_name(chip)} back to the bag"

  defp die_text({:vp, n}), do: "#{n} VP"
  defp die_text(:ruby), do: "ruby"
  defp die_text(:droplet), do: "droplet +1"
  defp die_text(:orange), do: "orange 1 chip"
  defp die_text(other), do: inspect(other)

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
