defmodule HeartsWeb.Board do
  @moduledoc """
  The Hearts board on the table page (`TableWeb.TableLive`, a `TableWeb.Board`).

  It draws one seat's `Table.View` (`Hearts.Game.view/2`): your hand as a fan at
  the bottom, the others around (`HeartsWeb.TableComponents`), the trick in the
  middle, the scores on the seat labels. A tap on a legal card plays it; in the
  pass, taps pick 3 cards and Pass sends them.

  ## Motion

  The motion comes from the log events between the old view and the new one
  (`put_view/3`); the `TableMotion` hook plays it from DOM data:

  - another seat's card flies from its hand to the trick; yours slides (same id);
  - a full trick stays in the middle with the winner's card lit, then flies to the
    winner's pile (`{:hearts_sweep, version}` after `@sweep_ms`: the last card
    lands in `TableMotion`'s 420 ms, then all the cards stay at rest for about
    1 s). The last trick of a hand shows too, before the score table opens;
  - your passed cards fly to the seat you pass to, the cards you get fly in
    from the seat that passes them and stay marked until you play a card or
    for `@new_ms` (`{:hearts_seen, cards}`), whichever comes first;
  - a new hand: the cards fly from the deck to every seat.

  ## Dialogs

  At the end of a hand (after the last trick flies) the score table opens; "Next
  hand" closes it, deals, and tells the room that this seat is ready: the bots
  wait for every seated human (`Table.Server`, Hold). "Last trick" (over your
  hand, once a trick of this hand is taken) shows the cards of the newest
  trick and who played them. At the end of the game it says who won and has
  "Play again". The header's Scores button opens the same table at any time.
  """
  @behaviour TableWeb.Board

  use QuacksWeb, :html

  import HeartsWeb.TableComponents

  alias Hearts.Game
  alias Phoenix.LiveView
  alias TableWeb.Components.{Cards, Theme}

  @sweep_ms Application.compile_env(:quacks, :hearts_sweep_ms, 1450)
  @new_ms 2800
  @deal_step 28
  @table "ht"

  # -- TableWeb.Board -------------------------------------------------------------

  @impl true
  def init(socket) do
    Phoenix.Component.assign(socket,
      selected: [],
      new_cards: [],
      collect: nil,
      scores: nil,
      scores_open: false,
      history_open: false,
      last_open: false,
      dealing: false,
      motion: %{}
    )
  end

  @impl true
  def put_view(socket, env, old) do
    v = env.view
    me = me(env)
    n = length(v.seats)
    pos = &pos(&1, me, n)
    a = socket.assigns

    socket = Phoenix.Component.assign(socket, view: v, actions: env.actions, me: me, n: n)

    case events(old, env) do
      :mount ->
        over = if v.phase == :over, do: last_scores(v.log)
        Phoenix.Component.assign(socket, scores: over, scores_open: over != nil, motion: %{})

      :fresh ->
        socket
        |> Phoenix.Component.assign(
          selected: [],
          new_cards: [],
          collect: nil,
          scores: nil,
          scores_open: false
        )
        |> deal(env.version)

      events ->
        trick_motion =
          for {:play, s, c} <- events, s != me, into: %{}, do: {c, %{from: hand_id(pos.(s))}}

        {collect, trick_motion} = collect(a.collect, events, v, pos, trick_motion, env.version)

        if collect && collect != a.collect,
          do: later(socket, {:hearts_sweep, env.version}, @sweep_ms)

        {received, hand_motion} = received(events, me, pos)
        mark_until_seen(socket, received)

        scores =
          Enum.find_value(events, a.scores, fn
            {:hand_scored, data} -> data
            _ -> nil
          end)

        Phoenix.Component.assign(socket,
          collect: collect,
          scores: scores,
          scores_open: a.scores_open and scores != nil,
          selected: selected(a.selected, v, events),
          new_cards: new_cards(a.new_cards, received, events, me),
          motion: %{trick: trick_motion, hand: Map.merge(pass_out(v, me, pos), hand_motion)}
        )
    end
  end

  @impl true
  def handle_event("tap", %{"card" => code}, socket) do
    a = socket.assigns
    card = Cards.parse(code)

    cond do
      is_nil(card) ->
        {:noreply, socket}

      passing?(a) ->
        {:noreply, Phoenix.Component.assign(socket, selected: toggle(a.selected, card))}

      {:play, card} in a.actions ->
        {:act, {:play, card}, socket}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("pass", _params, socket) do
    a = socket.assigns

    if passing?(a) and length(a.selected) == 3,
      do: {:act, {:pass, Game.sort_hand(a.selected)}, socket},
      else: {:noreply, socket}
  end

  def handle_event("next_hand", _params, socket) do
    socket = Phoenix.Component.assign(socket, scores: nil, scores_open: false)

    if socket.assigns.view.phase == :over,
      do: {:noreply, socket},
      else: {:ready, deal(socket, socket.assigns.env.version)}
  end

  def handle_event("last_trick", %{"open" => open}, socket),
    do: {:noreply, Phoenix.Component.assign(socket, last_open: open == "true")}

  def handle_event("history", %{"open" => open}, socket),
    do: {:noreply, Phoenix.Component.assign(socket, history_open: open == "true")}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:hearts_sweep, version}, socket) do
    a = socket.assigns

    if a.collect && a.collect.version == version,
      do:
        {:noreply,
         Phoenix.Component.assign(socket,
           collect: nil,
           scores_open: a.scores != nil,
           motion: %{}
         )},
      else: {:noreply, socket}
  end

  def handle_info({:hearts_seen, cards}, socket) do
    if socket.assigns.new_cards == cards,
      do: {:noreply, Phoenix.Component.assign(socket, new_cards: [])},
      else: {:noreply, socket}
  end

  def handle_info({:hearts_dealt, version}, socket) do
    if socket.assigns.dealing == version,
      do: {:noreply, Phoenix.Component.assign(socket, dealing: false, motion: %{})},
      else: {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # -- from the events to the motion ------------------------------------------------

  defp me(%{seat: :spectator}), do: 0
  defp me(%{seat: seat}), do: seat

  defp pos(seat, me, n), do: Enum.at(positions(n), rem(seat - me + n, n))

  defp hand_id(pos), do: part(@table, :hand, pos)

  # The new log events, oldest first; `:mount` with no old view; `:fresh` for a
  # new game (Play again).
  defp events(nil, _env), do: :mount

  defp events(old, env) do
    new_log = env.view.log
    added = length(new_log) - length(old.view.log)

    if added < 0 or env.view.hand_no < old.view.hand_no,
      do: :fresh,
      else: new_log |> Enum.take(added) |> Enum.reverse()
  end

  # A full trick stays in the middle until the sweep. Its cards fly to the winner,
  # one after the other (`leave_delay`); the last card flies in at once.
  defp collect(old, events, v, pos, trick_motion, version) do
    case Enum.find(events, &match?({:trick_won, _, _, _}, &1)) do
      {:trick_won, winner, _cards, points} ->
        plays = last_trick(v.log, length(v.seats))
        to = part(@table, :pile, pos.(winner))

        motion =
          plays
          |> Enum.with_index()
          |> Map.new(fn {{_s, c}, i} ->
            {c, Map.merge(%{to: to, leave_delay: i * 40}, Map.get(trick_motion, c, %{}))}
          end)

        {%{
           plays: Enum.map(plays, fn {s, c} -> {pos.(s), c} end),
           winner: pos.(winner),
           seat: winner,
           points: points,
           version: version
         }, motion}

      nil ->
        {if(v.trick == [], do: old), trick_motion}
    end
  end

  # The plays of the last full trick, from the log (newest first).
  defp last_trick(log, n) do
    log
    |> Enum.drop_while(&(not match?({:trick_won, _, _, _}, &1)))
    |> Enum.flat_map(fn
      {:play, s, c} -> [{s, c}]
      _ -> []
    end)
    |> Enum.take(n)
    |> Enum.reverse()
  end

  defp received(events, me, pos) do
    Enum.find_value(events, {[], %{}}, fn
      {:pass, _dir, moves} ->
        Enum.find_value(moves, fn
          {from, {^me, cards}} when is_list(cards) ->
            {cards, Map.new(cards, &{&1, %{from: hand_id(pos.(from)), delay: 300}})}

          _ ->
            nil
        end)

      _ ->
        nil
    end)
  end

  # While your pass waits for the others, your 3 cards know where they go.
  defp pass_out(%{phase: :passing, pass: [_ | _] = cards} = v, me, pos) do
    to = Game.pass_target(me, v.pass_direction, length(v.seats))
    Map.new(cards, &{&1, %{to: hand_id(pos.(to))}})
  end

  defp pass_out(_v, _me, _pos), do: %{}

  defp selected(selected, %{phase: :passing, pass: nil}, _events), do: selected
  defp selected(_selected, _v, _events), do: []

  defp new_cards(_old, [_ | _] = received, _events, _me), do: received

  defp new_cards(old, [], events, me) do
    if Enum.any?(events, &match?({:play, ^me, _}, &1)) or
         Enum.any?(events, &match?({:deal, _, _, _}, &1)),
       do: [],
       else: old
  end

  # The deal: every card flies from the deck, round the table, #{@deal_step} ms apart.
  defp deal(socket, version) do
    %{view: v, me: me, n: n} = socket.assigns
    deck = part(@table, :deck)
    hand = v.hand || []

    hand_motion =
      hand
      |> Enum.with_index()
      |> Map.new(fn {c, i} -> {c, %{from: deck, delay: i * n * @deal_step}} end)

    backs =
      for {s, count} <- v.hand_sizes, s != me or is_nil(v.hand), into: %{} do
        k = rem(s - me + n, n)

        {pos(s, me, n),
         Map.new(0..(count - 1)//1, fn i ->
           {i, %{from: deck, delay: (i * n + k) * @deal_step}}
         end)}
      end

    total = v.hand_sizes |> Map.values() |> Enum.sum()
    later(socket, {:hearts_dealt, version}, total * @deal_step + 450)

    Phoenix.Component.assign(socket,
      dealing: version,
      motion: %{hand: hand_motion, backs: backs}
    )
  end

  # The received cards stay marked for @new_ms (or until you play).
  defp mark_until_seen(socket, []), do: socket
  defp mark_until_seen(socket, cards), do: later(socket, {:hearts_seen, cards}, @new_ms)

  defp later(socket, msg, ms) do
    cond do
      !LiveView.connected?(socket) or socket.assigns[:static] -> nil
      ms == 0 -> send(self(), msg)
      true -> Process.send_after(self(), msg, ms)
    end

    socket
  end

  defp last_scores(log) do
    Enum.find_value(log, fn
      {:hand_scored, data} -> data
      _ -> nil
    end)
  end

  defp passing?(%{view: %{phase: :passing, pass: nil}, actions: [_ | _]}), do: true
  defp passing?(_assigns), do: false

  defp toggle(selected, card) do
    cond do
      card in selected -> selected -- [card]
      length(selected) >= 3 -> selected
      true -> selected ++ [card]
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
    assigns =
      assign(assigns,
        table: table_assigns(assigns),
        history: history(assigns.view.log),
        newest: newest_trick(assigns.view),
        open_seats: for({s, %{open: true}} <- assigns.seats, do: s)
      )

    ~H"""
    <Theme.root
      id="hearts-root"
      remember
      class="min-h-dvh bg-tb-base-200 text-tb-base-content"
      data-phase={@view.phase}
    >
      <div class="mx-auto flex max-w-3xl flex-col gap-2 px-2 pt-2 pb-4 sm:gap-3 sm:px-4 sm:pt-4">
        <.top_bar code={@code} view={@view} scores={@scores} />
        <.hearts_table id="ht" {@table}>
          <:status>
            <button
              :if={@newest}
              id="last-trick-open"
              type="button"
              phx-click="last_trick"
              phx-value-open="true"
              class="inline-flex shrink-0 items-center gap-1 rounded-full bg-tb-base-100/90 px-2 py-0.5 text-[11px] font-semibold text-tb-base-content shadow-sm ring-1 ring-black/10 transition hover:bg-tb-base-100 active:scale-95 sm:text-xs"
            >
              <.icon name="hero-arrow-uturn-left-mini" class="size-3" /> Last trick
            </button>
            <span id="hearts-status" class="min-w-0 truncate">{status(assigns)}</span>
          </:status>
        </.hearts_table>
        <.pass_bar
          :if={passing?(assigns) and @scores == nil}
          view={@view}
          selected={@selected}
          to={name(@seats, Game.pass_target(@me, @view.pass_direction, @n), @me)}
        />
        <.invite :if={@open_seats != []} code={@code} key={@key} open={length(@open_seats)} />
        <details class="group rounded-tb bg-tb-base-100 px-3 py-2 ring-1 ring-tb-base-content/10">
          <summary class="cursor-pointer text-sm font-medium select-none">Table colours</summary>
          <Theme.picker id="hearts-picker" class="pt-2" />
        </details>
      </div>

      <.hb_dialog :if={@scores_open and @view.phase == :over} id="hearts-over">
        <.game_over view={@view} seats={@seats} me={@me} history={@history} />
      </.hb_dialog>
      <.hb_dialog :if={@scores_open and @view.phase != :over} id="hearts-scores">
        <.hand_scores scores={@scores} seats={@seats} me={@me} history={@history} />
      </.hb_dialog>
      <.hb_dialog :if={@last_open and @newest != nil and !@scores_open} id="hearts-last-trick">
        <.last_trick_view trick={@newest} seats={@seats} me={@me} />
      </.hb_dialog>
      <.hb_dialog :if={@history_open and !@scores_open} id="hearts-history">
        <h2 class="text-lg font-bold">Scores</h2>
        <.score_table seats={@seats} me={@me} history={@history} view={@view} />
        <button
          id="history-close"
          type="button"
          phx-click="history"
          phx-value-open="false"
          class={button_class(:quiet)}
        >
          Close
        </button>
      </.hb_dialog>
    </Theme.root>
    """
  end

  @doc false
  # The table's attrs from the page's assigns (also for the gallery).
  def table_assigns(assigns) do
    %{view: v, me: me, n: n, collect: collect} = assigns
    mode = mode(assigns)
    hidden = mode != :live
    dealing = assigns.dealing != false
    hand = if hidden, do: [], else: v.hand

    %{
      players: n,
      seats: seat_infos(assigns, mode),
      hand: hand,
      legal: legal(assigns),
      selected: if(v.pass, do: v.pass, else: assigns.selected),
      new: assigns.new_cards,
      on_tap: if(tappable?(assigns), do: "tap"),
      plays: plays(v, collect, me, n),
      winner: collect && collect.winner,
      deck: if(mode == :hidden, do: v.hand_sizes |> Map.values() |> Enum.sum(), else: 0),
      drain: if(dealing and !hidden, do: total(v) * @deal_step, else: 0),
      motion: assigns.motion
    }
  end

  # :live, :ending (the hand's last trick is still on the table: the view is the
  # next hand already) or :hidden (the hand's scores show, the next hand waits).
  defp mode(%{scores: nil}), do: :live
  defp mode(%{collect: %{}}), do: :ending
  defp mode(_assigns), do: :hidden

  defp total(v), do: v.hand_sizes |> Map.values() |> Enum.sum()

  defp plays(_v, %{plays: plays}, _me, _n), do: plays
  defp plays(v, nil, me, n), do: Enum.map(v.trick, fn {s, c} -> {pos(s, me, n), c} end)

  defp legal(%{view: %{phase: :playing}, actions: actions}), do: for({:play, c} <- actions, do: c)
  defp legal(_assigns), do: :all

  defp tappable?(%{view: %{phase: :playing}, actions: [_ | _]}), do: true
  defp tappable?(assigns), do: passing?(assigns)

  defp seat_infos(assigns, mode) do
    %{view: v, me: me, n: n, seats: seats, collect: collect} = assigns
    ended = if mode == :ending, do: ended_hand(v.log)

    Map.new(v.seats, fn s ->
      seat = Map.get(seats, s, %{name: "Player #{s + 1}", bot: false, open: false})

      {pos(s, me, n),
       %{
         name: if(s == me and assigns.seat != :spectator, do: "You", else: seat.name),
         bot: seat.bot,
         open: seat.open,
         score: score(v, s, mode, assigns.scores),
         passed: v.phase == :passing and s in v.passed,
         turn: v.phase == :playing and v.turn == s and collect == nil and mode == :live
       }
       |> Map.merge(this_hand(v, s, n, mode, ended))}
    end)
  end

  # While the hand's last trick shows, the score before the hand.
  defp score(v, s, :ending, scores), do: v.scores[s] - scores.points[s]
  defp score(v, s, _mode, _scores), do: v.scores[s]

  # While the hand's scores show, the new hand is not on the table yet; while its
  # last trick shows, the seats show the hand that ends.
  defp this_hand(v, s, n, :live, _ended),
    do: %{points: v.points_taken[s], count: v.hand_sizes[s], tricks: div(length(v.taken[s]), n)}

  defp this_hand(_v, s, _n, :ending, ended) do
    won = for {:trick_won, ^s, _cards, p} <- ended, do: p
    %{points: Enum.sum(won), count: 0, tricks: length(won)}
  end

  defp this_hand(_v, _s, _n, :hidden, _ended), do: %{points: 0, count: 0, tricks: 0}

  # The log events of the hand that just ended (newest first).
  defp ended_hand(log) do
    log
    |> Enum.drop_while(&(not match?({:hand_scored, _}, &1)))
    |> Enum.drop(1)
    |> Enum.take_while(&(not match?({:deal, _, _, _}, &1)))
  end

  # The newest trick taken in this hand: who took it, the points, the plays
  # (`[{seat, card}]` in play order). Nil before the first trick of a hand.
  defp newest_trick(%{log: log, seats: seats}) do
    hand = Enum.take_while(log, &(not match?({:deal, _, _, _}, &1)))

    case Enum.find(hand, &match?({:trick_won, _, _, _}, &1)) do
      {:trick_won, winner, _cards, points} ->
        %{winner: winner, points: points, plays: last_trick(hand, length(seats))}

      nil ->
        nil
    end
  end

  defp name(seats, s, me) do
    if s == me, do: "You", else: get_in(seats, [s, :name]) || "Player #{s + 1}"
  end

  defp status(%{collect: %{seat: s, points: p}} = a),
    do:
      "#{name(a.seats, s, a.me)} #{if s == a.me, do: "take", else: "takes"} the trick#{points_note(p)}"

  defp status(%{seat: :spectator, view: %{phase: :over}}), do: "Game over"
  defp status(%{seat: :spectator}), do: "You are watching"
  defp status(%{view: %{phase: :over}}), do: "Game over"

  defp status(%{view: %{phase: :passing, pass: nil}, actions: [_ | _]} = a) do
    left = 3 - length(a.selected)
    if left == 0, do: "Ready to pass", else: "Pick #{left} to pass"
  end

  defp status(%{view: %{phase: :passing} = v} = a) do
    waiting = for s <- v.seats, s not in v.passed, do: name(a.seats, s, a.me)
    "Waiting for #{Enum.join(waiting, ", ")}"
  end

  defp status(%{view: %{phase: :playing, turn: me}, me: me, seat: me} = a) do
    if a.view.trick == [], do: "Your lead", else: "Your turn"
  end

  defp status(%{view: %{turn: turn}} = a) do
    if get_in(a.seats, [turn, :open]),
      do: "Waiting for a player to join",
      else: "#{name(a.seats, turn, a.me)} to play"
  end

  defp points_note(0), do: ""
  defp points_note(p) when p > 0, do: " (+#{p})"
  defp points_note(p), do: " (#{p})"

  # The hands scored so far, oldest first.
  defp history(log), do: log |> Enum.flat_map(&scored/1) |> Enum.reverse()

  defp scored({:hand_scored, data}), do: [data]
  defp scored(_event), do: []

  # -- the parts of the page ------------------------------------------------------------

  attr :code, :string, required: true
  attr :view, :map, required: true

  attr :scores, :map,
    default: nil,
    doc: "the hand that ended, while its last trick or scores show"

  defp top_bar(assigns) do
    ~H"""
    <header class="flex items-center gap-2">
      <.link
        navigate={~p"/games"}
        class="grid size-9 shrink-0 place-items-center rounded-full bg-tb-base-100 ring-1 ring-tb-base-content/10 transition hover:bg-tb-base-300 active:scale-95"
        aria-label="Games"
      >
        <.icon name="hero-arrow-left" class="size-4" />
      </.link>
      <h1 class="text-lg font-bold"><span class="text-(--tb-card-red)">♥</span> Hearts</h1>
      <span
        id="hearts-code"
        class="rounded-full bg-tb-base-100 px-2 py-0.5 font-mono text-xs tracking-widest ring-1 ring-tb-base-content/10"
        title="room code"
      >
        {@code}
      </span>
      <span class="ml-auto truncate text-xs text-tb-base-content/70 sm:text-sm" id="hearts-hand-no">
        <%= if @scores do %>
          Hand {@scores.hand}
        <% else %>
          Hand {@view.hand_no}{direction_text(@view)}
        <% end %>
      </span>
      <button
        id="history-open"
        type="button"
        phx-click="history"
        phx-value-open="true"
        class="shrink-0 rounded-full bg-tb-base-100 px-3 py-1 text-xs font-semibold ring-1 ring-tb-base-content/10 transition hover:bg-tb-base-300 active:scale-95"
      >
        Scores
      </button>
    </header>
    """
  end

  defp direction_text(%{phase: :passing, pass_direction: :across}), do: " · pass across"
  defp direction_text(%{phase: :passing, pass_direction: dir}), do: " · pass #{dir}"
  defp direction_text(%{phase: :playing, hearts_broken: true}), do: " · hearts broken"
  defp direction_text(_view), do: ""

  attr :view, :map, required: true
  attr :selected, :list, required: true
  attr :to, :string, required: true

  defp pass_bar(assigns) do
    ~H"""
    <div
      id="pass-bar"
      class="flex items-center gap-3 rounded-tb bg-tb-base-100 px-3 py-2 ring-1 ring-tb-base-content/10"
    >
      <p class="min-w-0 flex-1 text-sm">
        Pick 3 cards to pass <strong>{direction_words(@view.pass_direction)}</strong> to {@to}.
      </p>
      <button
        id="pass-button"
        type="button"
        phx-click="pass"
        disabled={length(@selected) != 3}
        class={[button_class(:primary), "shrink-0"]}
      >
        Pass {length(@selected)}/3
      </button>
    </div>
    """
  end

  defp direction_words(:left), do: "left"
  defp direction_words(:right), do: "right"
  defp direction_words(:across), do: "across"

  attr :code, :string, required: true
  attr :key, :string, required: true
  attr :open, :integer, required: true

  defp invite(assigns) do
    ~H"""
    <div
      id="hearts-invite"
      class="rounded-tb bg-tb-base-100 px-3 py-2 text-sm ring-1 ring-tb-base-content/10"
    >
      {if @open == 1, do: "1 seat is open.", else: "#{@open} seats are open."} Share this link, or the code <strong class="font-mono tracking-widest">{@code}</strong>:
      <span class="block truncate font-mono text-xs select-all">
        {url(~p"/games/#{@key}/#{@code}")}
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  slot :inner_block, required: true

  defp hb_dialog(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-40 grid place-items-center p-3"
      role="dialog"
      aria-modal="true"
    >
      <div class="hb-backdrop absolute inset-0 bg-black/45"></div>
      <div class="hb-dialog relative flex max-h-[90dvh] w-full max-w-md flex-col gap-3 overflow-y-auto rounded-2xl bg-tb-base-100 p-4 text-tb-base-content shadow-2xl ring-1 ring-black/10 sm:p-5">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :trick, :map, required: true
  attr :seats, :map, required: true
  attr :me, :integer, required: true

  defp last_trick_view(assigns) do
    ~H"""
    <h2 class="text-lg font-bold">Last trick</h2>
    <p class="text-sm text-tb-base-content/80">
      {name(@seats, @trick.winner, @me)} took it{points_note(@trick.points)}.
    </p>
    <ol
      id="last-trick-cards"
      class="tb-felt flex justify-center gap-2 rounded-tb p-3 sm:gap-3"
      style={"--card-w: " <> if(length(@trick.plays) > 4, do: "clamp(2.9rem, 13vw, 4.5rem)", else: "clamp(3.4rem, 17vw, 4.5rem)")}
    >
      <li
        :for={{s, c} <- @trick.plays}
        class="flex min-w-0 flex-col items-center gap-1"
        data-seat={s}
        data-winner={to_string(s == @trick.winner)}
      >
        <Cards.card card={c} state={if s == @trick.winner, do: :won} />
        <span class={[
          "max-w-[var(--card-w)] truncate text-xs text-tb-felt-ink",
          s == @trick.winner && "font-bold"
        ]}>
          {name(@seats, s, @me)}
        </span>
      </li>
    </ol>
    <button
      id="last-trick-close"
      type="button"
      phx-click="last_trick"
      phx-value-open="false"
      class={button_class(:quiet)}
    >
      Close
    </button>
    """
  end

  attr :scores, :map, required: true
  attr :seats, :map, required: true
  attr :me, :integer, required: true
  attr :history, :list, required: true

  defp hand_scores(assigns) do
    ~H"""
    <h2 class="text-lg font-bold">Hand {@scores.hand}</h2>
    <p
      :if={@scores.moon}
      id="moon-note"
      class="rounded-tb bg-tb-warning px-3 py-2 text-sm font-semibold text-tb-warning-content"
    >
      🌙 {name(@seats, @scores.moon, @me)} shot the moon!
    </p>
    <.score_table seats={@seats} me={@me} history={@history} />
    <button id="next-hand" type="button" phx-click="next_hand" class={button_class(:primary)}>
      Next hand
    </button>
    """
  end

  attr :view, :map, required: true
  attr :seats, :map, required: true
  attr :me, :integer, required: true
  attr :history, :list, required: true

  defp game_over(assigns) do
    ranking = Enum.sort_by(assigns.view.seats, &{assigns.view.scores[&1], &1})
    assigns = assign(assigns, ranking: ranking)

    ~H"""
    <h2 class="text-xl font-bold">
      {winners_text(@view.winners, @seats, @me)}
    </h2>
    <ol id="final-ranking" class="flex flex-col gap-1">
      <li
        :for={{s, i} <- Enum.with_index(@ranking, 1)}
        class={[
          "flex items-center gap-2 rounded-tb px-3 py-1.5",
          if(s in @view.winners, do: "bg-tb-accent text-tb-accent-content", else: "bg-tb-base-200")
        ]}
      >
        <span class="w-5 text-sm font-semibold opacity-70">{i}.</span>
        <span class="min-w-0 flex-1 truncate font-medium">{name(@seats, s, @me)}</span>
        <span class="font-bold tabular-nums">{@view.scores[s]}</span>
      </li>
    </ol>
    <details>
      <summary class="cursor-pointer text-sm font-medium">Every hand</summary>
      <.score_table seats={@seats} me={@me} history={@history} />
    </details>
    <div class="flex gap-2">
      <.link navigate={~p"/games"} class={[button_class(:quiet), "flex-1 text-center"]}>
        Games
      </.link>
      <button
        id="play-again"
        type="button"
        phx-click="play_again"
        class={[button_class(:primary), "flex-1"]}
      >
        Play again
      </button>
    </div>
    """
  end

  defp winners_text([w], _seats, w), do: "You win!"
  defp winners_text([w], seats, me), do: "#{name(seats, w, me)} wins!"

  defp winners_text(ws, seats, me),
    do: "#{Enum.map_join(ws, " and ", &name(seats, &1, me))} win!"

  attr :seats, :map, required: true
  attr :me, :integer, required: true
  attr :history, :list, required: true
  attr :view, :map, default: nil

  defp score_table(assigns) do
    seats = assigns.seats |> Map.keys() |> Enum.sort()
    last = List.last(assigns.history)
    assigns = assign(assigns, cols: seats, last: last)

    ~H"""
    <div class="overflow-x-auto">
      <table id="score-table" class="w-full text-sm tabular-nums">
        <thead>
          <tr class="text-xs text-tb-base-content/70">
            <th class="py-1 pr-2 text-left font-medium">Hand</th>
            <th
              :for={s <- @cols}
              class={[
                "max-w-16 truncate px-1 py-1 text-right font-semibold",
                s == @me && "text-tb-base-content"
              ]}
            >
              {name(@seats, s, @me)}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={h <- @history} class="border-t border-tb-base-content/10">
            <td class="py-1 pr-2 text-tb-base-content/70">{h.hand}{if h.moon, do: " 🌙"}</td>
            <td :for={s <- @cols} class="px-1 py-1 text-right">{h.points[s]}</td>
          </tr>
          <tr :if={@history == []}>
            <td colspan={length(@cols) + 1} class="py-2 text-center text-tb-base-content/60">
              No hand scored yet.
            </td>
          </tr>
        </tbody>
        <tfoot :if={@last}>
          <tr class="border-t-2 border-tb-base-content/30 font-bold">
            <td class="py-1 pr-2">Total</td>
            <td :for={s <- @cols} class="px-1 py-1 text-right" data-role="total">
              {@last.totals[s]}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  defp button_class(:primary),
    do:
      "rounded-tb bg-tb-primary px-4 py-2 font-semibold text-tb-primary-content shadow-sm transition hover:brightness-110 active:scale-[0.97] disabled:opacity-40 disabled:active:scale-100"

  defp button_class(:quiet),
    do:
      "rounded-tb px-4 py-2 font-semibold text-tb-base-content ring-1 ring-tb-base-content/25 transition hover:bg-tb-base-200 active:scale-[0.97]"
end
