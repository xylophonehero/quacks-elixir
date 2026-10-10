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
  alias Quacks.Rules.{Alchemists, Books, Chips, PotTrack, ScoringTrack, TestTubes}
  alias Quacks.Rules.Fortune
  alias Quacks.Rules.Witches
  alias QuacksWeb.{AlchemistsComponents, Replay}

  import QuacksWeb.GameText
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
  Round 35 (item 8): a chip with no value (`{colour, nil}`, a result that is a
  chip) has its icon in the centre and no badge. The `:sm` and `:md` badge sticks
  out 4 px to the lower right: a row of valued chips needs a gap of 6 px
  (`gap-1.5`), else the badge touches the next chip (round 41).

  ## Examples

      <.chip chip={{:green, 2}} />
      <.chip chip={{:white, 1}} size={:sm} />
  """
  attr :chip, :any, required: true, doc: "a `{colour, value}` tuple (value nil: no badge)"
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
        "inline-flex size-[18px] shrink-0 items-center justify-center rounded-full text-tag leading-none font-bold tabular-nums",
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
          @colour != :locoweed && @value != nil && "-translate-x-[8%] -translate-y-[8%]"
        ]}
      />
      <span
        :if={@colour != :locoweed and @value != nil}
        class={[
          "absolute inline-flex items-center justify-center rounded-full bg-parchment-light font-hand leading-none font-bold text-ink tabular-nums ring-ink",
          @size == :sm && "-right-1 -bottom-1 size-4 text-tag ring-1",
          @size == :md && "-right-1 -bottom-1 size-[18px] text-tag ring-2",
          @size == :lg && "-right-0.5 -bottom-0.5 size-5 text-sm ring-2"
        ]}
        data-role="chip-value"
      >
        {@value}
      </span>
    </span>
    """
  end

  # Round 29 (B3): the pot's numbers in SVG units. On a phone the pot is at least
  # 328 px wide (360 x 780), so 13 px (`--text-tag`, the floor) is 21.2 units.
  @pot_tag Float.round(13 * 536 / 328, 1)

  # A function, so the templates read it (an `@name` in HEEx is an assign).
  defp pot_tag, do: @pot_tag

  @doc """
  One seat's 54-space pot track, drawn as the board's cauldron: an inline SVG with
  the spaces on a spiral from the centre (space 0) out to the rim (space 53).

  `size={:lg}` (your own pot) shows each space's coins (a plain numeral), its
  victory points (a small gold seal, only where VP > 0) and a ruby gem. Spaces
  before the scoring space are dimmed; the scoring space glows gold. `size={:sm}`
  (another player's pot) shows only the chips. In both, the droplet is a full blue
  piece on its space, each rat tail is a grey rat piece on its own space after it
  (`data-role="rat"`, in the `rat-stone` group), and placed chips sit on their spaces.
  Round 35: the rats keep their spaces when the droplet moves after the first draw;
  the droplet takes the first rat's space and that rat goes (`rat_spaces/1`).

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

  attr :droplet, :integer,
    default: nil,
    doc: "round 31: the droplet's space while the evaluation steps play (nil: the seat's own)"

  attr :fx_key, :string, default: "", doc: "round 31: the step, so each step's effects play"

  attr :targets, :map,
    default: %{},
    doc: """
    round 36: `%{chip => %{event, value, label}}`, the pot chips a choice is about:
    they glow and a tap (or Enter) sends `event` with `value` as `action`
    """

  attr :bagged, :boolean,
    default: false,
    doc: "round 35: the round went to the shop, so the chips are back in the bag (none drawn)"

  def pot(assigns) do
    player = assigns.game.players[assigns.seat]
    player = if assigns.droplet, do: %{player | droplet: assigns.droplet}, else: player
    scoring = Game.scoring_index(assigns.game, assigns.seat)
    rings = assigns.rings || %{assigns.seat => scoring}

    assigns =
      assign(assigns,
        me: player,
        track:
          track(
            if(assigns.bagged, do: %{player | drawn: []}, else: player),
            placements(assigns.game.log, assigns.seat),
            rings,
            scoring,
            assigns.beats
          ),
        rats: rat_spaces(player),
        hop: ruby_hop?(assigns.game.log, assigns.seat),
        fx: Enum.map(assigns.effects, &Map.put(&1, :xy, fx_at(&1, player.droplet, scoring)))
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
      data-mine={@size == :lg && @flask && "true"}
      data-bagged={@bagged && "true"}
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
        points={groove()}
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
        points={groove()}
        fill="none"
        stroke="var(--color-potion-light)"
        stroke-opacity="0.35"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        transform="translate(0 -1)"
      />
      <g
        :for={%{index: index, chip: chip, placed: placed, rings: rings, at: at} = space <- @track}
        :key={index}
        data-space={index}
        data-x={@size == :lg && elem(elem(positions(), index), 0)}
        data-y={@size == :lg && elem(elem(positions(), index), 1)}
        transform={translate(index)}
        data-spoon={index == spoon() && "true"}
      >
        <title :if={@size == :lg}>{space_title(index)}</title>
        <%!-- Round 37: the spoon (53) is not a space a chip covers: no disc, only
             its coins and VP, so it still shows as the scoring space. --%>
        <circle
          :if={index != spoon()}
          r="22"
          fill="var(--color-potion-light)"
          stroke="var(--color-potion-deep)"
          stroke-width="2"
        />
        <circle
          :if={@size == :lg and at == :next}
          r="22"
          fill="var(--color-gold)"
          fill-opacity="0.35"
          data-role="next-space"
        />
        <g
          :if={@size == :lg}
          opacity={if at == :passed, do: "0.45"}
          data-passed={at == :passed && "true"}
        >
          <%!-- Round 31 (Nick): back to the round 28 sizes: the round 29 type
               floor made the board crowded. --%>
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
          :if={chip}
          chip={elem(chip, 0)}
          order={elem(chip, 1)}
          seat={@seat}
          index={index}
          placed={placed}
          size={@size}
          beat={space.beat}
          target={@size == :lg && @targets[elem(chip, 0)]}
        />
        <%!-- Round 41: the spoon sits by the rim; its rings are smaller, so they
             stay inside the brew. --%>
        <.scoring_ring :if={rings} seats={rings} r={if index == spoon(), do: 22, else: 26} />
        <.beat_ring
          :if={at == :next}
          beat={space.ring_beat}
          r={if index == spoon(), do: 24, else: 32}
        />
      </g>
      <%!-- The droplet and the rats are full pieces, like chips: the droplet on its
           space, then one rat per rat tail on each space after it, so the first chip
           lands after the last rat. Fixed ids: when the droplet moves, only `translate`
           changes and CSS slides them. `data-hop`: this seat's newest move paid rubies
           for the droplet, so `PotMotion` hops it (round 32). --%>
      <g
        id={"droplet-#{@seat}-#{@size}"}
        data-role="droplet"
        data-index={@me.droplet}
        data-hop={@hop && "rubies"}
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
        :if={@rats != []}
        id={"rat-#{@seat}-#{@size}"}
        data-role="rat-stone"
        data-index={List.last(@rats)}
        data-tails={length(@rats)}
      >
        <g
          :for={space <- @rats}
          id={"rat-#{@seat}-#{@size}-#{space}"}
          data-role="rat"
          data-index={space}
          style={translate_style(space)}
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
        id={"beat-fx-#{@seat}-#{@game.round}-#{@fx_key}#{fx.kind}-#{fx.beat}-#{fx.n}"}
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
              x="-36"
              y="-14"
              width="72"
              height="28"
              rx="14"
              fill="var(--color-gold)"
              stroke="#7a5a10"
            />
            <text
              dy="0.35em"
              text-anchor="middle"
              font-size={pot_tag()}
              font-weight="700"
              fill="#3a2508"
            >
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
  the glass the player reached; glasses already paid are dimmed. Round 35: the ruby
  and the VP crown are the game's icons (no "VP" text), and the glasses are shorter.
  """
  attr :tube, :integer, required: true, doc: "the player's `tube` (0..12)"
  attr :class, :any, default: "block h-auto w-full"

  attr :id, :string,
    required: true,
    doc: "the hook's id: the droplet moves along the strip to its new glass (`.TubeDrop`)"

  def test_tubes(assigns) do
    assigns = assign(assigns, glasses: 0..TestTubes.last(), last: TestTubes.last())

    ~H"""
    <%!-- Round 33: a move of the test-tube droplet (the hawkmoth's free move, the
         rubies, a card) slides it from its old glass to the new one on a low arc
         (WAAPI `translate`, 28 units a glass); reduced motion: it just sits there. --%>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".TubeDrop">
      export default {
        mounted() { this.tube = +this.el.dataset.tube },
        updated() {
          const from = this.tube, to = +this.el.dataset.tube
          this.tube = to
          const d = this.el.querySelector("[data-role=tube-droplet]")
          if (!d || from === to || matchMedia("(prefers-reduced-motion: reduce)").matches) return
          const dx = (from - to) * 28
          d.animate([{translate: `${dx}px 0`}, {translate: `${dx / 2}px -9px`, offset: 0.5}, {translate: "0 0"}],
            {duration: Math.min(320 + 60 * Math.abs(to - from), 700), easing: "cubic-bezier(0.65, 0, 0.35, 1)"})
        }
      }
    </script>
    <svg
      id={@id}
      phx-hook=".TubeDrop"
      viewBox="0 -18 364 72"
      class={[@class, "select-none"]}
      role="img"
      aria-label={"Test tubes: glass #{@tube} of #{@last}"}
      data-role="test-tubes"
      data-tube={@tube}
    >
      <rect x="2" y="44" width="360" height="8" rx="3" fill="var(--color-wood)" />
      <rect x="2" y="44" width="360" height="3" rx="1.5" fill="var(--color-wood-dark)" opacity="0.5" />
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
              do: "M-7 18 v14 a7 7 0 0 0 14 0 v-14",
              else: "M-10 6 v28 a10 10 0 0 0 20 0 v-28"
          }
          fill="var(--color-parchment-light)"
          fill-opacity="0.85"
          stroke="var(--color-iron)"
          stroke-width="2"
        />
        <line
          x1={if glass == 0, do: "-9", else: "-12"}
          x2={if glass == 0, do: "9", else: "12"}
          y1={if glass == 0, do: "18", else: "6"}
          y2={if glass == 0, do: "18", else: "6"}
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
    <.piece_icon
      name={:ruby}
      x="-8"
      y="16"
      width="16"
      height="16"
      class="text-ruby"
      style="filter: drop-shadow(0 0 1px #4a0d0a)"
      data-role="glass-ruby"
    />
    """
  end

  defp glass_bonus(%{bonus: {:vp, n}} = assigns) do
    assigns = assign(assigns, n: n)

    ~H"""
    <.piece_icon
      name={:vp}
      x="-7"
      y="10"
      width="14"
      height="14"
      class="text-gold"
      style="filter: drop-shadow(0 0 1px #5a3d0a)"
      data-role="glass-vp"
    />
    <text y="37" text-anchor="middle" font-size="13" font-weight="800" fill="var(--color-ink)">
      {@n}
    </text>
    """
  end

  defp glass_bonus(%{bonus: {:chip, {colour, value}}} = assigns) do
    ink = if colour in @light_chips, do: "var(--color-ink)", else: "white"
    assigns = assign(assigns, colour: colour, value: value, ink: ink)

    ~H"""
    <circle
      cy="26"
      r="8"
      fill={"var(--color-chip-#{@colour})"}
      stroke="rgb(0 0 0 / 0.4)"
      stroke-width="1.5"
    />
    <text y="29.5" text-anchor="middle" font-size="10" font-weight="700" fill={@ink}>
      {@value}
    </text>
    """
  end

  defp glass_title(0), do: "Start"
  defp glass_title(glass), do: "Glass #{glass}: #{tube_bonus(TestTubes.bonus(glass))}"

  # A scoring ring: one full circle, or one arc per seat when seats share the space.
  # `pathLength="100"` lets each arc be "100 / n" long whatever the radius.
  attr :seats, :list, required: true
  attr :r, :integer, default: 26

  defp scoring_ring(assigns) do
    assigns = assign(assigns, arc: 100 / length(assigns.seats))

    ~H"""
    <circle
      :for={{seat, i} <- Enum.with_index(@seats)}
      r={@r}
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

  # This seat's newest log entry is a ruby spend on the droplet (2 rubies, or 1 with
  # the gold witch G4).
  defp ruby_hop?(log, seat) do
    Enum.find(log, &match?({^seat, _}, &1)) in [
      {seat, {:rubies_spent, :droplet}},
      {seat, {:rubies_spent, :droplet, 1}}
    ]
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
      <%!-- The clip sits on a group, so `PotMotion` can raise the brew inside it. --%>
      <g :if={@full} clip-path={"url(#flask-body-#{@uid})"}>
        <path
          d="M-30 -8 q7.5 -4 15 0 t15 0 t15 0 t15 0 V30 H-30 Z"
          fill={"url(#flask-brew-#{@uid})"}
          data-role="flask-brew"
        />
      </g>
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

  # Round 41: the labels' room on the narrowest track (a 360 px phone: 328 px
  # between the insets, less a margin), a 13 px digit and the space between labels.
  @track_px 320
  @digit_px 8
  @label_gap_px 3

  # A label's centre and half width in px on the narrowest track.
  defp label_box(x, shift, vp),
    do: {x * @track_px + shift * 7, length(Integer.digits(vp)) * @digit_px / 2}

  defp clear?({c, half}, {c2, half2}), do: abs(c - c2) >= half + half2 + @label_gap_px

  # From the leader's side: each label above the line when it does not touch the
  # label before it above, else below; when both touch, the side with more room.
  defp place_vp_labels(labels) do
    labels
    |> Enum.map_reduce({nil, nil}, fn l, {above, below} ->
      box = label_box(l.x, l.shift, l.vp)

      below? =
        cond do
          above == nil or clear?(box, above) -> false
          below == nil or clear?(box, below) -> true
          true -> gap(box, below) > gap(box, above)
        end

      l = Map.put(l, :below, below?)
      {l, if(below?, do: {above, box}, else: {box, below})}
    end)
    |> elem(0)
  end

  defp gap({c, half}, {c2, half2}), do: abs(c - c2) - half - half2

  # Round 35: a rat keeps its VP only in a small gap (1 or 2 rats) between two
  # neighbouring seats. Round 41: and only when it does not repeat a seat's VP and
  # its number does not touch a VP below the line or the rat VP before it.
  defp label_rats(rats, dots, vp_labels) do
    seat_vps = MapSet.new(dots, & &1.vp)
    below = for l <- vp_labels, l.below, do: label_box(l.x, l.shift, l.vp)

    big_gaps =
      dots
      |> Enum.map(& &1.step)
      |> Enum.uniq()
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.filter(fn [a, b] -> b - a >= 3 end)

    rats
    |> Enum.map_reduce(nil, fn rat, last ->
      box = label_box(rat.x, 0, rat.vp)

      show? =
        not Enum.any?(big_gaps, fn [a, b] -> a <= rat.j and rat.j < b end) and
          rat.vp not in seat_vps and
          Enum.all?(below, &clear?(box, &1)) and
          (last == nil or clear?(box, last))

      {Map.put(rat, :show_vp, show?), if(show?, do: box, else: last)}
    end)
    |> elem(0)
  end

  @doc """
  The pot spaces of a player's rat pebbles: the spaces after the droplet, at most
  `rat_stone` of them, and never past `mods.rat_end` (the stone's space). Before the first draw
  the start follows the droplet (`Game.move_droplet/3`); after it the rats stay put,
  so a droplet move takes the first rat's space and that rat goes (round 35).
  """
  @spec rat_spaces(Player.t()) :: [non_neg_integer]
  def rat_spaces(%Player{rat_stone: 0}), do: []

  def rat_spaces(%Player{droplet: droplet, rat_stone: n, mods: mods, drawn: drawn}) do
    rat_end = mods[:rat_end]

    last = if drawn == [] or is_nil(rat_end), do: droplet + n, else: min(droplet + n, rat_end)
    Enum.to_list((droplet + 1)..last//1)
  end

  @doc """
  The rat track (round 16; equal steps since round 22): a slim strip between the
  name cards and the pot. Not to scale: one step per rat tail
  (`ScoringTrack.tails_between/2`, on every lap) between the last player and the leader, the leader on
  the left. Every seat's dot sits in the step of its rats
  (`ScoringTrack.rat_tails/2`: the leader's step has none, each tail to the right
  adds one); seats in one step stack. Under each rat tail its VP. Since round 28
  every seat's VP sits by its dot (`track-vp`, the leader's `leader-vp`): one
  number for seats in a step with the same VP, above the line or, when it would
  touch the number before it, below. Since round 35 a rat shows its VP only in a
  gap of 1 or 2 rats between neighbouring seats; since round 41 only when it is
  not a seat's VP and touches no other number. A fixed height; nothing to tap.
  """
  attr :game, :map, required: true
  attr :seat, :any, default: nil, doc: "this browser's seat, nil for a spectator"
  attr :names, :map, required: true
  attr :class, :any, default: nil

  attr :vps, :any,
    default: nil,
    doc: "`%{seat => vp}` in place of the seats' VP (the evaluation on the tiles)"

  def rat_track(assigns) do
    game = assigns.game
    vps = for s <- game.seats, do: {s, (assigns.vps || %{})[s] || Game.player(game, s).vp}
    {low, leader} = vps |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    # The tails from the leader's side: a seat behind tail `t` (VP <= t) gets its rat.
    tails = low |> ScoringTrack.tails_between(leader) |> Enum.reverse()
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

    rats = for {t, j} <- Enum.with_index(tails), do: %{vp: t, x: (j + 1) / steps, j: j}

    # Round 28: every seat's VP by its dot. Seats in one step with the same VP share
    # one number. A number goes above the line, or below it when it would touch the
    # number before it above (round 41: also across neighbouring steps).
    vp_labels =
      dots
      |> Enum.chunk_by(& &1.step)
      |> Enum.flat_map(fn same ->
        same
        |> Enum.chunk_by(& &1.vp)
        |> Enum.map(fn group ->
          %{
            vp: hd(group).vp,
            x: hd(group).x,
            shift: Enum.sum(Enum.map(group, & &1.shift)) / length(group),
            leader: hd(group).vp == leader,
            seats: Enum.map(group, & &1.seat)
          }
        end)
      end)
      |> place_vp_labels()

    rats = label_rats(rats, dots, vp_labels)

    label =
      Enum.map_join(vps, "; ", fn {s, vp} ->
        n = ScoringTrack.rat_tails(vp, leader)

        "#{Map.get(assigns.names, s, "Player #{s + 1}")} #{vp} VP, #{n} #{if n == 1, do: "rat", else: "rats"}"
      end)

    assigns =
      assign(assigns,
        dots: dots,
        rats: rats,
        vp_labels: vp_labels,
        steps: steps,
        leader: leader,
        label: label
      )

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
        <span
          :if={rat.show_vp}
          class="absolute top-full text-tag leading-none font-semibold tabular-nums"
        >
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
        :for={l <- @vp_labels}
        class={[
          "absolute top-3.5 -translate-x-1/2 text-tag leading-none font-bold tabular-nums transition-[left] duration-500 ease-out motion-reduce:transition-none",
          if(l.below, do: "translate-y-[0.4rem]", else: "-translate-y-[calc(100%+0.4rem)]"),
          if(l.leader, do: "text-parchment-light", else: "text-parchment")
        ]}
        style={"left: calc(#{pos(l.x)} + #{Float.round(l.shift * 7.0, 2)}px)"}
        aria-hidden="true"
        data-role={if l.leader, do: "leader-vp", else: "track-vp"}
        data-vp={l.vp}
        data-seats={Enum.join(l.seats, " ")}
        data-below={l.below && "true"}
      >
        {l.vp}
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

  attr :target, :map,
    default: nil,
    doc: "round 36: `%{event, value, label}` when a tap on this chip chooses it"

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
      aria-label={if @target, do: @target.label, else: "#{@colour} #{@value}"}
      role={@target && "button"}
      tabindex={@target && "0"}
      class={@target && "pot-target"}
      phx-click={@target && @target.event}
      phx-keydown={@target && @target.event}
      phx-key={@target && "Enter"}
      phx-value-action={@target && @target.value}
      data-target={@target && "true"}
    >
      <circle :if={@target} r="27" class="pot-target-glow" data-role="target-glow" />
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

  # Round 28: the track's fixed geometry comes from functions, not assigns. An assign
  # set inside a function component counts as changed on every render, so each move
  # re-sent all 54 spaces (about 7 KB per pot per move).
  defp positions, do: @positions
  defp groove, do: @groove

  # One entry per space, holding all that the space shows: a `:key`ed comprehension
  # over it re-sends only the spaces whose entry changed (round 28).
  defp track(player, placed, rings, scoring, beats) do
    chips = chips_by_index(player)
    rings = rings |> Enum.sort() |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))

    for index <- 0..PotTrack.last() do
      %{
        index: index,
        chip: chips[index],
        placed: Map.get(placed, index, 0),
        rings: rings[index],
        beat: beats[index],
        ring_beat: if(index == scoring, do: beats[:ring]),
        at:
          cond do
            index < scoring -> :passed
            index == scoring -> :next
            true -> :ahead
          end
      }
    end
  end

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

  defp space_title(53) do
    space = PotTrack.at(53)
    "The spoon (past the last space): #{space.coins} coins, #{space.vp} VP"
  end

  defp space_title(index) do
    space = PotTrack.at(index)
    ruby = if space.ruby?, do: ", ruby", else: ""
    "Space #{index}: #{space.coins} coins, #{space.vp} VP#{ruby}"
  end

  # Round 37: the spoon, the last index of the track, which no chip covers.
  defp spoon, do: PotTrack.last()

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
      <h2 class="sheet-head text-lg font-bold">Bag ({length(@bag)} chips)</h2>
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
  attr :tap, :any, default: nil, doc: "round 38: also run on a tap (the bag hint closes)"

  def bag_button(assigns) do
    ~H"""
    <button
      type="button"
      popovertarget="sheet-bag"
      phx-click={@tap}
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
      assign(assigns, p: assigns.game.players[assigns.seat], border: @seat_border[assigns.seat])

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
        bg: @seat_bg[assigns.seat],
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
  Red Set 2 chips waiting beside the pot (not in the bag): a small pill of chips
  for the pot's top right corner (round 22), under the rubies. Round 35: they
  stack in a column (the corner has room down the pot's side, not across it),
  apart, so each value badge shows. The label is for screen readers only.
  """
  attr :chips, :list, required: true, doc: "the player's `aside` chips"
  attr :class, :any, default: nil

  def aside(assigns) do
    ~H"""
    <div
      class={[
        "paper flex flex-col items-center gap-1.5 rounded-full p-1 pb-1.5 shadow-md ring-2 ring-ruby/70",
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
  It shows in the bar's tray (the overlay's results; the tiles' stage has its own
  die step).
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

  # Round 9 has no shop: its shopping phase is the final scoring (rubies, Done).
  defp round_phase_name(%Game{round: 9}, :shop), do: "Final scoring"
  defp round_phase_name(_game, phase), do: phase_name(phase)
end
