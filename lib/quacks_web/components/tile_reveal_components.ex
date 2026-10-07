defmodule QuacksWeb.TileRevealComponents do
  @moduledoc """
  Round 27 (experimental, branch `round-27-eval`): the evaluation on the player
  tiles (`QuacksWeb.TileReveal`). `tile_gains/1` goes inside a tile
  (`GameComponents.player_chip/1`'s inner block): the die face by the crown, the
  step's badge, the chips bought and the droplet pushes. `tile_stage/1` is the
  small pill over the pot that names the step, with Next (Step mode) and Skip.
  Everything is absolute, so neither the tiles nor the pot move. The badges pop in
  and fold into the tile's counters on the beat (`--beat-ms`, app.css
  `.tile-gain`).
  """
  use Phoenix.Component

  import QuacksWeb.Icons, only: [ingredient_icon: 1, piece_icon: 1]
  import QuacksWeb.GameComponents, only: [chip: 1, die_face: 1]

  alias QuacksWeb.TileReveal

  attr :game, :any, required: true
  attr :seat, :integer, required: true
  attr :reveal, :any, default: nil, doc: "the reveal state; `tiles: true` while the tiles play"
  attr :mode, :atom, default: :auto, doc: "Auto: a badge folds into the counters; Step: it stays"

  def tile_gains(assigns) do
    reveal = assigns.reveal
    playing? = match?(%{tiles: true}, reveal)
    slide = if playing?, do: Enum.at(reveal.slides, reveal.index)

    assigns =
      assign(assigns,
        slide: slide,
        index: if(playing?, do: reveal.index, else: -1),
        badges: if(slide, do: TileReveal.badges(slide, assigns.seat), else: []),
        rolls: TileReveal.rolls(assigns.game, assigns.seat),
        rolling?: match?(%{kind: :die}, slide),
        shop:
          if(playing?,
            do: %{chips: [], droplets: 0},
            else: TileReveal.shop(assigns.game, assigns.seat)
          )
      )

    ~H"""
    <span
      :if={@rolls != []}
      id={"tile-die-#{@seat}-#{@game.round}"}
      class={[
        "absolute -top-2.5 left-5 z-10 flex gap-px drop-shadow-[0_1px_2px_rgb(0_0_0/0.6)]",
        @rolling? && "tile-gain-in"
      ]}
      data-role="tile-die"
    >
      <.die_face :for={face <- @rolls} face={face} class="size-4" />
    </span>
    <span
      :if={@badges != []}
      id={"tile-gain-#{@seat}-#{@index}"}
      class={[
        "absolute -bottom-2 left-1/2 z-10 flex -translate-x-1/2 items-center gap-1 rounded-full bg-parchment px-1.5 text-[10px] leading-4 font-bold whitespace-nowrap text-ink tabular-nums shadow-md ring-1 ring-black/30",
        if(@mode == :auto, do: "tile-gain", else: "tile-gain-stay")
      ]}
      data-role="tile-gain"
      data-kind={@slide.kind}
    >
      <.badge :for={badge <- @badges} badge={badge} />
    </span>
    <span
      :if={@shop.chips != []}
      class="absolute -right-1 -bottom-2 z-10 flex -space-x-1 drop-shadow-[0_1px_2px_rgb(0_0_0/0.6)]"
      data-role="tile-bought"
    >
      <span
        :for={{chip, n} <- Enum.with_index(@shop.chips)}
        id={"tile-bought-#{@seat}-#{n}"}
        class="tile-gain-in rounded-full ring-1 ring-black/40"
      >
        <.chip chip={chip} size={:xs} />
      </span>
    </span>
    <span
      :if={@shop.droplets > 0}
      id={"tile-droplet-#{@seat}-#{@shop.droplets}"}
      class="tile-gain-in absolute -bottom-2 -left-1 z-10 flex items-center rounded-full bg-parchment px-1 text-[10px] leading-4 font-bold text-ink shadow-md ring-1 ring-black/30"
      title="Droplet pushed"
      data-role="tile-droplet"
    >
      <.piece_icon name={:droplet} class="size-3 text-droplet" />+{@shop.droplets}
    </span>
    """
  end

  attr :badge, :any, required: true

  defp badge(%{badge: {:book, colour}} = assigns) do
    assigns = assign(assigns, colour: colour)

    ~H"""
    <.ingredient_icon colour={@colour} class={["size-3", book_ink(@colour)]} />
    """
  end

  defp badge(%{badge: {:vp, n}} = assigns) do
    assigns = assign(assigns, n: n)

    ~H"""
    <span class="flex items-center" data-gain="vp">
      <.piece_icon name={:vp} class="size-3 text-gold" />+{@n}
    </span>
    """
  end

  defp badge(%{badge: {:rubies, n}} = assigns) do
    assigns = assign(assigns, n: n)

    ~H"""
    <span class="flex items-center" data-gain="rubies">
      <.piece_icon name={:ruby} class="size-2.5 text-ruby" />+{@n}
    </span>
    """
  end

  defp badge(%{badge: {:droplet, n}} = assigns) do
    assigns = assign(assigns, n: n)

    ~H"""
    <span class="flex items-center" data-gain="droplet">
      <.piece_icon name={:droplet} class="size-3 text-droplet" />+{@n}
    </span>
    """
  end

  defp badge(%{badge: {:coins, n}} = assigns) do
    assigns = assign(assigns, n: n)

    ~H"""
    <span class="flex items-center gap-px" data-gain="coins">
      <.piece_icon name={:coin} class="size-3 text-gold" />{@n}
    </span>
    """
  end

  defp badge(%{badge: {:chip, _colour}} = assigns) do
    ~H"""
    <span data-gain="chip">+chip</span>
    """
  end

  defp book_ink(:black), do: "text-ink"
  defp book_ink(:green), do: "text-chip-green"
  defp book_ink(:purple), do: "text-chip-purple"
  defp book_ink(:orange), do: "text-chip-orange"
  defp book_ink(:blue), do: "text-chip-blue"
  defp book_ink(:red), do: "text-chip-red"
  defp book_ink(:yellow), do: "text-ink"
  defp book_ink(_colour), do: "text-ink"

  attr :reveal, :map, required: true
  attr :mode, :atom, required: true, doc: "`:step` shows Next; `:auto` moves on by itself"

  @doc "The step that plays on the tiles, over the pot's top edge."
  def tile_stage(assigns) do
    assigns =
      assign(assigns,
        slide: Enum.at(assigns.reveal.slides, assigns.reveal.index),
        count: length(assigns.reveal.slides)
      )

    ~H"""
    <div
      id="tile-stage"
      class="absolute top-0 left-1/2 z-20 flex -translate-x-1/2 items-center gap-1.5 rounded-full bg-iron-dark/90 py-1 pr-1 pl-3 text-xs font-semibold whitespace-nowrap text-parchment shadow-lg ring-1 ring-gold/40"
      data-role="tile-stage"
      data-kind={@slide.kind}
      aria-live="polite"
    >
      <span>{TileReveal.label(@slide)}</span>
      <span class="text-parchment-dim tabular-nums">{@reveal.index + 1}/{@count}</span>
      <button
        :if={@mode == :step}
        type="button"
        phx-click="reveal_next"
        class="rounded-full bg-gold px-2 py-0.5 text-ink"
        data-role="tile-next"
      >
        Next
      </button>
      <button
        type="button"
        phx-click="reveal_close"
        class="rounded-full px-2 py-0.5 text-parchment-dim hover:text-parchment"
        data-role="tile-skip"
      >
        Skip
      </button>
    </div>
    """
  end
end
