defmodule TableWeb.Gallery.Hearts do
  @moduledoc """
  The gallery's Hearts stories (`/dev/gallery/hearts/*`): the deck, a hand, the
  table in every theme, the table with the theme picker, and the motion.

  No Hearts engine yet: the states here are built by hand from one fixed deal
  (`deal/0`, a fixed order of the deck, no RNG). `QuacksWeb.GalleryFrameLive`
  draws them with `frame/1` and sends the taps and the motion's Play to
  `tap/2` and its own `motion` event.
  """
  use Phoenix.Component

  import TableWeb.Components.Cards
  import TableWeb.Components.HeartsTable

  alias TableWeb.Components.{Cards, Theme}

  @names %{s: "You", w: "Ada", n: "Bram", e: "Cleo"}
  @long %{s: "You", w: "Wilhelmina Pottersfield", n: "Bartholomew Quackenbush", e: "Cleo"}
  # The deal starts left of the dealer (you): west, north, east, you.
  @order [:w, :n, :e, :s]
  @deal_step 28

  @doc "The motion story's kinds."
  @spec motions() :: [String.t()]
  def motions, do: ~w(deal play collect pass-left pass-right pass-across)

  @doc "The table states a story can show."
  @spec states() :: [String.t()]
  def states, do: ~w(play pass collect deal)

  # -- the fixed deal --------------------------------------------------------------------

  @doc "The deal: `[{seat, card}]` in deal order. A fixed order of the deck."
  @spec deal() :: [{Cards.seat(), Cards.card()}]
  def deal do
    Cards.deck()
    |> Enum.sort_by(&:erlang.phash2({&1, 2026}))
    |> Enum.with_index()
    |> Enum.map(fn {c, i} -> {Enum.at(@order, rem(i, 4)), c} end)
  end

  @doc "Each seat's 13 cards, sorted as a hand (`sort/1`)."
  @spec hands() :: %{Cards.seat() => [Cards.card()]}
  def hands do
    deal()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {seat, cards} -> {seat, sort(cards)} end)
  end

  @doc "A hand in Hearts order: clubs, diamonds, spades, hearts; low to high."
  @spec sort([Cards.card()]) :: [Cards.card()]
  def sort(cards) do
    order = Cards.suits() |> Enum.with_index() |> Map.new()
    Enum.sort_by(cards, fn {r, s} -> {order[s], r} end)
  end

  defp seats(names, counts, extra \\ %{}) do
    scores = %{n: 12, e: 5, w: 0, s: 9}

    Map.new([:n, :e, :s, :w], fn seat ->
      base = %{name: names[seat], score: scores[seat], points: 0, count: counts[seat], taken: 0}
      {seat, Map.merge(base, Map.get(extra, seat, %{}))}
    end)
  end

  defp counts(n), do: %{n: n, e: n, s: n, w: n}

  # -- the table states ---------------------------------------------------------------------

  @doc """
  The table's attrs for a state (`HeartsTable.table/1` without `id`):
  `"play"`, `"pass"`, `"collect"`, `"deal"`, and the motion's after-states.
  `opts`: `long_names`, `tap` (your hand is tappable).
  """
  @spec state(String.t(), keyword) :: map
  def state(name, opts \\ [])

  def state("deal", opts),
    do: %{seats: seats(names(opts), counts(0)), hand: [], deck: 52, status: "Dealing"}

  def state("dealt", opts) do
    h = hands()

    %{
      seats: seats(names(opts), counts(13)),
      hand: h.s,
      drain: length(deal()) * @deal_step,
      status: "Pick 3 cards to pass"
    }
  end

  def state("play", opts) do
    {h, suit, plays} = opening()
    legal = for {_r, s} = c <- h.s, s == suit, do: c

    %{
      seats: seats(names(opts), %{n: 12, e: 13, s: 13, w: 12}, %{n: %{points: 1, taken: 4}}),
      hand: h.s,
      legal: if(legal == [], do: :all, else: legal),
      on_tap: opts[:tap] && "hearts_tap",
      plays: plays,
      turn: :s,
      status: "Your turn: follow #{suit_mark(suit)}"
    }
  end

  def state("played", opts) do
    {h, suit, plays} = opening()
    mine = my_card(h.s, suit)
    east = follow(h.e, suit)
    base = state("play", opts)

    %{
      base
      | hand: h.s -- [mine],
        plays: plays ++ [{:s, mine}, {:e, east}],
        legal: :all,
        on_tap: nil,
        turn: nil,
        status: "#{@names.e} plays"
    }
    |> put_in([:seats, :e, :count], 12)
    |> Map.put(:east, east)
  end

  def state("collect", opts) do
    played = state("played", opts)
    {_h, suit, _plays} = opening()
    winner = winner(played.plays, suit)

    %{
      played
      | status: "#{played.seats[winner].name} takes the trick",
        turn: nil
    }
    |> Map.put(:winner, winner)
  end

  def state("collected", opts) do
    trick = state("collect", opts)
    w = trick.winner
    points = Enum.sum(Enum.map(trick.plays, fn {_s, c} -> points(c) end))
    info = trick.seats[w]

    %{
      trick
      | plays: [],
        winner: nil,
        turn: w,
        status: "#{info.name} leads",
        seats:
          Map.put(trick.seats, w, %{info | taken: info.taken + 4, points: info.points + points})
    }
  end

  def state("pass", opts) do
    h = hands()

    %{
      seats: seats(names(opts), counts(13)),
      hand: h.s,
      selected: passed(h.s),
      on_tap: opts[:tap] && "hearts_tap",
      status: "Pass 3 cards to the left"
    }
  end

  defp names(opts), do: if(opts[:long_names], do: @long, else: @names)

  defp opening do
    h = hands()
    suit = Enum.find([:clubs, :diamonds, :spades], &(holds?(h.w, &1) and holds?(h.n, &1)))
    w = follow(h.w, suit)
    n = h.n |> Enum.filter(&(elem(&1, 1) == suit)) |> List.last()
    {%{h | w: h.w -- [w], n: h.n -- [n]}, suit, [{:w, w}, {:n, n}]}
  end

  defp holds?(cards, suit), do: Enum.any?(cards, &(elem(&1, 1) == suit))

  # The lowest card of the suit, else the first card.
  defp follow(cards, suit), do: Enum.find(cards, &(elem(&1, 1) == suit)) || hd(cards)

  defp my_card(cards, suit), do: follow(cards, suit)

  defp winner(plays, suit) do
    {seat, _c} =
      plays
      |> Enum.filter(fn {_s, {_r, s}} -> s == suit end)
      |> Enum.max_by(fn {_s, {r, _}} -> r end)

    seat
  end

  defp points({_r, :hearts}), do: 1
  defp points({12, :spades}), do: 13
  defp points(_card), do: 0

  # The three highest cards: the usual pass.
  defp passed(cards), do: cards |> Enum.sort_by(&elem(&1, 0), :desc) |> Enum.take(3)

  defp suit_mark(:clubs), do: "♣"
  defp suit_mark(:diamonds), do: "♦"
  defp suit_mark(:spades), do: "♠"
  defp suit_mark(:hearts), do: "♥"

  # -- the stories -------------------------------------------------------------------------

  @doc "Every theme side by side, the same table in each."
  @spec themes_story(map) :: map
  def themes_story(args),
    do: %{
      view: :hearts,
      kind: :themes,
      table: args["state"] |> state(long_names: args["long_names"]) |> Map.delete(:east),
      deck_colours: deck_arg(args)
    }

  @doc "One table with the theme picker; your taps play (or pick for the pass)."
  @spec table_story(map) :: map
  def table_story(args) do
    remember = args["theme"] == "stored"

    %{
      view: :hearts,
      kind: :table,
      state_name: args["state"],
      table:
        args["state"] |> state(tap: true, long_names: args["long_names"]) |> Map.delete(:east),
      theme: if(remember, do: Theme.default(), else: args["theme"]),
      remember: remember,
      deck_colours: deck_arg(args)
    }
  end

  @doc "The 52 faces and the back."
  @spec deck_story(map) :: map
  def deck_story(args),
    do: %{view: :hearts, kind: :deck, theme: args["theme"], deck_colours: deck_arg(args)}

  @doc "Your hand alone: `cards` 1..13 and a `mode` (play, pass, view)."
  @spec hand_story(map) :: map
  def hand_story(%{"cards" => n, "mode" => mode} = args) do
    {h, suit, _plays} = opening()
    cards = Enum.take(h.s, n)
    legal = for {_r, s} = c <- cards, s == suit, do: c

    %{
      view: :hearts,
      kind: :hand,
      theme: args["theme"],
      deck_colours: deck_arg(args),
      cards: cards,
      legal: if(mode == "play" and legal != [], do: legal, else: :all),
      selected: if(mode == "pass", do: passed(cards), else: []),
      on_tap: mode != "view" && "hearts_tap"
    }
  end

  @doc """
  The motion story: the table before and after one change. Play patches the
  table from `before` to `after`, so the `TableMotion` hook plays it.
  """
  @spec motion_story(map) :: map
  def motion_story(args) do
    {before, aft} = motion(args["motion"])

    %{
      view: :hearts,
      kind: :motion,
      motion: args["motion"],
      before: before,
      after: aft,
      theme: args["theme"],
      deck_colours: deck_arg(args)
    }
  end

  defp deck_arg(args), do: if(args["four_colour"], do: "4", else: "2")

  @doc false
  # The before and after of a motion. The after-state carries the motion data.
  def motion("deal"), do: {state("deal"), state("dealt") |> deal_motion("hm")}

  def motion("play") do
    aft = state("played")

    {state("play"),
     Map.put(aft, :motion, %{trick: %{aft.east => %{from: part("hm", :hand, :e), delay: 420}}})}
  end

  def motion("collect") do
    before = state("collect")
    to = part("hm", :pile, before.winner)

    motion =
      before.plays
      |> Enum.with_index()
      |> Map.new(fn {{_s, c}, i} -> {c, %{to: to, delay: i * 50}} end)

    {Map.put(before, :motion, %{trick: motion}), state("collected")}
  end

  def motion("pass-" <> dir) when dir in ~w(left right across) do
    {to, from} = pass_seats(dir)
    h = hands()
    out = passed(h.s)
    received = passed(h[from])
    before = %{state("pass") | status: "Pass 3 cards #{pass_words(dir)}"}

    aft = %{
      before
      | hand: sort((h.s -- out) ++ received),
        selected: [],
        status: "#{@names[from]} passed you 3 cards"
    }

    {Map.put(before, :motion, %{hand: Map.new(out, &{&1, %{to: part("hm", :hand, to)}})}),
     aft
     |> Map.put(:new, received)
     |> Map.put(
       :motion,
       %{hand: Map.new(received, &{&1, %{from: part("hm", :hand, from), delay: 300}})}
     )}
  end

  # Pass left: you give to west and get from east.
  defp pass_seats("left"), do: {:w, :e}
  defp pass_seats("right"), do: {:e, :w}
  defp pass_seats("across"), do: {:n, :n}

  defp pass_words("left"), do: "to the left"
  defp pass_words("right"), do: "to the right"
  defp pass_words("across"), do: "across"

  # Each card flies from the deck in deal order, #{@deal_step} ms apart.
  defp deal_motion(state, id) do
    from = part(id, :deck)

    {hand, backs} =
      deal()
      |> Enum.with_index()
      |> Enum.reduce({%{}, %{}}, fn {{seat, c}, i}, {hand, backs} ->
        m = %{from: from, delay: i * @deal_step}

        if seat == :s do
          {Map.put(hand, c, m), backs}
        else
          k = backs |> Map.get(seat, %{}) |> map_size()
          {hand, Map.update(backs, seat, %{k => m}, &Map.put(&1, k, m))}
        end
      end)

    Map.put(state, :motion, %{hand: hand, backs: backs})
  end

  # -- the taps (the table story) -----------------------------------------------------------

  @doc """
  A tap on a card of your hand in the table story: in play, a legal card goes to
  the trick and east follows; in the pass, a card is picked or put back (3 at most).
  """
  @spec tap(map, String.t()) :: map
  def tap(%{kind: :table, table: t} = assigns, code) do
    case {assigns.state_name, Cards.parse(code)} do
      {"play", card} when not is_nil(card) -> %{table: play(t, card)}
      {"pass", card} when not is_nil(card) -> %{table: pick(t, card)}
      _other -> %{}
    end
  end

  def tap(%{kind: :hand} = assigns, code) do
    case Cards.parse(code) do
      nil -> %{}
      card -> %{selected: toggle(assigns.selected, card)}
    end
  end

  def tap(_assigns, _code), do: %{}

  defp play(%{on_tap: nil} = t, _card), do: t

  defp play(t, card) do
    if t.legal == :all or card in t.legal do
      {_h, suit, _plays} = opening()
      east = follow(hands().e, suit)

      %{
        t
        | hand: t.hand -- [card],
          plays: t.plays ++ [{:s, card}, {:e, east}],
          on_tap: nil,
          turn: nil,
          status: "#{t.seats.e.name} plays"
      }
      |> Map.put(:motion, %{trick: %{east => %{from: part("ht", :hand, :e), delay: 420}}})
      |> put_in([:seats, :e, :count], 12)
    else
      t
    end
  end

  defp pick(t, card) do
    selected = toggle(t.selected, card)
    left = 3 - length(selected)
    status = if left == 0, do: "Ready to pass", else: "Pick #{left} more to pass"
    %{t | selected: selected, status: status}
  end

  defp toggle(selected, card) do
    cond do
      card in selected -> selected -- [card]
      length(selected) >= 3 -> selected
      true -> selected ++ [card]
    end
  end

  # -- the frames ----------------------------------------------------------------------------

  @doc "A Hearts story's frame (`QuacksWeb.GalleryFrameLive`)."
  def frame(%{kind: :themes} = assigns) do
    ~H"""
    <div class="min-h-dvh bg-neutral-900 p-2 sm:p-4" data-role="hearts-themes">
      <div class="mx-auto grid max-w-[90rem] grid-cols-1 gap-3 md:grid-cols-2 sm:gap-4">
        <Theme.root
          :for={t <- Theme.themes()}
          id={"th-#{t.id}"}
          theme={t.id}
          deck={@deck_colours}
          class="overflow-hidden rounded-tb bg-tb-base-200 ring-1 ring-white/10"
        >
          <header class="flex items-center justify-between gap-2 px-3 py-1.5 text-tb-base-content">
            <h2 class="text-sm font-bold">
              {t.name}
              <span
                :if={t.id == Theme.default()}
                class="ml-1 rounded-full bg-tb-accent px-1.5 text-[11px] font-semibold text-tb-accent-content"
              >
                default
              </span>
            </h2>
            <span class="text-xs text-tb-base-content/60">{if t.dark, do: "dark", else: "light"}</span>
          </header>
          <.table id={"th-#{t.id}-t"} {@table} class="rounded-none" />
        </Theme.root>
      </div>
    </div>
    """
  end

  def frame(%{kind: :table} = assigns) do
    ~H"""
    <Theme.root
      id="hearts-root"
      theme={@theme}
      deck={@deck_colours}
      remember={@remember}
      class="min-h-dvh bg-tb-base-200 p-2 sm:p-4"
    >
      <div class="mx-auto flex max-w-3xl flex-col gap-2 sm:gap-3">
        <Theme.picker id="hearts-picker" theme={@theme} deck={@deck_colours} />
        <.table id="ht" {@table} />
      </div>
    </Theme.root>
    """
  end

  def frame(%{kind: :motion} = assigns) do
    after? = assigns[:stage] == :after

    assigns =
      assign(assigns, after?: after?, shown: if(after?, do: assigns.after, else: assigns.before))

    ~H"""
    <Theme.root
      id="hearts-root"
      theme={@theme}
      deck={@deck_colours}
      class="min-h-dvh bg-tb-base-200 p-2 sm:p-4"
    >
      <div class="mx-auto flex max-w-3xl flex-col gap-2" data-role="hearts-motion">
        <div class="flex items-center gap-2">
          <button
            id="motion-play"
            type="button"
            class="rounded-tb bg-tb-primary px-4 py-2 font-semibold text-tb-primary-content shadow-sm transition active:scale-[0.97] disabled:opacity-50"
            phx-click="motion"
            phx-value-to="after"
            disabled={@after?}
          >
            Play
          </button>
          <button
            id="motion-reset"
            type="button"
            class="rounded-tb px-4 py-2 text-tb-base-content ring-1 ring-tb-base-content/30 transition active:scale-[0.97] disabled:opacity-50"
            phx-click="motion"
            phx-value-to="before"
            disabled={!@after?}
          >
            Reset
          </button>
          <span class="font-mono text-xs text-tb-base-content/70">{@motion}</span>
        </div>
        <.table id="hm" {Map.drop(@shown, [:east])} />
      </div>
    </Theme.root>
    """
  end

  def frame(%{kind: :deck} = assigns) do
    ~H"""
    <Theme.root
      id="hearts-root"
      theme={@theme}
      deck={@deck_colours}
      class="tb-felt min-h-dvh p-3 sm:p-6"
    >
      <div class="tb-table mx-auto max-w-6xl space-y-3" data-role="hearts-deck">
        <div
          :for={suit <- Cards.suits()}
          class="grid grid-cols-[repeat(auto-fill,minmax(4.25rem,1fr))] gap-2 sm:grid-cols-[repeat(13,minmax(0,1fr))]"
          style="--card-w: 100%"
        >
          <.card :for={r <- 2..14} card={{r, suit}} />
        </div>
        <div class="flex gap-2" style="--card-w: 5rem">
          <.card_back />
          <.card card={{12, :spades}} state={:won} />
          <.card card={{10, :hearts}} state={:new} />
        </div>
      </div>
    </Theme.root>
    """
  end

  def frame(%{kind: :hand} = assigns) do
    ~H"""
    <Theme.root
      id="hearts-root"
      theme={@theme}
      deck={@deck_colours}
      class="tb-felt min-h-dvh p-3 pt-10"
    >
      <div class="tb-table mx-auto max-w-3xl" data-role="hearts-hand">
        <.hand
          id="hh-hand"
          scope="hh"
          cards={@cards}
          legal={@legal}
          selected={@selected}
          on_tap={@on_tap}
        />
      </div>
    </Theme.root>
    """
  end
end
