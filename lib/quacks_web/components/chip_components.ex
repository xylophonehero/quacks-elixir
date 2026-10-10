defmodule QuacksWeb.ChipComponents do
  @moduledoc """
  The small pieces drawn everywhere: an ingredient chip (chip/1), the bonus die
  (die/1), a seat's colour dot (seat_dot/1), and the seat and palette colour
  classes.
  """
  use Phoenix.Component

  alias Quacks.Game
  alias Quacks.Rules.Chips

  import QuacksWeb.Icons

  @colours %{
    white: "bg-chip-white text-ink border-2 border-zinc-400",
    orange: "bg-chip-orange text-ink",
    green: "bg-chip-green text-ink",
    blue: "bg-chip-blue text-white",
    red: "bg-chip-red text-white",
    yellow: "bg-chip-yellow text-ink",
    purple: "bg-chip-purple text-white",
    black: "bg-chip-black text-white border border-iron",
    locoweed: "bg-chip-locoweed text-white"
  }

  # Seat colours (theme tokens `--color-player-N`, see `seat_style/1`), as full class
  # names so Tailwind finds them in the source.
  @seat_bg %{
    0 => "bg-player-0",
    1 => "bg-player-1",
    2 => "bg-player-2",
    3 => "bg-player-3",
    4 => "bg-player-4",
    5 => "bg-player-5",
    6 => "bg-player-6",
    7 => "bg-player-7"
  }

  @seat_border %{
    0 => "border-player-0",
    1 => "border-player-1",
    2 => "border-player-2",
    3 => "border-player-3",
    4 => "border-player-4",
    5 => "border-player-5",
    6 => "border-player-6",
    7 => "border-player-7"
  }

  # A ring in the seat colour (the "You" name pill).
  @seat_ring %{
    0 => "ring-player-0",
    1 => "ring-player-1",
    2 => "ring-player-2",
    3 => "ring-player-3",
    4 => "ring-player-4",
    5 => "ring-player-5",
    6 => "ring-player-6",
    7 => "ring-player-7"
  }

  # The palette itself (`--color-seat-N`), for the colour picker.
  @palette_bg %{
    0 => "bg-seat-0",
    1 => "bg-seat-1",
    2 => "bg-seat-2",
    3 => "bg-seat-3",
    4 => "bg-seat-4",
    5 => "bg-seat-5",
    6 => "bg-seat-6",
    7 => "bg-seat-7"
  }

  # Chips whose icon is ink; the icon is white on every other chip.
  @ink_icon_chips [:white, :yellow, :orange, :green]

  @doc "The class of a chip colour's face, e.g. `\"bg-chip-red text-white\"`, by colour."
  @spec chip_classes() :: %{Chips.colour() => String.t()}
  def chip_classes, do: @colours

  @doc "The class of the icon on a chip of `colour`: ink on light chips, else white."
  @spec chip_icon_class(Chips.colour()) :: String.t()
  def chip_icon_class(colour) when colour in @ink_icon_chips, do: "text-ink"
  def chip_icon_class(_colour), do: "text-white"

  @doc """
  One chip: a disc in the chip colour with the ingredient icon and the value in a
  parchment badge. `size={:xs}` is too small for the icon: it shows only the value.
  Round 35 (item 8): a chip with no value (`{colour, nil}`, a result that is a
  chip) has its icon in the centre and no badge. The `:sm` and `:md` badge sticks
  out 4 px to the lower right: a row of valued chips needs a gap of 6 px
  (`gap-1.5`), else the badge touches the next chip (round 41).

  ## Examples

      <.chip chip={{:green, 2}} />
      <.chip chip={{:white, 1}} size={:sm} />
  """
  attr :chip, :any, required: true, doc: "a `{colour, value}` tuple (value nil: no badge)"
  attr :size, :atom, default: :md, values: [:xs, :sm, :md, :lg]
  attr :rest, :global

  def chip(assigns) do
    {colour, value} = assigns.chip

    assigns =
      assign(assigns,
        colour: colour,
        value: value,
        colour_class: Map.get(@colours, colour, "bg-zinc-400 text-white"),
        icon_class: if(colour in @ink_icon_chips, do: "text-ink", else: "text-white")
      )

    ~H"""
    <span
      :if={@size == :xs}
      class={[
        "inline-flex size-[18px] shrink-0 items-center justify-center rounded-full text-tag leading-none font-bold tabular-nums",
        @colour_class
      ]}
      aria-label={"#{@colour} #{@value}"}
      {@rest}
    >
      {face(@chip)}
    </span>
    <span
      :if={@size != :xs}
      class={[
        "chip-token relative inline-flex shrink-0 items-center justify-center rounded-full",
        @size == :sm && "size-6",
        @size == :md && "size-9",
        @size == :lg && "size-12",
        @colour_class
      ]}
      aria-label={"#{@colour} #{@value}"}
      data-chip-icon={@colour}
      {@rest}
    >
      <.ingredient_icon
        colour={@colour}
        class={[
          "size-[58%]",
          @icon_class,
          @colour != :locoweed && @value != nil && "-translate-x-[8%] -translate-y-[8%]"
        ]}
      />
      <span
        :if={@colour != :locoweed and @value != nil}
        class={[
          "absolute inline-flex items-center justify-center rounded-full bg-parchment-light font-hand leading-none font-bold text-ink tabular-nums ring-ink",
          @size == :sm && "-right-1 -bottom-1 size-4 text-tag ring-1",
          @size == :md && "-right-1 -bottom-1 size-[18px] text-tag ring-2",
          @size == :lg && "-right-0.5 -bottom-0.5 size-5 text-sm ring-2"
        ]}
        data-role="chip-value"
      >
        {@value}
      </span>
    </span>
    """
  end

  @doc ~s{The CSS colour of a seat, e.g. "var(--color-player-1)", for SVG fills.}
  @spec seat_colour(Game.seat()) :: String.t()
  def seat_colour(seat), do: "var(--color-player-#{seat})"

  @doc """
  The inline style that gives each seat its chosen colour: `colours` is
  `%{seat => 0..7}` (`GameServer` table), e.g. `%{0 => 5}` gives
  `"--color-player-0: var(--color-seat-5);"`. Put it on an element around the page.
  """
  @spec seat_style(%{Game.seat() => 0..7}) :: String.t()
  def seat_style(colours),
    do:
      Enum.map_join(colours, " ", fn {seat, c} ->
        "--color-player-#{seat}: var(--color-seat-#{c});"
      end)

  @doc "The background class of palette colour `colour` (0..7), e.g. `\"bg-seat-5\"`."
  @spec palette_bg(0..7) :: String.t()
  def palette_bg(colour), do: @palette_bg[colour]

  @doc "A small dot in the seat's colour, before a player's name."
  attr :seat, :integer, required: true
  attr :class, :any, default: nil

  def seat_dot(assigns) do
    assigns = assign(assigns, bg: @seat_bg[assigns.seat])

    ~H"""
    <span
      class={["inline-block size-2.5 shrink-0 rounded-full ring-1 ring-black/30", @bg, @class]}
      data-role="seat-dot"
      data-seat={@seat}
    />
    """
  end

  # What a chip shows: its value. Locoweed has no printed value: an "L".
  defp face({:locoweed, _}), do: "L"
  defp face({_colour, value}), do: value

  # One face of the bonus die in a 48 × 48 frame: a parchment square with its glyph
  # (the VP number on a laurel, a ruby, a droplet or an orange chip).
  attr :face, :any, required: true, doc: "`{:vp, n}`, `:ruby`, `:droplet` or `:orange`"

  defp die_art(assigns) do
    ~H"""
    <rect
      x="2"
      y="2"
      width="44"
      height="44"
      rx="6"
      fill="var(--color-parchment-light)"
      stroke="var(--color-ink)"
      stroke-width="2.5"
    />
    <%= case @face do %>
      <% {:vp, n} -> %>
        <.piece_icon name={:vp} x="7" y="7" width="34" height="34" class="text-gold" />
        <text
          x="24"
          y="25"
          dy="0.36em"
          text-anchor="middle"
          font-size="20"
          font-weight="700"
          font-family="var(--font-hand)"
          fill="var(--color-ink)"
        >
          {n}
        </text>
      <% :ruby -> %>
        <.piece_icon name={:ruby} x="9" y="9" width="30" height="30" class="text-ruby" />
      <% :droplet -> %>
        <path
          d="M24 6 L35.7 21.4 A13 13 0 1 1 12.3 21.4 Z"
          fill="var(--color-droplet)"
          stroke="#1f3f8a"
          stroke-width="2"
          stroke-linejoin="round"
        />
      <% _orange -> %>
        <circle
          cx="24"
          cy="24"
          r="15"
          fill="var(--color-chip-orange)"
          stroke="rgb(0 0 0 / 0.4)"
          stroke-width="2"
        />
        <.ingredient_icon colour={:orange} x="15" y="15" width="18" height="18" class="text-ink" />
    <% end %>
    """
  end

  @die_faces [{:vp, 1}, {:vp, 1}, {:vp, 2}, :ruby, :droplet, :orange]

  @doc """
  The bonus die while the replay plays (scoring sequence): it shows on its beat,
  rolls through its strip, lands, and its line ("Bonus die: +1 VP") fades in after.
  It shows in the bar's tray (the overlay's results; the tiles' stage has its own
  die step).
  """
  attr :lines, :list, required: true, doc: "the replay's `:die` lines (`Replay.beats/3`)"
  attr :class, :any, default: nil

  def replay_die(assigns) do
    ~H"""
    <div
      :for={line <- @lines}
      class={["replay-die items-center gap-2 rounded-lg bg-iron-dark/70 px-2 py-1", @class]}
      data-role="replay-die"
      data-beat={line.beat}
      style={"--beat: #{line.beat}"}
    >
      <.die face={line.face} />
      <span class="replay-die-text text-sm font-semibold text-parchment">{line.text}</span>
    </div>
    """
  end

  @doc """
  The bonus die for a result line: a strip of seven frames (the six faces in a
  fixed rotated order, no RNG, then `face`), which CSS steps through and lands on
  the last. Without motion only the last frame shows. `data-face` names the face.
  """
  attr :face, :any, required: true, doc: "a die face from the log: `{:vp, n}`, `:ruby`, ..."

  def die(assigns) do
    i = Enum.find_index(@die_faces, &(&1 == assigns.face)) || 0
    {a, b} = Enum.split(@die_faces, rem(i + 3, 6))
    assigns = assign(assigns, frames: Enum.with_index(b ++ a ++ [assigns.face]))

    ~H"""
    <span class="die" data-role="die" data-face={die_key(@face)} aria-hidden="true">
      <svg class="die-strip" viewBox="0 0 48 336">
        <g :for={{face, n} <- @frames} transform={"translate(0 #{n * 48})"}>
          <.die_art face={face} />
        </g>
      </svg>
    </span>
    """
  end

  @doc "One bonus die face, still (round 18: the results table's die column)."
  attr :face, :any, required: true
  attr :class, :any, default: "size-5"

  def die_face(assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 48 48" data-role="die-face" data-face={die_key(@face)}>
      <.die_art face={@face} />
    </svg>
    """
  end

  defp die_key({:vp, n}), do: "vp#{n}"
  defp die_key(face) when is_atom(face), do: Atom.to_string(face)

  @doc "The border class of a seat's colour, e.g. `\"border-player-1\"`."
  @spec seat_border(Game.seat()) :: String.t()
  def seat_border(seat), do: @seat_border[seat]

  @doc "The background class of a seat's colour, e.g. `\"bg-player-1\"`."
  @spec seat_bg(Game.seat()) :: String.t()
  def seat_bg(seat), do: @seat_bg[seat]

  @doc "The ring class of seat `seat`'s colour, e.g. `\"ring-player-1\"`."
  @spec seat_ring(Game.seat()) :: String.t()
  def seat_ring(seat), do: @seat_ring[seat]
end
