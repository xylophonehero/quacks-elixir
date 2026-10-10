defmodule QuacksWeb.BarComponents do
  @moduledoc """
  The bottom bar and the header: the round and phase (round_phase/1), the white
  fuse above Stop and Draw (fuse_meter/1) and the reward and risk line
  (reward_line/1). Rendering only, as every component module of the game page
  (module map: `docs/guide/06-components.md`).
  """
  use Phoenix.Component

  alias Quacks.AI.Odds
  alias Quacks.Game
  alias Quacks.Game.Potions
  alias Quacks.Rules.PotTrack

  import QuacksWeb.GameText
  import QuacksWeb.TileComponents
  import QuacksWeb.Icons

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

  # Round 9 has no shop: its shopping phase is the final scoring (rubies, Done).
  defp round_phase_name(%Game{round: 9}, :shop), do: "Final scoring"
  defp round_phase_name(_game, phase), do: phase_name(phase)
end
