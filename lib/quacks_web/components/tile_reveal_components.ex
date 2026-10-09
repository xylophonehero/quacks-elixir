defmodule QuacksWeb.TileRevealComponents do
  @moduledoc """
  The evaluation on the player tiles (`QuacksWeb.TileReveal`; round 27, the phone
  default since round 28). `tile_news/1` fills a tile's bottom line while a step
  plays and after a buy in the shop (`GameComponents.player_chip/1` swaps the line
  to the news and back, app.css `.tile-line`). `tile_stage/1` names the step,
  with Skip and Next (Step mode), in the bar where Stop and Draw sit (round 29). Nothing hangs
  outside a tile, so neither the tiles nor the pot move.
  """
  use Phoenix.Component

  import QuacksWeb.Icons, only: [ingredient_icon: 1, piece_icon: 1]
  import QuacksWeb.CoreComponents, only: [button: 1]
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

  defp badge(%{badge: {:flea, traded, got}} = assigns) do
    assigns = assign(assigns, traded: traded, got: got)

    ~H"""
    <span class="flex items-center gap-px" title="Flea Market" data-gain="flea">
      <span :if={@traded} class="rounded-full opacity-60 ring-1 ring-black/40">
        <.chip chip={@traded} size={:xs} />
      </span>
      <span :if={@traded} aria-hidden="true">→</span>
      <span :if={!@traded}>+</span>
      <span class="rounded-full ring-1 ring-black/40"><.chip chip={@got} size={:xs} /></span>
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

  @doc """
  The step that plays on the tiles. Round 29: in the bar, where Stop and Draw sit
  (not over the pot): the step's name and number, then Skip and Next (Step mode).
  It keeps the bar's height (`min-h-12`), so the pot does not move.
  """
  def tile_stage(assigns) do
    assigns =
      assign(assigns,
        slide: Enum.at(assigns.reveal.slides, assigns.reveal.index),
        count: length(assigns.reveal.slides)
      )

    ~H"""
    <section
      id="tile-stage"
      class="flex min-h-12 items-center gap-2 *:min-h-12 *:touch-manipulation"
      aria-label="Round results"
      data-role="tile-stage"
      data-kind={@slide.kind}
    >
      <p class="flex min-w-0 flex-1 flex-col justify-center leading-tight" aria-live="polite">
        <span class="truncate font-semibold text-parchment" data-role="tile-step">
          {TileReveal.label(@slide)}
        </span>
        <span class="text-xs text-parchment-dim tabular-nums">
          Step {@reveal.index + 1} of {@count}
        </span>
      </p>
      <.button
        type="button"
        phx-click="reveal_close"
        variant={:secondary}
        class="shrink-0 px-4"
        data-role="tile-skip"
      >
        Skip
      </.button>
      <.button
        :if={@mode == :step}
        type="button"
        phx-click="reveal_next"
        variant={:primary}
        class="w-2/5 shrink-0"
        data-role="tile-next"
      >
        Next
      </.button>
    </section>
    """
  end
end
