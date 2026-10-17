defmodule CodexWeb.Board do
  @moduledoc """
  The Codex sandbox board on the table page (`TableWeb.TableLive`, a
  `TableWeb.Board`). It draws `Codex.Game.view/2`: a free table where one
  browser moves the cards of both sides (hot-seat).

  - The layout follows the TTS table: the other side at the top, your side at the
    bottom. "View as P1 / P2" turns the table; "End turn" turns it to the side
    that plays next. Each side: a header (base HP, gold), the patrol zone (5
    named slots), the cards in play, the command zone (heroes, buildings) and
    the piles as counter chips (codex, deck, discard, workers, trash). Your hand
    is docked at the bottom. The other side's hand shows card backs; "Show
    hand" shows its faces.
  - A phone (under 1024 px) is one screen (100dvh) with no page scroll: the top
    bar, the other side as a strip (its header and one row of its cards; a tap
    opens the whole side as a sheet), the status bar (phase, Undo, End turn),
    your board, the selected card and your hand. A row that is too long
    scrolls sideways inside the row.
  - Move a card: drag it to a zone (a mouse; the hook `.CodexTable`), or tap it
    to select it and tap a zone (a phone). A tap on a pile with no card selected
    opens it: the deck draws 1; the discard pile, the codex, the workers and the
    trash open a sheet of their cards.
  - A selected card shows its actions: exhaust, damage, +1/+1 and -1/-1 runes,
    hero level, flip, to hand / discard / trash. On a desktop the actions and a
    large face are in the right column; on a phone they are a bar at the bottom.
  - A card on the board (patrol, in play, command) is a mini card (`mini/1`): an
    art crop, the cost or the hero level, the name and the ATK/HP now (green: above
    the printed value, violet: below, red HP: damaged). Exhausted: grey.
  - Hover (mouse) or a long press (touch) shows a large face of a card.
  - Motion (240 ms or less, off with reduced motion): a card that arrives in a
    zone flies from where it was; a number that changes bumps, and the base HP
    and gold show their change ("−2") for a moment.
  - The face is the art from `mix codex.cards` (`/images/codex/<slug>.webp`).
    Without the art the card is drawn in CSS from the data (`Codex.Cards`).

  The board's CSS is `assets/css/codex.css` (`cx-*`).
  """
  @behaviour TableWeb.Board

  use QuacksWeb, :html

  alias Codex.{Cards, Game}
  alias CodexWeb.Moves
  alias QuacksWeb.Plugs.CodexArt

  @zone_names Map.new([:patrol | Game.list_zones()], &{Atom.to_string(&1), &1})
  @slot_names Map.new(Game.patrol_slots(), &{Atom.to_string(&1), &1})
  @card_keys %{"damage" => :damage, "plus" => :plus, "minus" => :minus, "level" => :level}
  @counters %{"gold" => :gold, "base_hp" => :base_hp}
  @building_names Map.new(Game.buildings(), &{Atom.to_string(&1), &1})
  @drawers ~w(discard codex workers trash)a
  @target_buildings %{
    "base" => :base,
    "tech_1" => :tech_1,
    "tech_2" => :tech_2,
    "tech_3" => :tech_3,
    "tower" => :tower,
    "surplus" => :surplus,
    "heroes_hall" => :heroes_hall
  }

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
      reveal: false,
      targeting: nil,
      actions: [],
      tech_pick: [],
      zoom: nil,
      opp_open: false,
      expanded: false,
      summary: nil,
      patrolling: false,
      focus: nil
    )
  end

  @impl true
  def put_view(socket, env, old) do
    v = env.view
    a = socket.assigns
    # Hot-seat: the table turns to the side that plays. Against the bot: P1 stays at the bottom.
    new_turn? = old != nil and old.view.active != v.active
    turned? = new_turn? and v.bot == nil
    pov = if(turned?, do: v.active, else: a.pov)
    kept? = Map.has_key?(v.cards, a.selected)

    Phoenix.Component.assign(socket,
      view: v,
      actions: env.actions,
      spectator?: env.seat == :spectator,
      pov: pov,
      summary: summary_after(a.summary, v, new_turn? and v.active == pov),
      reveal: a.reveal and not turned?,
      selected: if(kept?, do: a.selected),
      expanded: a.expanded and kept?,
      targeting: nil,
      patrolling: false,
      tech_pick: if(v.phase == :tech, do: a.tech_pick, else: []),
      drawer: drawer_after(a.drawer, v, env.actions)
    )
  end

  # The tech sheet opens by itself in your tech step and closes after it.
  defp drawer_after(_drawer, %{phase: :tech, active: s}, [_ | _]), do: {s, :tech}
  defp drawer_after({_s, :tech}, _v, _actions), do: nil
  defp drawer_after(drawer, _v, _actions), do: drawer

  # The turn comes back to the side at the bottom: what the other side did.
  defp summary_after(_summary, %{phase: :over}, _back?), do: nil
  defp summary_after(_summary, v, true), do: turn_summary(v, v.active)
  defp summary_after(summary, _v, false), do: summary

  # The log lines of the other side's last turn (the log is newest first): all
  # after `seat`'s last "end turn", without `seat`'s own actions. Nil: no lines.
  defp turn_summary(v, seat) do
    lines =
      v.log
      |> Enum.take_while(&(&1 != {:action, seat, :end_turn}))
      |> Enum.reverse()
      |> Enum.reject(&(match?({:action, ^seat, _}, &1) or match?({:action, _, :end_turn}, &1)))
      |> Enum.map(&log_text(&1, v))

    case lines do
      [] -> nil
      _ -> %{seat: 1 - seat, lines: lines}
    end
  end

  @impl true
  def handle_event("select", %{"id" => id}, %{assigns: %{targeting: %{}}} = socket),
    do: pick(socket, int(id))

  def handle_event("select", %{"id" => id}, socket) do
    id = int(id)
    a = socket.assigns

    selected =
      cond do
        a.selected == id -> nil
        Map.has_key?(a.view.cards, id) -> id
        true -> a.selected
      end

    {:noreply,
     Phoenix.Component.assign(socket,
       selected: selected,
       drawer: nil,
       opp_open: false,
       expanded: false,
       summary: nil,
       patrolling: false
     )}
  end

  # An action chip on a card (a desktop), or its key (A, L, P) from the hook:
  # one legal target acts at once; else a target pick starts, or Patrol lights
  # the free slots of the selected card.
  def handle_event("chip", %{"id" => id} = params, socket) do
    id = int(id)
    chips = Moves.chips(socket.assigns.actions, id)

    chip =
      Enum.find(chips, fn c ->
        c.key == params["key"] or (c.hotkey != nil and c.hotkey == params["hotkey"])
      end)

    case chip do
      %{do: action} ->
        {:act, action,
         Phoenix.Component.assign(socket, selected: nil, targeting: nil, patrolling: false)}

      %{target: key} ->
        {:noreply, socket |> start_pick(key) |> Phoenix.Component.assign(patrolling: false)}

      %{patrol: _slots} ->
        {:noreply,
         Phoenix.Component.assign(socket,
           selected: id,
           targeting: nil,
           patrolling: true,
           expanded: false,
           drawer: nil,
           summary: nil
         )}

      nil ->
        {:noreply, socket}
    end
  end

  # The selected card's sheet on a phone: its peek or the full card and all actions.
  def handle_event("expand", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, expanded: !socket.assigns.expanded)}

  def handle_event("summary_ok", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, summary: nil)}

  # The opponent's whole side on a phone (a sheet from the top).
  def handle_event("opp", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, opp_open: !socket.assigns.opp_open)}

  def handle_event("deselect", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, selected: nil, expanded: false)}

  # A tap on a zone: move the selected card there, or open the pile.
  def handle_event("zone", params, socket) do
    a = socket.assigns

    with {:ok, zone} <- target(params),
         {:ok, at} <- at(zone, params) do
      case {a.selected, zone} do
        {id, _} when is_integer(id) and not a.view.free ->
          rules_drop(socket, id, zone, at)

        {id, _} when is_integer(id) ->
          {:act, {:move, id, zone, at}, Phoenix.Component.assign(socket, selected: nil)}

        {nil, {_seat, :deck}} when not a.view.free ->
          {:noreply, socket}

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
      if socket.assigns.view.free,
        do: {:act, {:move, int(id), zone, at}, Phoenix.Component.assign(socket, selected: nil)},
        else: rules_drop(socket, int(id), zone, at)
    else
      _ -> {:noreply, socket}
    end
  end

  # Rules mode: a legal action of the selected card (`CodexWeb.Moves.buttons/2`).
  def handle_event("rule", %{"key" => key}, %{assigns: %{selected: id}} = socket)
      when is_integer(id) do
    case Enum.find(Moves.buttons(socket.assigns.actions, id), &(&1.key == key)) do
      %{do: action} -> {:act, action, socket}
      %{target: tkey} -> {:noreply, start_pick(socket, tkey)}
      nil -> {:noreply, socket}
    end
  end

  def handle_event("pick_building", %{"seat" => s, "name" => name}, socket) do
    with {:ok, seat} <- seat(s),
         {:ok, b} <- Map.fetch(@target_buildings, name) do
      pick(socket, {:building, seat, b})
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("skip_target", _params, socket), do: pick(socket, nil)

  # A pick by its button (a card out of sight, a worker, a choice).
  def handle_event(
        "pick_index",
        %{"i" => i},
        %{assigns: %{targeting: %{key: key, picked: picked}}} = socket
      ) do
    values = Moves.options(socket.assigns.actions, key, picked).values

    case Enum.at(values, int(i)) do
      nil -> {:noreply, socket}
      value -> pick(socket, value)
    end
  end

  def handle_event(
        "pick_done",
        _params,
        %{assigns: %{targeting: %{key: key, picked: picked}}} = socket
      ) do
    case Moves.options(socket.assigns.actions, key, picked).complete do
      nil -> {:noreply, socket}
      action -> {:act, action, Phoenix.Component.assign(socket, targeting: nil, selected: nil)}
    end
  end

  def handle_event("cancel_target", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, targeting: nil)}

  def handle_event("free", _params, socket),
    do: {:act, {:free_mode, !socket.assigns.view.free}, socket}

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
    do:
      {:act, :end_turn,
       Phoenix.Component.assign(socket, selected: nil, drawer: nil, summary: nil)}

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

  def handle_event(
        "drawer",
        %{"zone" => "tech"},
        %{assigns: %{view: %{phase: :tech} = v}} = socket
      ),
      do: {:noreply, Phoenix.Component.assign(socket, drawer: {v.active, :tech})}

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

  # The tech step: pick up to 2 codex cards (by name), then confirm.
  def handle_event("tech_pick", %{"slug" => slug}, socket) do
    a = socket.assigns
    {s, :tech} = a.drawer
    copies = Enum.count(a.view.sides[s].zones.codex, &(a.view.cards[&1].card == slug))
    picked = Enum.count(a.tech_pick, &(&1 == slug))

    pick =
      cond do
        picked < copies and length(a.tech_pick) < 2 -> a.tech_pick ++ [slug]
        picked > 0 -> List.delete(a.tech_pick, slug)
        true -> a.tech_pick
      end

    {:noreply, Phoenix.Component.assign(socket, tech_pick: pick)}
  end

  def handle_event("tech_done", _params, socket) do
    a = socket.assigns

    case tech_action(a.actions, a.view, a.tech_pick) do
      nil -> {:noreply, socket}
      action -> {:act, action, Phoenix.Component.assign(socket, tech_pick: [])}
    end
  end

  def handle_event("build", %{"building" => "tech_2", "spec" => spec}, socket) do
    action = Enum.find(socket.assigns.actions, &match?({:build, :tech_2, ^spec}, &1))
    if action, do: {:act, action, socket}, else: {:noreply, socket}
  end

  def handle_event("build", %{"building" => b}, socket) do
    case Map.fetch(@building_names, b) do
      {:ok, building} -> {:act, {:build, building}, socket}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("close_drawer", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, drawer: nil)}

  def handle_event("key", %{"key" => "Escape"}, socket),
    do:
      {:noreply,
       Phoenix.Component.assign(socket,
         selected: nil,
         drawer: nil,
         opp_open: false,
         zoom: nil,
         expanded: false,
         summary: nil,
         targeting: nil,
         patrolling: false
       )}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def act_error(reason, _action, socket),
    do: Phoenix.LiveView.put_flash(socket, :error, error_text(reason))

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # The legal tech action with the picked card names.
  defp tech_action(actions, v, pick) do
    want = Enum.sort(pick)

    Enum.find(actions, fn
      {:tech, ids} -> Enum.sort(Enum.map(ids, &v.cards[&1].card)) == want
      _ -> false
    end)
  end

  # -- rules mode: drops and target picks -------------------------------------------------

  defp rules_drop(socket, id, zone, at) do
    case Moves.drop(socket.assigns.actions, id, zone, at) do
      {:act, action} -> {:act, action, Phoenix.Component.assign(socket, selected: nil)}
      {:target, key} -> {:noreply, start_pick(socket, key)}
      :error -> {:noreply, Phoenix.LiveView.put_flash(socket, :error, drop_text(zone))}
    end
  end

  defp drop_text({_s, :workers}),
    do: "You can hire one worker per turn, from your hand, for 1 gold."

  defp drop_text({_s, :patrol}),
    do: "Only your ready units and heroes in play can patrol, in your main phase."

  defp drop_text(_zone),
    do: "That move is not a legal action now. Turn on Free mode to move cards by hand."

  defp start_pick(socket, {_kind, id, _name} = key) do
    targeting = %{key: key, picked: []}
    Phoenix.Component.assign(socket, selected: id, targeting: targeting, expanded: false)
  end

  # A tapped target: the full action acts; else the pick goes on.
  defp pick(%{assigns: %{targeting: %{key: key, picked: picked}}} = socket, value) do
    picked = picked ++ [value]
    opts = Moves.options(socket.assigns.actions, key, picked)

    cond do
      opts.complete && opts.values == [] ->
        {:act, opts.complete, Phoenix.Component.assign(socket, targeting: nil, selected: nil)}

      opts.complete || opts.values != [] ->
        {:noreply, Phoenix.Component.assign(socket, targeting: %{key: key, picked: picked})}

      true ->
        {:noreply, socket}
    end
  end

  defp pick(socket, _value), do: {:noreply, socket}

  defp error_text(:slot_taken), do: "That patrol slot is taken. Move its card first."
  defp error_text(:empty_deck), do: "The deck and the discard pile are empty."
  defp error_text(:out_of_range), do: "That value is at its limit."
  defp error_text(:not_a_hero), do: "Only a hero has a level."
  defp error_text(:nothing_to_undo), do: "Nothing to undo."
  defp error_text(:no_seat), do: "You watch this table: only its player moves the cards."
  defp error_text(:free_mode_off), do: "Turn on Free mode to move cards by hand."
  defp error_text(:worker_hired), do: "You already hired a worker this turn."
  defp error_text(:no_gold), do: "Not enough gold."
  defp error_text(:game_over), do: "The game is over."
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
    assigns = assign(assigns, page_assigns(assigns))

    ~H"""
    <div
      id="cx-root"
      phx-hook=".CodexTable"
      phx-window-keydown="key"
      phx-key="Escape"
      class={["cx-table text-stone-100", @sel && "cx-selecting"]}
      data-pov={@pov}
      data-active={@view.active}
      data-targeting={to_string(@targeting != nil)}
    >
      <div class={["cx-layout", @summary && "cx-noted"]}>
        <.top_bar
          code={@code}
          pov={@pov}
          reveal={@reveal}
          opp={@opp}
          spectator?={@spectator?}
          free={@free}
        />
        <.side {assigns} seat={@opp} far open={@opp_open} />
        <button
          :if={@opp_open}
          id="cx-opp-backdrop"
          type="button"
          phx-click="opp"
          class="cx-backdrop lg:hidden"
          aria-label={"Close the side of P#{@opp + 1}"}
        ></button>
        <.center view={@view} actions={@actions} targeting={@targeting != nil} />
        <.pick_banner :if={@targeting} targeting={@targeting} pick={@pick} view={@view} />
        <.turn_summary_card :if={@summary} summary={@summary} />
        <.side {assigns} seat={@pov} far={false} />
        <.hand
          seat={@pov}
          ids={@view.sides[@pov].zones.hand}
          view={@view}
          art={@art}
          sel={@sel}
          tg={@tg}
          ui={@ui}
          dock
        />

        <button
          :if={@sel && @expanded}
          id="cx-sheet-backdrop"
          type="button"
          phx-click="expand"
          class="cx-backdrop lg:hidden"
          aria-label="Show less"
        ></button>
        <aside
          id="cx-aside"
          class={[
            "cx-a-sheet flex-col gap-3 lg:flex",
            if(@sel, do: "flex", else: "hidden"),
            @targeting && "max-lg:hidden"
          ]}
        >
          <.inspector
            :if={@sel}
            card={@sel}
            where={@where}
            art={@art}
            free={@free}
            buttons={@buttons}
            pick={@pick}
            targeting={@targeting}
            stats={@view.stats[@sel.id]}
            view={@view}
            expanded={@expanded}
          />
          <.inspector_help :if={!@sel} free={@free} />
          <.log_list view={@view} id="cx-log" class="hidden lg:flex" />
        </aside>
      </div>

      <.drawer
        :if={@drawer}
        drawer={@drawer}
        view={@view}
        art={@art}
        actions={@actions}
        tech_pick={@tech_pick}
      />

      <div :if={@zoom} id="cx-zoom" class="cx-preview" data-side="center">
        <%= if MapSet.member?(@art, @zoom.card) do %>
          <img
            class="cx-preview-img"
            src={"/images/codex/zoom/#{@zoom.card}.webp"}
            alt={Cards.fetch!(@zoom.card).name}
          />
        <% else %>
          <div class="cx-card cx-preview-card"><.css_face d={Cards.fetch!(@zoom.card)} /></div>
        <% end %>
      </div>

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
              if (card) this.pressTimer = setTimeout(() => { this.pressed = true; this.showPreview(card, null) }, 400)
            }, {passive: true})
            this.on(el, "touchmove", () => clearTimeout(this.pressTimer), {passive: true})
            const release = e => {
              clearTimeout(this.pressTimer)
              if (this.pressed) { if (e.cancelable) e.preventDefault(); this.pressed = false; this.hidePreview() }
            }
            this.on(el, "touchend", release)
            this.on(el, "touchcancel", release)
            this.on(el, "contextmenu", e => { if (e.target.closest && e.target.closest("[data-card-id]")) e.preventDefault() })

            // Keyboard: Enter or Space on a focused card (or another role=button)
            // clicks it. A / L / P: attack, level up, patrol with the focused card,
            // else the selected one (the server checks each action).
            this.on(window, "pointerdown", () => { this.kbd = false }, {capture: true})
            this.on(window, "keydown", e => {
              this.kbd = true
              if (e.altKey || e.ctrlKey || e.metaKey || e.repeat) return
              const t = e.target
              if (t.closest && t.closest("input, textarea, select, [contenteditable]")) return
              if ((e.key === "Enter" || e.key === " ") && t.matches && t.matches('[role="button"][tabindex]') && el.contains(t)) {
                e.preventDefault()
                t.click()
                return
              }
              const k = e.key.toLowerCase()
              if (!["a", "l", "p"].includes(k) || document.getElementById("cx-drawer")) return
              const card = (el.contains(t) && t.closest && t.closest("[data-card-id]:not([data-hidden])")) ||
                el.querySelector("[data-card-id].cx-selected")
              if (!card) return
              e.preventDefault()
              this.pushEvent("chip", {id: card.dataset.cardId, hotkey: k})
            })

            // Motion (off with reduced motion): a card that arrives in a zone flies
            // from where it was (FLIP); a number that changes bumps.
            this.reduce = window.matchMedia("(prefers-reduced-motion: reduce)")
            this.snap()
            // The old values live here: a patch removes attributes that the server does not send.
            this.vals = new WeakMap()
            el.querySelectorAll("[data-bump]").forEach(b => this.vals.set(b, b.textContent.trim()))
            const resnap = () => {
              if (this.snapping) return
              this.snapping = requestAnimationFrame(() => { this.snapping = null; this.snap() })
            }
            this.on(window, "resize", resnap)
            this.on(el, "scroll", resnap, {capture: true, passive: true})
            this.observer = new MutationObserver(muts => this.changed(muts))
            this.observer.observe(el, {subtree: true, childList: true, characterData: true})
          },
          updated() {
            // A pick started from the keyboard: the focus goes to the first lit target.
            const on = this.el.dataset.targeting === "true"
            if (on && !this.wasTargeting && this.kbd) {
              const t = this.el.querySelector(".cx-targetable[tabindex], .cx-targetable-pill[tabindex], #cx-pick button")
              if (t) t.focus()
            }
            this.wasTargeting = on
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
            const tpl = card.querySelector("template.cx-zoom-tpl")
            if (card.dataset.zoom) {
              const img = document.createElement("img")
              img.src = card.dataset.zoom
              img.alt = card.title || ""
              img.className = "cx-preview-img"
              p.appendChild(img)
            } else if (tpl) {
              p.appendChild(tpl.content.cloneNode(true))
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
          snap() {
            this.rects = new Map()
            this.el.querySelectorAll('[id^="cx-card-"]').forEach(c => {
              const r = c.getBoundingClientRect()
              if (r.width) this.rects.set(c.id, r)
            })
          },
          changed(muts) {
            const added = new Set(), bumps = new Set()
            for (const m of muts) {
              for (const n of m.addedNodes) {
                if (n.nodeType !== 1) continue
                if (n.id && n.id.startsWith("cx-card-")) added.add(n)
                n.querySelectorAll('[id^="cx-card-"]').forEach(c => added.add(c))
                if (n.matches("[data-bump]")) bumps.add(n)
                n.querySelectorAll("[data-bump]").forEach(b => bumps.add(b))
              }
              const t = m.target.nodeType === 1 ? m.target : m.target.parentElement
              const b = t && t.closest("[data-bump]")
              if (b) bumps.add(b)
            }
            const still = this.reduce.matches
            // Many cards at once (the table turns): no flight.
            if (!still && added.size <= 6) added.forEach(c => this.fly(c))
            bumps.forEach(b => this.bump(b, still))
            this.snap()
          },
          fly(card) {
            const from = this.rects.get(card.id)
            const to = card.getBoundingClientRect()
            if (!to.width) return
            const ease = "cubic-bezier(0.2, 0.8, 0.2, 1)"
            if (!from) {
              card.animate([{opacity: 0, scale: 0.85}, {opacity: 1, scale: 1}], {duration: 180, easing: ease})
              return
            }
            const dx = from.left - to.left, dy = from.top - to.top
            if (Math.abs(dx) < 2 && Math.abs(dy) < 2) return
            card.animate(
              [{translate: `${dx}px ${dy}px`, scale: from.width / to.width}, {translate: "0 0", scale: 1}],
              {duration: 240, easing: ease}
            )
          },
          bump(el, still) {
            const v = el.textContent.trim(), old = this.vals.get(el)
            this.vals.set(el, v)
            if (still || old === undefined || old === v) return
            el.animate([{scale: 1.35}, {scale: 1}], {duration: 220, easing: "cubic-bezier(0.2, 0.8, 0.2, 1)"})
            const d = parseInt(v, 10) - parseInt(old, 10)
            if (el.dataset.bump !== "float" || !d) return
            const r = el.getBoundingClientRect()
            const f = document.createElement("span")
            f.className = d < 0 ? "cx-float cx-float-down" : "cx-float"
            f.textContent = (d > 0 ? "+" : "−") + Math.abs(d)
            f.style.left = `${r.left + r.width / 2}px`
            f.style.top = `${r.top}px`
            document.body.appendChild(f)
            f.animate([{opacity: 1, translate: "-50% 0"}, {opacity: 0, translate: "-50% -20px"}], {duration: 700, easing: "ease-out"})
              .onfinish = () => f.remove()
          },
          destroyed() {
            if (this.observer) this.observer.disconnect()
            this.hidePreview()
            document.body.classList.remove("cx-dragging")
            ;(this.listeners || []).forEach(([t, n, f, o]) => t.removeEventListener(n, f, o))
          }
        }
      </script>
    </div>
    """
  end

  # The page's derived assigns (the gallery passes only the board's own assigns).
  defp page_assigns(assigns) do
    v = assigns.view

    [
      opp: 1 - assigns.pov,
      art: art(),
      players: assigns[:seats] || %{},
      free: v.free,
      expanded: assigns[:expanded] || false,
      opp_open: assigns[:opp_open] || false,
      zoom: assigns[:zoom] && v.cards[assigns.zoom],
      summary: assigns[:summary]
    ] ++ selection_assigns(assigns, v)
  end

  # The selected card, its place and buttons, and the target pick in progress.
  defp selection_assigns(assigns, v) do
    selected = assigns.selected && v.cards[assigns.selected]
    targeting = assigns[:targeting]
    pick = targeting && Moves.options(assigns.actions, targeting.key, targeting.picked)

    [
      sel: selected,
      where: selected && where(v, selected.id),
      pick: pick,
      tg: MapSet.new((pick && pick.values) || []),
      buttons: if(selected && !v.free, do: Moves.buttons(assigns.actions, selected.id), else: []),
      ui: ui(assigns, v, selected)
    ]
  end

  # Per-card marks for the cards on the table: `chips` (card id => its action
  # chips, `Moves.chips/2` with a label; none in free mode or in a pick),
  # `focus` and `hover` (the gallery draws a focus ring or the hover look on
  # that card) and `lit`: the free patrol slots ({seat, slot}) of the selected
  # card after Patrol.
  defp ui(assigns, v, selected) do
    lit =
      if assigns[:patrolling] && selected,
        do:
          for(
            {:patrol, id, slot} <- assigns.actions,
            id == selected.id,
            into: MapSet.new(),
            do: {v.active, slot}
          ),
        else: MapSet.new()

    %{
      chips: card_chips(assigns, v),
      focus: assigns[:focus],
      hover: assigns[:hover],
      lit: lit
    }
  end

  defp card_chips(%{targeting: t}, _v) when t != nil, do: %{}
  defp card_chips(_assigns, %{free: true}), do: %{}

  defp card_chips(assigns, v) do
    ids =
      for a <- assigns.actions, is_tuple(a), is_integer(elem(a, 1)), uniq: true, do: elem(a, 1)

    Map.new(ids, fn id ->
      chips =
        for chip <- Enum.sort_by(Moves.chips(assigns.actions, id), &chip_rank(&1.kind)),
            do: Map.put(chip, :label, chip_label(chip, v))

      {id, chips}
    end)
  end

  defp chip_label(%{kind: :attack, one: value}, v), do: "Attack #{value_label(v, value)}"
  defp chip_label(%{kind: :attack}, _v), do: "Attack…"

  defp chip_label(%{kind: :patrol, do: {:patrol, _, slot}}, _v),
    do: "Patrol as #{elem(@slot_labels[slot], 0)}"

  defp chip_label(%{kind: :patrol}, _v), do: "Patrol…"

  defp chip_label(%{one: value} = chip, v),
    do: "#{String.trim_trailing(chip_base_label(chip), "…")}: #{value_label(v, value)}"

  defp chip_label(chip, _v), do: chip_base_label(chip)

  defp chip_base_label(%{key: "level"}), do: "Level up (1 gold)"
  defp chip_base_label(%{key: "hire"}), do: "Hire as a worker (1 gold)"
  defp chip_base_label(%{key: "summon"}), do: "Summon"
  defp chip_base_label(%{key: "sideline"}), do: "Sideline"
  defp chip_base_label(%{key: "play"}), do: "Play"
  defp chip_base_label(%{key: "play-pick"}), do: "Play…"

  defp chip_base_label(%{key: "ability-" <> _, target: {:ability, _, name}}),
    do: Moves.ability_label(name) <> "…"

  defp chip_base_label(%{key: "ability-" <> _, do: {:ability, _, name, _}}),
    do: Moves.ability_label(name)

  defp chip_base_label(%{key: key}), do: key

  @chip_order ~w(attack play hire summon level ability patrol sideline)a
  defp chip_rank(kind), do: Enum.find_index(@chip_order, &(&1 == kind))

  defp chip_icon(:attack), do: "hero-bolt-solid"
  defp chip_icon(:level), do: "hero-chevron-double-up-solid"
  defp chip_icon(:patrol), do: "hero-shield-check-solid"
  defp chip_icon(:sideline), do: "hero-shield-exclamation-solid"
  defp chip_icon(:hire), do: "hero-wrench-solid"
  defp chip_icon(:summon), do: "hero-arrow-down-circle-solid"
  defp chip_icon(:play), do: "hero-play-solid"
  defp chip_icon(:ability), do: "hero-sparkles-solid"

  # The action chips on a card (a desktop): round buttons on its top edge. CSS
  # shows them on hover, focus and selection; a phone keeps the bottom sheet.
  # Not in the tab order: the card's keys (A, L, P) and the inspector reach them.
  attr :c, :map, required: true
  attr :chips, :list, required: true

  defp chip_bar(assigns) do
    # At most 3 buttons: with 4 or more chips, 2 and "…" (all, in the inspector).
    {shown, more} = Enum.split(assigns.chips, if(length(assigns.chips) > 3, do: 2, else: 3))
    assigns = assign(assigns, shown: shown, more: more != [])

    ~H"""
    <div class="cx-chipbar" role="group" aria-label="Actions">
      <button
        :for={chip <- @shown}
        id={"cx-chip-#{@c.id}-#{chip.key}"}
        type="button"
        tabindex="-1"
        draggable="false"
        phx-click="chip"
        phx-value-id={@c.id}
        phx-value-key={chip.key}
        class={["cx-chipbtn", "cx-chipbtn-#{chip.kind}"]}
        aria-label={chip.label}
        title={if(chip.hotkey, do: "#{chip.label} (#{String.upcase(chip.hotkey)})", else: chip.label)}
        data-kind={chip.kind}
      >
        <.icon name={chip_icon(chip.kind)} class="size-4" />
      </button>
      <button
        :if={@more}
        id={"cx-chip-#{@c.id}-more"}
        type="button"
        tabindex="-1"
        draggable="false"
        phx-click="select"
        phx-value-id={@c.id}
        class="cx-chipbtn"
        aria-label="All actions"
        title="All actions"
      >
        <.icon name="hero-ellipsis-horizontal-mini" class="size-4" />
      </button>
    </div>
    """
  end

  # What the other side did in its turn: a card over the board until "OK".
  attr :summary, :map, required: true

  defp turn_summary_card(assigns) do
    {lines, more} = Enum.split(assigns.summary.lines, 6)
    assigns = assign(assigns, lines: lines, more: length(more))

    ~H"""
    <div id="cx-summary" class="cx-a-note cx-summary cx-toast-lg" role="status">
      <div class="flex items-center gap-2">
        <span class={[
          "rounded-md px-1.5 py-0.5 text-xs font-black tracking-wide text-white",
          seat_bg(@summary.seat)
        ]}>
          P{@summary.seat + 1}
        </span>
        <p class="flex-1 text-sm font-bold">P{@summary.seat + 1}'s turn</p>
        <button
          id="cx-summary-ok"
          type="button"
          phx-click="summary_ok"
          class="min-h-11 rounded-full bg-amber-300 px-5 text-sm font-bold text-stone-900 shadow transition hover:bg-amber-200 active:scale-95"
        >
          OK
        </button>
      </div>
      <ol class="flex flex-col gap-1 text-sm text-white/85">
        <li :for={{line, i} <- Enum.with_index(@lines)} id={"cx-summary-#{i}"} class="flex gap-2">
          <span class="mt-1.5 size-1.5 shrink-0 rounded-full bg-white/40"></span>
          <span>{line}</span>
        </li>
      </ol>
      <p :if={@more > 0} class="text-xs text-white/50">… and {@more} more in the log.</p>
    </div>
    """
  end

  # -- the top bar and the status bar ----------------------------------------------------

  attr :code, :string, required: true
  attr :pov, :integer, required: true
  attr :opp, :integer, required: true
  attr :reveal, :boolean, required: true
  attr :spectator?, :boolean, required: true
  attr :free, :boolean, default: false

  defp top_bar(assigns) do
    ~H"""
    <header class="cx-a-top flex items-center gap-1.5">
      <.link
        navigate={~p"/games"}
        class="cx-icon-btn shrink-0"
        aria-label="Games"
      >
        <.icon name="hero-arrow-left" class="size-4" />
      </.link>
      <h1 class="hidden text-base font-bold tracking-tight sm:block sm:text-lg">Codex</h1>
      <span
        id="cx-code"
        class="rounded-full bg-black/25 px-2 py-0.5 font-mono text-[11px] tracking-widest text-white/80 ring-1 ring-white/10 max-[379px]:hidden sm:text-xs"
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
      <div class="ml-auto flex items-center gap-1">
        <div
          class="flex rounded-full bg-black/30 text-xs font-semibold ring-1 ring-white/10"
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
              "min-h-11 min-w-11 rounded-full px-2.5 transition lg:min-h-9",
              if(@pov == s,
                do: [seat_bg(s), "text-white shadow"],
                else: "text-white/60 hover:text-white"
              )
            ]}
          >
            <span class="hidden sm:inline">View</span> P{s + 1}
          </button>
        </div>
        <button
          id="cx-reveal"
          type="button"
          phx-click="reveal"
          aria-pressed={to_string(@reveal)}
          class={[
            "cx-icon-btn sm:w-auto sm:gap-1 sm:px-3",
            @reveal && "bg-amber-300! text-stone-900!"
          ]}
          title={"Show or hide the hand of P#{@opp + 1}"}
          aria-label={"Show or hide the hand of P#{@opp + 1}"}
        >
          <.icon name={if @reveal, do: "hero-eye-mini", else: "hero-eye-slash-mini"} class="size-4" />
          <span class="hidden text-xs font-medium sm:inline">P{@opp + 1} hand</span>
        </button>
        <button
          id="cx-free"
          type="button"
          phx-click="free"
          aria-pressed={to_string(@free)}
          class={[
            "cx-icon-btn sm:w-auto sm:gap-1 sm:px-3",
            @free && "bg-fuchsia-300! text-stone-900!"
          ]}
          title="Free mode: move cards and change counters by hand, without the rules"
          aria-label="Free mode"
        >
          <.icon name="hero-hand-raised-mini" class="size-4" />
          <span class="hidden text-xs font-medium sm:inline">Free mode</span>
        </button>
        <button
          id="cx-log-open"
          type="button"
          phx-click="drawer"
          phx-value-zone="log"
          class="cx-icon-btn lg:hidden"
          aria-label="Log"
        >
          <.icon name="hero-list-bullet-mini" class="size-4" />
        </button>
      </div>
    </header>
    """
  end

  attr :view, :map, required: true
  attr :actions, :list, default: []
  attr :targeting, :boolean, default: false

  # The status bar. In a target pick it stays in its row on a desktop (the
  # banner floats over it: nothing moves); a phone shows the banner in its place.
  defp center(assigns) do
    v = assigns.view

    assigns =
      assign(assigns, hint: hint(v, assigns.actions), can_end?: :end_turn in assigns.actions)

    ~H"""
    <div id="cx-status" class={["cx-a-status cx-status", @targeting && "max-lg:hidden"]}>
      <div
        id="cx-active"
        class={[
          "cx-st-pill flex min-w-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold text-white shadow-sm sm:text-sm",
          seat_bg(@view.active)
        ]}
      >
        <span class="size-1.5 shrink-0 animate-pulse rounded-full bg-white"></span>
        <span class="truncate sm:hidden">
          P{@view.active + 1} · T{@view.sides[@view.active].turn} · {phase_short(@view.phase)}
        </span>
        <span class="hidden truncate sm:inline">
          P{@view.active + 1} · turn {@view.sides[@view.active].turn} · {phase_text(@view.phase)}
        </span>
      </div>
      <div class="cx-st-line h-px bg-gradient-to-r from-white/5 via-white/20 to-white/5"></div>
      <button
        id="cx-undo"
        type="button"
        phx-click="undo"
        disabled={!@view.undo}
        class="cx-st-undo cx-icon-btn sm:w-auto sm:gap-1 sm:px-3"
        title="Undo the last action"
        aria-label="Undo"
      >
        <.icon name="hero-arrow-uturn-left-mini" class="size-4" />
        <span class="hidden text-xs font-semibold sm:inline">Undo</span>
      </button>
      <button
        :if={@can_end?}
        id="cx-end-turn"
        type="button"
        phx-click="end_turn"
        class="cx-st-end min-h-11 shrink-0 rounded-full bg-amber-300 px-4 text-sm font-bold whitespace-nowrap text-stone-900 shadow-md ring-1 ring-amber-100 transition hover:bg-amber-200 active:scale-95"
      >
        End turn
      </button>
      <p
        :if={@view.phase == :over}
        id="cx-winner"
        class="cx-st-hint rounded-xl bg-amber-300 px-3 py-2 text-center text-sm font-bold text-stone-900 shadow"
      >
        P{@view.winner + 1} wins: the base of P{1 - @view.winner + 1} is destroyed.
      </p>
      <div :if={@hint && @view.phase != :over} class="cx-st-hint flex min-w-0 items-center gap-2 px-1">
        <p id="cx-hint" class="min-w-0 flex-1 text-xs text-white/70 max-lg:line-clamp-2">
          {@hint}
        </p>
        <button
          :if={@view.phase == :tech and @actions != []}
          id="cx-tech-open"
          type="button"
          phx-click="drawer"
          phx-value-zone="tech"
          class="min-h-11 shrink-0 rounded-full bg-amber-300 px-4 text-sm font-bold text-stone-900 shadow"
        >
          Pick codex cards
        </button>
      </div>
    </div>
    """
  end

  defp phase_text(:main), do: "main phase"
  defp phase_text(:tech), do: "tech"
  defp phase_text(:over), do: "game over"

  defp phase_short(:main), do: "Main"
  defp phase_short(:tech), do: "Tech"
  defp phase_short(:over), do: "Over"

  # What the active side can do now, in a line (rules mode).
  defp hint(%{phase: :over}, _actions), do: nil
  defp hint(%{bot: b, active: b}, []) when b != nil, do: "The bot is playing its turn…"
  defp hint(_v, []), do: nil
  defp hint(%{phase: :tech}, _actions), do: "Pick codex cards for your discard pile."

  defp hint(%{free: true}, _actions),
    do: "Free mode: drag cards and change counters by hand. The rules do not check them."

  defp hint(_v, actions) do
    kinds = for a <- actions, is_tuple(a), uniq: true, do: elem(a, 0)

    can =
      [
        hire: "hire a worker",
        summon: "summon your hero",
        level_up: "level up",
        play: "play a card",
        patrol: "set patrollers",
        attack: "attack",
        ability: "use an ability",
        build: "build"
      ]
      |> Enum.filter(fn {k, _} -> k in kinds end)
      |> Enum.map(&elem(&1, 1))

    case can do
      [] -> "Nothing more to do: end the turn."
      list -> "You can " <> Enum.join(list, ", ") <> ". Tap a card to see its actions."
    end
  end

  # -- a side ------------------------------------------------------------------------------
  #
  # The far side (the opponent) on a phone is a strip: its header and one row of
  # its patrollers and units. "open" shows all of it in a sheet from the top.

  attr :seat, :integer, required: true
  attr :far, :boolean, default: false
  attr :open, :boolean, default: false
  attr :view, :map, required: true
  attr :art, :any, required: true
  attr :sel, :map, default: nil
  attr :tg, :any, default: nil
  attr :reveal, :boolean, default: false
  attr :players, :map, default: %{}
  attr :actions, :list, default: []
  attr :ui, :map, default: %{chips: %{}, focus: nil, hover: nil, lit: MapSet.new()}

  defp side(assigns) do
    side = assigns.view.sides[assigns.seat]
    zones = side.zones

    assigns =
      assign(assigns,
        side: side,
        zones: zones,
        board?: zones.in_play != [] or Enum.any?(zones.patrol, fn {_s, id} -> id end)
      )

    ~H"""
    <section
      id={"cx-side-#{@seat}"}
      class={[
        "cx-side flex flex-col gap-1.5 rounded-2xl p-1.5 ring-1 lg:gap-2 lg:p-2",
        if(@far, do: "cx-a-opp", else: "cx-a-board"),
        @seat == 0 && "bg-rose-950/20 ring-rose-300/15",
        @seat == 1 && "bg-sky-950/20 ring-sky-300/15",
        @view.active == @seat && "cx-active-side"
      ]}
      data-far={to_string(@far)}
      data-open={to_string(@open)}
    >
      <.side_header
        seat={@seat}
        side={@side}
        view={@view}
        free={@view.free}
        tg={@tg}
        far={@far}
        open={@open}
      />
      <button
        :if={@tg && {:building, @seat, :base} in @tg}
        id={"cx-base-#{@seat}"}
        type="button"
        phx-click="pick_building"
        phx-value-seat={@seat}
        phx-value-name="base"
        class="cx-base-tile cx-targetable-pill lg:hidden"
      >
        <.icon name="hero-home-solid" class="size-5" />
        <span class="font-bold">Attack the base of P{@seat + 1}</span>
        <span class="ml-auto flex items-center gap-1 font-black tabular-nums">
          <.icon name="hero-heart-solid" class="size-4 text-rose-600" />{@side.base_hp}
        </span>
      </button>
      <p :if={@far and !@board?} class="cx-strip-empty">No units or heroes in play.</p>
      <div class="cx-side-body">
        <%= if @far do %>
          <div class="cx-pair cx-pair-mat">
            <.mat {assigns} />
            <.hand
              seat={@seat}
              ids={@zones.hand}
              view={@view}
              art={@art}
              sel={@sel}
              tg={@tg}
              hidden?={!@reveal}
              ui={@ui}
              far
            />
          </div>
        <% end %>
        <div class="cx-pair cx-pair-board">
          <.patrol
            seat={@seat}
            slots={@zones.patrol}
            view={@view}
            art={@art}
            sel={@sel}
            tg={@tg}
            ui={@ui}
          />
          <.row
            seat={@seat}
            zone={:in_play}
            ids={@zones.in_play}
            view={@view}
            art={@art}
            sel={@sel}
            tg={@tg}
            ui={@ui}
          />
        </div>
        <div :if={!@far} class="cx-pair cx-pair-mat">
          <.mat {assigns} />
        </div>
      </div>
    </section>
    """
  end

  attr :seat, :integer, required: true
  attr :side, :map, required: true
  attr :view, :map, required: true
  attr :free, :boolean, default: false
  attr :tg, :any, default: nil
  attr :far, :boolean, default: false
  attr :open, :boolean, default: false

  defp side_header(assigns) do
    side = assigns.side
    specs = Map.get(side, :specs, [side.spec])

    title =
      case specs do
        [spec] -> Cards.fetch!(Cards.hero(spec)).name
        _ -> Map.get(side, :starter, "")
      end

    assigns = assign(assigns, hero: title, spec_text: Enum.join(specs, ", "))

    ~H"""
    <div class="flex min-h-9 items-center gap-x-1.5 px-0.5">
      <span class={[
        "rounded-md px-1.5 py-0.5 text-xs font-black tracking-wide text-white",
        seat_bg(@seat)
      ]}>
        P{@seat + 1}
      </span>
      <span class="min-w-0 flex-1 truncate text-xs text-white/80 sm:text-sm">
        <span class="font-semibold text-white">{@hero}</span>
        <span class="hidden sm:inline">· {@spec_text}</span>
        <span class="hidden text-[11px] text-white/50 tabular-nums sm:inline">· turn {@side.turn}</span>
      </span>
      <div class="flex shrink-0 items-center gap-1">
        <.stepper
          id={"cx-hp-#{@seat}"}
          seat={@seat}
          key="base_hp"
          value={@side.base_hp}
          icon="hero-heart-solid"
          tone="text-rose-300"
          label="Base HP"
          free={@free}
          target={@tg && {:building, @seat, :base} in @tg}
          building="base"
        />
        <.stepper
          id={"cx-gold-#{@seat}"}
          seat={@seat}
          key="gold"
          value={@side.gold}
          icon="hero-circle-stack-solid"
          tone="text-amber-300"
          label="Gold"
          free={@free}
        />
        <button
          :if={@far}
          id="cx-opp-open"
          type="button"
          phx-click="opp"
          aria-expanded={to_string(@open)}
          aria-label={"The side of P#{@seat + 1}: hand, workers, deck"}
          class="flex min-h-11 items-center gap-1.5 rounded-full bg-black/30 pr-2 pl-2.5 text-xs font-bold tabular-nums ring-1 ring-white/10 transition active:scale-95 lg:hidden"
        >
          <span class="flex items-center gap-0.5" title="hand">
            <.icon name="hero-hand-raised-mini" class="size-3.5 text-white/60" />{length(
              @side.zones.hand
            )}
          </span>
          <span class="flex items-center gap-0.5" title="workers">
            <.icon name="hero-wrench-mini" class="size-3.5 text-white/60" />{length(
              @side.zones.workers
            )}
          </span>
          <.icon
            name={if @open, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"}
            class="size-4 text-white/70"
          />
        </button>
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

  attr :free, :boolean, default: true
  attr :target, :any, default: false
  attr :building, :string, default: nil

  defp stepper(assigns) do
    ~H"""
    <div
      class={[
        "flex items-center rounded-full bg-black/30 ring-1 ring-white/10",
        @target && "cx-targetable-pill cx-hit cursor-pointer"
      ]}
      title={@label}
      phx-click={@target && "pick_building"}
      phx-value-seat={@seat}
      phx-value-name={@building}
      id={@target && "#{@id}-target"}
      tabindex={@target && "0"}
      role={@target && "button"}
    >
      <button
        :if={@free}
        id={"#{@id}-minus"}
        type="button"
        phx-click="adjust"
        phx-value-seat={@seat}
        phx-value-key={@key}
        phx-value-delta="-1"
        class="cx-hit grid size-7 place-items-center rounded-full text-white/70 transition hover:bg-white/10 hover:text-white active:scale-90"
        aria-label={"#{@label} -1"}
      >
        <.icon name="hero-minus-mini" class="size-3.5" />
      </button>
      <span class="flex min-h-8 min-w-11 items-center justify-center gap-0.5 px-1.5 text-sm font-bold tabular-nums">
        <.icon name={@icon} class={["size-3.5", @tone]} />
        <span id={@id} data-bump="float">{@value}</span>
      </span>
      <button
        :if={@free}
        id={"#{@id}-plus"}
        type="button"
        phx-click="adjust"
        phx-value-seat={@seat}
        phx-value-key={@key}
        phx-value-delta="1"
        class="cx-hit grid size-7 place-items-center rounded-full text-white/70 transition hover:bg-white/10 hover:text-white active:scale-90"
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
  attr :tg, :any, default: nil
  attr :ui, :map, default: %{chips: %{}, focus: nil, hover: nil, lit: MapSet.new()}

  defp patrol(assigns) do
    assigns = assign(assigns, order: Game.patrol_slots(), labels: @slot_labels)

    ~H"""
    <div id={"cx-patrol-#{@seat}"} class="cx-patrol">
      <div
        :for={slot <- @order}
        id={"cx-slot-#{@seat}-#{slot}"}
        data-drop
        data-seat={@seat}
        data-zone="patrol"
        data-slot={slot}
        data-empty={to_string(@slots[slot] == nil)}
        phx-click="zone"
        phx-value-seat={@seat}
        phx-value-zone="patrol"
        phx-value-slot={slot}
        class={[
          "cx-zone cx-slot",
          @sel && "cx-target",
          {@seat, slot} in @ui.lit && "cx-slot-lit"
        ]}
      >
        <span class="cx-label truncate" title={elem(@labels[slot], 0)}>
          <span class="hidden lg:inline">{elem(@labels[slot], 0)}</span>
          <span class="lg:hidden">{elem(@labels[slot], 1)}</span>
        </span>
        <div class="cx-slot-card">
          <.mini
            :if={@slots[slot]}
            c={@view.cards[@slots[slot]]}
            art={@art}
            selected={@sel && @sel.id == @slots[slot]}
            target={@tg && @slots[slot] in @tg}
            ui={@ui}
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
  attr :tg, :any, default: nil
  attr :ui, :map, default: %{chips: %{}, focus: nil, hover: nil, lit: MapSet.new()}

  defp row(assigns) do
    ~H"""
    <div
      id={"cx-zone-#{@seat}-#{@zone}"}
      data-drop
      data-list="true"
      data-seat={@seat}
      data-zone={@zone}
      data-empty={to_string(@ids == [])}
      phx-click="zone"
      phx-value-seat={@seat}
      phx-value-zone={@zone}
      class={["cx-zone cx-row", @sel && "cx-target"]}
    >
      <span class="cx-label cx-row-label">{label(@zone)}</span>
      <div class="cx-row-cards">
        <.mini
          :for={id <- @ids}
          c={@view.cards[id]}
          art={@art}
          selected={@sel && @sel.id == id}
          target={@tg && id in @tg}
          ui={@ui}
        />
      </div>
    </div>
    """
  end

  attr :seat, :integer, required: true
  attr :ids, :list, required: true
  attr :view, :map, required: true
  attr :art, :any, required: true
  attr :sel, :map, default: nil
  attr :tg, :any, default: nil
  attr :hidden?, :boolean, default: false
  attr :far, :boolean, default: false
  attr :dock, :boolean, default: false
  attr :ui, :map, default: %{chips: %{}, focus: nil, hover: nil, lit: MapSet.new()}

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
        @dock && "cx-a-hand cx-dock",
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
          target={@tg && id in @tg}
          style={fan_style(i, @mid, @far)}
          ui={@ui}
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

  # The command zone (heroes, buildings) and the piles as counter chips.
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
        seat: seat
      )

    ~H"""
    <div
      id={"cx-zone-#{@seat}-command"}
      data-drop
      data-list="true"
      data-seat={@seat}
      data-zone="command"
      phx-click="zone"
      phx-value-seat={@seat}
      phx-value-zone="command"
      data-empty={to_string(@command == [] and @buildings == [] and @side.pending == [])}
      class={["cx-zone cx-row cx-command", @sel && "cx-target"]}
    >
      <span class="cx-label cx-row-label">Command</span>
      <div class="cx-row-cards">
        <.mini
          :for={id <- @command}
          c={@view.cards[id]}
          art={@art}
          selected={@sel && @sel.id == id}
          target={@tg && id in @tg}
          ui={@ui}
        />
        <button
          :for={b <- @buildings}
          id={"cx-building-#{@seat}-#{b}"}
          type="button"
          phx-click={@tg && {:building, @seat, b} in @tg && "pick_building"}
          phx-value-seat={@seat}
          phx-value-name={b}
          class={[
            "cx-building",
            @tg && {:building, @seat, b} in @tg && "cx-targetable-pill cursor-pointer"
          ]}
          title={"#{building_label(b)}: #{building_hp_left(@side, b)} HP"}
        >
          <.icon name="hero-building-library-mini" class="size-4 opacity-70" />
          <span>{building_label(b)}</span>
          <span :if={Map.get(@side.building_damage, b, 0) > 0} class="text-red-700">
            −{Map.get(@side.building_damage, b)}
          </span>
        </button>
        <span
          :for={b <- @side.pending}
          id={"cx-pending-#{@seat}-#{b}"}
          class="cx-building cx-building-pending"
          title="Building: ready at the end of the turn"
        >
          {building_label(b)} …
        </span>
        <button
          :if={
            @view.free or (@view.active == @seat and Enum.any?(@actions, &match?({:build, _}, &1)))
          }
          id={"cx-build-#{@seat}"}
          type="button"
          phx-click="drawer"
          phx-value-seat={@seat}
          phx-value-zone="buildings"
          class="cx-chip cx-chip-btn"
        >
          <.icon name="hero-plus-mini" class="size-4" /> Build
        </button>
      </div>
    </div>
    <div class="cx-chips">
      <.pile
        id={"cx-codex-#{@seat}"}
        zone={:codex}
        seat={@seat}
        label="Codex"
        icon="hero-book-open-mini"
        count={length(@codex)}
        target?={@sel != nil}
      />
      <.pile
        id={"cx-deck-#{@seat}"}
        zone={:deck}
        seat={@seat}
        label="Deck"
        icon="hero-rectangle-stack-mini"
        count={@deck}
        target?={@sel != nil}
      />
      <.pile
        id={"cx-discard-#{@seat}"}
        zone={:discard}
        seat={@seat}
        label="Discard"
        icon="hero-arrow-down-tray-mini"
        count={length(@discard)}
        target?={@sel != nil}
      />
      <.pile
        id={"cx-workers-#{@seat}"}
        zone={:workers}
        seat={@seat}
        label="Workers"
        icon="hero-wrench-mini"
        count={length(@workers)}
        target?={@sel != nil}
      />
      <.pile
        :if={!@far}
        id="cx-trash"
        zone={:trash}
        label="Trash"
        icon="hero-trash-mini"
        count={length(@view.trash)}
        target?={@sel != nil and @view.free}
      />
      <button
        :if={@view.free}
        id={"cx-draw-#{@seat}"}
        type="button"
        phx-click="draw"
        phx-value-seat={@seat}
        class="cx-chip cx-chip-btn"
        title="Draw a card"
      >
        Draw
      </button>
      <button
        :if={@view.free}
        id={"cx-shuffle-#{@seat}"}
        type="button"
        phx-click="shuffle"
        phx-value-seat={@seat}
        phx-value-zone="deck"
        class="cx-chip cx-chip-btn"
        title="Shuffle the deck"
        aria-label="Shuffle the deck"
      >
        <.icon name="hero-arrows-right-left-mini" class="size-4" />
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :zone, :atom, required: true
  attr :seat, :any, default: nil
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :count, :integer, required: true
  attr :target?, :boolean, default: false

  # A pile as a counter chip: tap it to open it (or to move the selected card there).
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
      class={["cx-zone cx-chip", @target? && "cx-target"]}
      title={"#{@label}: #{@count}"}
      role="button"
      tabindex="0"
    >
      <span class="flex items-center gap-1">
        <.icon name={@icon} class="size-4 text-white/55" />
        <span class="cx-chip-count" id={"#{@id}-count"} data-bump>{@count}</span>
      </span>
      <span class="cx-chip-label">{@label}</span>
    </div>
    """
  end

  # -- a card ------------------------------------------------------------------------------

  attr :c, :map, required: true, doc: "a card instance from the view"
  attr :art, :any, required: true
  attr :selected, :any, default: false
  attr :target, :any, default: false, doc: "a legal target of the pick in progress"
  attr :ui, :map, default: %{chips: %{}, focus: nil, hover: nil, lit: MapSet.new()}

  # A card on the board: an art crop, the cost (or the hero level), the name and
  # the ATK/HP now; on a desktop its action chips (`chip_bar/1`). Colours: green above the printed value, violet below, red HP
  # when damaged. Exhausted: grey. A long press (or a hover) shows the full card.
  defp mini(assigns) do
    c = assigns.c
    d = Cards.fetch!(c.card)
    art? = MapSet.member?(assigns.art, c.card)
    back? = c.face_down

    assigns =
      assign(assigns,
        d: d,
        back?: back?,
        hero?: d.type == "Hero",
        img: art? && "/images/codex/#{c.card}.webp",
        zoom: !back? && art? && "/images/codex/zoom/#{c.card}.webp",
        st: !back? && mini_stats(c, d)
      )

    ~H"""
    <div
      id={"cx-card-#{@c.id}"}
      data-card-id={@c.id}
      data-zoom={@zoom}
      draggable="true"
      phx-click="select"
      phx-value-id={@c.id}
      title={@d.name}
      tabindex="0"
      role="button"
      aria-pressed={to_string(@selected == true)}
      aria-label={if(@back?, do: "A face-down card", else: @d.name)}
      class={[
        "cx-mc cursor-pointer",
        tone(@d),
        @c.exhausted && "cx-exhausted",
        @selected && "cx-selected",
        @target && "cx-targetable",
        @ui.focus == @c.id && "cx-focus",
        @ui.hover == @c.id && "cx-hover"
      ]}
    >
      <.chip_bar :if={@ui.chips[@c.id] not in [nil, []]} c={@c} chips={@ui.chips[@c.id]} />
      <div class="cx-mc-art">
        <%= cond do %>
          <% @back? -> %>
            <.back art={@art} />
          <% @img -> %>
            <img class="cx-mc-img" src={@img} alt="" loading="lazy" draggable="false" />
          <% true -> %>
            <div class="cx-mc-css"></div>
        <% end %>
      </div>
      <%= if !@back? do %>
        <span :if={@hero? and @c.level} class="cx-mc-lvl" title="level">
          <span class="text-[0.7em]">L</span>{@c.level}
        </span>
        <span :if={!@hero? and @d.cost} class="cx-mc-cost" title="cost">{@d.cost}</span>
        <span class="cx-mc-flags">
          <span :if={@c.exhausted} class="cx-mc-flag" title="exhausted">
            <.icon name="hero-arrow-path-mini" class="size-3" />
          </span>
          <span
            :if={Map.get(@c, :fatigued)}
            class="cx-mc-flag cx-mc-new"
            title="arrived this turn: cannot attack yet"
          >
            new
          </span>
          <span :if={@c.plus > 0} class="cx-mc-flag cx-mc-plus" title="+1/+1 runes">
            +{@c.plus}
          </span>
          <span :if={@c.minus > 0} class="cx-mc-flag cx-mc-minus" title="-1/-1 runes">
            −{@c.minus}
          </span>
        </span>
        <div class="cx-mc-foot">
          <span class="cx-mc-name">{@d.name}</span>
          <div :if={@st} class="cx-mc-stats">
            <span class="cx-mc-atk" data-tone={@st.atk_tone} title="ATK" data-bump>{@st.atk}</span>
            <span class="cx-mc-hp" data-tone={@st.hp_tone} title="HP left" data-bump>
              {@st.hp}
            </span>
          </div>
        </div>
      <% end %>
      <template :if={!@img and !@back?} class="cx-zoom-tpl">
        <div class="cx-card cx-preview-card"><.css_face d={@d} /></div>
      </template>
    </div>
    """
  end

  # ATK and HP left now, and how they differ from the printed values (a hero: its band).
  defp mini_stats(c, d) do
    {base_atk, base_hp} = printed_stats(c, d)

    case Map.get(c, :now) || (base_hp && {base_atk || 0, base_hp}) do
      {atk, hp} ->
        %{
          atk: atk,
          hp: hp - c.damage,
          atk_tone: tone_of(atk, base_atk || 0),
          hp_tone: hp_tone(c.damage, hp, base_hp || 0)
        }

      nil ->
        nil
    end
  end

  defp printed_stats(c, %{type: "Hero"} = d) do
    case Cards.band(c.card, c.level || 1) do
      %{atk: a, hp: h} -> {a, h}
      _ -> {d.atk, d.hp}
    end
  end

  defp printed_stats(_c, d), do: {d.atk, d.hp}

  defp hp_tone(damage, _hp, _base) when damage > 0, do: "hurt"
  defp hp_tone(_damage, hp, base), do: tone_of(hp, base)

  defp tone_of(now, base) when now > base, do: "up"
  defp tone_of(now, base) when now < base, do: "down"
  defp tone_of(_now, _base), do: nil

  attr :c, :map, required: true, doc: "a card instance from the view"
  attr :art, :any, required: true
  attr :selected, :any, default: false
  attr :target, :any, default: false, doc: "a legal target of the pick in progress"
  attr :hidden, :boolean, default: false, doc: "draw the back (the other side's hand)"
  attr :peek, :boolean, default: false, doc: "draw the face of a face-down card (a sheet)"
  attr :prefix, :string, default: "cx-card"
  attr :click, :boolean, default: true
  attr :style, :string, default: nil
  attr :ui, :map, default: %{chips: %{}, focus: nil, hover: nil, lit: MapSet.new()}

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
      tabindex={@click && !@hidden && "0"}
      role={@click && !@hidden && "button"}
      aria-pressed={@click && !@hidden && to_string(@selected == true)}
      class={[
        "cx-card",
        @c.exhausted && "cx-exhausted",
        @selected && "cx-selected",
        @target && "cx-targetable",
        @click && !@hidden && "cursor-pointer",
        @ui.focus == @c.id && "cx-focus",
        @ui.hover == @c.id && "cx-hover"
      ]}
    >
      <.chip_bar
        :if={@click && !@hidden && @ui.chips[@c.id] not in [nil, []]}
        c={@c}
        chips={@ui.chips[@c.id]}
      />
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
        <span
          :if={Map.get(@c, :fatigued) && !@c.face_down}
          class="cx-tok cx-new"
          title="arrived this turn: cannot attack yet"
        >
          new
        </span>
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
  # ATK/HP now (from the view), when it differs from the printed values.
  defp stats(%{now: {atk, hp}}, d) do
    if {atk, hp} != {d.atk, d.hp}, do: "#{atk}/#{hp}"
  end

  defp stats(_c, _d), do: nil

  # -- the inspector (the selected card) ------------------------------------------------------
  #
  # A phone: a bottom sheet over the hand. Its peek (about 120 px) has a thumbnail,
  # the name, the ATK/HP and up to 3 actions; the handle, the thumbnail or "More"
  # expand it to the full card and all actions. The board scrolls so the selected
  # card stays in sight above the sheet (`.KeepInView`). A desktop: all of it in
  # the right column.

  attr :card, :map, required: true
  attr :where, :string, required: true
  attr :art, :any, required: true

  attr :free, :boolean, default: false
  attr :buttons, :list, default: []
  attr :pick, :map, default: nil
  attr :targeting, :map, default: nil
  attr :stats, :any, default: nil
  attr :view, :map, default: nil
  attr :expanded, :boolean, default: false

  defp inspector(assigns) do
    c = assigns.card

    d = Cards.fetch!(c.card)
    max = Cards.max_level(c.card)
    acts = if assigns.free, do: free_buttons(c), else: rule_buttons(assigns.buttons)

    assigns =
      assign(assigns,
        d: d,
        max: max,
        zoom?: MapSet.member?(assigns.art, c.card),
        acts: Enum.with_index(acts),
        more?: assigns.free or length(acts) > 3
      )

    ~H"""
    <div
      id="cx-actions"
      phx-hook=".KeepInView"
      data-sel={@card.id}
      data-expanded={to_string(@expanded)}
      class="cx-inspector flex flex-col gap-2 bg-stone-950/95 p-3 shadow-2xl ring-1 ring-white/15 backdrop-blur max-lg:rounded-t-2xl max-lg:px-3 max-lg:pt-1 max-lg:pb-2.5 lg:rounded-2xl lg:bg-black/35"
    >
      <button
        id="cx-sheet-handle"
        type="button"
        phx-click="expand"
        aria-expanded={to_string(@expanded)}
        aria-label={if @expanded, do: "Show less", else: "Show the full card and all actions"}
        class="cx-handle cx-hit lg:hidden"
      >
        <span></span>
      </button>
      <div class="cx-insp-big justify-center">
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
      <div class="flex items-start gap-2.5">
        <button
          id="cx-sheet-thumb"
          type="button"
          phx-click="expand"
          class="cx-insp-thumb lg:hidden"
          aria-label="Show the full card"
        >
          <.card c={@card} art={@art} prefix="cx-thumb" click={false} peek />
        </button>
        <div class="flex min-w-0 flex-1 flex-col gap-1.5">
          <div class="flex items-start gap-2">
            <div class="min-w-0 flex-1">
              <p id="cx-actions-name" class="truncate text-sm font-bold">{@d.name}</p>
              <p class="truncate text-xs text-white/60">
                {@where}<span :if={@stats} id="cx-actions-stats"> · ATK {elem(@stats, 0)} · HP {elem(
                  @stats,
                  1
                ) - @card.damage}/{elem(
                  @stats,
                  1
                )}</span><span :if={@card.level}> · level {@card.level}</span>
              </p>
            </div>
            <button
              id="cx-act-close"
              type="button"
              phx-click="deselect"
              class="cx-icon-btn -mt-1 -mr-1 bg-white/10!"
              aria-label="Deselect"
            >
              <.icon name="hero-x-mark-mini" class="size-4" />
            </button>
          </div>
          <p :if={@targeting} class="py-1 text-xs font-semibold text-amber-100">
            {pick_text(@targeting, @pick)}
          </p>
          <div :if={!@targeting} class="flex flex-wrap gap-1.5">
            <button
              :for={{b, i} <- @acts}
              id={b.id}
              type="button"
              class={["cx-act", b.class, i >= 3 && "cx-extra"]}
              {b.attrs}
            >
              <.icon :if={b.icon} name={b.icon} class="size-4" />
              {b.label}
            </button>
            <button
              :if={@more? and !@expanded}
              id="cx-sheet-more"
              type="button"
              phx-click="expand"
              class="cx-act lg:hidden"
            >
              More <.icon name="hero-chevron-up-mini" class="size-4" />
            </button>
            <p :if={@acts == []} class="py-1 text-xs text-white/50">
              No action for this card now.
            </p>
          </div>
        </div>
      </div>
      <div
        :if={@free and !@targeting}
        class="cx-extra grid grid-cols-2 gap-1.5 sm:grid-cols-4 lg:grid-cols-1"
      >
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
          label={"Level ≤#{@max}"}
          key="level"
          value={@card.level}
          tone="bg-amber-500"
        />
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".KeepInView">
        export default {
          mounted() { this.keep() },
          updated() { if (this.el.dataset.sel !== this.last) this.keep() },
          keep() {
            this.last = this.el.dataset.sel
            if (window.matchMedia("(min-width: 1024px)").matches) return
            const card = document.getElementById("cx-card-" + this.last)
            if (!card) return
            const smooth = !window.matchMedia("(prefers-reduced-motion: reduce)").matches
            requestAnimationFrame(() =>
              card.scrollIntoView({block: "nearest", inline: "nearest", behavior: smooth ? "smooth" : "auto"})
            )
          }
        }
      </script>
    </div>
    """
  end

  # The action buttons of the selected card: `%{id, label, icon, class, attrs}`.
  defp rule_buttons(buttons) do
    for b <- buttons do
      %{
        id: "cx-rule-#{b.key}",
        label: b.label,
        icon: nil,
        class: "cx-act-rule",
        attrs: [{"phx-click", "rule"}, {"phx-value-key", b.key}]
      }
    end
  end

  defp free_buttons(c) do
    to = fn id, label, zone, class ->
      %{
        id: id,
        label: label,
        icon: nil,
        class: class,
        attrs: [{"phx-click", "card"}, {"phx-value-op", "to"}, {"phx-value-zone", zone}]
      }
    end

    [
      %{
        id: "cx-act-exhaust",
        label: if(c.exhausted, do: "Ready", else: "Exhaust"),
        icon: "hero-arrow-path-rounded-square-mini",
        class: nil,
        attrs: [{"phx-click", "card"}, {"phx-value-op", "exhaust"}]
      },
      to.("cx-act-play", "To play", "in_play", nil),
      to.("cx-act-hand", "To hand", "hand", nil),
      to.("cx-act-discard", "Discard", "discard", nil),
      %{
        id: "cx-act-flip",
        label: if(c.face_down, do: "Face up", else: "Face down"),
        icon: "hero-arrows-up-down-mini",
        class: nil,
        attrs: [{"phx-click", "card"}, {"phx-value-op", "flip"}]
      },
      to.("cx-act-trash", "Trash", "trash", "cx-act-danger")
    ]
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
          class="grid size-11 place-items-center rounded-full bg-white/10 transition hover:bg-white/20 active:scale-90 lg:size-8"
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
          class="grid size-11 place-items-center rounded-full bg-white/10 transition hover:bg-white/20 active:scale-90 lg:size-8"
          aria-label={"#{@label} +1"}
        >
          <.icon name="hero-plus-mini" class="size-3.5" />
        </button>
      </div>
    </div>
    """
  end

  # The text of a pick value on its button.
  defp value_label(v, id) when is_integer(id), do: name(v, id)
  defp value_label(_v, {:building, s, b}), do: "P#{s + 1}'s #{target_text(b)}"
  defp value_label(_v, {:worker, s}), do: "A worker of P#{s + 1}"
  defp value_label(_v, :boost), do: "Boost"
  defp value_label(_v, :plain), do: "No boost"
  defp value_label(_v, :beast), do: "A 4/4 Beast"
  defp value_label(_v, :frogs), do: "Four 1/1 Frogs"

  defp value_label(_v, atom) when is_atom(atom),
    do: atom |> to_string() |> String.replace("_", " ")

  # A target pick in progress: a banner in place of the status bar (a desktop: a
  # pill that floats over it). The legal targets glow, the rest of the table dims;
  # each target also has a button here.
  attr :targeting, :map, required: true
  attr :pick, :map, required: true
  attr :view, :map, required: true

  defp pick_banner(assigns) do
    {_kind, id, _name} = assigns.targeting.key

    assigns =
      assign(assigns,
        who: name(assigns.view, id),
        choices: for({v, i} <- Enum.with_index(assigns.pick.values), v != nil, do: {v, i})
      )

    ~H"""
    <div id="cx-pick" class="cx-a-status cx-banner cx-float-lg" role="status">
      <div class="flex items-center gap-2">
        <span class="grid size-9 shrink-0 place-items-center rounded-full bg-amber-300 text-stone-900">
          <.icon
            name={
              if match?({:attack, _, _}, @targeting.key),
                do: "hero-bolt-solid",
                else: "hero-cursor-arrow-rays-solid"
            }
            class="size-5"
          />
        </span>
        <p class="min-w-0 flex-1 text-sm leading-tight">
          <span class="block truncate font-bold text-amber-100">{@who}</span>
          <span class="block truncate text-xs text-white/80">{pick_text(@targeting, @pick)}</span>
        </p>
        <button
          :if={nil in @pick.values}
          id="cx-pick-skip"
          type="button"
          phx-click="skip_target"
          class="cx-act cx-pick-ctl"
        >
          Skip
        </button>
        <button
          :if={@pick.complete && @pick.values != []}
          id="cx-pick-done"
          type="button"
          phx-click="pick_done"
          class="cx-act cx-act-rule cx-pick-ctl"
        >
          Done
        </button>
        <button
          id="cx-pick-cancel"
          type="button"
          phx-click="cancel_target"
          class="cx-act cx-pick-ctl"
          title="Cancel (Esc)"
        >
          Cancel
        </button>
      </div>
      <div :if={@choices != []} class="cx-banner-choices">
        <button
          :for={{v, i} <- @choices}
          id={"cx-pick-#{i}"}
          type="button"
          phx-click="pick_index"
          phx-value-i={i}
          class="cx-act cx-act-rule shrink-0"
        >
          {value_label(@view, v)}
        </button>
      </div>
    </div>
    """
  end

  defp pick_text(%{key: {:attack, _, _}}, _pick), do: "Attacks: tap a glowing target."
  defp pick_text(%{key: {_, _, _}, picked: []}, _pick), do: "Tap a glowing target."
  defp pick_text(%{picked: picked}, _pick), do: "Tap target #{length(picked) + 1}."

  attr :free, :boolean, default: false

  defp inspector_help(assigns) do
    ~H"""
    <div
      :if={!@free}
      class="hidden rounded-2xl bg-black/25 p-3 text-xs leading-relaxed text-white/70 ring-1 ring-white/10 lg:block"
    >
      <p class="mb-1 font-semibold text-white">How to play</p>
      <p>
        Point at a card: its action buttons show on it (attack, level up, patrol, play,
        hire). One click acts; with more than one target, click a glowing target next.
        Keys: Tab to a card, then A attack, L level up, P patrol, Enter select, Esc
        cancel. Drag a card from your hand to In play to play it, to Workers to hire
        it. Hover a card to see it large. Free mode lets you fix anything by hand.
      </p>
    </div>
    <div
      :if={@free}
      class="hidden rounded-2xl bg-black/25 p-3 text-xs leading-relaxed text-white/70 ring-1 ring-white/10 lg:block"
    >
      <p class="mb-1 font-semibold text-white">Free mode</p>
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

  defp log_text({:setup, _seed}, v) do
    specs = for s <- [0, 1], do: Enum.join(Map.get(v.sides[s], :specs, [v.sides[s].spec]), ", ")
    "New game: P1 #{Enum.at(specs, 0)}, P2 #{Enum.at(specs, 1)}."
  end

  defp log_text({:reshuffle, s}, _v), do: "P#{s + 1} shuffles the discard pile into the deck."
  defp log_text({:action, s, :end_turn}, _v), do: "P#{s + 1} ends the turn."
  defp log_text({:action, s, action}, v), do: action_text(s, action, v)
  defp log_text({:dies, id}, v), do: "#{name(v, id)} dies."
  defp log_text({:free_levels, id}, v), do: "#{name(v, id)} gets 2 free levels."
  defp log_text({:dancer, s}, _v), do: "P#{s + 1} gets a Dancer token."
  defp log_text({:destroyed, s, b}, _v), do: "P#{s + 1}'s #{target_text(b)} is destroyed."
  defp log_text({:sacrificed, id}, v), do: "#{name(v, id)} is sacrificed."
  defp log_text({:summon, s, slug, n}, _v), do: "P#{s + 1} gets #{n} #{Cards.fetch!(slug).name}."
  defp log_text({:manual, id}, v), do: "#{name(v, id)}: manual. Resolve its text in free mode."
  defp log_text({:returns, id}, v), do: "#{name(v, id)} goes back to the hand."
  defp log_text({:trashed, id}, v), do: "#{name(v, id)} is trashed."
  defp log_text({:worker_trashed, s}, _v), do: "A worker of P#{s + 1} is trashed."

  defp log_text({:legendary, id}, v),
    do: "#{name(v, id)} is legendary: the second copy is discarded."

  defp log_text({:destroyed_card, id}, v), do: "#{name(v, id)} is destroyed."
  defp log_text({:coin, :heads}, _v), do: "The coin: heads. Phew!"
  defp log_text({:coin, :tails}, _v), do: "The coin: tails."
  defp log_text(other, _v), do: inspect(other)

  defp action_text(s, {:hire, _id}, _v), do: "P#{s + 1} hires a worker."
  defp action_text(s, {:play, id, []}, v), do: "P#{s + 1} plays #{name(v, id)}."

  defp action_text(s, {:play, id, targets}, v),
    do: "P#{s + 1} plays #{name(v, id)} on #{Enum.map_join(targets, ", ", &target_name(v, &1))}."

  defp action_text(_s, {:patrol, id, slot}, v),
    do: "#{name(v, id)} patrols as #{elem(@slot_labels[slot], 0)}."

  defp action_text(_s, {:sideline, id}, v), do: "#{name(v, id)} leaves the patrol zone."
  defp action_text(s, {:summon, id}, v), do: "P#{s + 1} summons #{name(v, id)}."
  defp action_text(_s, {:level_up, id}, v), do: "#{name(v, id)} levels up."

  defp action_text(_s, {:ability, id, name, targets}, v),
    do:
      "#{name(v, id)}: #{Moves.ability_label(name)}" <>
        if(targets == [],
          do: ".",
          else: " (#{Enum.map_join(targets, ", ", &target_name(v, &1))})."
        )

  defp action_text(s, {:build, b}, _v), do: "P#{s + 1} builds #{target_text(b)}."
  defp action_text(s, {:build, :tech_2, spec}, _v), do: "P#{s + 1} builds Tech II (#{spec})."
  defp action_text(s, {:tech, ids}, _v), do: "P#{s + 1} techs #{length(ids)} codex cards."
  defp action_text(_s, {:attack, a, t}, v), do: "#{name(v, a)} attacks #{target_name(v, t)}."
  defp action_text(_s, {:free_mode, on}, _v), do: "Free mode #{if on, do: "on", else: "off"}."
  defp action_text(_s, action, v), do: action_text(action, v)

  defp target_name(_v, nil), do: "nothing"
  defp target_name(_v, {:building, s, b}), do: "P#{s + 1}'s #{target_text(b)}"
  defp target_name(_v, {:worker, s}), do: "a worker of P#{s + 1}"
  defp target_name(_v, atom) when is_atom(atom), do: to_string(atom)
  defp target_name(v, id), do: name(v, id)

  defp target_text(:base), do: "base"
  defp target_text(b), do: Map.get(@building_labels, b, to_string(b))

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

  attr :actions, :list, default: []
  attr :tech_pick, :list, default: []

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
            :if={@view.free and match?({_, z} when z in [:discard, :codex], @drawer)}
            id="cx-drawer-shuffle"
            type="button"
            phx-click="shuffle"
            phx-value-seat={elem(@drawer, 0)}
            phx-value-zone={elem(@drawer, 1)}
            class="cx-mini min-h-11 px-3"
          >
            Shuffle
          </button>
          <button
            id="cx-drawer-close"
            type="button"
            phx-click="close_drawer"
            class="cx-icon-btn ml-auto bg-white/10!"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-5" />
          </button>
        </div>
        <%= case @drawer do %>
          <% :log -> %>
            <.log_list view={@view} id="cx-drawer-log" class="flex" />
          <% {seat, :buildings} -> %>
            <.buildings
              :if={@view.free}
              seat={seat}
              built={@view.sides[seat].tech_buildings}
            />
            <.build_list :if={!@view.free} seat={seat} view={@view} actions={@actions} />
          <% {seat, :tech} -> %>
            <.tech_sheet seat={seat} view={@view} art={@art} actions={@actions} pick={@tech_pick} />
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
          "min-h-11 rounded-xl px-3 py-2.5 text-sm font-semibold ring-1 transition active:scale-[0.98]",
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

  attr :seat, :integer, required: true
  attr :view, :map, required: true
  attr :actions, :list, required: true

  defp build_list(assigns) do
    side = assigns.view.sides[assigns.seat]

    rows =
      for b <- [:tech_1, :tech_2, :tech_3, :tower, :surplus, :heroes_hall],
          b != :heroes_hall or length(Map.get(side, :specs, [])) > 1 do
        state = build_state(side, assigns.actions, b)
        {b, state}
      end

    tech2 = for {:build, :tech_2, spec} <- assigns.actions, do: spec
    assigns = assign(assigns, rows: rows, tech2: tech2)

    ~H"""
    <p :if={@tech2 != []} class="text-xs font-semibold text-amber-100">
      Tech II: pick its spec. Tech II and III then make only that spec's cards.
    </p>
    <div :if={@tech2 != []} class="flex flex-wrap gap-2">
      <button
        :for={spec <- @tech2}
        id={"cx-build-tech_2-#{spec}"}
        type="button"
        phx-click="build"
        phx-value-building="tech_2"
        phx-value-spec={spec}
        class="min-h-11 rounded-xl bg-amber-300 px-3 py-2 text-sm font-semibold text-stone-900 ring-1 ring-amber-200 transition hover:bg-amber-200 active:scale-[0.98]"
      >
        Tech II · {spec}
      </button>
    </div>
    <p class="text-xs text-white/60">
      Tech I: 6 workers, 1 gold. Tech II: 8 workers, tech I, 4 gold. Tech III: 10
      workers, tech II, 5 gold. One add-on: Tower (3 gold) or Surplus (5 gold). A
      building finishes at the end of your turn.
    </p>
    <div class="grid grid-cols-2 gap-2 sm:grid-cols-5">
      <button
        :for={{b, state} <- @rows}
        id={"cx-build-#{b}"}
        type="button"
        phx-click={state == :can && "build"}
        phx-value-building={b}
        disabled={state != :can}
        class={[
          "flex min-h-11 flex-col items-start rounded-xl px-3 py-2.5 text-left text-sm font-semibold ring-1 transition active:scale-[0.98]",
          state == :can && "bg-amber-300 text-stone-900 ring-amber-200 hover:bg-amber-200",
          state in [:built, :pending] && "bg-emerald-800/60 text-white ring-emerald-500/40",
          state in [:no, :spec] && "bg-white/5 text-white/40 ring-white/10"
        ]}
      >
        {building_label(b)}
        <span class="text-[11px] font-normal opacity-80">{build_state_text(state)}</span>
      </button>
    </div>
    """
  end

  defp building_hp_left(side, b),
    do: Codex.Effects.building_hp(b) - Map.get(side.building_damage, b, 0)

  defp build_state(side, actions, b) do
    cond do
      b in side.tech_buildings -> :built
      b in side.pending -> :pending
      {:build, b} in actions -> :can
      b == :tech_2 and Enum.any?(actions, &match?({:build, :tech_2, _}, &1)) -> :spec
      true -> :no
    end
  end

  defp build_state_text(:built), do: "built"
  defp build_state_text(:pending), do: "building: ready next turn"
  defp build_state_text(:can), do: "build"
  defp build_state_text(:no), do: "not yet"
  defp build_state_text(:spec), do: "pick a spec above"

  attr :seat, :integer, required: true
  attr :view, :map, required: true
  attr :art, :any, required: true
  attr :actions, :list, required: true
  attr :pick, :list, required: true

  defp tech_sheet(assigns) do
    v = assigns.view
    codex = v.sides[assigns.seat].zones.codex

    groups =
      codex |> Enum.group_by(&v.cards[&1].card) |> Enum.sort_by(fn {_slug, [id | _]} -> id end)

    assigns =
      assign(assigns,
        groups: groups,
        done: tech_action(assigns.actions, v, assigns.pick),
        none?: {:tech, []} in assigns.actions
      )

    ~H"""
    <p class="text-xs text-white/70">
      Pick 2 cards from your codex (2 copies of one card, or 1 each of two cards). They
      go face down into your discard pile.
      <span :if={@none?}>With 10 workers you may pick fewer.</span>
    </p>
    <div class="cx-sheet-grid -mx-1 overflow-y-auto px-1 pt-1 pb-2">
      <button
        :for={{slug, [id | _] = ids} <- @groups}
        id={"cx-tech-#{slug}"}
        type="button"
        phx-click="tech_pick"
        phx-value-slug={slug}
        class="relative"
        aria-pressed={to_string(slug in @pick)}
      >
        <.card
          c={@view.cards[id]}
          art={@art}
          prefix="cx-tech-card"
          click={false}
          selected={slug in @pick}
        />
        <span class="cx-count">×{length(ids)}</span>
        <span
          :if={slug in @pick}
          class="absolute -top-1 -left-1 z-10 rounded-full bg-amber-300 px-1.5 text-xs font-black text-stone-900 shadow"
        >
          {Enum.count(@pick, &(&1 == slug))}
        </span>
      </button>
    </div>
    <div class="flex items-center gap-2">
      <p class="text-sm text-white/70">Picked {length(@pick)} of 2.</p>
      <button
        id="cx-tech-done"
        type="button"
        phx-click="tech_done"
        disabled={@done == nil}
        class="ml-auto min-h-11 rounded-full bg-amber-300 px-5 text-sm font-bold text-stone-900 shadow transition hover:bg-amber-200 active:scale-95 disabled:opacity-40"
      >
        {if @pick == [], do: "Pick none", else: "Add to my discard pile"}
      </button>
    </div>
    """
  end

  defp drawer_title({s, :tech}), do: "P#{s + 1}: tech"

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
    dir = CodexArt.dir() || Application.app_dir(:quacks, @art_dir)

    case File.ls(dir) do
      {:ok, files} ->
        for f <- files, String.ends_with?(f, ".webp"), into: MapSet.new(), do: Path.rootname(f)

      {:error, _} ->
        MapSet.new()
    end
  end
end
