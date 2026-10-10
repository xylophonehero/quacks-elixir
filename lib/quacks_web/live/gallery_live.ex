defmodule QuacksWeb.GalleryLive do
  @moduledoc """
  The component gallery (dev only, `/dev/gallery`): the components that took the
  most rounds to get right, each in its edge cases (`QuacksWeb.Gallery.Fixtures`).

  Round 40 (Nick): a viewer like Storybook. The sidebar lists every component with
  its variants; each variant has its own URL (`/dev/gallery/bar/crow-4`) and shows
  in ONE iframe (`/dev/gallery/frame/...`, `QuacksWeb.GalleryFrameLive`), so only
  one frame loads at a time. The toolbar sets the frame's viewport width (360,
  392, 768, 1280 px or the full width), kept in the URL (`?w=392`), so the app's
  viewport breakpoints apply; a frame wider than the screen is scaled down to fit
  (`.FitFrame`). Prev / Next (and the arrow keys) step through every variant.
  """
  use QuacksWeb, :live_view

  alias QuacksWeb.Gallery.Fixtures

  @widths ~w(360 392 768 1280 full)
  @default_width "392"

  @impl true
  def mount(_params, _session, socket) do
    catalog = Fixtures.catalog()
    flat = for c <- catalog, v <- c.variants, do: {c.id, v.id}

    {:ok,
     assign(socket,
       catalog: catalog,
       flat: flat,
       widths: @widths,
       page_title: "Component gallery"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    width = if params["w"] in @widths, do: params["w"], else: @default_width

    case pick(socket.assigns.catalog, params) do
      {:ok, component, variant} ->
        {:noreply,
         assign(socket,
           current: component,
           variant: variant,
           width: width,
           page_title: "#{component.id}/#{variant.id} · Gallery"
         )}

      :error ->
        {:noreply, push_navigate(socket, to: "/dev/gallery")}
    end
  end

  # `/dev/gallery/:component/:variant`; `/dev/gallery` (`?c=` picks the
  # component) shows the first variant.
  defp pick(catalog, %{"component" => cid, "variant" => vid}) do
    with %{} = c <- Enum.find(catalog, &(&1.id == cid)),
         %{} = v <- Enum.find(c.variants, &(&1.id == vid)) do
      {:ok, c, v}
    else
      _ -> :error
    end
  end

  defp pick(catalog, params) do
    c = Enum.find(catalog, hd(catalog), &(&1.id == params["c"]))
    {:ok, c, hd(c.variants)}
  end

  @impl true
  def handle_event("key", %{"key" => key}, socket) when key in ["ArrowLeft", "ArrowRight"] do
    step = if key == "ArrowLeft", do: -1, else: 1
    {:noreply, push_patch(socket, to: step_path(socket.assigns, step))}
  end

  def handle_event("key", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full>
      <div
        id="gallery"
        class="flex min-h-dvh flex-col lg:h-dvh lg:flex-row"
        phx-window-keydown="key"
      >
        <nav
          class="shrink-0 overflow-y-auto border-parchment/15 p-3 max-lg:max-h-56 max-lg:border-b lg:w-60 lg:border-r"
          aria-label="Components"
          data-role="gallery-nav"
        >
          <h1 class="font-hand text-2xl font-bold">Component gallery</h1>
          <p class="mb-2 text-xs text-parchment-dim">Dev only. One variant at a time.</p>
          <section
            :for={c <- @catalog}
            class="mb-2"
            data-role="gallery-component"
            data-component={c.id}
          >
            <h2 class="px-2 text-xs font-bold tracking-wide text-parchment-dim uppercase">
              {c.title}
            </h2>
            <ul>
              <li :for={v <- c.variants}>
                <.link
                  patch={view_path(c.id, v.id, @width)}
                  class={[
                    "block truncate rounded-md px-2 py-0.5 text-sm transition-colors",
                    if({c.id, v.id} == {@current.id, @variant.id},
                      do: "bg-parchment font-semibold text-ink",
                      else: "text-parchment hover:bg-black/30"
                    )
                  ]}
                  title={v.title}
                  data-role="gallery-variant-link"
                  data-variant={"#{c.id}/#{v.id}"}
                >
                  {v.title}
                </.link>
              </li>
            </ul>
          </section>
        </nav>
        <main class="flex min-w-0 flex-1 flex-col gap-3 p-3" id={"gallery-#{@current.id}"}>
          <header class="flex flex-wrap items-center gap-2" data-role="gallery-toolbar">
            <div class="min-w-0 flex-1">
              <h2 class="truncate text-sm font-semibold" data-role="gallery-title">
                {@current.title} · {@variant.title}
              </h2>
              <p class="truncate font-mono text-xs text-parchment-dim">{@current.note}</p>
            </div>
            <div class="flex items-center gap-1" role="group" aria-label="Viewport width">
              <.link
                :for={w <- @widths}
                patch={view_path(@current.id, @variant.id, w)}
                class={[
                  "rounded-md px-2 py-1 font-mono text-xs transition-colors",
                  if(w == @width,
                    do: "bg-parchment text-ink",
                    else: "text-parchment ring-1 ring-parchment/25 hover:bg-black/30"
                  )
                ]}
                aria-current={w == @width && "true"}
                data-role="gallery-width"
                data-width={w}
              >
                {if w == "full", do: "Full", else: w}
              </.link>
            </div>
            <div class="flex items-center gap-1">
              <.link
                patch={step_path(assigns, -1)}
                class="rounded-md px-2 py-1 text-xs ring-1 ring-parchment/25 transition-colors hover:bg-black/30"
                title="Previous variant (←)"
                data-role="gallery-prev"
              >
                <.icon name="hero-chevron-left" class="size-4" />
              </.link>
              <.link
                patch={step_path(assigns, 1)}
                class="rounded-md px-2 py-1 text-xs ring-1 ring-parchment/25 transition-colors hover:bg-black/30"
                title="Next variant (→)"
                data-role="gallery-next"
              >
                <.icon name="hero-chevron-right" class="size-4" />
              </.link>
              <a
                href={frame_path(@current.id, @variant.id)}
                target="_blank"
                class="rounded-md px-2 py-1 text-xs ring-1 ring-parchment/25 transition-colors hover:bg-black/30"
                title="Open the frame alone"
                data-role="gallery-open"
              >
                <.icon name="hero-arrow-top-right-on-square" class="size-4" />
              </a>
            </div>
          </header>
          <div
            id="gallery-stage"
            class="min-w-0"
            phx-hook=".FitFrame"
            data-width={if @width == "full", do: 0, else: @width}
            data-height={@current.height}
          >
            <script :type={Phoenix.LiveView.ColocatedHook} name=".FitFrame">
              export default {
                mounted() {
                  this.ro = new ResizeObserver(() => this.fit())
                  this.ro.observe(this.el)
                  this.fit()
                },
                updated() { this.fit() },
                destroyed() { this.ro.disconnect() },
                fit() {
                  const box = this.el.querySelector("[data-role=frame-box]")
                  const frame = box && box.querySelector("iframe")
                  if (!frame) return
                  const w = +this.el.dataset.width, h = +this.el.dataset.height
                  const s = w ? Math.min(1, this.el.clientWidth / w) : 1
                  box.style.width = w ? `${w * s}px` : "100%"
                  box.style.height = `${h * s}px`
                  frame.style.scale = s
                  box.dataset.scale = s.toFixed(2)
                }
              }
            </script>
            <p class="mb-1 font-mono text-xs text-parchment-dim">
              {if @width == "full", do: "full width", else: "#{@width}px"}
            </p>
            <div
              class="overflow-hidden rounded-md ring-1 ring-parchment/20"
              style={"width: #{box_width(@width)}; height: #{@current.height}px"}
              data-role="frame-box"
            >
              <iframe
                id={"frame-#{@current.id}-#{@variant.id}-#{@width}"}
                src={frame_path(@current.id, @variant.id)}
                title={"#{@variant.title} at #{@width}"}
                class="origin-top-left border-0"
                style={"width: #{box_width(@width)}; height: #{@current.height}px"}
                data-role="gallery-frame"
              />
            </div>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  defp box_width("full"), do: "100%"
  defp box_width(w), do: "#{w}px"

  defp view_path(cid, vid, w), do: "/dev/gallery/#{cid}/#{vid}?w=#{w}"
  defp frame_path(cid, vid), do: "/dev/gallery/frame/#{cid}/#{vid}"

  # The variant `step` places on in the flat list (it wraps round).
  defp step_path(%{flat: flat, current: c, variant: v, width: w}, step) do
    i = Enum.find_index(flat, &(&1 == {c.id, v.id}))
    {cid, vid} = Enum.at(flat, rem(i + step + length(flat), length(flat)))
    view_path(cid, vid, w)
  end
end
