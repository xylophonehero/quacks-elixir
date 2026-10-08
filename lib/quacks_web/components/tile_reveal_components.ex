defmodule QuacksWeb.TileRevealComponents do
  @moduledoc """
  The evaluation on the player tiles (`QuacksWeb.TileReveal`; round 27, the phone
  default since round 28). `tile_news/1` fills a tile's bottom line while a step
  plays and after a buy in the shop (`GameComponents.player_chip/1` swaps the line
  to the news and back, app.css `.tile-line`). `tile_stage/1` is the small pill
  over the pot that names the step, with Next (Step mode) and Skip. Nothing hangs
  outside a tile, so neither the tiles nor the pot move.
  """
  use Phoenix.Component

  import QuacksWeb.Icons, only: [ingredient_icon: 1, piece_icon: 1]
  import QuacksWeb.GameComponents, only: [chip: 1, die_face: 1]

  alias QuacksWeb.TileReveal

  attr :items, :list, required: true, doc: "`QuacksWeb.TileReveal.news/3`'s items"

  @doc """
  Round 28 (R2): the news on a tile's bottom line (`GameComponents.player_chip/1`
  draws the line and swaps it): die faces, a book's ingredient and its rewards,
  the space's VP and ruby, the chips bought and the droplet pushes in the shop.
  """
  def tile_news(assigns) do
    ~H"""
    <.badge :for={item <- @items} badge={item} />
    """
  end

  attr :badge, :any, required: true

  defp badge(%{badge: {:die, face}} = assigns) do
    assigns = assign(assigns, face: face)

    ~H"""
    <.die_face face={@face} class="size-3.5" />
    """
  end

  defp badge(%{badge: {:bought, chip}} = assigns) do
    assigns = assign(assigns, chip: chip)

    ~H"""
    <span class="rounded-full ring-1 ring-black/40" data-gain="bought">
      <.chip chip={@chip} size={:xs} />
    </span>
    """
  end

  defp badge(%{badge: {:book, colour}} = assigns) do
    assigns = assign(assigns, colour: colour)

    ~H"""
    <.ingredient_icon colour={@colour} class={["size-3.5", book_ink(@colour)]} />
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
      <.piece_icon name={:ruby} class="size-2.5 text-ruby-light" />+{@n}
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

  defp book_ink(:black), do: "text-parchment-light"
  defp book_ink(:green), do: "text-chip-green"
  defp book_ink(:purple), do: "text-chip-purple"
  defp book_ink(:orange), do: "text-chip-orange"
  defp book_ink(:blue), do: "text-chip-blue"
  defp book_ink(:red), do: "text-chip-red"
  defp book_ink(:yellow), do: "text-chip-yellow"
  defp book_ink(_colour), do: "text-parchment-light"

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
