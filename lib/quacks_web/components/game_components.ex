defmodule QuacksWeb.GameComponents do
  @moduledoc """
  Function components that draw a `Quacks.Game` struct. Rendering only: nothing in
  here changes game state. The LiveView passes the struct in; each component reads
  the fields it needs.
  """
  use Phoenix.Component

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Rules.{Chips, PotTrack}
  alias Quacks.Rules.Fortune

  @colours %{
    white: "bg-white text-zinc-900 border border-zinc-300",
    orange: "bg-orange-400 text-zinc-900",
    green: "bg-green-600 text-white",
    blue: "bg-blue-600 text-white",
    red: "bg-red-600 text-white",
    yellow: "bg-yellow-300 text-zinc-900",
    purple: "bg-purple-600 text-white",
    black: "bg-zinc-900 text-white"
  }

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
  One seat's 54-space pot track as a wrapping grid.

  `size={:lg}` (your own pot) shows each space's index, coins, victory points and a
  ruby dot. `size={:sm}` (another player's pot) shows only the chips. In both, the
  droplet space gets a blue ring, placed chips sit on their spaces, the scoring space
  (the one directly after the last chip) is highlighted and the rat stone, when the
  player has one, is a grey dot on its space.
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
        spaces: 0..PotTrack.last()
      )

    ~H"""
    <ol
      class={[
        "grid",
        @size == :lg && "grid-cols-6 gap-1 sm:grid-cols-9",
        @size == :sm && "grid-cols-9 gap-0.5"
      ]}
      aria-label="Pot track"
    >
      <li
        :for={index <- @spaces}
        class={[
          "relative flex aspect-square flex-col items-center justify-center rounded-md leading-tight",
          @size == :lg && "p-1 text-[10px]",
          index == @scoring_index && "bg-amber-200 ring-2 ring-amber-500",
          index != @scoring_index && "bg-zinc-100",
          index == @me.droplet && "ring-2 ring-sky-500"
        ]}
        data-space={index}
      >
        <span :if={@size == :lg} class="absolute left-1 top-0.5 text-zinc-400">{index}</span>
        <span
          :if={@size == :lg and PotTrack.at(index).ruby?}
          class="absolute right-1 top-1 size-2 rounded-full bg-rose-500"
          aria-label="ruby"
        />
        <span
          :if={index == @rat_index}
          class="absolute bottom-0.5 right-0.5 size-2 rounded-full bg-zinc-500"
          aria-label="rat stone"
          data-role="rat-stone"
        />
        <%= cond do %>
          <% chip = @chips_by_index[index] -> %>
            <.chip chip={chip} size={if @size == :lg, do: :sm, else: :xs} data-role="pot-chip" />
          <% @size == :lg -> %>
            <span class="font-semibold text-zinc-700">{PotTrack.at(index).coins}c</span>
            <span :if={PotTrack.at(index).vp > 0} class="text-zinc-500">
              {PotTrack.at(index).vp}vp
            </span>
          <% true -> %>
        <% end %>
      </li>
    </ol>
    """
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
    <div>
      <h2 class="text-sm font-semibold text-zinc-600">Bag ({length(@bag)} chips)</h2>
      <ul class="mt-2 flex flex-wrap gap-2" aria-label="Chips in the bag">
        <li :for={{chip, count} <- @counts} class="flex items-center gap-1 text-sm">
          <.chip chip={chip} /> <span class="text-zinc-600">x{count}</span>
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
    <dl class="grid grid-cols-3 gap-2 text-sm sm:grid-cols-6">
      <.stat label="Round" value={"#{@game.round} / 9"} />
      <.stat label="Phase" value={phase_name(Game.phase(@game, @seat))} />
      <.stat label="VP" value={@me.vp} />
      <.stat label="Rubies" value={@me.rubies} />
      <.stat label="Flask" value={if @me.flask, do: "full", else: "empty"} />
      <.stat label="White" value={"#{Game.white_sum(@game, @seat)} / 7"} />
      <div :if={@game.phase == :buy_chips and @game.turn == @seat} class="col-span-3 sm:col-span-6">
        <span class="rounded-md bg-amber-100 px-2 py-1 font-semibold text-amber-900">
          {@me.coins} coins to spend
        </span>
      </div>
      <div :if={@me.exploded?} class="col-span-3 sm:col-span-6">
        <span class="rounded-md bg-rose-600 px-2 py-1 font-semibold text-white">Exploded!</span>
      </div>
    </dl>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-md bg-zinc-100 px-2 py-1">
      <dt class="text-xs text-zinc-500">{@label}</dt>
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
    <article class="space-y-2 rounded-lg bg-zinc-50 p-2 text-xs" data-seat={@seat}>
      <header class="flex flex-wrap items-center gap-1">
        <span class="font-semibold" data-role="player-name">{@name}</span>
        <span :if={@game.phase == :potions} class="rounded bg-zinc-200 px-1">
          {if @p.done?, do: "done", else: "waiting"}
        </span>
        <span :if={@game.turn == @seat} class="rounded bg-amber-200 px-1">their turn</span>
        <span :if={@p.exploded?} class="rounded bg-rose-600 px-1 text-white">Exploded!</span>
      </header>
      <p class="text-zinc-600">
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
  `title` and `hint` let the fortune cards B7 and P13 reuse the strip.
  """
  attr :pending, :list, required: true, doc: "the player's `pending` chips"
  attr :title, :string, default: "Crow skull drew:"
  attr :hint, :string, default: "Place one of them, or return them all."
  attr :label, :string, default: "Crow skull offer"

  def blue_offer(assigns) do
    ~H"""
    <div
      class="flex flex-wrap items-center gap-2 rounded-md bg-blue-50 p-2 text-sm"
      aria-label={@label}
    >
      <span class="font-semibold text-blue-900">{@title}</span>
      <.chip :for={chip <- @pending} chip={chip} data-role="offer-chip" />
      <span class="text-zinc-600">{@hint}</span>
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
      class="overflow-hidden rounded-lg border border-zinc-200 bg-white text-sm"
      aria-label="Fortune teller card"
      data-role="fortune-card"
      data-colour={@card.colour}
    >
      <div class={[
        "px-3 py-1 text-xs font-semibold uppercase tracking-wide text-white",
        @card.colour == :blue && "bg-blue-600",
        @card.colour == :purple && "bg-purple-600"
      ]}>
        Fortune teller · {if @card.colour == :blue, do: "this round", else: "now"}
      </div>
      <div class="px-3 py-2">
        <h2 class="font-bold">{@card.name}</h2>
        <p class="text-zinc-700">{@card.text}</p>
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
    <div>
      <h2 class="text-sm font-semibold text-zinc-600">Log</h2>
      <ol class="mt-2 space-y-1 text-sm text-zinc-700" aria-label="Recent actions">
        <li :for={line <- @entries}>{line}</li>
        <li :if={@entries == []} class="text-zinc-400">Nothing yet. Draw a chip.</li>
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

  def label({:fortune, choice}), do: fortune_choice(choice, nil)
  def label({:fortune_drawn, id}), do: "Fortune teller: #{Fortune.card(id).name}"

  def label({:fortune_skipped, id}),
    do: "Fortune teller: #{Fortune.card(id).name} (skipped in solo)"

  def label({:fortune, id, outcome}),
    do: "#{Fortune.card(id).name}: #{fortune_outcome(outcome, id)}"

  def label(other), do: inspect(other)

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

  defp phase_name(:potions), do: "Brewing"
  defp phase_name(:explosion_choice), do: "Explosion"
  defp phase_name(:yellow_choice), do: "Mandrake"
  defp phase_name(:blue_choice), do: "Crow skull"
  defp phase_name(:fortune_choice), do: "Fortune teller"
  defp phase_name(:buy_chips), do: "Shop"
  defp phase_name(:spend_rubies), do: "Rubies"
  defp phase_name(:done), do: "Done"
  defp phase_name(:over), do: "Over"
  defp phase_name(other), do: inspect(other)
end
