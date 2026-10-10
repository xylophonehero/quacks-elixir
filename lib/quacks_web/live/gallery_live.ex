defmodule QuacksWeb.GalleryLive do
  @moduledoc """
  The component gallery (dev only, `/dev/gallery`): the components that took the
  most rounds to get right, each in its edge cases (`QuacksWeb.Gallery.Fixtures`).
  Each variant shows in iframes at real viewport widths (360, 392 and 1280 px), so
  the app's viewport breakpoints apply; the 1280 frame is drawn at half scale.
  `?c=<component>` picks the component; one at a time keeps the frames few.
  """
  use QuacksWeb, :live_view

  alias QuacksWeb.Gallery.Fixtures

  @widths [360, 392, 1280]

  @impl true
  def mount(_params, _session, socket) do
    catalog = Fixtures.catalog()
    {:ok, assign(socket, catalog: catalog, widths: @widths, page_title: "Component gallery")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    current =
      Enum.find(socket.assigns.catalog, hd(socket.assigns.catalog), &(&1.id == params["c"]))

    {:noreply, assign(socket, current: current)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full>
      <div id="gallery" class="flex min-h-dvh flex-col gap-4 p-4 lg:flex-row">
        <nav class="shrink-0 space-y-1 lg:w-56" aria-label="Components" data-role="gallery-nav">
          <h1 class="font-hand text-3xl font-bold">Component gallery</h1>
          <p class="text-xs text-parchment-dim">Dev only. Frames at 360 · 392 · 1280 px.</p>
          <ul class="flex flex-wrap gap-1 lg:flex-col">
            <li :for={c <- @catalog}>
              <.link
                patch={"/dev/gallery?c=#{c.id}"}
                class={[
                  "block rounded-md px-2 py-1 text-sm font-semibold transition-colors",
                  if(c.id == @current.id,
                    do: "bg-parchment text-ink",
                    else: "text-parchment hover:bg-black/30"
                  )
                ]}
                data-role="gallery-component"
                data-component={c.id}
              >
                {c.title}
                <span class="text-xs font-normal opacity-70">{length(c.variants)}</span>
              </.link>
            </li>
          </ul>
        </nav>
        <main class="min-w-0 flex-1 space-y-6" id={"gallery-#{@current.id}"}>
          <header>
            <h2 class="font-hand text-2xl font-bold">{@current.title}</h2>
            <p class="font-mono text-xs text-parchment-dim">{@current.note}</p>
          </header>
          <section
            :for={v <- @current.variants}
            id={"variant-#{@current.id}-#{v.id}"}
            class="space-y-2"
            data-role="gallery-variant"
          >
            <h3 class="flex items-baseline gap-2 text-sm font-semibold">
              {v.title}
              <a
                href={frame_path(@current, v)}
                target="_blank"
                class="font-mono text-xs font-normal text-parchment-dim underline"
              >
                {v.id}
              </a>
            </h3>
            <div class="flex flex-wrap gap-4 pb-2">
              <figure :for={w <- @widths} class="shrink-0 space-y-1">
                <figcaption class="font-mono text-xs text-parchment-dim">{w}px</figcaption>
                <div
                  class="overflow-hidden rounded-md ring-1 ring-parchment/20"
                  style={"width: #{shown(w)}px; height: #{scaled(@current.height, w)}px"}
                >
                  <iframe
                    src={frame_path(@current, v)}
                    title={"#{v.title} at #{w}px"}
                    loading="lazy"
                    class="origin-top-left border-0"
                    style={"width: #{w}px; height: #{@current.height}px; scale: #{scale(w)}"}
                  />
                </div>
              </figure>
            </div>
          </section>
        </main>
      </div>
    </Layouts.app>
    """
  end

  defp frame_path(component, variant), do: "/dev/gallery/#{component.id}/#{variant.id}"

  # Desktop frames are drawn at half scale so the three widths fit side by side.
  defp scale(w) when w > 1000, do: 0.5
  defp scale(_w), do: 1
  defp shown(w), do: round(w * scale(w))
  defp scaled(h, w), do: round(h * scale(w))
end
