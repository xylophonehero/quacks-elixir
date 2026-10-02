defmodule QuacksWeb.GameComponents do
  @moduledoc """
  Function components that draw a `Quacks.Game` struct. Rendering only: nothing in
  here changes game state. The LiveView passes the struct in; each component reads
  the fields it needs.
  """
  use Phoenix.Component

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Game.Potions
  alias Quacks.Rules.{Chips, PotTrack}
  alias Quacks.Rules.Fortune

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

  The SVG scales to its box and keeps its shape, so `class="block size-full"` fits
  the whole pot into whatever space the page gives it. On phones the VP tags are too
  small to read and are left out; each space's `<title>` still names its VP.
  """
  attr :game, Game, required: true
  attr :seat, :integer, default: 0
  attr :size, :atom, default: :lg, values: [:sm, :lg]
  attr :class, :string, default: "block h-auto w-full"

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
      preserveAspectRatio="xMidYMid meet"
      class={[@class, "select-none"]}
      role="group"
      aria-label="Pot track"
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
      <circle r="262" fill="var(--color-iron-dark)" />
      <circle
        r="250"
        fill={"url(#brew-#{@seat}-#{@size})"}
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
        :if={(@game.phase == :buy_chips and @game.turn == @seat) or @me.exploded?}
        class="col-span-4 flex flex-wrap gap-1"
      >
        <span
          :if={@game.phase == :buy_chips and @game.turn == @seat}
          class="rounded-md bg-gold px-2 font-semibold text-ink"
        >
          {@me.coins} coins to spend
        </span>
        <span
          :if={@me.exploded?}
          class="rounded-md bg-ruby px-2 font-semibold text-white"
          data-role="exploded"
        >
          {if protected?(@me), do: "Exploded (protected)", else: "Exploded!"}
        </span>
      </div>
    </dl>
    """
  end

  # B2: the crow skull protected the explosion. No explosion choice is made then.
  defp protected?(%Player{} = p),
    do: p.exploded? and p.explosion_choice == nil and p.phase != :explosion_choice

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
        <span :if={@p.exploded?} class="rounded bg-ruby px-1 text-white">
          {if protected?(@p), do: "Exploded (protected)", else: "Exploded!"}
        </span>
      </header>
      <p class="text-ink-soft">
        Round {@game.round} · {@p.vp} VP · {@p.rubies} rubies · flask {if @p.flask,
          do: "full",
          else: "empty"} · white {Game.white_sum(@game, @seat)} / {Potions.explode_above(
          @game,
          @seat
        )}
      </p>
      <.pot game={@game} seat={@seat} size={:sm} />
    </article>
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
        [:green, :blue, :red, :yellow, :purple],
        " · ",
        &"#{&1} #{@sets[&1]}"
      )}
    </p>
    """
  end

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
  # Every card choice logs its outcome right after, as `{:fortune, id, outcome}`.
  defp narrated_by_event?({:fortune, _choice}), do: true
  # Every chip choice logs its `{:effect, ...}` right after.
  defp narrated_by_event?({:chip, _choice}), do: true
  defp narrated_by_event?(_entry), do: false

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

  defp effect(book, detail), do: inspect({:effect, book, detail})

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

  @doc "\"green 2\" for `{:green, 2}`."
  @spec chip_name(Chips.chip()) :: String.t()
  def chip_name({colour, value}), do: "#{colour} #{value}"

  @doc "The name of a phase, as the header shows it."
  @spec phase_name(atom) :: String.t()
  def phase_name(:potions), do: "Brewing"
  def phase_name(:explosion_choice), do: "Explosion"
  def phase_name(:yellow_choice), do: "Mandrake"
  def phase_name(:blue_choice), do: "Crow skull"
  def phase_name(:fortune_choice), do: "Fortune teller"
  def phase_name(:chip_choice), do: "Chip actions"
  def phase_name(:red_choice), do: "Toadstool"
  def phase_name(:buy_chips), do: "Shop"
  def phase_name(:spend_rubies), do: "Rubies"
  def phase_name(:done), do: "Done"
  def phase_name(:over), do: "Over"
  def phase_name(other), do: inspect(other)
end
