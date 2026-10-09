defmodule QuacksWeb.CardRevealComponents do
  @moduledoc """
  Round 30: the result of a fortune card that draws chips for every player (P8 Less
  is More, P13 Flea Market, B7 Safety Procedure): one row per player with the seat
  disc, the drawn chips, the key number (P8: the sum) and what the card gave.
  Round 35: also a card that offers everyone a choice (Choices, Choices, Decisions,
  Decisions…): per row what the player took, with icons (or "choosing…"). Data:
  `Quacks.Game.Fortune.reveals/1`. The card's result sheet, the fortune sheet and the
  grown corner card show it.
  """
  use Phoenix.Component
  import QuacksWeb.Icons, only: [piece_icon: 1]
  import QuacksWeb.GameComponents, only: [chip: 1, chip_name: 1, flea_reason: 1, seat_bg: 1]

  alias Quacks.Game.Fortune

  @doc """
  Every seat that drew, one row each: your row first (ringed), then the turn order.
  The best row (P8: the lowest sum) is gold. Nothing when `reveals` is empty. With
  `game`, your Flea Market chips name why they could not go up (their title).
  """
  attr :id, :string, required: true
  attr :card, :atom, required: true, doc: "`game.fortune_card`"
  attr :reveals, :map, required: true, doc: "`Quacks.Game.Fortune.reveals/1`"
  attr :order, :list, required: true, doc: "the seats in turn order"
  attr :seat, :integer, default: nil, doc: "this browser's seat, or nil"
  attr :names, :map, required: true
  attr :game, :any, default: nil, doc: "the game, for the Flea Market notes"
  attr :compact, :boolean, default: false, doc: "small chips, for the grown corner card"
  attr :class, :any, default: nil

  def card_reveals(assigns) do
    seats = Enum.filter(assigns.order, &Map.has_key?(assigns.reveals, &1))
    {mine, others} = Enum.split_with(seats, &(&1 == assigns.seat))
    assigns = assign(assigns, seats: mine ++ others)

    ~H"""
    <div
      :if={@seats != []}
      id={@id}
      class={["space-y-1 text-left text-sm", @class]}
      data-role="card-reveals"
      data-card={@card}
    >
      <p class="text-center text-xs font-semibold text-ink-soft" data-role="card-reveals-rule">
        {rule(@card)}
      </p>
      <ol class="space-y-1">
        <.reveal_row
          :for={seat <- @seats}
          seat={seat}
          row={@reveals[seat]}
          me={seat == @seat}
          name={name(@names, seat, @seat)}
          initial={initial(Map.get(@names, seat, "#{seat + 1}"))}
          card={@card}
          game={@game}
          size={if(@compact, do: :xs, else: :sm)}
        />
      </ol>
      <p
        :if={@card == :p13 && @reveals[@seat] && !@reveals[@seat].choosing?}
        class="text-center text-xs text-ink-soft"
        data-role="flea-result"
      >
        {flea_result(@reveals[@seat])}
      </p>
    </div>
    """
  end

  attr :seat, :integer, required: true
  attr :row, :map, required: true
  attr :me, :boolean, required: true
  attr :name, :string, required: true
  attr :initial, :string, required: true
  attr :card, :atom, required: true
  attr :game, :any, required: true
  attr :size, :atom, required: true, doc: "the chip size, `:sm` or `:xs`"

  defp reveal_row(assigns) do
    ~H"""
    <li
      class={[
        "flex items-center gap-1.5 rounded-md px-1.5",
        if(@size == :xs, do: "min-h-6 py-0.5", else: "min-h-9 py-1"),
        if(@row.best?, do: "bg-gold/30", else: "bg-parchment-deep/30"),
        @me && "ring-2 ring-gold"
      ]}
      data-role="card-reveal-row"
      data-seat={@seat}
      data-me={@me && "true"}
      data-best={@row.best? && "true"}
    >
      <span
        class={[
          "grid shrink-0 place-items-center rounded-full leading-none font-extrabold text-ink ring-1 ring-black/40",
          if(@size == :xs, do: "size-5 text-[10px]", else: "size-6 text-xs"),
          seat_bg(@seat)
        ]}
        title={@name}
        aria-hidden="true"
        data-role="seat-disc"
      >
        {@initial}
      </span>
      <span class="sr-only">{@name}:</span>
      <%!-- Round 35: a choice card draws nothing: what the seat took fills the row. --%>
      <span
        :if={Fortune.choice_card?(@card)}
        class="flex min-w-0 flex-1 flex-wrap items-center gap-1.5 font-bold"
        data-role="reveal-result"
      >
        <%= cond do %>
          <% @row.choosing? -> %>
            <span class="text-xs font-semibold text-ink-soft">choosing…</span>
          <% @row.gains == [] -> %>
            <span class="text-xs font-semibold text-ink-soft">passed</span>
          <% true -> %>
            <.gain :for={gain <- @row.gains} gain={gain} size={@size} />
        <% end %>
      </span>
      <span
        :if={!Fortune.choice_card?(@card)}
        class="flex min-w-0 flex-1 flex-wrap items-center gap-0.5"
        data-role="reveal-chips"
      >
        <span
          :for={{chip, i} <- Enum.with_index(@row.drew)}
          class={[
            "inline-flex rounded-full",
            traded?(@row, chip, i) && "ring-2 ring-gold",
            placed?(@row, chip, i) && "ring-2 ring-gold"
          ]}
          title={note(@card, @row, @game, @me, chip, i)}
          data-role="reveal-chip"
          data-traded={traded?(@row, chip, i) && "true"}
        >
          <.chip chip={chip} size={@size} />
        </span>
        <span :if={@row.drew == []} class="text-xs text-ink-soft">no chips</span>
      </span>
      <span
        :if={@row.number}
        class={[
          "w-7 shrink-0 text-right text-base font-extrabold tabular-nums",
          !@row.best? && "text-ink-soft"
        ]}
        title="Sum"
        data-role="reveal-number"
      >
        {@row.number}
      </span>
      <span
        :if={!Fortune.choice_card?(@card)}
        class="flex w-14 shrink-0 items-center justify-end gap-0.5 font-bold"
        data-role="reveal-result"
      >
        <%= cond do %>
          <% @row.choosing? -> %>
            <span class="text-xs font-semibold text-ink-soft">choosing…</span>
          <% @row.gains == [] -> %>
            <span class="text-xs font-semibold text-ink-soft">{none(@card)}</span>
          <% true -> %>
            <.gain :for={gain <- @row.gains} gain={gain} size={@size} />
        <% end %>
      </span>
    </li>
    """
  end

  attr :gain, :any, required: true
  attr :size, :atom, default: :sm

  # One ruby is "+" and the gem; more (or a price) shows the number too.
  defp gain(%{gain: {:rubies, n}} = assigns) do
    assigns = assign(assigns, n: n, text: count_text(n))

    ~H"""
    <span class="flex items-center gap-0.5 tabular-nums" data-gain="rubies">
      <span aria-hidden="true">{@text}</span><.piece_icon name={:ruby} class="size-4 text-ruby" /><span class="sr-only">{@n} ruby</span>
    </span>
    """
  end

  defp gain(%{gain: {kind, n}} = assigns) when kind in [:vp, :droplet, :rats] do
    assigns = assign(assigns, kind: kind, n: n, text: count_text(n))

    ~H"""
    <span class="flex items-center gap-0.5 tabular-nums" data-gain={@kind}>
      <span aria-hidden="true">{@text}</span><.piece_icon
        name={if(@kind == :rats, do: :rat, else: @kind)}
        class="size-4"
      /><span class="sr-only">{@n} {@kind}</span>
    </span>
    """
  end

  defp gain(%{gain: {:removed, chip}} = assigns) do
    assigns = assign(assigns, chip: chip)

    ~H"""
    <span
      class="flex items-center gap-0.5"
      data-gain="removed"
      title={"removed " <> chip_name(@chip)}
    >
      −<.chip chip={@chip} size={@size} />
    </span>
    """
  end

  defp gain(%{gain: {:chip, chip}} = assigns) do
    assigns = assign(assigns, chip: chip)

    ~H"""
    <span class="flex items-center gap-0.5" data-gain="chip" title={"took " <> chip_name(@chip)}>
      +<.chip chip={@chip} size={@size} />
    </span>
    """
  end

  defp gain(%{gain: {:placed, chip}} = assigns) do
    assigns = assign(assigns, chip: chip)

    ~H"""
    <span class="flex items-center gap-0.5" data-gain="placed" title={"placed " <> chip_name(@chip)}>
      <span class="text-xs">pot</span>
      <.chip chip={@chip} size={@size} />
    </span>
    """
  end

  defp rule(:p8), do: "Lowest sum takes a blue 2. Everyone else takes a ruby."
  defp rule(:p13), do: "Each trades one chip up, or takes a green 1."
  defp rule(:b7), do: "Drawn on stopping: one may go on the pot."
  defp rule(card), do: if(Fortune.choice_card?(card), do: "What everyone took")

  defp count_text(1), do: "+"
  defp count_text(n) when n > 1, do: "+#{n}"
  defp count_text(n), do: "−#{abs(n)}"

  defp none(:b7), do: "returned"
  defp none(_card), do: "kept"

  # The first copy of the traded (or placed) chip is the one that went.
  defp traded?(%{traded: chip, drew: drew}, chip, i), do: first?(drew, chip, i)
  defp traded?(_row, _chip, _i), do: false

  defp placed?(%{gains: [{:placed, chip}], drew: drew}, chip, i), do: first?(drew, chip, i)
  defp placed?(_row, _chip, _i), do: false

  defp first?(drew, chip, i), do: Enum.find_index(drew, &(&1 == chip)) == i

  defp note(:p13, row, game, true, chip, i) when game != nil do
    cond do
      traded?(row, chip, i) -> "traded up"
      reason = Fortune.flea_block(game, chip) -> flea_reason(reason)
      true -> "kept"
    end
  end

  defp note(_card, _row, _game, _me, chip, _i), do: chip_name(chip)

  defp flea_result(%{traded: chip, gains: [{:chip, got}]}) when chip != nil,
    do: "You traded #{chip_name(chip)} for #{chip_name(got)}."

  defp flea_result(%{gains: [{:chip, {:green, 1}}]}), do: "None could go up: you took a green 1."
  defp flea_result(_row), do: "You kept them all."

  defp name(_names, seat, seat), do: "You"
  defp name(names, seat, _me), do: Map.get(names, seat, "Player #{seat + 1}")

  defp initial(name),
    do: name |> String.trim() |> String.first() |> Kernel.||("?") |> String.upcase()
end
