defmodule QuacksWeb.GalleryLive do
  @moduledoc """
  The gallery (`/dev/gallery`; dev and test, and staging at runtime:
  `QuacksWeb.Plugs.Gallery`): a viewer like Storybook for the stories of
  `QuacksWeb.Gallery.Stories`: the components in their edge cases, whole game
  screens, and the scenarios (`Quacks.Scenarios`) step by step.

  The sidebar lists every group with its stories; each story has its own URL
  (`/dev/gallery/tiles/tiles`) and shows in ONE iframe (`/dev/gallery/frame/...`,
  `QuacksWeb.GalleryFrameLive`). The toolbar sets the frame's viewport width (360,
  392, 768, 1280 px or the full width, `?w=392`), so the app's breakpoints apply; a
  frame wider than the screen is scaled down to fit (`.FitFrame`). Under it the
  controls change the story's args (`?players=8&state=shop`, only the values that
  differ from the default) and the presets set several at once. Prev / Next (and
  the arrow keys) step through every story. An old variant URL that a story with
  args took over goes to that story with the variant's args.
  """
  use QuacksWeb, :live_view

  alias Quacks.Scenarios
  alias QuacksWeb.Gallery.Stories

  @widths ~w(360 392 768 1280 full)
  @default_width "392"

  @impl true
  def mount(_params, _session, socket) do
    catalog = Stories.catalog()
    flat = for g <- catalog, s <- g.stories, do: {g.id, s.id}

    {:ok,
     assign(socket,
       catalog: catalog,
       flat: flat,
       widths: @widths,
       results: Scenarios.results(),
       page_title: "Gallery"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    width = if params["w"] in @widths, do: params["w"], else: @default_width

    case pick(socket.assigns.catalog, params) do
      {:ok, group, story} ->
        {:noreply, show(socket, group, story, params, width)}

      {:claimed, story, args} ->
        query = Stories.query(story, args)
        {:noreply, push_patch(socket, to: view_path(story, query, width), replace: true)}

      :error ->
        {:noreply, push_navigate(socket, to: "/dev/gallery")}
    end
  end

  defp show(socket, group, story, params, width) do
    specs = Stories.specs(story, params)
    args = Stories.args(story, params)
    query = Stories.query(story, args)

    assign(socket,
      group: group,
      story: story,
      specs: specs,
      args: args,
      query: query,
      width: width,
      form: to_form(Map.new(args, fn {k, v} -> {k, to_string(v)} end), as: :args),
      note: note(story, args),
      page_title: "#{story.title} · Gallery"
    )
  end

  # A scenario step's note (one line); for the rest the component's note.
  defp note(%{scenario: _} = story, args) do
    case Stories.build(story, args) do
      {:ok, %{note: note}} when is_binary(note) -> note
      _ -> story.note
    end
  end

  defp note(story, _args), do: story.note

  # `/dev/gallery/:component/:variant`; `/dev/gallery` (`?c=` picks the group)
  # shows its first story.
  defp pick(catalog, %{"component" => gid, "variant" => sid}) do
    with %{} = g <- Enum.find(catalog, &(&1.id == gid)) do
      case Enum.find(g.stories, &(&1.id == sid)) do
        %{} = s ->
          {:ok, g, s}

        nil ->
          case Stories.claimed(gid, sid) do
            {s, args} -> {:claimed, s, args}
            nil -> :error
          end
      end
    else
      _ -> :error
    end
  end

  defp pick(catalog, params) do
    g = Enum.find(catalog, hd(catalog), &(&1.id == params["c"]))
    {:ok, g, hd(g.stories)}
  end

  @impl true
  def handle_event("key", %{"key" => key} = params, socket)
      when key in ["ArrowLeft", "ArrowRight"] do
    # Not while a control has the focus: there the arrows change its value.
    if params["typing"] == true do
      {:noreply, socket}
    else
      step = if key == "ArrowLeft", do: -1, else: 1
      {:noreply, push_patch(socket, to: step_path(socket.assigns, step))}
    end
  end

  def handle_event("key", _params, socket), do: {:noreply, socket}

  def handle_event("args", %{"args" => raw}, socket) do
    %{story: story, width: width} = socket.assigns
    args = Stories.args(story, raw)
    {:noreply, push_patch(socket, to: view_path(story, Stories.query(story, args), width))}
  end

  def handle_event("args", _params, socket), do: {:noreply, socket}

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
          id="gallery-nav"
          class="relative shrink-0 overflow-y-auto border-parchment/15 p-3 max-lg:max-h-56 max-lg:border-b lg:w-64 lg:border-r"
          aria-label="Stories"
          data-role="gallery-nav"
          phx-hook=".ShowCurrent"
        >
          <script :type={Phoenix.LiveView.ColocatedHook} name=".ShowCurrent">
            export default {
              mounted() { this.show() },
              updated() { this.show() },
              show() {
                const a = this.el.querySelector("[aria-current=page]")
                if (a) this.el.scrollTop = a.offsetTop - this.el.clientHeight / 2
              }
            }
          </script>
          <h1 class="font-hand text-2xl font-bold">Gallery</h1>
          <p class="mb-2 text-xs text-parchment-dim">
            Stories with args, screens and scenarios. One at a time.
          </p>
          <details
            :for={g <- @catalog}
            class="group mb-1"
            open={g.id == @group.id or not String.starts_with?(g.id, "scenario-")}
            data-role="gallery-component"
            data-component={g.id}
          >
            <summary class="cursor-pointer list-none rounded-md px-2 py-0.5 text-xs font-bold tracking-wide text-parchment-dim uppercase transition-colors hover:bg-black/30">
              <span class="inline-block transition-transform group-open:rotate-90">›</span>
              {g.title}
              <span class="font-normal normal-case">({length(g.stories)})</span>
            </summary>
            <ul>
              <li :for={s <- g.stories}>
                <.link
                  patch={view_path(s, %{}, @width)}
                  class={[
                    "flex items-center gap-1 rounded-md px-2 py-0.5 text-sm transition-colors",
                    if({g.id, s.id} == {@group.id, @story.id},
                      do: "bg-parchment font-semibold text-ink",
                      else: "text-parchment hover:bg-black/30"
                    )
                  ]}
                  title={s.title}
                  aria-current={{g.id, s.id} == {@group.id, @story.id} && "page"}
                  data-role="gallery-variant-link"
                  data-variant={"#{g.id}/#{s.id}"}
                >
                  <span class="min-w-0 flex-1 truncate">{s.title}</span>
                  <span
                    :if={s.args != []}
                    class="font-mono text-[10px] opacity-60"
                    title="has args"
                  >
                    ⚙
                  </span>
                  <span
                    :if={s[:scenario] && s.scenario.hand}
                    class="rounded bg-gold/60 px-1 text-[10px] font-semibold text-ink"
                    title="hand-written: its own choices and checks"
                    data-role="hand-written"
                  >
                    hand
                  </span>
                  <.result :if={s[:scenario]} result={@results[Scenarios.key(s.scenario)]} />
                </.link>
              </li>
            </ul>
          </details>
        </nav>
        <main class="flex min-w-0 flex-1 flex-col gap-2 p-3" id={"gallery-#{@group.id}"}>
          <header class="flex flex-wrap items-center gap-2" data-role="gallery-toolbar">
            <div class="min-w-0 flex-1 max-sm:basis-full">
              <h2 class="truncate text-sm font-semibold" data-role="gallery-title">
                {@group.title} · {@story.title}
              </h2>
              <p class="truncate font-mono text-xs text-parchment-dim" data-role="gallery-note">
                {@note}
              </p>
            </div>
            <div class="flex items-center gap-1" role="group" aria-label="Viewport width">
              <.link
                :for={w <- @widths}
                patch={view_path(@story, @query, w)}
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
                title="Previous story (←)"
                data-role="gallery-prev"
              >
                <.icon name="hero-chevron-left" class="size-4" />
              </.link>
              <.link
                patch={step_path(assigns, 1)}
                class="rounded-md px-2 py-1 text-xs ring-1 ring-parchment/25 transition-colors hover:bg-black/30"
                title="Next story (→)"
                data-role="gallery-next"
              >
                <.icon name="hero-chevron-right" class="size-4" />
              </.link>
              <a
                href={frame_path(@story, @query)}
                target="_blank"
                class="rounded-md px-2 py-1 text-xs ring-1 ring-parchment/25 transition-colors hover:bg-black/30"
                title="Open the frame alone"
                data-role="gallery-open"
              >
                <.icon name="hero-arrow-top-right-on-square" class="size-4" />
              </a>
            </div>
          </header>
          <.controls
            :if={@specs != [] or @story.presets != [] or @story.live}
            story={@story}
            specs={@specs}
            args={@args}
            form={@form}
            width={@width}
          />
          <div
            id="gallery-stage"
            class="min-w-0"
            phx-hook=".FitFrame"
            data-width={if @width == "full", do: 0, else: @width}
            data-height={height(@story, @width)}
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
              {if @width == "full", do: "full width", else: "#{@width}px"} × {height(@story, @width)}px
            </p>
            <div
              class="overflow-hidden rounded-md ring-1 ring-parchment/20"
              style={"width: #{box_width(@width)}; height: #{height(@story, @width)}px"}
              data-role="frame-box"
            >
              <iframe
                id={"frame-#{@group.id}-#{@story.id}-#{@width}-#{:erlang.phash2(@query)}"}
                src={frame_path(@story, @query)}
                title={"#{@story.title} at #{@width}"}
                class="origin-top-left border-0"
                style={"width: #{box_width(@width)}; height: #{height(@story, @width)}px"}
                data-role="gallery-frame"
              />
            </div>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  attr :story, :map, required: true
  attr :specs, :list, required: true
  attr :args, :map, required: true
  attr :form, :any, required: true
  attr :width, :string, required: true

  # The args' controls (a select per number or choice, a box per flag), the presets
  # and, for a scenario, the link to the live game at this step.
  defp controls(assigns) do
    ~H"""
    <section
      class="flex flex-wrap items-end gap-x-3 gap-y-1 rounded-md bg-black/20 px-3 py-2"
      data-role="gallery-controls"
    >
      <.form
        :if={@specs != []}
        for={@form}
        id="gallery-args"
        phx-change="args"
        class="flex flex-wrap items-end gap-x-3 gap-y-1"
      >
        <div :for={spec <- @specs} class="flex flex-col" data-role="gallery-arg" data-arg={spec.name}>
          <%= if spec.type == :bool do %>
            <.input
              type="checkbox"
              id={"arg-#{spec.name}"}
              name={"args[#{spec.name}]"}
              value={@args[spec.name]}
              label={spec.name}
              class="size-4 accent-gold"
            />
          <% else %>
            <label for={"arg-#{spec.name}"} class="font-mono text-[11px] text-parchment-dim">
              {spec.name}
            </label>
            <.input
              type="select"
              id={"arg-#{spec.name}"}
              name={"args[#{spec.name}]"}
              value={to_string(@args[spec.name])}
              options={options(spec)}
              class="min-h-9 rounded-md border border-parchment/25 bg-wood-dark px-2 py-1 text-sm text-parchment transition-colors hover:border-parchment/50"
            />
          <% end %>
        </div>
      </.form>
      <div :if={@story.presets != []} class="flex flex-wrap items-center gap-1 pb-2">
        <span class="font-mono text-[11px] text-parchment-dim">presets</span>
        <.link
          :for={{id, title, args} <- @story.presets}
          patch={view_path(@story, Stories.query(@story, Map.merge(@args, args)), @width)}
          class="rounded-full px-2 py-0.5 text-xs ring-1 ring-parchment/25 transition-colors hover:bg-black/30"
          data-role="gallery-preset"
          data-preset={id}
        >
          {title}
        </.link>
        <.link
          patch={view_path(@story, %{}, @width)}
          class="rounded-full px-2 py-0.5 text-xs text-parchment-dim transition-colors hover:bg-black/30"
          data-role="gallery-reset"
        >
          defaults
        </.link>
      </div>
      <a
        :if={@story.live}
        href={@story.live.(@args)}
        target="_blank"
        class="mb-2 ml-auto inline-flex items-center gap-1 rounded-md bg-parchment px-2 py-1 text-xs font-semibold text-ink transition-colors hover:bg-parchment-light"
        data-role="gallery-live"
      >
        Open as a live game <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
      </a>
    </section>
    """
  end

  attr :result, :map, default: nil

  # A scenario's last test result (`Quacks.Scenarios.results/0`): a dot.
  defp result(assigns) do
    ~H"""
    <span
      class={[
        "size-2 shrink-0 rounded-full",
        case @result do
          nil -> "ring-1 ring-current opacity-40"
          %{"status" => "pass"} -> "bg-green-500"
          _ -> "bg-red-500"
        end
      ]}
      title={result_title(@result)}
      data-role="test-result"
      data-status={(@result && @result["status"]) || "none"}
    />
    """
  end

  defp result_title(nil), do: "no test run"
  defp result_title(%{"status" => "pass"}), do: "test: pass"
  defp result_title(r), do: "test: fail at #{r["step"]}: #{r["message"]}"

  defp options(%{type: :int, min: min, max: max} = spec),
    do: for(n <- min..max, do: {(spec[:labels] || %{})[n] || to_string(n), to_string(n)})

  defp options(%{type: :enum, values: values}), do: values

  defp box_width("full"), do: "100%"
  defp box_width(w), do: "#{w}px"

  # A screen is as tall as a phone (to 392), a tablet or a laptop.
  defp height(%{height: :screen}, w) when w in ["360", "392"], do: 780
  defp height(%{height: :screen}, "768"), do: 1024
  defp height(%{height: :screen}, _w), do: 800
  defp height(%{height: h}, _w), do: h

  defp view_path(story, query, w),
    do: "/dev/gallery/#{story.group}/#{story.id}?" <> URI.encode_query(Map.put(query, "w", w))

  defp frame_path(story, query) when map_size(query) == 0,
    do: "/dev/gallery/frame/#{story.group}/#{story.id}"

  defp frame_path(story, query),
    do: "/dev/gallery/frame/#{story.group}/#{story.id}?" <> URI.encode_query(query)

  # The story `step` places on in the flat list (it wraps round), with its defaults.
  defp step_path(%{flat: flat, catalog: catalog, group: g, story: s, width: w}, step) do
    i = Enum.find_index(flat, &(&1 == {g.id, s.id}))
    {gid, sid} = Enum.at(flat, rem(i + step + length(flat), length(flat)))

    story =
      catalog |> Enum.find(&(&1.id == gid)) |> Map.fetch!(:stories) |> Enum.find(&(&1.id == sid))

    view_path(story, %{}, w)
  end
end
