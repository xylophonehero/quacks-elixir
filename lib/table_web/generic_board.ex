defmodule TableWeb.GenericBoard do
  @moduledoc """
  The board of a generic card game (`Table.Generic.Game`) on the table page
  (`TableWeb.TableLive`, a `TableWeb.Board`). It draws any zones view with the
  card components of `TableWeb.Components.Cards`:

  - your `hand` zones as a fan (tap a lit card to play it); the other seats'
    hidden zones as backs, their open zones as cards;
  - the shared `pile` zones as the top card (or a face-down stack), `row` zones
    as every card;
  - the counters on the seat labels and in a strip over the middle;
  - the prompt (`pending`) as a line and one button per choice.

  ## Motion

  A card keeps its DOM id (`"gt-card-QS"`) in every zone, so `TableMotion`
  slides it from one place to the next. A card that comes out of a zone you
  cannot see (another hand, the deck) flies in from that zone (`data-from`);
  the new backs of another hand fly in from where their cards came from.
  The motion comes from the log entries between the old view and the new one.
  """
  @behaviour TableWeb.Board

  use QuacksWeb, :html

  alias Table.Generic.Spec
  alias Table.Kit.PlayingCards
  alias TableWeb.Components.{Cards, Theme}

  @scope "gt"
  @suits %{"clubs" => "♣", "diamonds" => "♦", "hearts" => "♥", "spades" => "♠"}

  # -- TableWeb.Board ---------------------------------------------------------------

  @impl true
  def init(socket), do: Phoenix.Component.assign(socket, motion: %{}, over_open: true)

  @impl true
  def put_view(socket, env, old) do
    v = env.view
    me = if env.seat == :spectator, do: 0, else: env.seat
    motion = if old && length(old.view.log) <= length(v.log), do: motion(old.view, v), else: %{}

    Phoenix.Component.assign(socket,
      view: v,
      actions: env.actions,
      me: me,
      you: if(env.seat == :spectator, do: nil, else: me),
      motion: motion,
      over_open: v.result != nil
    )
  end

  @impl true
  def handle_event("play", %{"card" => card}, socket) do
    case Enum.find(socket.assigns.actions, &match?({:play, _, ^card}, &1)) do
      nil -> {:noreply, socket}
      action -> {:act, action, socket}
    end
  end

  def handle_event("choose", %{"label" => label}, socket) do
    if {:choose, label} in socket.assigns.actions,
      do: {:act, {:choose, label}, socket},
      else: {:noreply, socket}
  end

  def handle_event("over", %{"open" => open}, socket),
    do: {:noreply, Phoenix.Component.assign(socket, over_open: open == "true")}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # -- motion -----------------------------------------------------------------------

  # The new log entries, oldest first, as `{cards | count, from, to}` moves.
  defp moves(old, new) do
    new.log
    |> Enum.take(length(new.log) - length(old.log))
    |> Enum.reverse()
    |> Enum.flat_map(fn
      {:op, {:move, _ref, from, to}, %{cards: cards}} ->
        [{cards, from, to}]

      {:op, {:deal, _, from, _}, %{dealt: dealt}} ->
        for {to, cards, _} <- dealt, do: {cards, from, to}

      _ ->
        []
    end)
  end

  @doc false
  # `%{cards: %{card => m}, backs: %{zone => %{k => m}}}` (`Cards` motion maps).
  def motion(old, new) do
    moves = moves(old, new)

    cards =
      for {cards, from, _to} <- moves,
          is_list(cards),
          not visible?(new.zones[from]),
          {c, i} <- Enum.with_index(cards),
          into: %{},
          do: {c, %{from: dom(from), delay: i * 60}}

    backs =
      moves
      |> Enum.group_by(&elem(&1, 2), &elem(&1, 1))
      |> Enum.flat_map(fn {to, froms} ->
        z = new.zones[to]
        was = old.zones[to]

        if z && was && not visible?(z) && length(z.items) > length(was.items) do
          from = List.last(froms)
          ks = length(was.items)..(length(z.items) - 1)
          [{to, Map.new(ks, &{&1, %{from: dom(from), delay: (&1 - length(was.items)) * 60}})}]
        else
          []
        end
      end)
      |> Map.new()

    %{cards: cards, backs: backs}
  end

  defp visible?(nil), do: false
  defp visible?(zone), do: zone.items == [] or hd(zone.items) != :hidden

  @doc "The DOM id of a zone."
  @spec dom(String.t()) :: String.t()
  def dom(zone), do: "#{@scope}-z-" <> String.replace(zone, ":", "-")

  # -- the page -----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full>
      <.page {assigns} />
    </Layouts.app>
    """
  end

  @doc "The page without the layout (also the gallery's story)."
  def page(assigns) do
    v = assigns.view
    n = length(v.seats)
    others = for k <- 1..(n - 1)//1, do: rem(assigns.me + k, n)

    assigns =
      assign(assigns,
        others: others,
        shared: for(z <- v.layout, z.seat == nil, do: z),
        global: for(c <- v.counter_specs, !c.per_seat, c.show, do: c),
        acting: v.pending && v.pending.seat,
        open_seats: for({s, %{open: true}} <- assigns.seats, do: s)
      )

    ~H"""
    <Theme.root
      id="generic-root"
      remember
      class="min-h-dvh bg-tb-base-200 text-tb-base-content"
      data-spec={@view.name}
    >
      <div class="mx-auto flex max-w-3xl flex-col gap-2 px-2 pt-2 pb-4 sm:gap-3 sm:px-4 sm:pt-4">
        <header class="flex items-center gap-2">
          <.link
            navigate={~p"/games"}
            class="grid size-9 shrink-0 place-items-center rounded-full bg-tb-base-100 ring-1 ring-tb-base-content/10 transition hover:bg-tb-base-300 active:scale-95"
            aria-label="Games"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </.link>
          <h1 class="truncate text-lg font-bold">{@view.title}</h1>
          <span
            id="generic-code"
            class="rounded-full bg-tb-base-100 px-2 py-0.5 font-mono text-xs tracking-widest ring-1 ring-tb-base-content/10"
            title="room code"
          >
            {@code}
          </span>
          <button
            :if={@view.result}
            id="generic-scores-open"
            type="button"
            phx-click="over"
            phx-value-open="true"
            class="ml-auto shrink-0 rounded-full bg-tb-base-100 px-3 py-1 text-xs font-semibold ring-1 ring-tb-base-content/10 transition hover:bg-tb-base-300 active:scale-95"
          >
            Scores
          </button>
        </header>

        <div
          id={"#{scope()}"}
          class="tb-table tb-felt relative overflow-hidden rounded-tb"
          phx-hook="TableMotion"
          data-role="generic-table"
        >
          <div id={"#{scope()}-fx"} phx-update="ignore" class="pointer-events-none absolute inset-0">
          </div>
          <div class="flex flex-col gap-3 p-2 sm:gap-4 sm:p-4">
            <div id="generic-others" class="flex flex-wrap items-start justify-center gap-2 sm:gap-4">
              <.seat_panel
                :for={s <- @others}
                seat={s}
                view={@view}
                seats={@seats}
                me={@you}
                acting={@acting}
                motion={@motion}
              />
            </div>

            <div
              :if={@global != []}
              id="generic-counters"
              class="flex flex-wrap justify-center gap-1.5"
            >
              <span
                :for={c <- @global}
                class="rounded-full bg-tb-base-100/90 px-2.5 py-0.5 text-xs font-semibold shadow-sm ring-1 ring-black/10"
                data-counter={c.id}
              >
                {c.label}: {counter_text(@view.counters[c.id])}
              </span>
            </div>

            <div
              id="generic-shared"
              class="flex min-h-[7rem] flex-wrap items-end justify-center gap-4 sm:gap-8"
            >
              <.zone_box
                :for={z <- @shared}
                zone={z}
                items={@view.zones[z.id].items}
                names={@view.names}
                actions={@actions}
                motion={@motion}
                mine={false}
              />
            </div>

            <div class="flex flex-col items-center gap-1">
              <div class="flex w-full items-center justify-between gap-2 px-1">
                <.seat_label seat={@me} view={@view} seats={@seats} me={@you} acting={@acting} />
                <p
                  class="min-w-0 truncate text-right text-xs font-medium text-tb-felt-ink/80 sm:text-sm"
                  id="generic-last"
                >
                  {last_action(@view, @seats, @you)}
                </p>
              </div>
              <.zone_box
                :for={z <- @view.layout}
                :if={z.seat == @me}
                zone={z}
                items={@view.zones[z.id].items}
                names={@view.names}
                actions={@actions}
                motion={@motion}
                mine={true}
              />
            </div>
          </div>
        </div>

        <.prompt_bar view={@view} actions={@actions} seats={@seats} me={@you} seat={@seat} />

        <div
          :if={@open_seats != []}
          id="generic-invite"
          class="rounded-tb bg-tb-base-100 px-3 py-2 text-sm ring-1 ring-tb-base-content/10"
        >
          {if length(@open_seats) == 1,
            do: "1 seat is open.",
            else: "#{length(@open_seats)} seats are open."} Share this link, or the code <strong class="font-mono tracking-widest">{@code}</strong>:
          <span class="block truncate font-mono text-xs select-all">
            {url(~p"/games/#{@key}/#{@code}")}
          </span>
        </div>

        <details class="group rounded-tb bg-tb-base-100 px-3 py-2 ring-1 ring-tb-base-content/10">
          <summary class="cursor-pointer text-sm font-medium select-none">Table colours</summary>
          <Theme.picker id="generic-picker" class="pt-2" />
        </details>
      </div>

      <.over_dialog
        :if={@view.result && @over_open}
        view={@view}
        seats={@seats}
        me={@you}
      />
    </Theme.root>
    """
  end

  defp scope, do: @scope

  # -- seats ----------------------------------------------------------------------------

  attr :seat, :integer, required: true
  attr :view, :map, required: true
  attr :seats, :map, required: true
  attr :me, :any, required: true
  attr :acting, :any, default: nil
  attr :motion, :map, default: %{}

  defp seat_panel(assigns) do
    ~H"""
    <div
      class="flex min-w-[5.5rem] flex-col items-center gap-1"
      data-role="seat-panel"
      data-seat={@seat}
    >
      <.seat_label seat={@seat} view={@view} seats={@seats} me={@me} acting={@acting} />
      <.zone_box
        :for={z <- @view.layout}
        :if={z.seat == @seat}
        zone={z}
        items={@view.zones[z.id].items}
        names={@view.names}
        actions={[]}
        motion={@motion}
        mine={false}
        small
      />
    </div>
    """
  end

  attr :seat, :integer, required: true
  attr :view, :map, required: true
  attr :seats, :map, required: true
  attr :me, :any, required: true
  attr :acting, :any, default: nil

  defp seat_label(assigns) do
    assigns =
      assign(assigns,
        counters:
          for(
            c <- assigns.view.counter_specs,
            c.per_seat,
            c.show,
            do: {c.label, assigns.view.counters["#{c.id}:#{assigns.seat}"]}
          )
      )

    ~H"""
    <div
      id={"#{scope()}-seat-#{@seat}"}
      class={[
        "flex max-w-full items-center gap-2 rounded-tb bg-tb-base-100/90 px-2 py-0.5 text-tb-base-content shadow-sm ring-1 ring-black/10 transition",
        @acting == @seat && "ring-2 ring-tb-accent"
      ]}
      data-role="seat"
      data-turn={to_string(@acting == @seat)}
    >
      <span class="max-w-[9rem] truncate text-xs font-semibold sm:text-sm">
        {seat_name(@seats, @seat, @me)}
      </span>
      <span
        :for={{label, value} <- @counters}
        class="text-xs font-bold tabular-nums"
        title={label}
      >
        {value}
      </span>
    </div>
    """
  end

  # `you`: your seat, or nil when you watch.
  defp seat_name(_seats, you, you), do: "You"
  defp seat_name(seats, s, _you), do: get_in(seats, [s, :name]) || "Player #{s + 1}"

  # -- zones ----------------------------------------------------------------------------

  attr :zone, :map, required: true
  attr :items, :list, required: true
  attr :names, :map, required: true
  attr :actions, :list, default: []
  attr :motion, :map, default: %{}
  attr :mine, :boolean, default: false
  attr :small, :boolean, default: false

  defp zone_box(assigns) do
    items = assigns.items
    hidden? = items != [] and hd(items) == :hidden
    standard? = Enum.all?(items, &(&1 == :hidden or Spec.standard(&1) != nil))
    legal = for {:play, z, c} <- assigns.actions, z == assigns.zone.id, do: c

    assigns =
      assign(assigns,
        dom: dom(assigns.zone.id),
        hidden: hidden?,
        standard: standard?,
        legal: legal,
        count: length(items)
      )

    ~H"""
    <%= cond do %>
      <% @zone.layout == :hand and @mine and not @hidden and @standard -> %>
        <Cards.hand
          id={@dom}
          scope={scope()}
          cards={Enum.map(@items, &Spec.standard/1) |> sort_hand()}
          legal={Enum.map(@legal, &Spec.standard/1)}
          on_tap={@legal != [] && "play"}
          motion={card_motion(@motion)}
          class="mt-1"
        />
      <% @hidden and @zone.layout == :pile -> %>
        <.zone_frame zone={@zone} count={@count}>
          <Cards.deck id={@dom} count={@count} />
        </.zone_frame>
      <% @hidden -> %>
        <Cards.backs
          id={@dom}
          count={@count}
          motion={get_in(@motion, [:backs, @zone.id]) || %{}}
        />
      <% @zone.layout == :pile -> %>
        <.zone_frame zone={@zone} count={@count}>
          <div
            id={@dom}
            class="relative aspect-[5/7] w-(--card-w) rounded-[calc(var(--card-w)*0.072)]"
            style="--card-w: clamp(3rem, 13cqi, 4.5rem)"
            data-anchor
            data-count={@count}
          >
            <span
              :if={@count == 0}
              class="absolute inset-0 rounded-[inherit] outline-2 outline-dashed -outline-offset-2 outline-tb-felt-ink/25"
            ></span>
            <.face
              :for={{c, i} <- @items |> Enum.take(2) |> Enum.with_index() |> Enum.reverse()}
              card={c}
              name={@names[c]}
              style={"position: absolute; inset: 0; width: 100%" <> if(i == 1, do: "; rotate: -5deg", else: "")}
              motion={card_motion(@motion)}
            />
          </div>
        </.zone_frame>
      <% true -> %>
        <.zone_frame zone={@zone} count={@count}>
          <div
            id={@dom}
            class="flex min-h-[calc(var(--card-w)*1.4)] min-w-[calc(var(--card-w)*1)] flex-wrap justify-center gap-1"
            style={
              if @small,
                do: "--card-w: clamp(1.9rem, 8cqi, 2.8rem)",
                else: "--card-w: clamp(2.4rem, 10cqi, 3.6rem)"
            }
            data-anchor
            data-count={@count}
          >
            <.face
              :for={c <- @items}
              card={c}
              name={@names[c]}
              legal={c in @legal}
              motion={card_motion(@motion)}
            />
          </div>
        </.zone_frame>
    <% end %>
    """
  end

  attr :zone, :map, required: true
  attr :count, :integer, required: true
  slot :inner_block, required: true

  defp zone_frame(assigns) do
    ~H"""
    <figure class="flex flex-col items-center gap-1" data-zone={@zone.id}>
      {render_slot(@inner_block)}
      <figcaption class="text-[11px] font-medium text-tb-felt-ink/75 sm:text-xs">
        {@zone.label} · {@count}
      </figcaption>
    </figure>
    """
  end

  # One card, any deck: a standard card face, else a tile with the card's name.
  attr :card, :string, required: true
  attr :name, :string, default: nil
  attr :legal, :boolean, default: false
  attr :class, :any, default: nil
  attr :style, :string, default: nil
  attr :motion, :map, default: %{}

  defp face(assigns) do
    assigns = assign(assigns, std: Spec.standard(assigns.card))

    ~H"""
    <%= if @std do %>
      <Cards.card
        id={Cards.card_id(scope(), @std)}
        card={@std}
        as={if @legal, do: "button", else: "div"}
        state={@legal && :legal}
        phx-click={@legal && "play"}
        phx-value-card={@legal && @card}
        class={@class}
        style={@style}
        {Cards.motion_attrs(@motion, @std)}
      />
    <% else %>
      <div
        id={"#{scope()}-card-#{@card}"}
        class={[
          "tb-card grid place-items-center bg-white p-1 text-center text-[10px] leading-tight font-semibold text-stone-900",
          @class
        ]}
        style={@style}
        data-flip="card"
      >
        {@name || @card}
      </div>
    <% end %>
    """
  end

  # The motion map of `Cards` is keyed by `{rank, suit}`.
  defp card_motion(%{cards: cards}) do
    for {id, m} <- cards, c = Spec.standard(id), c != nil, into: %{}, do: {c, m}
  end

  defp card_motion(_motion), do: %{}

  defp sort_hand(cards), do: PlayingCards.sort(cards)

  # -- the prompt -------------------------------------------------------------------------

  attr :view, :map, required: true
  attr :actions, :list, required: true
  attr :seats, :map, required: true
  attr :me, :any, required: true
  attr :seat, :any, required: true

  defp prompt_bar(assigns) do
    assigns =
      assign(assigns,
        choices: for({:choose, l} <- assigns.actions, do: l),
        cards?: Enum.any?(assigns.actions, &match?({:play, _, _}, &1))
      )

    ~H"""
    <div
      id="generic-prompt"
      class="flex min-h-12 flex-wrap items-center gap-2 rounded-tb bg-tb-base-100 px-3 py-2 ring-1 ring-tb-base-content/10"
      data-mine={to_string(@actions != [])}
    >
      <p class="min-w-0 flex-1 text-sm" id="generic-status">
        <%= cond do %>
          <% @view.result -> %>
            Game over.
          <% @actions != [] -> %>
            <strong>{@view.pending.prompt}</strong>
            <span :if={@cards?} class="text-tb-base-content/70"> · tap a lit card</span>
          <% @seat == :spectator and @view.pending -> %>
            You are watching. {seat_name(@seats, @view.pending.seat, nil)} to act.
          <% @view.pending -> %>
            Waiting for {seat_name(@seats, @view.pending.seat, @me)}…
          <% true -> %>
            …
        <% end %>
      </p>
      <div :if={@choices != []} class="flex flex-wrap gap-2">
        <button
          :for={l <- @choices}
          id={"choose-#{l}"}
          type="button"
          phx-click="choose"
          phx-value-label={l}
          class="rounded-tb bg-tb-primary px-4 py-2 font-semibold text-tb-primary-content shadow-sm transition hover:brightness-110 active:scale-[0.97]"
        >
          {choice_text(l)}
        </button>
      </div>
    </div>
    """
  end

  defp choice_text(label) do
    case @suits[label] do
      nil -> String.capitalize(label)
      symbol -> "#{symbol} #{String.capitalize(label)}"
    end
  end

  defp choice_done("draw"), do: "drew a card"
  defp choice_done("pass"), do: "passed"
  defp choice_done(label), do: "chose #{choice_text(label)}"

  defp counter_text(value) when is_binary(value) do
    case @suits[value] do
      nil -> if value == "", do: "–", else: value
      symbol -> "#{symbol} #{value}"
    end
  end

  defp counter_text(value), do: to_string(value)

  # The newest action, in words: "Ada played 7♥", "Ada chose hearts".
  defp last_action(view, seats, me) do
    Enum.find_value(view.log, fn
      {:action, s, {:play, _zone, card}, _} when is_binary(card) ->
        "#{seat_name(seats, s, me)} played #{Map.get(view.names, card, card)}"

      {:action, s, {:choose, label}, _} ->
        "#{seat_name(seats, s, me)} #{choice_done(label)}"

      _ ->
        nil
    end)
  end

  # -- the end ------------------------------------------------------------------------------

  attr :view, :map, required: true
  attr :seats, :map, required: true
  attr :me, :any, required: true

  defp over_dialog(assigns) do
    ranking = Enum.sort_by(assigns.view.seats, &{-assigns.view.result[&1], &1})
    top = assigns.view.result[hd(ranking)]
    winners = for s <- ranking, assigns.view.result[s] == top, do: s
    assigns = assign(assigns, ranking: ranking, winners: winners)

    ~H"""
    <div
      id="generic-over"
      class="fixed inset-0 z-40 grid place-items-center p-3"
      role="dialog"
      aria-modal="true"
    >
      <div class="absolute inset-0 bg-black/45"></div>
      <div class="relative flex w-full max-w-md flex-col gap-3 rounded-2xl bg-tb-base-100 p-4 text-tb-base-content shadow-2xl ring-1 ring-black/10 sm:p-5">
        <h2 class="text-xl font-bold">
          {Enum.map_join(@winners, " and ", &seat_name(@seats, &1, @me))} {if @winners == [@me],
            do: "win!",
            else: if(length(@winners) == 1, do: "wins!", else: "win!")}
        </h2>
        <ol id="generic-ranking" class="flex flex-col gap-1">
          <li
            :for={{s, i} <- Enum.with_index(@ranking, 1)}
            class={[
              "flex items-center gap-2 rounded-tb px-3 py-1.5",
              if(s in @winners, do: "bg-tb-accent text-tb-accent-content", else: "bg-tb-base-200")
            ]}
          >
            <span class="w-5 text-sm font-semibold opacity-70">{i}.</span>
            <span class="min-w-0 flex-1 truncate font-medium">{seat_name(@seats, s, @me)}</span>
            <span class="font-bold tabular-nums">{@view.result[s]}</span>
          </li>
        </ol>
        <div class="flex gap-2">
          <button
            id="generic-over-close"
            type="button"
            phx-click="over"
            phx-value-open="false"
            class="flex-1 rounded-tb px-4 py-2 font-semibold ring-1 ring-tb-base-content/25 transition hover:bg-tb-base-200 active:scale-[0.97]"
          >
            See the table
          </button>
          <button
            id="play-again"
            type="button"
            phx-click="play_again"
            class="flex-1 rounded-tb bg-tb-primary px-4 py-2 font-semibold text-tb-primary-content shadow-sm transition hover:brightness-110 active:scale-[0.97]"
          >
            Play again
          </button>
        </div>
      </div>
    </div>
    """
  end
end
