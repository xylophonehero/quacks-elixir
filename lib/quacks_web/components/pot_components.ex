defmodule QuacksWeb.PotComponents do
  @moduledoc """
  The pot and what stands around it: the pot with its chips, scoring ring and
  droplet (pot/1), the test-tube rack (test_tubes/1), the flask, the bag (bag/1,
  bag_button/1), the kept Toadstool chips (aside/1) and the overflow bowl
  (bowl/1).
  """
  use Phoenix.Component

  alias Quacks.Game
  alias Quacks.Rules.{Chips, PotTrack, TestTubes}

  import QuacksWeb.ChipComponents
  import QuacksWeb.GameText
  import QuacksWeb.Icons
  import QuacksWeb.TrackComponents

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
    icon = chip_icon_class(colour)
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
end
