defmodule QuacksWeb.GameComponents do
  @moduledoc """
  Function components that draw a `Quacks.Game` struct. Rendering only: nothing in
  here changes game state. The LiveView passes the struct in; each component reads
  the fields it needs.
  """
  use Phoenix.Component

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Rules.{Chips, PotTrack}

  @colours %{
    white: "bg-chip-white text-ink border-2 border-zinc-400",
    orange: "bg-chip-orange text-ink",
    green: "bg-chip-green text-ink",
    blue: "bg-chip-blue text-white",
    red: "bg-chip-red text-white",
    yellow: "bg-chip-yellow text-ink",
    purple: "bg-chip-purple text-white",
    black: "bg-chip-black text-white border border-iron"
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
      {@value}
    </span>
    """
  end

  @doc """
  One seat's 54-space pot track, drawn as the board's cauldron: an inline SVG with
  the spaces on a spiral from the centre (space 0) out to the rim (space 53).

  `size={:lg}` (your own pot) shows each space's coins (top tag), victory points
  (lower tag) and a ruby gem. `size={:sm}` (another player's pot) shows only the
  chips. In both, the droplet is a blue drop on its space, placed chips sit on their
  spaces, the scoring space (the one directly after the last chip) has a gold ring
  and the rat stone, when the player has one, is a grey pebble on its space.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0
  attr :size, :atom, default: :lg, values: [:sm, :lg]

  def pot(assigns) do
    player = assigns.game.players[assigns.seat]

    assigns =
      assign(assigns,
        me: player,
        chips_by_index: chips_by_index(player),
        scoring_index: Game.scoring_index(assigns.game, assigns.seat),
        rat_index: if(player.rat_stone > 0, do: Player.start_index(player)),
        spaces: 0..PotTrack.last(),
        groove: @groove
      )

    ~H"""
    <svg
      viewBox="-268 -268 536 536"
      class="block h-auto w-full select-none"
      role="group"
      aria-label="Pot track"
    >
      <defs>
        <radialGradient id={"brew-#{@seat}"}>
          <stop offset="0%" stop-color="var(--color-potion-light)" stop-opacity="0.55" />
          <stop offset="70%" stop-color="var(--color-potion)" />
          <stop offset="100%" stop-color="var(--color-potion-deep)" />
        </radialGradient>
      </defs>
      <%!-- the table under the pot --%>
      <rect x="-268" y="-10" width="536" height="278" rx="14" fill="var(--color-wood)" />
      <%!-- iron rim and the brew --%>
      <circle r="262" fill="var(--color-iron-dark)" />
      <circle
        r="250"
        fill={"url(#brew-#{@seat})"}
        stroke="var(--color-iron)"
        stroke-width="12"
      />
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
          <g :if={PotTrack.at(index).vp > 0}>
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
        <circle
          :if={index == @scoring_index}
          r="26"
          fill="none"
          stroke="var(--color-gold)"
          stroke-width="5"
          aria-label="scoring space"
        />
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
    </svg>
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
        {@value}
      </text>
    </g>
    """
  end

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

  @doc "Round, phase, score and one seat's resources in one strip."
  attr :game, Game, required: true
  attr :seat, :integer, default: 0

  def status(assigns) do
    assigns = assign(assigns, me: assigns.game.players[assigns.seat])

    ~H"""
    <dl class="paper grid grid-cols-3 gap-2 rounded-lg p-2 text-sm sm:grid-cols-6">
      <.stat label="Round" value={"#{@game.round} / 9"} />
      <.stat label="Phase" value={phase_name(Game.phase(@game, @seat))} />
      <.stat label="VP" value={@me.vp} />
      <.stat label="Rubies" value={@me.rubies} />
      <.stat label="Flask" value={if @me.flask, do: "full", else: "empty"} />
      <.stat label="White" value={"#{Game.white_sum(@game, @seat)} / 7"} />
      <div :if={@game.phase == :buy_chips and @game.turn == @seat} class="col-span-3 sm:col-span-6">
        <span class="rounded-md bg-gold px-2 py-1 font-semibold text-ink">
          {@me.coins} coins to spend
        </span>
      </div>
      <div :if={@me.exploded?} class="col-span-3 sm:col-span-6">
        <span class="rounded-md bg-ruby px-2 py-1 font-semibold text-white">Exploded!</span>
      </div>
    </dl>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-md bg-parchment-deep/70 px-2 py-1">
      <dt class="text-xs text-ink-soft">{@label}</dt>
      <dd class="font-semibold">{@value}</dd>
    </div>
    """
  end

  @doc """
  Another player at the table, read-only: name, resources, whether they are still
  brewing, whose turn it is, and their pot drawn small.
  """
  attr :game, Game, required: true
  attr :seat, :integer, required: true
  attr :name, :string, required: true

  def player_card(assigns) do
    assigns = assign(assigns, p: assigns.game.players[assigns.seat])

    ~H"""
    <article class="paper space-y-2 rounded-lg p-2 text-xs" data-seat={@seat}>
      <header class="flex flex-wrap items-center gap-1">
        <span class="font-hand text-sm font-bold" data-role="player-name">{@name}</span>
        <span :if={@game.phase == :potions} class="rounded bg-parchment-deep px-1">
          {if @p.done?, do: "done", else: "waiting"}
        </span>
        <span :if={@game.turn == @seat} class="rounded bg-gold px-1">their turn</span>
        <span :if={@p.exploded?} class="rounded bg-ruby px-1 text-white">Exploded!</span>
      </header>
      <p class="text-ink-soft">
        Round {@game.round} · {@p.vp} VP · {@p.rubies} rubies · flask {if @p.flask,
          do: "full",
          else: "empty"} · white {Game.white_sum(@game, @seat)} / 7
      </p>
      <.pot game={@game} seat={@seat} size={:sm} />
    </article>
    """
  end

  @doc """
  The chips a blue chip drew, duplicates included, so two identical offers are both
  visible. The action buttons below it show one button per distinct chip.
  """
  attr :pending, :list, required: true, doc: "`game.pending`"

  def blue_offer(assigns) do
    ~H"""
    <div
      class="paper flex flex-wrap items-center gap-2 rounded-md border-l-4 border-droplet p-2 text-sm"
      aria-label="Crow skull offer"
    >
      <span class="font-semibold">Crow skull drew:</span>
      <.chip :for={chip <- @pending} chip={chip} data-role="offer-chip" />
      <span class="text-ink-soft">Place one of them, or return them all.</span>
    </div>
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
        <li :for={line <- @entries}>{line}</li>
        <li :if={@entries == []} class="text-ink-soft">Nothing yet. Draw a chip.</li>
      </ol>
    </div>
    """
  end

  defp log_line({seat, entry}, names) when is_integer(seat) and is_map(names),
    do: "#{Map.get(names, seat, GameServer.default_name(seat))}: #{label(entry)}"

  defp log_line(entry, _names), do: entry |> untag() |> label()

  defp untag({seat, entry}) when is_integer(seat), do: entry
  defp untag(entry), do: entry

  defp narrated_by_event?(:draw), do: true
  defp narrated_by_event?({:buy, [_ | _]}), do: true
  defp narrated_by_event?({:rubies, _}), do: true
  defp narrated_by_event?(:end_round), do: true
  defp narrated_by_event?(_entry), do: false

  @doc """
  Human label for an action or a log entry. Unknown shapes fall back to `inspect/1`,
  so a new engine action never crashes the page.
  """
  @spec label(term) :: String.t()
  def label(:draw), do: "Draw a chip"
  def label(:stop), do: "Stop"
  def label(:use_flask), do: "Use flask"
  def label(:end_round), do: "End round"
  def label({:explosion_choice, :vp}), do: "Exploded: take the victory points"
  def label({:explosion_choice, :buy}), do: "Exploded: buy chips instead"
  def label({:rubies, :droplet}), do: "Spend 2 rubies: droplet +1"
  def label({:rubies, :flask}), do: "Spend 2 rubies: refill flask"
  def label({:buy, []}), do: "Buy nothing"

  def label({:buy, chips}) when is_list(chips) do
    names = Enum.map_join(chips, " + ", &chip_name/1)
    cost = chips |> Enum.map(&Chips.price/1) |> Enum.sum()
    "Buy #{names} (#{cost} coins)"
  end

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

  def label(other), do: inspect(other)

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many

  @doc "\"green 2\" for `{:green, 2}`."
  @spec chip_name(Chips.chip()) :: String.t()
  def chip_name({colour, value}), do: "#{colour} #{value}"

  defp phase_name(:potions), do: "Brewing"
  defp phase_name(:explosion_choice), do: "Explosion"
  defp phase_name(:yellow_choice), do: "Mandrake"
  defp phase_name(:blue_choice), do: "Crow skull"
  defp phase_name(:buy_chips), do: "Shop"
  defp phase_name(:spend_rubies), do: "Rubies"
  defp phase_name(:done), do: "Done"
  defp phase_name(:over), do: "Over"
  defp phase_name(other), do: inspect(other)
end
