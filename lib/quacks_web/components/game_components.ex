defmodule QuacksWeb.GameComponents do
  @moduledoc """
  Function components that draw a `Quacks.Game` struct. Rendering only: nothing in
  here changes game state. The LiveView passes the struct in; each component reads
  the fields it needs.
  """
  use Phoenix.Component

  alias Quacks.Game
  alias Quacks.Rules.{Chips, PotTrack}

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
  attr :size, :atom, default: :md, values: [:sm, :md]
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
  The 54-space pot track as a wrapping grid.

  Each space shows its index, coins, victory points and a ruby dot. The droplet space
  gets a blue ring, placed chips sit on their spaces, and the scoring space (the one
  directly after the last chip) is highlighted.
  """
  attr :game, Game, required: true

  def pot(assigns) do
    assigns =
      assign(assigns,
        me: assigns.game.players[0],
        chips_by_index: chips_by_index(assigns.game.players[0]),
        scoring_index: Game.scoring_index(assigns.game),
        spaces: 0..PotTrack.last()
      )

    ~H"""
    <ol class="grid grid-cols-6 gap-1 sm:grid-cols-9" aria-label="Pot track">
      <li
        :for={index <- @spaces}
        class={[
          "relative flex aspect-square flex-col items-center justify-center rounded-md p-1 text-[10px] leading-tight",
          index == @scoring_index && "bg-amber-200 ring-2 ring-amber-500",
          index != @scoring_index && "bg-zinc-100",
          index == @me.droplet && "ring-2 ring-sky-500"
        ]}
        data-space={index}
      >
        <span class="absolute left-1 top-0.5 text-zinc-400">{index}</span>
        <span
          :if={PotTrack.at(index).ruby?}
          class="absolute right-1 top-1 size-2 rounded-full bg-rose-500"
          aria-label="ruby"
        />
        <%= if chip = @chips_by_index[index] do %>
          <.chip chip={chip} size={:sm} data-role="pot-chip" />
        <% else %>
          <span class="font-semibold text-zinc-700">{PotTrack.at(index).coins}c</span>
          <span :if={PotTrack.at(index).vp > 0} class="text-zinc-500">{PotTrack.at(index).vp}vp</span>
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

  @doc "Round, phase, score and the player's resources in one strip."
  attr :game, Game, required: true

  def status(assigns) do
    assigns = assign(assigns, me: assigns.game.players[0])

    ~H"""
    <dl class="grid grid-cols-3 gap-2 text-sm sm:grid-cols-6">
      <.stat label="Round" value={"#{@game.round} / 9"} />
      <.stat label="Phase" value={phase_name(Game.phase(@game, 0))} />
      <.stat label="VP" value={@me.vp} />
      <.stat label="Rubies" value={@me.rubies} />
      <.stat label="Flask" value={if @me.flask, do: "full", else: "empty"} />
      <.stat label="White" value={"#{Game.white_sum(@game)} / 7"} />
      <div :if={@game.phase == :buy_chips} class="col-span-3 sm:col-span-6">
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
  The chips a blue chip drew, duplicates included, so two identical offers are both
  visible. The action buttons below it show one button per distinct chip.
  """
  attr :pending, :list, required: true, doc: "`game.pending`"

  def blue_offer(assigns) do
    ~H"""
    <div
      class="flex flex-wrap items-center gap-2 rounded-md bg-blue-50 p-2 text-sm"
      aria-label="Crow skull offer"
    >
      <span class="font-semibold text-blue-900">Crow skull drew:</span>
      <.chip :for={chip <- @pending} chip={chip} data-role="offer-chip" />
      <span class="text-zinc-600">Place one of them, or return them all.</span>
    </div>
    """
  end

  @doc """
  The last few game events, newest first. Every log entry runs through `label/1`.
  Actions that an event already narrates (`:draw` → "Drew ...", a buy → "Bought ...",
  spending rubies → "Spent ...") are left out so the log does not say things twice.
  """
  attr :log, :list, required: true, doc: "`game.log`, newest first"
  attr :limit, :integer, default: 20

  def action_log(assigns) do
    entries =
      assigns.log
      |> Enum.map(&untag/1)
      |> Enum.reject(&narrated_by_event?/1)
      |> Enum.take(assigns.limit)

    assigns = assign(assigns, entries: entries)

    ~H"""
    <div>
      <h2 class="text-sm font-semibold text-zinc-600">Log</h2>
      <ol class="mt-2 space-y-1 text-sm text-zinc-700" aria-label="Recent actions">
        <li :for={entry <- @entries}>{label(entry)}</li>
        <li :if={@entries == []} class="text-zinc-400">Nothing yet. Draw a chip.</li>
      </ol>
    </div>
    """
  end

  # The solo page shows seat 0 only, so the seat tag on player entries is dropped.
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
  defp phase_name(:over), do: "Over"
  defp phase_name(other), do: inspect(other)
end
