defmodule HeartsWeb.TableComponents do
  @moduledoc """
  The Hearts table for 3, 4 or 5 seats, as one seat sees it: you at the bottom
  (`:s`), the others around in play order (`positions/1`). It puts the parts of
  `TableWeb.Components.Cards` on the felt like `TableWeb.Components.HeartsTable`
  (which has 4 fixed seats): the seat labels, the other hands (backs), the deck
  or the trick in the middle, and your hand.

  The motion hook `TableMotion` sits on the table. The ids: the table `id` (also
  the card id scope), `"<id>-hand-<pos>"`, `"<id>-pile-<pos>"`, `"<id>-deck"`,
  `"<id>-trick"`.
  """
  use Phoenix.Component

  import TableWeb.Components.Cards

  @positions %{3 => [:s, :w, :e], 4 => [:s, :w, :n, :e], 5 => [:s, :w, :nw, :ne, :e]}

  @doc """
  The places around the table for `n` seats, from you on in play order (a seat
  plays after the seat before it in the list; it passes "left" to the next).
  """
  @spec positions(3..5) :: [atom]
  def positions(n), do: Map.fetch!(@positions, n)

  @doc "The DOM id of a part of table `id`."
  @spec part(String.t(), atom, atom | nil) :: String.t()
  def part(id, kind, pos \\ nil)
  def part(id, kind, nil), do: "#{id}-#{kind}"
  def part(id, kind, pos), do: "#{id}-#{kind}-#{pos}"

  @doc """
  The table. `seats`: a map of position to a seat info: `name`, `score`,
  `points` (this hand), `count` (cards in hand), `tricks`, `bot`, `open`,
  `passed`, `turn`, `you`.

  - `hand`, `legal`, `selected`, `new`, `on_tap`: your hand (`Cards.hand/1`);
    `hand: nil` shows your seat's backs (a spectator).
  - `plays`: `[{pos, card}]` in play order; `winner`: the pos that takes them.
  - `deck`, `drain`: the deck in the middle instead of the trick (the deal).
  - `motion`: `%{hand: %{card => m}, trick: %{card => m}, backs: %{pos => %{k => m}}}`.
  """
  attr :id, :string, required: true
  attr :players, :integer, required: true
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
  attr :motion, :map, default: %{}
  attr :class, :any, default: nil
  slot :status

  def hearts_table(assigns) do
    top = assigns.players |> positions() |> Enum.filter(&(&1 in [:n, :nw, :ne]))
    assigns = assign(assigns, top: top)

    ~H"""
    <div
      id={@id}
      class={["tb-table tb-felt relative overflow-hidden rounded-tb", @class]}
      phx-hook="TableMotion"
      data-role="hearts-table"
      data-players={@players}
    >
      <div id={"#{@id}-fx"} phx-update="ignore" class="pointer-events-none absolute inset-0"></div>
      <div class="grid grid-cols-[auto_minmax(0,1fr)_auto] grid-rows-[auto_minmax(0,1fr)_auto] gap-x-1 gap-y-2 p-2 sm:gap-x-4 sm:p-4">
        <div class={[
          "col-span-3 flex items-start gap-2",
          if(length(@top) > 1, do: "justify-around", else: "justify-center"),
          @top == [] && "min-h-2"
        ]}>
          <div :for={pos <- @top} class="flex min-w-0 flex-col items-center gap-1">
            <.seat_label id={@id} pos={pos} info={@seats[pos]} />
            <.backs
              id={part(@id, :hand, pos)}
              count={@seats[pos].count}
              motion={get_in(@motion, [:backs, pos]) || %{}}
            />
          </div>
        </div>
        <.side id={@id} pos={:w} info={@seats[:w]} motion={@motion} />
        <div class="flex min-h-[9rem] items-center justify-center">
          <.deck
            :if={@deck > 0 or @drain > 0}
            id={part(@id, :deck)}
            count={@deck}
            drain={@drain}
          />
          <.trick_slots
            :if={@deck == 0 and @drain == 0}
            id={@id}
            players={@players}
            plays={@plays}
            winner={@winner}
            motion={@motion[:trick] || %{}}
          />
        </div>
        <.side id={@id} pos={:e} info={@seats[:e]} motion={@motion} />
        <div class="col-span-3 flex flex-col items-center gap-1">
          <div class="flex w-full items-center justify-between gap-2 px-1">
            <.seat_label id={@id} pos={:s} info={@seats[:s]} />
            <div
              class="flex min-w-0 items-center justify-end gap-2 text-right text-xs font-medium text-tb-felt-ink/85 sm:text-sm"
              data-role="table-status"
            >
              {render_slot(@status)}
            </div>
          </div>
          <.hand
            :if={@hand}
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
          <.backs
            :if={!@hand}
            id={part(@id, :hand, :s)}
            count={@seats[:s].count}
            motion={get_in(@motion, [:backs, :s]) || %{}}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :pos, :atom, required: true
  attr :info, :map, default: nil
  attr :motion, :map, default: %{}

  defp side(%{info: nil} = assigns) do
    ~H"""
    <div class="w-[4.25rem] sm:w-32"></div>
    """
  end

  defp side(assigns) do
    ~H"""
    <div class="flex w-[4.25rem] flex-col items-center justify-center gap-1 sm:w-32">
      <.seat_label id={@id} pos={@pos} info={@info} stacked />
      <.backs
        id={part(@id, :hand, @pos)}
        count={@info.count}
        axis="y"
        motion={get_in(@motion, [:backs, @pos]) || %{}}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :pos, :atom, required: true
  attr :info, :map, required: true
  attr :stacked, :boolean, default: false

  defp seat_label(assigns) do
    ~H"""
    <div
      id={part(@id, :seat, @pos)}
      class={[
        "hb-seat flex max-w-full items-center rounded-tb bg-tb-base-100/90 px-2 py-0.5 text-tb-base-content shadow-sm ring-1 ring-black/10 transition",
        @stacked && "flex-col gap-0 px-1.5 text-center sm:px-2",
        !@stacked && "gap-2",
        @info.turn && "ring-2 ring-tb-accent",
        @info.open && "opacity-80"
      ]}
      data-role="seat"
      data-seat={@pos}
      data-turn={to_string(@info.turn)}
    >
      <span class={[
        "flex min-w-0 items-center gap-1 text-xs font-semibold sm:text-sm",
        if(@stacked, do: "max-w-[3.9rem] sm:max-w-28", else: "max-w-[9rem] sm:max-w-48")
      ]}>
        <span :if={@info.bot} class="shrink-0 text-[10px] opacity-60" title="bot">🤖</span>
        <span class={["truncate", @info.open && "italic"]}>
          {if @info.open, do: "Open seat", else: @info.name}
        </span>
        <span
          :if={@info.passed}
          class="shrink-0 font-bold text-tb-accent"
          title="passed"
          data-role="passed"
        >
          ✓
        </span>
      </span>
      <span class={[
        "flex items-center text-xs tabular-nums",
        if(@stacked, do: "gap-1 sm:gap-1.5", else: "gap-1.5")
      ]}>
        <span class="font-bold" data-role="score" title="score">{@info.score}</span>
        <span
          :if={@info.points != 0}
          class="text-(--tb-points)"
          data-role="points"
          title="points this hand"
        >
          {if @info.points > 0, do: "+"}{@info.points}
        </span>
        <span
          id={part(@id, :pile, @pos)}
          class="tb-pile inline-flex items-center gap-1 text-tb-base-content/70"
          data-anchor
          data-count={@info.tricks}
          title={"#{@info.tricks} tricks taken"}
        >
          <span class="tb-pile-card" aria-hidden="true"><span class="tb-back"></span></span>
          <span>{@info.tricks}</span>
        </span>
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :players, :integer, required: true
  attr :plays, :list, default: []
  attr :winner, :atom, default: nil
  attr :motion, :map, default: %{}

  defp trick_slots(assigns) do
    by_pos = Map.new(Enum.with_index(assigns.plays), fn {{pos, c}, i} -> {pos, {c, i}} end)
    assigns = assign(assigns, by_pos: by_pos, slots: Enum.reverse(positions(assigns.players)))

    ~H"""
    <div
      id={part(@id, :trick)}
      class="tb-trick"
      data-anchor
      data-players={@players}
      data-winner={@winner}
    >
      <div
        :for={pos <- @slots}
        class="tb-slot"
        data-seat={pos}
        style={slot_z(@by_pos[pos])}
        data-empty={!@by_pos[pos]}
      >
        <.card
          :if={@by_pos[pos]}
          id={card_id(@id, elem(@by_pos[pos], 0))}
          card={elem(@by_pos[pos], 0)}
          state={if @winner == pos, do: :won}
          {motion_attrs(@motion, elem(@by_pos[pos], 0))}
        />
      </div>
    </div>
    """
  end

  defp slot_z(nil), do: nil
  defp slot_z({_c, i}), do: "z-index: #{i + 1}"
end
