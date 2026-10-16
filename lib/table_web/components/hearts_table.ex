defmodule TableWeb.Components.HeartsTable do
  @moduledoc """
  A Hearts table for four seats, as you see it: you at the bottom (`:s`), the
  others at west, north and east. It puts the parts of
  `TableWeb.Components.Cards` on the felt: the seats' labels and scores, the
  other hands (backs), the deck or the trick in the middle, and your hand.

  The motion hook `TableMotion` (`assets/js/table.js`) sits on the table, so a
  patch between two states animates (see `TableWeb.Components.Cards`). The ids:

  - the table: `id` (also the card id scope: `"<id>-card-QS"`)
  - the hands: `"<id>-hand-<seat>"` (seat `n`, `e`, `s`, `w`)
  - the taken piles: `"<id>-pile-<seat>"`, the deck `"<id>-deck"`, the trick `"<id>-trick"`
  """
  use Phoenix.Component

  import TableWeb.Components.Cards

  alias TableWeb.Components.Cards

  @typedoc """
  One seat: `name`, `score` (the game total), `points` (this round), `count`
  (cards in hand: the other seats), `taken` (cards taken this round).
  """
  @type seat_info :: %{
          name: String.t(),
          score: non_neg_integer,
          points: non_neg_integer,
          count: non_neg_integer,
          taken: non_neg_integer
        }

  @doc "The DOM id of a part of table `id`: `:hand`, `:pile`, `:deck`, `:trick`."
  @spec part(String.t(), atom, Cards.seat() | nil) :: String.t()
  def part(id, kind, seat \\ nil)
  def part(id, kind, nil), do: "#{id}-#{kind}"
  def part(id, kind, seat), do: "#{id}-#{kind}-#{seat}"

  @doc """
  The table. `seats` maps `:n`, `:e`, `:s`, `:w` to a `t:seat_info/0`.

  - `hand`, `legal`, `selected`, `new`, `on_tap`: your hand (`Cards.hand/1`).
  - `plays`, `winner`: the trick (`Cards.trick/1`).
  - `deck`, `drain`: the deck in the middle instead of the trick (the deal).
  - `turn`: the seat to play (its label is lit).
  - `status`: one line over your hand.
  - `motion`: `%{hand: %{card => m}, trick: %{card => m}, backs: %{seat => %{k => m}}}`.
  """
  attr :id, :string, required: true
  attr :seats, :map, required: true
  attr :hand, :list, default: []
  attr :legal, :any, default: :all
  attr :selected, :list, default: []
  attr :new, :list, default: []
  attr :on_tap, :any, default: nil
  attr :plays, :list, default: []
  attr :winner, :atom, default: nil
  attr :deck, :integer, default: 0
  attr :drain, :integer, default: 0
  attr :turn, :atom, default: nil
  attr :status, :string, default: nil
  attr :motion, :map, default: %{}
  attr :class, :any, default: nil

  def table(assigns) do
    ~H"""
    <div
      id={@id}
      class={["tb-table tb-felt relative overflow-hidden rounded-tb", @class]}
      phx-hook="TableMotion"
      data-role="hearts-table"
    >
      <div id={"#{@id}-fx"} phx-update="ignore" class="pointer-events-none absolute inset-0"></div>
      <div class="grid grid-cols-[auto_minmax(0,1fr)_auto] grid-rows-[auto_minmax(0,1fr)_auto] gap-x-1 gap-y-2 p-2 sm:gap-x-4 sm:p-4">
        <div class="col-span-3 flex flex-col items-center gap-1">
          <.seat_label id={@id} seat={:n} info={@seats.n} turn={@turn} />
          <.backs
            id={part(@id, :hand, :n)}
            count={@seats.n.count}
            motion={get_in(@motion, [:backs, :n]) || %{}}
          />
        </div>
        <.side id={@id} seat={:w} info={@seats.w} turn={@turn} motion={@motion} />
        <div class="flex min-h-[9rem] items-center justify-center">
          <.deck
            :if={@deck > 0 or @drain > 0}
            id={part(@id, :deck)}
            count={@deck}
            drain={@drain}
          />
          <.trick
            :if={@deck == 0 and @drain == 0}
            id={part(@id, :trick)}
            scope={@id}
            plays={@plays}
            winner={@winner}
            motion={@motion[:trick] || %{}}
          />
        </div>
        <.side id={@id} seat={:e} info={@seats.e} turn={@turn} motion={@motion} />
        <div class="col-span-3 flex flex-col items-center gap-1">
          <div class="flex w-full items-center justify-between gap-2 px-1">
            <.seat_label id={@id} seat={:s} info={@seats.s} turn={@turn} />
            <p
              :if={@status}
              class="min-w-0 truncate text-right text-xs font-medium text-tb-felt-ink/80 sm:text-sm"
              data-role="table-status"
            >
              {@status}
            </p>
          </div>
          <.hand
            id={part(@id, :hand, :s)}
            scope={@id}
            cards={@hand}
            legal={@legal}
            selected={@selected}
            new={@new}
            on_tap={@on_tap}
            motion={@motion[:hand] || %{}}
            class="mt-1"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :seat, :atom, required: true
  attr :info, :map, required: true
  attr :turn, :atom, default: nil
  attr :motion, :map, default: %{}

  defp side(assigns) do
    ~H"""
    <div class="flex w-[4.25rem] flex-col items-center justify-center gap-1 sm:w-28">
      <.seat_label id={@id} seat={@seat} info={@info} turn={@turn} stacked />
      <.backs
        id={part(@id, :hand, @seat)}
        count={@info.count}
        axis="y"
        motion={get_in(@motion, [:backs, @seat]) || %{}}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :seat, :atom, required: true
  attr :info, :map, required: true
  attr :turn, :atom, default: nil
  attr :stacked, :boolean, default: false

  defp seat_label(assigns) do
    ~H"""
    <div
      id={part(@id, :seat, @seat)}
      class={[
        "flex max-w-full items-center rounded-tb bg-tb-base-100/90 px-2 py-0.5 text-tb-base-content shadow-sm ring-1 ring-black/10 transition",
        @stacked && "flex-col gap-0 px-1.5 text-center sm:flex-row sm:gap-2 sm:px-2",
        !@stacked && "gap-2",
        @turn == @seat && "ring-2 ring-tb-accent"
      ]}
      data-role="seat"
      data-seat={@seat}
      data-turn={@turn == @seat}
    >
      <span class={[
        "truncate text-xs font-semibold sm:max-w-32 sm:text-sm",
        if(@stacked, do: "max-w-[3.6rem]", else: "max-w-[9rem]")
      ]}>
        {@info.name}
      </span>
      <span class="flex items-center gap-1.5 text-xs tabular-nums">
        <span class="font-bold" data-role="score" title="score">{@info.score}</span>
        <span
          :if={@info.points > 0}
          class="text-(--tb-points)"
          data-role="points"
          title="points this round"
        >
          +{@info.points}
        </span>
        <.pile id={part(@id, :pile, @seat)} count={@info.taken} class="text-tb-base-content/70" />
      </span>
    </div>
    """
  end
end
