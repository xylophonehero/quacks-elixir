defmodule TableWeb.Components.Cards do
  @moduledoc """
  A standard 52-card deck for the card games (Hearts first): our own card faces,
  a back, and the parts of a table (`hand/1`, `backs/1`, `trick/1`, `deck/1`,
  `pile/1`). Pure function components. The colours come only from the theme
  tokens of `assets/css/table.css`, so a component must be inside
  `TableWeb.Components.Theme.root/1` (`.tb-root[data-theme]`).

  ## A card

  A card is `{rank, suit}`: `rank` 2..14 (11 jack, 12 queen, 13 king, 14 ace),
  `suit` one of `:clubs`, `:diamonds`, `:spades`, `:hearts`. `code/1` gives
  its short text (`"QS"`, `"10H"`), which is also the `phx-value-card` of a tap.

  ## Motion (`assets/js/table.js`, hook `TableMotion`)

  The hook animates the change between two renders. It needs only DOM data:

  - A card keeps its DOM id in every place (`card_id(scope, card)`): the same
    id in a hand, a trick slot or a flight. When the id moves, the card slides
    from its old place to its new one (FLIP).
  - A new element with `data-from="<dom id>"` flies in from that element
    (the deck, a seat's hand, a pile).
  - An element that goes away with `data-to="<dom id>"` (set on the render
    before) flies to that element as a copy, and fades there.
  - `data-flip-delay="<ms>"` starts the move later (the deal, a bot's card).

  The components take these per card in their `motion` attr:
  `%{card_or_index => %{from: dom_id, to: dom_id, delay: ms}}`.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @type suit :: :clubs | :diamonds | :spades | :hearts
  @type card :: {2..14, suit}
  @type seat :: :n | :e | :s | :w

  @suits [:clubs, :diamonds, :spades, :hearts]
  @letters %{clubs: "C", diamonds: "D", spades: "S", hearts: "H"}
  @ranks %{11 => "J", 12 => "Q", 13 => "K", 14 => "A"}
  @names %{11 => "jack", 12 => "queen", 13 => "king", 14 => "ace"}

  @doc "The four suits, in the order Hearts sorts a hand."
  @spec suits() :: [suit]
  def suits, do: @suits

  @doc "The 52 cards, suit by suit, 2 to ace."
  @spec deck() :: [card]
  def deck, do: for(s <- @suits, r <- 2..14, do: {r, s})

  @doc ~S'The rank as printed on the card: "2".."10", "J", "Q", "K", "A".'
  @spec rank_label(2..14) :: String.t()
  def rank_label(rank), do: Map.get(@ranks, rank, Integer.to_string(rank))

  @doc ~S'The short text of a card: `{12, :spades}` is `"QS"`.'
  @spec code(card) :: String.t()
  def code({rank, suit}), do: rank_label(rank) <> @letters[suit]

  @doc ~S'The card of a `code/1` text, or nil.'
  @spec parse(String.t()) :: card | nil
  def parse(code) when is_binary(code) do
    with {rank, letter} <- String.split_at(code, -1),
         {suit, _} <- Enum.find(@letters, fn {_s, l} -> l == letter end),
         r when r in 2..14 <- parse_rank(rank) do
      {r, suit}
    else
      _ -> nil
    end
  end

  defp parse_rank(rank) do
    case Enum.find(@ranks, fn {_r, l} -> l == rank end) do
      {r, _} ->
        r

      nil ->
        case Integer.parse(rank) do
          {r, ""} -> r
          _ -> nil
        end
    end
  end

  @doc ~S'The card in words, for screen readers: "queen of spades".'
  @spec name(card) :: String.t()
  def name({rank, suit}), do: "#{Map.get(@names, rank, Integer.to_string(rank))} of #{suit}"

  @doc "The DOM id of a card on the table `scope`. The same in every place, so it can move."
  @spec card_id(String.t(), card) :: String.t()
  def card_id(scope, card), do: "#{scope}-card-#{code(card)}"

  # -- one card -----------------------------------------------------------------------

  @doc """
  One card face. With an `id` it is a motion target (`data-flip`).

  `state`: nil, `:legal` (tap to play), `:illegal` (dimmed, no tap), `:selected`
  (lifted, for a pass), `:new` (just received) or `:won` (takes the trick).
  `as`: `"div"` or `"button"`.
  """
  attr :card, :any, required: true, doc: "`{rank, suit}`"
  attr :id, :string, default: nil
  attr :state, :atom, default: nil, values: [nil, :legal, :illegal, :selected, :new, :won]
  attr :as, :string, default: "div"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled type data-from data-to data-flip-delay)

  def card(assigns) do
    {rank, suit} = assigns.card
    assigns = assign(assigns, rank: rank, suit: suit)

    ~H"""
    <.dynamic_tag
      tag_name={@as}
      id={@id}
      class={["tb-card", @class]}
      data-flip={@id && "card"}
      data-card={code(@card)}
      data-suit={@suit}
      data-state={@state}
      aria-label={name(@card)}
      {@rest}
    >
      <svg
        class="tb-face tb-face-svg"
        viewBox="0 0 250 350"
        role="img"
        aria-hidden="true"
        focusable="false"
      >
        <.index rank={@rank} suit={@suit} />
        <g transform="rotate(180 125 175)"><.index rank={@rank} suit={@suit} /></g>
        <.middle rank={@rank} suit={@suit} />
      </svg>
    </.dynamic_tag>
    """
  end

  @doc "The back of a card. With an `id` it is a motion target."
  attr :id, :string, default: nil
  attr :flip, :boolean, default: true, doc: "false: not a motion target, even with an id"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(style data-from data-to data-flip-delay)

  def card_back(assigns) do
    ~H"""
    <div id={@id} class={["tb-card", @class]} data-flip={@id && @flip && "back"} {@rest}>
      <span class="tb-face tb-back" aria-hidden="true"></span>
    </div>
    """
  end

  # The corner index: the rank large, the suit under it. In a fan only the left
  # third of a card shows, so the index fits in x 8..72.
  attr :rank, :integer, required: true
  attr :suit, :atom, required: true

  defp index(assigns) do
    ~H"""
    <text
      x="40"
      y="72"
      text-anchor="middle"
      font-size="64"
      class="tb-rank"
      fill="currentColor"
      textLength={@rank == 10 && "66"}
      lengthAdjust={@rank == 10 && "spacingAndGlyphs"}
    >
      {rank_label(@rank)}
    </text>
    <.suit suit={@suit} x={18} y={82} size={44} />
    """
  end

  # The middle: pips for 2..10, a framed letter for J Q K, one big suit for an ace.
  attr :rank, :integer, required: true
  attr :suit, :atom, required: true

  defp middle(%{rank: 14} = assigns) do
    ~H"""
    <circle
      :if={@suit == :spades}
      cx="125"
      cy="175"
      r="78"
      fill="none"
      stroke="currentColor"
      stroke-width="3"
      opacity="0.35"
    />
    <.suit suit={@suit} x={70} y={120} size={110} />
    """
  end

  defp middle(%{rank: rank} = assigns) when rank in 11..13 do
    ~H"""
    <rect
      x="72"
      y="44"
      width="106"
      height="262"
      rx="12"
      fill="var(--tb-card-court)"
      stroke="currentColor"
      stroke-width="3"
    />
    <path d={emblem(@rank)} fill="currentColor" />
    <text
      x="125"
      y="214"
      text-anchor="middle"
      font-size="104"
      class="tb-court-letter"
      fill="currentColor"
    >
      {rank_label(@rank)}
    </text>
    <.suit suit={@suit} x={103} y={236} size={44} />
    """
  end

  defp middle(assigns) do
    assigns = assign(assigns, pips: pips(assigns.rank))

    ~H"""
    <g :for={{x, y} <- @pips} transform={y > 175 && "rotate(180 #{x} #{y})"}>
      <.suit suit={@suit} x={x - 21} y={y - 21} size={42} />
    </g>
    """
  end

  # Pip centres in the 250 x 350 face: columns 98 / 125 / 152.
  @l 98
  @c 125
  @r 152
  defp pips(2), do: [{@c, 62}, {@c, 288}]
  defp pips(3), do: [{@c, 62}, {@c, 175}, {@c, 288}]
  defp pips(4), do: [{@l, 62}, {@r, 62}, {@l, 288}, {@r, 288}]
  defp pips(5), do: pips(4) ++ [{@c, 175}]
  defp pips(6), do: pips(4) ++ [{@l, 175}, {@r, 175}]
  defp pips(7), do: pips(6) ++ [{@c, 118}]
  defp pips(8), do: pips(7) ++ [{@c, 232}]

  defp pips(9),
    do: for(y <- [62, 137, 213, 288], x <- [@l, @r], do: {x, y}) ++ [{@c, 175}]

  defp pips(10),
    do: for(y <- [62, 137, 213, 288], x <- [@l, @r], do: {x, y}) ++ [{@c, 100}, {@c, 250}]

  # Our own emblems over the court letters: a crown (K), a coronet (Q), a cap (J).
  defp emblem(13),
    do:
      "M92 112 L86 68 L106 88 L125 60 L144 88 L164 68 L158 112 Z " <>
        "M94 118 h62 v8 h-62 Z"

  defp emblem(12),
    do:
      "M94 116 Q125 76 156 116 Z M100 84 a7 7 0 1 0 0.1 0 Z " <>
        "M125 70 a8 8 0 1 0 0.1 0 Z M150 84 a7 7 0 1 0 0.1 0 Z"

  defp emblem(11),
    do: "M94 116 C96 84 110 72 128 72 C146 72 156 84 156 100 L168 106 L156 116 Z"

  @doc false
  # One suit symbol, our own paths in a 100 x 100 box, placed at x y with `size`.
  attr :suit, :atom, required: true
  attr :x, :integer, required: true
  attr :y, :integer, required: true
  attr :size, :integer, required: true

  def suit(assigns) do
    ~H"""
    <path
      d={suit_path(@suit)}
      fill="currentColor"
      transform={"translate(#{@x} #{@y}) scale(#{@size / 100})"}
    />
    """
  end

  @doc "The suit's path in a 100 x 100 box."
  @spec suit_path(suit) :: String.t()
  def suit_path(:hearts),
    do:
      "M50 92 C46 84 4 62 4 32 C4 16 16 6 29 6 C39 6 47 12 50 22 " <>
        "C53 12 61 6 71 6 C84 6 96 16 96 32 C96 62 54 84 50 92 Z"

  def suit_path(:diamonds),
    do: "M50 3 C60 22 74 38 88 50 C74 62 60 78 50 97 C40 78 26 62 12 50 C26 38 40 22 50 3 Z"

  def suit_path(:spades),
    do:
      "M50 4 C62 22 96 38 96 60 C96 74 86 82 74 82 C64 82 56 77 53 70 " <>
        "C54 80 58 89 66 95 L34 95 C42 89 46 80 47 70 C44 77 36 82 26 82 " <>
        "C14 82 4 74 4 60 C4 38 38 22 50 4 Z"

  def suit_path(:clubs),
    do:
      "M28 28 a22 22 0 1 0 44 0 a22 22 0 1 0 -44 0 Z " <>
        "M4 60 a22 22 0 1 0 44 0 a22 22 0 1 0 -44 0 Z " <>
        "M52 60 a22 22 0 1 0 44 0 a22 22 0 1 0 -44 0 Z " <>
        "M38 50 a12 12 0 1 0 24 0 a12 12 0 1 0 -24 0 Z " <>
        "M46 56 C46 76 42 88 32 96 L68 96 C58 88 54 76 54 56 Z"

  # -- a hand: the fan ------------------------------------------------------------------

  @doc """
  Your hand, fanned. Fits 13 cards at 360 px; the corner index of each card shows.

  - `legal`: `:all` or the cards you may play now; the others are `:illegal`.
  - `selected`: the cards picked for the pass (lifted).
  - `new`: the cards just received (marked).
  - `on_tap`: the event (string or `JS`) of a tap; it gets `phx-value-card`
    (`code/1`). nil: the hand is not tappable (another seat's turn).
  - `motion`: `%{card => %{from:, to:, delay:}}` (see the moduledoc).
  """
  attr :id, :string, required: true, doc: "the hand's id: a `from`/`to` for the motion"
  attr :scope, :string, required: true, doc: "the table's id prefix for the card ids"
  attr :cards, :list, required: true
  attr :legal, :any, default: :all
  attr :selected, :list, default: []
  attr :new, :list, default: []
  attr :on_tap, :any, default: nil
  attr :motion, :map, default: %{}
  attr :class, :any, default: nil

  def hand(assigns) do
    n = length(assigns.cards)
    assigns = assign(assigns, n: n, fan: fan(assigns.cards))

    ~H"""
    <div
      id={@id}
      class={["tb-hand", @class]}
      data-anchor
      data-count={@n}
      style={"--n: #{@n}; --n1: #{max(@n - 1, 1)}"}
    >
      <.card
        :for={{c, style} <- @fan}
        id={card_id(@scope, c)}
        card={c}
        as={if @on_tap, do: "button", else: "div"}
        type={@on_tap && "button"}
        state={hand_state(c, @legal, @selected, @new, @on_tap)}
        disabled={@on_tap && hand_state(c, @legal, @selected, @new, @on_tap) == :illegal}
        phx-click={@on_tap && tap(@on_tap)}
        phx-value-card={code(c)}
        style={style}
        {motion_attrs(@motion, c)}
      />
    </div>
    """
  end

  defp tap(event) when is_binary(event), do: event
  defp tap(%JS{} = js), do: js

  # The fan: a small arc. Each card turns up to 8 deg at the ends and drops a
  # little, about a point under the cards.
  defp fan(cards) do
    n = length(cards)
    mid = (n - 1) / 2

    for {c, i} <- Enum.with_index(cards) do
      d = if mid == 0, do: 0.0, else: (i - mid) / mid
      rot = Float.round(d * 8, 2)
      drop = Float.round(d * d * 0.09, 3)
      {c, "--i: #{i}; rotate: #{rot}deg; top: calc(var(--card-w) * #{drop})"}
    end
  end

  defp hand_state(card, legal, selected, new, on_tap) do
    cond do
      card in selected -> :selected
      card in new -> :new
      is_nil(on_tap) -> nil
      legal == :all or card in legal -> :legal
      true -> :illegal
    end
  end

  @doc false
  def motion_attrs(motion, key) do
    case Map.get(motion, key) do
      nil ->
        %{}

      m ->
        %{
          "data-from" => m[:from],
          "data-to" => m[:to],
          "data-flip-delay" => m[:delay]
        }
    end
  end

  @doc """
  Another seat's hand: `count` backs, in a row (`axis: "x"`, north) or a column
  (`"y"`, west and east). The backs have ids `"<id>-<k>"`; `motion` is keyed by `k`.
  """
  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :axis, :string, default: "x", values: ~w(x y)
  attr :motion, :map, default: %{}
  attr :class, :any, default: nil

  def backs(assigns) do
    ~H"""
    <div
      id={@id}
      class={["tb-backs", @class]}
      data-anchor
      data-axis={@axis}
      data-count={@count}
      style={"--n1: #{max(@count - 1, 1)}"}
      role="img"
      aria-label={"#{@count} cards"}
    >
      <.card_back
        :for={k <- 0..(@count - 1)//1}
        id={"#{@id}-#{k}"}
        style={"--i: #{k}"}
        {motion_attrs(@motion, k)}
      />
    </div>
    """
  end

  # -- the trick ------------------------------------------------------------------------

  @doc """
  The trick: four slots in a cross, north at the top and you (south) at the bottom.

  - `plays`: `[{seat, card}]` in play order (the first is the lead).
  - `winner`: the seat that takes the trick, once it is complete (its card is `:won`).
  - `motion`: `%{card => %{from:, to:, delay:}}`.
  """
  attr :id, :string, required: true
  attr :scope, :string, required: true
  attr :plays, :list, default: []
  attr :winner, :atom, default: nil
  attr :names, :map, default: %{}
  attr :motion, :map, default: %{}
  attr :class, :any, default: nil

  def trick(assigns) do
    plays = Map.new(Enum.with_index(assigns.plays), fn {{seat, c}, i} -> {seat, {c, i}} end)
    lead = with [{seat, _} | _] <- assigns.plays, do: seat
    assigns = assign(assigns, by_seat: plays, lead: lead)

    ~H"""
    <div id={@id} class={["tb-trick", @class]} data-anchor data-lead={@lead} data-winner={@winner}>
      <div
        :for={seat <- [:n, :w, :e, :s]}
        class="tb-slot"
        data-seat={seat}
        style={slot_z(@by_seat[seat])}
        data-empty={!@by_seat[seat]}
      >
        <.card
          :if={@by_seat[seat]}
          id={card_id(@scope, elem(@by_seat[seat], 0))}
          card={elem(@by_seat[seat], 0)}
          state={if @winner == seat, do: :won}
          {motion_attrs(@motion, elem(@by_seat[seat], 0))}
        />
      </div>
    </div>
    """
  end

  defp slot_z(nil), do: nil
  defp slot_z({_c, i}), do: "z-index: #{i + 1}"

  # -- the deck and the taken piles -----------------------------------------------------

  @doc """
  The deck, face down: a short stack. `drain` (ms): the stack empties over that
  time, a back at a time (the deal; render it with `count: 0`).
  """
  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :drain, :integer, default: 0
  attr :class, :any, default: nil

  def deck(assigns) do
    shown = if assigns.drain > 0, do: 6, else: min(assigns.count, 6)
    assigns = assign(assigns, shown: shown)

    ~H"""
    <div
      id={@id}
      class={["tb-deck", @class]}
      data-anchor
      data-count={@count}
      role="img"
      aria-label={"deck: #{@count} cards"}
    >
      <.card_back
        :for={k <- 0..(@shown - 1)//1}
        id={@drain > 0 && "#{@id}-drain-#{k}"}
        class={@drain > 0 && "tb-drain"}
        style={"--i: #{k}" <> drain_style(@drain, k, @shown)}
        flip={false}
      />
    </div>
    """
  end

  defp drain_style(0, _k, _n), do: ""

  defp drain_style(ms, k, n),
    do: "; animation-delay: #{div(ms * (n - k), n + 1)}ms"

  @doc "A seat's taken cards (face down) and how many. A target for the trick's flight."
  attr :id, :string, required: true
  attr :count, :integer, default: 0
  attr :class, :any, default: nil

  def pile(assigns) do
    ~H"""
    <span
      id={@id}
      class={["tb-pile inline-flex items-center gap-1", @class]}
      data-anchor
      data-count={@count}
      title={"#{@count} cards taken"}
    >
      <span class="tb-pile-card" aria-hidden="true"><span class="tb-back"></span></span>
      <span class="tabular-nums">{div(@count, 4)}</span>
    </span>
    """
  end
end
