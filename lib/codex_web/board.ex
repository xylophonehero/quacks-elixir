defmodule CodexWeb.Board do
  @moduledoc """
  The Codex sandbox board on the table page (`TableWeb.TableLive`, a
  `TableWeb.Board`). It draws `Codex.Game.view/2`: a free table where one
  browser moves the cards of both sides (hot-seat).

  - The layout follows the TTS table: the other side at the top, your side at the
    bottom. "View as P1 / P2" turns the table; "End turn" turns it to the side
    that plays next. Each side: a header (turn, base HP, gold, buildings), the
    patrol zone (5 named slots), the cards in play, the mat (command zone,
    workers, deck, discard, codex) and the hand. The other side's hand shows
    card backs; "Show hand" shows its faces.
  - Move a card: drag it to a zone (a mouse; the hook `.CodexTable`), or tap it
    to select it and tap a zone (a phone). A tap on a pile with no card selected
    opens it: the deck draws 1; the discard pile, the codex, the workers and the
    trash open a sheet of their cards.
  - A selected card shows its actions: exhaust, damage, +1/+1 and -1/-1 runes,
    hero level, flip, to hand / discard / trash. On a desktop the actions and a
    large face are in the right column; on a phone they are a bar at the bottom.
  - Hover (mouse) or a long press (touch) shows a large face of a card.
  - The face is the art from `mix codex.cards` (`/images/codex/<slug>.webp`).
    Without the art the card is drawn in CSS from the data (`Codex.Cards`).

  The board's CSS is `assets/css/codex.css` (`cx-*`).
  """
  @behaviour TableWeb.Board

  use QuacksWeb, :html

  alias Codex.{Cards, Game}

  @zone_names Map.new([:patrol | Game.list_zones()], &{Atom.to_string(&1), &1})
  @slot_names Map.new(Game.patrol_slots(), &{Atom.to_string(&1), &1})
  @card_keys %{"damage" => :damage, "plus" => :plus, "minus" => :minus, "level" => :level}
  @counters %{"gold" => :gold, "base_hp" => :base_hp}
  @building_names Map.new(Game.buildings(), &{Atom.to_string(&1), &1})
  @drawers ~w(discard codex workers trash)a

  @slot_labels %{
    squad_leader: {"Squad leader", "Leader"},
    elite: {"Elite", "Elite"},
    scavenger: {"Scavenger", "Scav."},
    technician: {"Technician", "Tech."},
    lookout: {"Lookout", "Look."}
  }

  @building_labels %{
    tech_1: "Tech I",
    tech_2: "Tech II",
    tech_3: "Tech III",
    tower: "Tower",
    surplus: "Surplus",
    tech_lab: "Tech Lab",
    heroes_hall: "Heroes' Hall"
  }

  @zone_labels %{
    deck: "Deck",
    hand: "Hand",
    discard: "Discard",
    codex: "Codex",
    command: "Command",
    workers: "Workers",
    in_play: "In play",
    patrol: "Patrol",
    trash: "Trash"
  }

  @art_dir "priv/static/images/codex"

  # -- TableWeb.Board -------------------------------------------------------------

  @impl true
  def init(socket) do
    Phoenix.Component.assign(socket,
      pov: 0,
      selected: nil,
      drawer: nil,
      reveal: false
    )
  end

  @impl true
  def put_view(socket, env, old) do
    v = env.view
    a = socket.assigns
    turned? = old != nil and old.view.active != v.active

    Phoenix.Component.assign(socket,
      view: v,
      spectator?: env.seat == :spectator,
      pov: if(turned?, do: v.active, else: a.pov),
      reveal: if(turned?, do: false, else: a.reveal),
      selected: if(Map.has_key?(v.cards, a.selected), do: a.selected)
    )
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    id = int(id)
    a = socket.assigns

    selected =
      cond do
        a.selected == id -> nil
        Map.has_key?(a.view.cards, id) -> id
        true -> a.selected
      end

    {:noreply, Phoenix.Component.assign(socket, selected: selected, drawer: nil)}
  end

  def handle_event("deselect", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, selected: nil)}

  # A tap on a zone: move the selected card there, or open the pile.
  def handle_event("zone", params, socket) do
    a = socket.assigns

    with {:ok, zone} <- target(params),
         {:ok, at} <- at(zone, params) do
      case {a.selected, zone} do
        {id, _} when is_integer(id) ->
          {:act, {:move, id, zone, at}, Phoenix.Component.assign(socket, selected: nil)}

        {nil, {seat, :deck}} ->
          {:act, {:draw, seat, 1}, socket}

        {nil, {seat, name}} when name in @drawers ->
          {:noreply, Phoenix.Component.assign(socket, drawer: {seat, name})}

        {nil, :trash} ->
          {:noreply, Phoenix.Component.assign(socket, drawer: :trash)}

        _ ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # A drop from the hook: `index` is the place in a list zone (nil: the end).
  def handle_event("move", %{"id" => id} = params, socket) do
    with {:ok, zone} <- target(params),
         {:ok, at} <- at(zone, params) do
      {:act, {:move, int(id), zone, at}, Phoenix.Component.assign(socket, selected: nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("card", %{"op" => op} = params, %{assigns: %{selected: id}} = socket)
      when is_integer(id) do
    card = socket.assigns.view.cards[id]

    case card_action(op, params, card) do
      {:ok, action, keep?} ->
        socket = if keep?, do: socket, else: Phoenix.Component.assign(socket, selected: nil)
        {:act, action, socket}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("draw", %{"seat" => s}, socket),
    do: with_seat(s, socket, &{:act, {:draw, &1, 1}, socket})

  def handle_event("shuffle", %{"seat" => s, "zone" => z}, socket) do
    case Map.fetch(@zone_names, z) do
      {:ok, zone} -> with_seat(s, socket, &{:act, {:shuffle, &1, zone}, socket})
      :error -> {:noreply, socket}
    end
  end

  def handle_event("adjust", %{"seat" => s, "key" => k, "delta" => d}, socket) do
    case Map.fetch(@counters, k) do
      {:ok, key} -> with_seat(s, socket, &{:act, {:adjust, &1, key, int(d)}, socket})
      :error -> {:noreply, socket}
    end
  end

  def handle_event("building", %{"seat" => s, "building" => b}, socket) do
    case Map.fetch(@building_names, b) do
      {:ok, building} -> with_seat(s, socket, &{:act, {:building, &1, building}, socket})
      :error -> {:noreply, socket}
    end
  end

  def handle_event("end_turn", _params, socket),
    do: {:act, :end_turn, Phoenix.Component.assign(socket, selected: nil, drawer: nil)}

  def handle_event("undo", _params, socket), do: {:act, :undo, socket}

  def handle_event("pov", %{"seat" => s}, socket),
    do:
      with_seat(
        s,
        socket,
        &{:noreply, Phoenix.Component.assign(socket, pov: &1, reveal: false)}
      )

  def handle_event("reveal", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, reveal: !socket.assigns.reveal)}

  def handle_event("drawer", %{"seat" => s, "zone" => "buildings"}, socket),
    do:
      with_seat(
        s,
        socket,
        &{:noreply, Phoenix.Component.assign(socket, drawer: {&1, :buildings})}
      )

  def handle_event("drawer", %{"zone" => "log"}, socket),
    do: {:noreply, Phoenix.Component.assign(socket, drawer: :log)}

  def handle_event("drawer", params, socket) do
    case target(params) do
      {:ok, :trash} ->
        {:noreply, Phoenix.Component.assign(socket, drawer: :trash)}

      {:ok, {_s, z} = zone} when z in @drawers ->
        {:noreply, Phoenix.Component.assign(socket, drawer: zone)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_drawer", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, drawer: nil)}

  def handle_event("key", %{"key" => "Escape"}, socket),
    do: {:noreply, Phoenix.Component.assign(socket, selected: nil, drawer: nil)}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def act_error(reason, _action, socket),
    do: Phoenix.LiveView.put_flash(socket, :error, error_text(reason))

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp error_text(:slot_taken), do: "That patrol slot is taken. Move its card first."
  defp error_text(:empty_deck), do: "The deck and the discard pile are empty."
  defp error_text(:out_of_range), do: "That value is at its limit."
  defp error_text(:not_a_hero), do: "Only a hero has a level."
  defp error_text(:nothing_to_undo), do: "Nothing to undo."
  defp error_text(:no_seat), do: "You watch this table: only its player moves the cards."
  defp error_text(reason), do: "Not now (#{inspect(reason)})."

  defp card_action("exhaust", _params, c), do: {:ok, {:toggle, c.id, :exhausted}, true}
  defp card_action("flip", _params, c), do: {:ok, {:toggle, c.id, :face_down}, true}

  defp card_action("adjust", %{"key" => k, "delta" => d}, c) do
    case Map.fetch(@card_keys, k) do
      {:ok, key} -> {:ok, {:adjust_card, c.id, key, int(d)}, true}
      :error -> :error
    end
  end

  defp card_action("to", %{"zone" => "trash"}, c), do: {:ok, {:move, c.id, :trash, 0}, false}

  defp card_action("to", %{"zone" => z}, c) when z in ~w(hand discard in_play) do
    zone = Map.fetch!(@zone_names, z)
    {:ok, {:move, c.id, {c.seat, zone}, if(zone == :discard, do: 0)}, false}
  end

  defp card_action(_op, _params, _card), do: :error

  defp target(%{"zone" => "trash"}), do: {:ok, :trash}

  defp target(%{"seat" => s, "zone" => z}) do
    with {:ok, seat} <- seat(s),
         {:ok, zone} <- Map.fetch(@zone_names, z),
         do: {:ok, {seat, zone}}
  end

  defp target(_params), do: :error

  defp at({_seat, :patrol}, params), do: Map.fetch(@slot_names, params["slot"] || "")

  defp at(zone, params) do
    case params["index"] do
      i when is_integer(i) and i >= 0 -> {:ok, i}
      _ -> {:ok, if(match?({_, z} when z in [:deck, :discard], zone) or zone == :trash, do: 0)}
    end
  end

  defp with_seat(s, socket, fun) do
    case seat(s) do
      {:ok, seat} -> fun.(seat)
      :error -> {:noreply, socket}
    end
  end

  defp seat(s) when s in [0, 1], do: {:ok, s}
  defp seat("0"), do: {:ok, 0}
  defp seat("1"), do: {:ok, 1}
  defp seat(_s), do: :error

  defp int(value) when is_integer(value), do: value

  defp int(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> -1
    end
  end

  # -- the page ------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full>
      <.page {assigns} />
    </Layouts.app>
    """
  end

  @doc "The page without the layout (also the gallery's board story)."
  def page(assigns) do
    v = assigns.view
    pov = assigns.pov
    selected = assigns.selected && v.cards[assigns.selected]

    assigns =
      assign(assigns,
        opp: 1 - pov,
        art: art(),
        sel: selected,
        where: selected && where(v, selected.id),
        players: assigns[:seats] || %{}
      )

    ~H"""
    <div
      id="cx-root"
      phx-hook=".CodexTable"
      phx-window-keydown="key"
      phx-key="Escape"
      class={["cx-table min-h-dvh text-stone-100", @sel && "cx-selecting"]}
      data-pov={@pov}
      data-active={@view.active}
    >
      <div class="mx-auto max-w-[90rem] px-2 pt-2 pb-40 sm:px-3 lg:grid lg:grid-cols-[minmax(0,1fr)_18rem] lg:items-start lg:gap-4 lg:px-4 lg:pb-6 xl:grid-cols-[minmax(0,1fr)_20rem]">
        <div class="flex min-w-0 flex-col gap-1.5 sm:gap-2">
          <.top_bar code={@code} pov={@pov} reveal={@reveal} opp={@opp} spectator?={@spectator?} />
          <.side {assigns} seat={@opp} far />
          <.center view={@view} art={@art} sel={@sel} />
          <.side {assigns} seat={@pov} far={false} />
        </div>

        <aside
          id="cx-aside"
          class={[
            "z-30 flex-col gap-3 lg:sticky lg:top-4 lg:flex",
            if(@sel,
              do: "fixed inset-x-0 bottom-0 flex",
              else: "hidden"
            )
          ]}
        >
          <.inspector :if={@sel} card={@sel} where={@where} art={@art} />
          <.inspector_help :if={!@sel} />
          <.log_list view={@view} id="cx-log" class="hidden lg:flex" />
        </aside>
      </div>

      <.drawer :if={@drawer} drawer={@drawer} view={@view} art={@art} />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CodexTable">
        export default {
          mounted() {
            const el = this.el
            this.coarse = window.matchMedia("(pointer: coarse)").matches
            this.on(el, "dragstart", e => {
              const card = e.target.closest && e.target.closest("[data-card-id]")
              if (!card || this.coarse || card.dataset.hidden !== undefined) { e.preventDefault(); return }
              this.dragId = card.dataset.cardId
              e.dataTransfer.setData("text/plain", this.dragId)
              e.dataTransfer.effectAllowed = "move"
              document.body.classList.add("cx-dragging")
              this.hidePreview()
            })
            this.on(el, "dragover", e => {
              if (!this.dragId) return
              const zone = e.target.closest && e.target.closest("[data-drop]")
              this.setOver(zone)
              if (zone) { e.preventDefault(); e.dataTransfer.dropEffect = "move" }
            })
            this.on(el, "drop", e => {
              const zone = this.dragId && e.target.closest && e.target.closest("[data-drop]")
              if (!zone) return
              e.preventDefault()
              this.pushEvent("move", {
                id: this.dragId,
                seat: zone.dataset.seat || "",
                zone: zone.dataset.zone,
                slot: zone.dataset.slot || "",
                index: this.dropIndex(zone, e.target)
              })
              this.endDrag()
            })
            this.on(el, "dragend", () => this.endDrag())

            // A large face: hover with a mouse, a long press on touch.
            this.on(el, "pointerover", e => {
              if (e.pointerType !== "mouse" || this.dragId) return
              const card = e.target.closest && e.target.closest("[data-card-id]:not([data-hidden])")
              if (card === this.hoverCard) return
              this.hoverCard = card
              clearTimeout(this.hoverTimer)
              this.hidePreview()
              if (card) this.hoverTimer = setTimeout(() => this.showPreview(card, e.clientX), 500)
            })
            this.on(el, "pointerleave", () => { this.hoverCard = null; clearTimeout(this.hoverTimer); this.hidePreview() })
            this.on(el, "pointerdown", () => { clearTimeout(this.hoverTimer); this.hidePreview() })
            this.on(el, "touchstart", e => {
              const card = e.target.closest && e.target.closest("[data-card-id]:not([data-hidden])")
              clearTimeout(this.pressTimer)
              if (card) this.pressTimer = setTimeout(() => { this.pressed = true; this.showPreview(card, null) }, 450)
            }, {passive: true})
            this.on(el, "touchmove", () => clearTimeout(this.pressTimer), {passive: true})
            const release = e => {
              clearTimeout(this.pressTimer)
              if (this.pressed) { if (e.cancelable) e.preventDefault(); this.pressed = false; this.hidePreview() }
            }
            this.on(el, "touchend", release)
            this.on(el, "touchcancel", release)
            this.on(el, "contextmenu", e => { if (e.target.closest && e.target.closest("[data-card-id]")) e.preventDefault() })
          },
          on(target, name, fun, opts) {
            this.listeners = this.listeners || []
            target.addEventListener(name, fun, opts)
            this.listeners.push([target, name, fun, opts])
          },
          dropIndex(zone, target) {
            if (zone.dataset.list !== "true") return null
            const cards = Array.from(zone.querySelectorAll("[data-card-id]")).filter(c => c.closest("[data-drop]") === zone)
            const before = target.closest("[data-card-id]")
            let i = before ? cards.indexOf(before) : -1
            if (i < 0) return null
            const from = cards.findIndex(c => c.dataset.cardId === this.dragId)
            if (from >= 0 && from < i) i -= 1
            return i
          },
          setOver(zone) {
            if (this.over === zone) return
            if (this.over) this.over.classList.remove("cx-over")
            this.over = zone
            if (zone) zone.classList.add("cx-over")
          },
          endDrag() {
            this.dragId = null
            this.setOver(null)
            document.body.classList.remove("cx-dragging")
          },
          showPreview(card, x) {
            this.hidePreview()
            const p = document.createElement("div")
            p.className = "cx-preview"
            p.dataset.side = x === null ? "center" : (x < window.innerWidth / 2 ? "right" : "left")
            if (card.dataset.zoom) {
              const img = document.createElement("img")
              img.src = card.dataset.zoom
              img.alt = card.title || ""
              img.className = "cx-preview-img"
              p.appendChild(img)
            } else {
              const face = card.querySelector(".cx-face")
              if (!face) return
              const c = document.createElement("div")
              c.className = "cx-card cx-preview-card"
              c.appendChild(face.cloneNode(true))
              p.appendChild(c)
            }
            document.body.appendChild(p)
            this.preview = p
          },
          hidePreview() {
            if (this.preview) this.preview.remove()
            this.preview = null
          },
          destroyed() {
            this.hidePreview()
            document.body.classList.remove("cx-dragging")
            ;(this.listeners || []).forEach(([t, n, f, o]) => t.removeEventListener(n, f, o))
          }
        }
      </script>
    </div>
    """
  end

  # -- the top bar and the centre --------------------------------------------------------

  attr :code, :string, required: true
  attr :pov, :integer, required: true
  attr :opp, :integer, required: true
  attr :reveal, :boolean, required: true
  attr :spectator?, :boolean, required: true

  defp top_bar(assigns) do
    ~H"""
    <header class="flex flex-wrap items-center gap-x-2 gap-y-1.5">
      <.link
        navigate={~p"/games"}
        class="grid size-8 shrink-0 place-items-center rounded-full bg-white/10 ring-1 ring-white/15 transition hover:bg-white/20 active:scale-95"
        aria-label="Games"
      >
        <.icon name="hero-arrow-left" class="size-4" />
      </.link>
      <h1 class="text-base font-bold tracking-tight sm:text-lg">Codex</h1>
      <span
        id="cx-code"
        class="rounded-full bg-black/25 px-2 py-0.5 font-mono text-xs tracking-widest text-white/80 ring-1 ring-white/10"
        title="room code"
      >
        {@code}
      </span>
      <span
        :if={@spectator?}
        class="rounded-full bg-amber-300/20 px-2 py-0.5 text-xs text-amber-100"
      >
        watching
      </span>
      <div class="ml-auto flex items-center gap-1.5">
        <div
          class="flex rounded-full bg-black/30 p-0.5 text-xs font-semibold ring-1 ring-white/10"
          role="group"
          aria-label="View as"
        >
          <button
            :for={s <- [0, 1]}
            id={"cx-pov-#{s}"}
            type="button"
            phx-click="pov"
            phx-value-seat={s}
            aria-pressed={to_string(@pov == s)}
            class={[
              "rounded-full px-2.5 py-1 transition",
              if(@pov == s,
                do: [seat_bg(s), "text-white shadow"],
                else: "text-white/60 hover:text-white"
              )
            ]}
          >
            View P{s + 1}
          </button>
        </div>
        <button
          id="cx-reveal"
          type="button"
          phx-click="reveal"
          aria-pressed={to_string(@reveal)}
          class={[
            "flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium ring-1 transition active:scale-95",
            if(@reveal,
              do: "bg-amber-300 text-stone-900 ring-amber-200",
              else: "bg-black/25 text-white/80 ring-white/10 hover:bg-black/40"
            )
          ]}
          title={"Show or hide the hand of P#{@opp + 1}"}
        >
          <.icon name={if @reveal, do: "hero-eye-mini", else: "hero-eye-slash-mini"} class="size-3.5" />
          <span class="hidden sm:inline">P{@opp + 1} hand</span>
        </button>
        <button
          id="cx-log-open"
          type="button"
          phx-click="drawer"
          phx-value-zone="log"
          class="grid size-7 place-items-center rounded-full bg-black/25 ring-1 ring-white/10 transition hover:bg-black/40 lg:hidden"
          aria-label="Log"
        >
          <.icon name="hero-list-bullet-mini" class="size-4" />
        </button>
      </div>
    </header>
    """
  end

  attr :view, :map, required: true
  attr :art, :any, required: true
  attr :sel, :map, default: nil

  defp center(assigns) do
    ~H"""
    <div class="flex items-center gap-2 py-0.5">
      <div
        id="cx-active"
        class={[
          "flex min-w-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold text-white shadow-sm sm:text-sm",
          seat_bg(@view.active)
        ]}
      >
        <span class="size-1.5 animate-pulse rounded-full bg-white"></span>
        <span class="truncate">
          P{@view.active + 1} · turn {@view.sides[@view.active].turn}
        </span>
      </div>
      <div class="h-px flex-1 bg-gradient-to-r from-white/5 via-white/20 to-white/5"></div>
      <.pile
        id="cx-trash"
        zone={:trash}
        label="Trash"
        count={length(@view.trash)}
        top={top_card(@view, @view.trash)}
        art={@art}
        target?={@sel != nil}
        small
      />
      <button
        id="cx-undo"
        type="button"
        phx-click="undo"
        disabled={!@view.undo}
        class="flex items-center gap-1 rounded-full bg-black/30 px-2.5 py-1.5 text-xs font-semibold ring-1 ring-white/10 transition hover:bg-black/45 active:scale-95 disabled:opacity-35"
        title="Undo the last action"
      >
        <.icon name="hero-arrow-uturn-left-mini" class="size-4" />
        <span class="hidden sm:inline">Undo</span>
      </button>
      <button
        id="cx-end-turn"
        type="button"
        phx-click="end_turn"
        class="rounded-full bg-amber-300 px-3 py-1.5 text-xs font-bold text-stone-900 shadow-md ring-1 ring-amber-100 transition hover:bg-amber-200 active:scale-95 sm:text-sm"
      >
        End turn
      </button>
    </div>
    """
  end

  # -- a side ------------------------------------------------------------------------------

  attr :seat, :integer, required: true
  attr :far, :boolean, default: false
  attr :view, :map, required: true
  attr :art, :any, required: true
  attr :sel, :map, default: nil
  attr :reveal, :boolean, default: false
  attr :players, :map, default: %{}

  defp side(assigns) do
    side = assigns.view.sides[assigns.seat]
    assigns = assign(assigns, side: side, zones: side.zones, target?: assigns.sel != nil)

    ~H"""
    <section
      id={"cx-side-#{@seat}"}
      class={[
        "flex flex-col gap-1.5 rounded-2xl p-1.5 ring-1 sm:gap-2 sm:p-2",
        @seat == 0 && "bg-rose-950/20 ring-rose-300/15",
        @seat == 1 && "bg-sky-950/20 ring-sky-300/15",
        @view.active == @seat && "cx-active-side"
      ]}
      data-far={to_string(@far)}
    >
      <.side_header seat={@seat} side={@side} view={@view} />
      <%= if @far do %>
        <div class="cx-pair">
          <.mat {assigns} />
          <.hand
            seat={@seat}
            ids={@zones.hand}
            view={@view}
            art={@art}
            sel={@sel}
            hidden?={!@reveal}
            far
          />
        </div>
        <div class="cx-pair">
          <.patrol seat={@seat} slots={@zones.patrol} view={@view} art={@art} sel={@sel} />
          <.row seat={@seat} zone={:in_play} ids={@zones.in_play} view={@view} art={@art} sel={@sel} />
        </div>
      <% else %>
        <div class="cx-pair">
          <.patrol seat={@seat} slots={@zones.patrol} view={@view} art={@art} sel={@sel} />
          <.row seat={@seat} zone={:in_play} ids={@zones.in_play} view={@view} art={@art} sel={@sel} />
        </div>
        <div class="cx-pair">
          <.mat {assigns} />
          <.hand seat={@seat} ids={@zones.hand} view={@view} art={@art} sel={@sel} hidden?={false} />
        </div>
      <% end %>
    </section>
    """
  end

  attr :seat, :integer, required: true
  attr :side, :map, required: true
  attr :view, :map, required: true

  defp side_header(assigns) do
    hero = Cards.hero(assigns.side.spec)
    assigns = assign(assigns, hero: Cards.fetch!(hero).name)

    ~H"""
    <div class="flex flex-wrap items-center gap-x-2 gap-y-1 px-0.5">
      <span class={[
        "rounded-md px-1.5 py-0.5 text-xs font-black tracking-wide text-white",
        seat_bg(@seat)
      ]}>
        P{@seat + 1}
      </span>
      <span class="min-w-0 truncate text-xs text-white/80 sm:text-sm">
        <span class="font-semibold text-white">{@hero}</span>
        <span class="hidden sm:inline">· {@side.spec}</span>
      </span>
      <span class="text-[11px] text-white/50 tabular-nums">turn {@side.turn}</span>
      <div class="ml-auto flex items-center gap-1.5">
        <.stepper
          id={"cx-hp-#{@seat}"}
          seat={@seat}
          key="base_hp"
          value={@side.base_hp}
          icon="hero-heart-solid"
          tone="text-rose-300"
          label="Base HP"
        />
        <.stepper
          id={"cx-gold-#{@seat}"}
          seat={@seat}
          key="gold"
          value={@side.gold}
          icon="hero-circle-stack-solid"
          tone="text-amber-300"
          label="Gold"
        />
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :seat, :integer, required: true
  attr :key, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :tone, :string, required: true
  attr :label, :string, required: true

  defp stepper(assigns) do
    ~H"""
    <div class="flex items-center rounded-full bg-black/30 ring-1 ring-white/10" title={@label}>
      <button
        id={"#{@id}-minus"}
        type="button"
        phx-click="adjust"
        phx-value-seat={@seat}
        phx-value-key={@key}
        phx-value-delta="-1"
        class="grid size-6 place-items-center rounded-full text-white/70 transition hover:bg-white/10 hover:text-white active:scale-90 sm:size-7"
        aria-label={"#{@label} -1"}
      >
        <.icon name="hero-minus-mini" class="size-3.5" />
      </button>
      <span class="flex min-w-9 items-center justify-center gap-0.5 text-sm font-bold tabular-nums">
        <.icon name={@icon} class={["size-3.5", @tone]} />
        <span id={@id}>{@value}</span>
      </span>
      <button
        id={"#{@id}-plus"}
        type="button"
        phx-click="adjust"
        phx-value-seat={@seat}
        phx-value-key={@key}
        phx-value-delta="1"
        class="grid size-6 place-items-center rounded-full text-white/70 transition hover:bg-white/10 hover:text-white active:scale-90 sm:size-7"
        aria-label={"#{@label} +1"}
      >
        <.icon name="hero-plus-mini" class="size-3.5" />
      </button>
    </div>
    """
  end

  attr :seat, :integer, required: true
  attr :slots, :map, required: true
  attr :view, :map, required: true
  attr :art, :any, required: true
  attr :sel, :map, default: nil

  defp patrol(assigns) do
    assigns = assign(assigns, order: Game.patrol_slots(), labels: @slot_labels)

    ~H"""
    <div id={"cx-patrol-#{@seat}"} class="flex justify-center gap-1 sm:gap-2">
      <div
        :for={slot <- @order}
        id={"cx-slot-#{@seat}-#{slot}"}
        data-drop
        data-seat={@seat}
        data-zone="patrol"
        data-slot={slot}
        phx-click="zone"
        phx-value-seat={@seat}
        phx-value-zone="patrol"
        phx-value-slot={slot}
        class={["cx-zone cx-slot", @sel && "cx-target"]}
      >
        <span class="cx-label truncate" title={elem(@labels[slot], 0)}>
          <span class="hidden sm:inline">{elem(@labels[slot], 0)}</span>
          <span class="sm:hidden">{elem(@labels[slot], 1)}</span>
        </span>
        <div class="cx-slot-card">
          <.card
            :if={@slots[slot]}
            c={@view.cards[@slots[slot]]}
            art={@art}
            selected={@sel && @sel.id == @slots[slot]}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :seat, :integer, required: true
  attr :zone, :atom, required: true
  attr :ids, :list, required: true
  attr :view, :map, required: true
  attr :art, :any, required: true
  attr :sel, :map, default: nil

  defp row(assigns) do
    ~H"""
    <div
      id={"cx-zone-#{@seat}-#{@zone}"}
      data-drop
      data-list="true"
      data-seat={@seat}
      data-zone={@zone}
      phx-click="zone"
      phx-value-seat={@seat}
      phx-value-zone={@zone}
      class={["cx-zone cx-row", @sel && "cx-target"]}
    >
      <span class="cx-label cx-row-label">{label(@zone)}</span>
      <.card
        :for={id <- @ids}
        c={@view.cards[id]}
        art={@art}
        selected={@sel && @sel.id == id}
      />
    </div>
    """
  end

  attr :seat, :integer, required: true
  attr :ids, :list, required: true
  attr :view, :map, required: true
  attr :art, :any, required: true
  attr :sel, :map, default: nil
  attr :hidden?, :boolean, default: false
  attr :far, :boolean, default: false

  defp hand(assigns) do
    n = length(assigns.ids)
    assigns = assign(assigns, n: n, mid: (n - 1) / 2)

    ~H"""
    <div
      id={"cx-zone-#{@seat}-hand"}
      data-drop
      data-list="true"
      data-seat={@seat}
      data-zone="hand"
      phx-click="zone"
      phx-value-seat={@seat}
      phx-value-zone="hand"
      class={[
        "cx-zone cx-hand",
        @far && "cx-hand-far",
        @hidden? && "cx-hand-hidden",
        @n > 6 && "cx-hand-tight",
        @sel && "cx-target"
      ]}
    >
      <span class="cx-label cx-row-label">Hand · {@n}</span>
      <div class="cx-fan">
        <.card
          :for={{id, i} <- Enum.with_index(@ids)}
          c={@view.cards[id]}
          art={@art}
          hidden={@hidden?}
          selected={@sel && @sel.id == id}
          style={fan_style(i, @mid, @far)}
        />
      </div>
    </div>
    """
  end

  defp fan_style(i, mid, far) do
    d = i - mid
    r = if far, do: -d * 2.5, else: d * 2.5
    y = abs(d) * abs(d) * 1.2
    y = if far, do: -y, else: y
    "--r: #{Float.round(r, 2)}deg; --y: #{Float.round(y, 2)}px"
  end

  defp mat(assigns) do
    z = assigns.zones
    seat = assigns.seat

    assigns =
      assign(assigns,
        command: z.command,
        buildings: assigns.side.tech_buildings,
        workers: z.workers,
        deck: z.deck,
        discard: z.discard,
        codex: z.codex,
        top_discard: top_card(assigns.view, z.discard),
        seat: seat
      )

    ~H"""
    <div class={["cx-mat flex items-stretch gap-1 sm:gap-2", @far && "flex-row-reverse"]}>
      <div
        id={"cx-zone-#{@seat}-command"}
        data-drop
        data-list="true"
        data-seat={@seat}
        data-zone="command"
        phx-click="zone"
        phx-value-seat={@seat}
        phx-value-zone="command"
        class={["cx-zone cx-command min-w-0 flex-1", @sel && "cx-target"]}
      >
        <span class="cx-label cx-row-label">Command</span>
        <.card :for={id <- @command} c={@view.cards[id]} art={@art} selected={@sel && @sel.id == id} />
        <div class="flex flex-col flex-wrap content-start gap-1 self-start pt-3">
          <span
            :for={b <- @buildings}
            id={"cx-building-#{@seat}-#{b}"}
            class="rounded-md bg-amber-200/90 px-1.5 py-0.5 text-[10px] font-bold text-stone-900 shadow-sm"
          >
            {building_label(b)}
          </span>
          <button
            id={"cx-build-#{@seat}"}
            type="button"
            phx-click="drawer"
            phx-value-seat={@seat}
            phx-value-zone="buildings"
            class="rounded-md bg-black/25 px-1.5 py-0.5 text-[10px] font-semibold text-white/70 ring-1 ring-white/10 transition hover:bg-black/40 hover:text-white"
          >
            + Build
          </button>
        </div>
      </div>
      <.pile
        id={"cx-workers-#{@seat}"}
        zone={:workers}
        seat={@seat}
        label="Workers"
        count={length(@workers)}
        back
        art={@art}
        target?={@sel != nil}
      />
      <div class="flex flex-col items-center gap-1">
        <.pile
          id={"cx-deck-#{@seat}"}
          zone={:deck}
          seat={@seat}
          label="Deck"
          count={@deck}
          back
          art={@art}
          target?={@sel != nil}
        />
        <div class="flex gap-1">
          <button
            id={"cx-draw-#{@seat}"}
            type="button"
            phx-click="draw"
            phx-value-seat={@seat}
            class="cx-mini"
            title="Draw a card"
          >
            Draw
          </button>
          <button
            id={"cx-shuffle-#{@seat}"}
            type="button"
            phx-click="shuffle"
            phx-value-seat={@seat}
            phx-value-zone="deck"
            class="cx-mini"
            title="Shuffle the deck"
            aria-label="Shuffle the deck"
          >
            <.icon name="hero-arrows-right-left-mini" class="size-3" />
          </button>
        </div>
      </div>
      <.pile
        id={"cx-discard-#{@seat}"}
        zone={:discard}
        seat={@seat}
        label="Discard"
        count={length(@discard)}
        top={@top_discard}
        art={@art}
        target?={@sel != nil}
      />
      <.pile
        id={"cx-codex-#{@seat}"}
        zone={:codex}
        seat={@seat}
        label="Codex"
        count={length(@codex)}
        codex
        art={@art}
        target?={@sel != nil}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :zone, :atom, required: true
  attr :seat, :any, default: nil
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :top, :any, default: nil
  attr :back, :boolean, default: false
  attr :codex, :boolean, default: false
  attr :small, :boolean, default: false
  attr :art, :any, required: true
  attr :target?, :boolean, default: false

  defp pile(assigns) do
    ~H"""
    <div
      id={@id}
      data-drop
      data-seat={@seat}
      data-zone={@zone}
      phx-click="zone"
      phx-value-seat={@seat}
      phx-value-zone={@zone}
      class={["cx-zone cx-pile", @small && "cx-pile-small", @target? && "cx-target"]}
      title={"#{@label}: #{@count}"}
    >
      <span class="cx-label">{@label}</span>
      <div class="cx-pile-stack" data-empty={to_string(@count == 0)}>
        <%= cond do %>
          <% @count == 0 -> %>
            <div class="cx-pile-empty"></div>
          <% @top -> %>
            <.card c={@top} art={@art} prefix="cx-top" click={false} />
          <% @codex -> %>
            <div class="cx-card cx-codex-face">
              <div class="cx-face">
                <span>Codex</span>
              </div>
            </div>
          <% true -> %>
            <div class="cx-card"><.back art={@art} /></div>
        <% end %>
        <span :if={@count > 0} class="cx-count" id={"#{@id}-count"}>{@count}</span>
      </div>
    </div>
    """
  end

  # -- a card ------------------------------------------------------------------------------

  attr :c, :map, required: true, doc: "a card instance from the view"
  attr :art, :any, required: true
  attr :selected, :any, default: false
  attr :hidden, :boolean, default: false, doc: "draw the back (the other side's hand)"
  attr :peek, :boolean, default: false, doc: "draw the face of a face-down card (a sheet)"
  attr :prefix, :string, default: "cx-card"
  attr :click, :boolean, default: true
  attr :style, :string, default: nil

  defp card(assigns) do
    c = assigns.c
    d = Cards.fetch!(c.card)
    back? = assigns.hidden or (c.face_down and not assigns.peek)
    art? = MapSet.member?(assigns.art, c.card)

    assigns =
      assign(assigns,
        d: d,
        back?: back?,
        img: art? && "/images/codex/#{c.card}.webp",
        zoom: !assigns.hidden && art? && "/images/codex/zoom/#{c.card}.webp",
        stats: stats(c, d)
      )

    ~H"""
    <div
      id={"#{@prefix}-#{@c.id}"}
      data-card-id={@c.id}
      data-hidden={@hidden}
      data-zoom={@zoom}
      draggable={to_string(!@hidden)}
      phx-click={@click && !@hidden && "select"}
      phx-value-id={@c.id}
      title={if(@hidden, do: "a card", else: @d.name)}
      style={@style}
      class={[
        "cx-card",
        @c.exhausted && "cx-exhausted",
        @selected && "cx-selected",
        @click && !@hidden && "cursor-pointer"
      ]}
    >
      <%= cond do %>
        <% @back? -> %>
          <.back art={@art} />
        <% @img -> %>
          <img class="cx-face" src={@img} alt={@d.name} loading="lazy" draggable="false" />
        <% true -> %>
          <.css_face d={@d} />
      <% end %>
      <span :if={@c.face_down and !@hidden and @peek} class="cx-tok cx-down">face down</span>
      <%= if !@hidden do %>
        <span :if={@c.level} class="cx-tok cx-lvl" title="level">L{@c.level}</span>
        <span :if={@c.damage > 0} class="cx-tok cx-dmg" title="damage">{@c.damage}</span>
        <span :if={@c.plus > 0} class="cx-tok cx-plus" title="+1/+1 runes">+{@c.plus}</span>
        <span :if={@c.minus > 0} class="cx-tok cx-minus" title="-1/-1 runes">−{@c.minus}</span>
        <span :if={@stats} class="cx-tok cx-stat" title="ATK/HP now">{@stats}</span>
      <% end %>
    </div>
    """
  end

  attr :art, :any, required: true

  defp back(assigns) do
    ~H"""
    <%= if MapSet.member?(@art, "card-back") do %>
      <img class="cx-face" src="/images/codex/card-back.webp" alt="" draggable="false" />
    <% else %>
      <div class="cx-face cx-back"><span>Codex</span></div>
    <% end %>
    """
  end

  attr :d, :map, required: true

  defp css_face(assigns) do
    ~H"""
    <div class={["cx-face cx-css", tone(@d)]}>
      <span :if={@d.cost} class="cx-cost">{@d.cost}</span>
      <span class="cx-name">{@d.name}</span>
      <span class="cx-type">{type_line(@d)}</span>
      <span :for={line <- face_text(@d)} class="cx-text">{line}</span>
      <span :if={@d.atk || @d.hp} class="cx-stats">{@d.atk}/{@d.hp}</span>
    </div>
    """
  end

  defp face_text(%{bands: [_ | _] = bands}),
    do: for(b <- bands, line <- b.text, do: "Lv #{b.level}+: #{line}")

  defp face_text(d), do: d.text

  defp type_line(d) do
    [d.type, d.subtype] |> Enum.reject(&is_nil/1) |> Enum.join(" — ") |> tech_suffix(d)
  end

  defp tech_suffix(line, %{tech: t, type: "Unit"}) when is_integer(t), do: "#{line} · tech #{t}"
  defp tech_suffix(line, _d), do: line

  defp tone(%{type: "Hero"}), do: "cx-tone-hero"
  defp tone(%{type: "Worker"}), do: "cx-tone-worker"
  defp tone(%{spec: "Bashing"}), do: "cx-tone-bashing"
  defp tone(%{spec: "Finesse"}), do: "cx-tone-finesse"
  defp tone(%{type: "Building"}), do: "cx-tone-building"
  defp tone(_d), do: "cx-tone-neutral"

  # ATK/HP after the runes and the hero band; nil when it is the printed value.
  defp stats(c, d) do
    {atk, hp, banded?} =
      case c.level && Cards.band(c.card, c.level) do
        %{atk: a, hp: h, level: l} -> {a, h, l > 1}
        _ -> {d.atk, d.hp, false}
      end

    runes = c.plus - c.minus

    if is_integer(atk) and is_integer(hp) and (runes != 0 or banded?),
      do: "#{atk + runes}/#{hp + runes}"
  end

  # -- the inspector (the selected card) ------------------------------------------------------

  attr :card, :map, required: true
  attr :where, :string, required: true
  attr :art, :any, required: true

  defp inspector(assigns) do
    c = assigns.card
    d = Cards.fetch!(c.card)
    max = Cards.max_level(c.card)
    assigns = assign(assigns, d: d, max: max, zoom?: MapSet.member?(assigns.art, c.card))

    ~H"""
    <div
      id="cx-actions"
      class="cx-inspector flex flex-col gap-2 rounded-t-2xl max-lg:gap-1.5 max-lg:p-2.5 bg-stone-950/95 p-3 shadow-2xl ring-1 ring-white/15 backdrop-blur lg:rounded-2xl lg:bg-black/35"
    >
      <div class="hidden justify-center lg:flex">
        <div class="cx-zoom">
          <%= if @zoom? do %>
            <img
              class="cx-zoom-img"
              src={"/images/codex/zoom/#{@card.card}.webp"}
              alt={@d.name}
            />
          <% else %>
            <div class="cx-card"><.css_face d={@d} /></div>
          <% end %>
        </div>
      </div>
      <div class="flex items-start gap-2">
        <div class="min-w-0 flex-1">
          <p id="cx-actions-name" class="truncate text-sm font-bold">{@d.name}</p>
          <p class="truncate text-xs text-white/60">
            P{@card.seat + 1}'s · {@where}<span class="lg:hidden"> · tap a zone to move it</span>
          </p>
        </div>
        <button
          id="cx-act-close"
          type="button"
          phx-click="deselect"
          class="grid size-7 shrink-0 place-items-center rounded-full bg-white/10 transition hover:bg-white/20"
          aria-label="Deselect"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </button>
      </div>
      <div class="flex flex-wrap gap-1.5">
        <button
          id="cx-act-exhaust"
          type="button"
          phx-click="card"
          phx-value-op="exhaust"
          class="cx-act"
        >
          <.icon name="hero-arrow-path-rounded-square-mini" class="size-4" />
          {if @card.exhausted, do: "Ready", else: "Exhaust"}
        </button>
        <button id="cx-act-flip" type="button" phx-click="card" phx-value-op="flip" class="cx-act">
          <.icon name="hero-arrows-up-down-mini" class="size-4" />
          {if @card.face_down, do: "Face up", else: "Face down"}
        </button>
        <button
          id="cx-act-hand"
          type="button"
          phx-click="card"
          phx-value-op="to"
          phx-value-zone="hand"
          class="cx-act"
        >
          To hand
        </button>
        <button
          id="cx-act-play"
          type="button"
          phx-click="card"
          phx-value-op="to"
          phx-value-zone="in_play"
          class="cx-act"
        >
          To play
        </button>
        <button
          id="cx-act-discard"
          type="button"
          phx-click="card"
          phx-value-op="to"
          phx-value-zone="discard"
          class="cx-act"
        >
          Discard
        </button>
        <button
          id="cx-act-trash"
          type="button"
          phx-click="card"
          phx-value-op="to"
          phx-value-zone="trash"
          class="cx-act cx-act-danger"
        >
          Trash
        </button>
      </div>
      <div class="grid grid-cols-2 gap-1.5 sm:grid-cols-4 lg:grid-cols-2">
        <.token_stepper
          id="cx-act-damage"
          label="Damage"
          key="damage"
          value={@card.damage}
          tone="bg-red-600"
        />
        <.token_stepper
          id="cx-act-plus"
          label="+1/+1"
          key="plus"
          value={@card.plus}
          tone="bg-emerald-600"
        />
        <.token_stepper
          id="cx-act-minus"
          label="−1/−1"
          key="minus"
          value={@card.minus}
          tone="bg-violet-600"
        />
        <.token_stepper
          :if={@card.level}
          id="cx-act-level"
          label={"Level (max #{@max})"}
          key="level"
          value={@card.level}
          tone="bg-amber-500"
        />
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :key, :string, required: true
  attr :value, :integer, required: true
  attr :tone, :string, required: true

  defp token_stepper(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-1 rounded-xl bg-white/5 py-1 pr-1 pl-2 ring-1 ring-white/10">
      <span class="truncate text-[11px] text-white/70">{@label}</span>
      <div class="flex items-center gap-0.5">
        <button
          id={"#{@id}-minus"}
          type="button"
          phx-click="card"
          phx-value-op="adjust"
          phx-value-key={@key}
          phx-value-delta="-1"
          class="grid size-7 place-items-center rounded-full bg-white/10 transition hover:bg-white/20 active:scale-90"
          aria-label={"#{@label} -1"}
        >
          <.icon name="hero-minus-mini" class="size-3.5" />
        </button>
        <span
          id={@id}
          class={["min-w-6 rounded-full px-1.5 text-center text-xs font-bold tabular-nums", @tone]}
        >
          {@value}
        </span>
        <button
          id={"#{@id}-plus"}
          type="button"
          phx-click="card"
          phx-value-op="adjust"
          phx-value-key={@key}
          phx-value-delta="1"
          class="grid size-7 place-items-center rounded-full bg-white/10 transition hover:bg-white/20 active:scale-90"
          aria-label={"#{@label} +1"}
        >
          <.icon name="hero-plus-mini" class="size-3.5" />
        </button>
      </div>
    </div>
    """
  end

  defp inspector_help(assigns) do
    ~H"""
    <div class="hidden rounded-2xl bg-black/25 p-3 text-xs leading-relaxed text-white/70 ring-1 ring-white/10 lg:block">
      <p class="mb-1 font-semibold text-white">A free table</p>
      <p>
        Drag a card to a zone, or click it and click a zone. A selected card shows its
        tokens here. Hover a card to see it large. Click the deck to draw; click the
        discard pile, the codex, the workers or the trash to look through it.
      </p>
    </div>
    """
  end

  # -- the log ------------------------------------------------------------------------------

  attr :view, :map, required: true
  attr :id, :string, required: true
  attr :class, :any, default: nil

  defp log_list(assigns) do
    assigns = assign(assigns, entries: assigns.view.log |> Enum.map(&log_text(&1, assigns.view)))

    ~H"""
    <div id={@id} class={["flex-col gap-1 rounded-2xl bg-black/25 p-3 ring-1 ring-white/10", @class]}>
      <p class="text-xs font-semibold tracking-wide text-white/60 uppercase">Log</p>
      <ol class="flex max-h-[30vh] flex-col gap-0.5 overflow-y-auto text-xs text-white/80">
        <li :for={{text, i} <- Enum.with_index(@entries)} id={"#{@id}-#{i}"} class="shrink-0 truncate">
          {text}
        </li>
      </ol>
    </div>
    """
  end

  defp log_text({:setup, _seed}, _v), do: "New game: P1 Bashing, P2 Finesse."
  defp log_text({:reshuffle, s}, _v), do: "P#{s + 1} shuffles the discard pile into the deck."
  defp log_text({:action, s, :end_turn}, _v), do: "P#{s + 1} ends the turn."
  defp log_text({:action, _s, action}, v), do: action_text(action, v)
  defp log_text(other, _v), do: inspect(other)

  defp action_text({:move, id, zone, at}, v), do: "#{name(v, id)} → #{zone_text(zone, at)}"
  defp action_text({:draw, s, n}, _v), do: "P#{s + 1} draws #{n}"

  defp action_text({:shuffle, s, z}, _v),
    do: "P#{s + 1} shuffles the #{String.downcase(label(z))}"

  defp action_text({:adjust_card, id, key, d}, v),
    do: "#{name(v, id)}: #{key_text(key)} #{signed(d)}"

  defp action_text({:toggle, id, key}, v), do: "#{name(v, id)}: #{key_text(key)}"
  defp action_text({:adjust, s, key, d}, _v), do: "P#{s + 1} #{key_text(key)} #{signed(d)}"
  defp action_text({:building, s, b}, _v), do: "P#{s + 1} #{building_label(b)} on/off"
  defp action_text(other, _v), do: inspect(other)

  defp zone_text(:trash, _at), do: "trash"
  defp zone_text({s, :patrol}, slot), do: "P#{s + 1} #{elem(@slot_labels[slot], 0)}"
  defp zone_text({s, :deck}, 0), do: "top of P#{s + 1}'s deck"
  defp zone_text({s, z}, _at), do: "P#{s + 1} #{String.downcase(label(z))}"

  defp key_text(:damage), do: "damage"
  defp key_text(:plus), do: "+1/+1"
  defp key_text(:minus), do: "−1/−1"
  defp key_text(:level), do: "level"
  defp key_text(:exhausted), do: "exhaust / ready"
  defp key_text(:face_down), do: "flip"
  defp key_text(:gold), do: "gold"
  defp key_text(:base_hp), do: "base HP"

  defp signed(d) when d > 0, do: "+#{d}"
  defp signed(d), do: "−#{abs(d)}"

  defp name(v, id) do
    case v.cards[id] do
      %{card: slug} -> Cards.fetch!(slug).name
      nil -> "a card"
    end
  end

  # -- the sheet (a pile's cards, the buildings, the log) ---------------------------------------

  attr :drawer, :any, required: true
  attr :view, :map, required: true
  attr :art, :any, required: true

  defp drawer(assigns) do
    assigns =
      assign(assigns,
        title: drawer_title(assigns.drawer),
        ids: drawer_ids(assigns.view, assigns.drawer)
      )

    ~H"""
    <div
      id="cx-drawer"
      class="cx-drawer fixed inset-0 z-40 flex items-end justify-center lg:items-center"
    >
      <button
        type="button"
        phx-click="close_drawer"
        class="absolute inset-0 bg-black/55 backdrop-blur-[2px]"
        aria-label="Close"
      ></button>
      <div class="cx-drawer-panel relative flex max-h-[85dvh] w-full flex-col gap-3 rounded-t-3xl bg-stone-900 p-4 text-stone-100 shadow-2xl ring-1 ring-white/10 lg:max-w-4xl lg:rounded-3xl">
        <div class="flex items-center gap-2">
          <h2 id="cx-drawer-title" class="text-base font-bold">{@title}</h2>
          <button
            :if={match?({_, z} when z in [:discard, :codex], @drawer)}
            id="cx-drawer-shuffle"
            type="button"
            phx-click="shuffle"
            phx-value-seat={elem(@drawer, 0)}
            phx-value-zone={elem(@drawer, 1)}
            class="cx-mini"
          >
            Shuffle
          </button>
          <button
            id="cx-drawer-close"
            type="button"
            phx-click="close_drawer"
            class="ml-auto grid size-8 place-items-center rounded-full bg-white/10 transition hover:bg-white/20"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-5" />
          </button>
        </div>
        <%= case @drawer do %>
          <% :log -> %>
            <.log_list view={@view} id="cx-drawer-log" class="flex" />
          <% {seat, :buildings} -> %>
            <.buildings seat={seat} built={@view.sides[seat].tech_buildings} />
          <% _ -> %>
            <p class="text-xs text-white/60">
              Tap a card to select it, then tap a zone. With a mouse, drag it out.
            </p>
            <p :if={@ids == []} class="py-6 text-center text-sm text-white/50">No cards.</p>
            <div class="cx-sheet-grid -mx-1 overflow-y-auto px-1 pt-1 pb-2">
              <.card :for={id <- @ids} c={@view.cards[id]} art={@art} prefix="cx-sheet" peek />
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :seat, :integer, required: true
  attr :built, :list, required: true

  defp buildings(assigns) do
    assigns = assign(assigns, all: Game.buildings())

    ~H"""
    <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
      <button
        :for={b <- @all}
        id={"cx-toggle-building-#{b}"}
        type="button"
        phx-click="building"
        phx-value-seat={@seat}
        phx-value-building={b}
        aria-pressed={to_string(b in @built)}
        class={[
          "rounded-xl px-3 py-2.5 text-sm font-semibold ring-1 transition active:scale-[0.98]",
          if(b in @built,
            do: "bg-amber-300 text-stone-900 ring-amber-200",
            else: "bg-white/5 text-white/80 ring-white/10 hover:bg-white/10"
          )
        ]}
      >
        {building_label(b)}
      </button>
    </div>
    """
  end

  defp drawer_title({s, :buildings}), do: "P#{s + 1}: tech buildings and add-ons"
  defp drawer_title(:log), do: "Log"
  defp drawer_title(:trash), do: "Trash"
  defp drawer_title({s, z}), do: "P#{s + 1}: #{label(z)}"

  defp drawer_ids(v, :trash), do: v.trash
  defp drawer_ids(v, {s, z}) when z in @drawers, do: v.sides[s].zones[z]
  defp drawer_ids(_v, _drawer), do: []

  # -- helpers -------------------------------------------------------------------------------

  defp label(zone), do: Map.fetch!(@zone_labels, zone)
  defp building_label(b), do: Map.fetch!(@building_labels, b)

  defp seat_bg(0), do: "bg-rose-700"
  defp seat_bg(1), do: "bg-sky-700"

  defp top_card(_v, []), do: nil
  defp top_card(v, [id | _]), do: v.cards[id]

  defp where(v, id) do
    case Game.locate(v, id) do
      :trash -> "trash"
      {s, :patrol, slot} -> "P#{s + 1} #{elem(@slot_labels[slot], 0)}"
      {s, zone} -> "P#{s + 1} #{String.downcase(label(zone))}"
      nil -> "?"
    end
  end

  # The slugs that have art (`mix codex.cards`), and "card-back". Off in tests
  # (`config :quacks, :codex_art, false`): the art is on some machines only, so the
  # HTML snapshots must not depend on it.
  defp art do
    if Application.get_env(:quacks, :codex_art, true), do: art_files(), else: MapSet.new()
  end

  defp art_files do
    case File.ls(Application.app_dir(:quacks, @art_dir)) do
      {:ok, files} ->
        for f <- files, String.ends_with?(f, ".webp"), into: MapSet.new(), do: Path.rootname(f)

      {:error, _} ->
        MapSet.new()
    end
  end
end
