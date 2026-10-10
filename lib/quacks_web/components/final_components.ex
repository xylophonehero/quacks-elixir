defmodule QuacksWeb.FinalComponents do
  @moduledoc """
  Round 31 (item 9): the end of the game, in place. No full-screen screen any
  more: the score chart lies over the pot (`final_board/1`) and the contextual
  button area holds Play again, Lobby and a small Share (`final_actions/1`).
  The pot never moves: the chart is absolute inside the pot's square.
  """
  use Phoenix.Component

  import QuacksWeb.CoreComponents, only: [button: 1, icon: 1]
  import QuacksWeb.Icons, only: [piece_icon: 1]
  import QuacksWeb.GameComponents, only: [bot_badge: 1]
  import QuacksWeb.ChipComponents, only: [seat_bg: 1]

  alias Phoenix.LiveView.JS
  alias Quacks.Game
  alias QuacksWeb.Reveal

  @doc """
  The score chart over the pot: who won, then one row per seat in final order
  (`Reveal.final_rows/1`): its place, its initial in the seat colour, its name,
  its final parts (coins, rubies, pennies → VP) and its VP, which counts up from
  the round-9 total (app.css `.final-count`). This browser's row has a gold ring
  and "you". Solo: the score as the title.
  """
  attr :game, Game, required: true
  attr :names, :map, required: true
  attr :bots, :map, default: %{}
  attr :seat, :integer, default: nil, doc: "this browser's seat, for \"You win!\" and \"you\""

  def final_board(assigns) do
    rows = Reveal.final_rows(assigns.game)

    assigns =
      assign(assigns,
        rows: rows,
        cols: final_columns(rows),
        shifts: shifts(rows),
        solo: length(rows) == 1,
        title: win_title(for(%{seat: s, place: 1} <- rows, do: s), assigns.seat, assigns.names)
      )

    ~H"""
    <section
      id="final-board"
      class="final-board paper absolute inset-x-[3%] top-1/2 z-30 flex max-h-[96%] -translate-y-1/2 flex-col gap-1 overflow-hidden rounded-2xl p-2.5 text-ink shadow-2xl ring-1 ring-black/30"
      aria-label="Final scores"
      data-role="final-board"
    >
      <header class="text-center">
        <p class="text-tag font-bold tracking-[0.12em] text-ink-soft uppercase">Game over</p>
        <h2
          class="win-shimmer flex items-center justify-center gap-1.5 font-hand text-2xl leading-tight font-bold"
          data-role="winner"
        >
          <.piece_icon name={:vp} class="size-6 shrink-0 text-gold drop-shadow-sm" />
          <%= if @solo do %>
            <span>
              <span class="tabular-nums">{hd(@rows).vp}</span> victory points
            </span>
          <% else %>
            {@title}
          <% end %>
        </h2>
      </header>
      <ol
        class="final-grid min-h-0"
        style={"--cols: #{length(@cols)}"}
        data-role="final-rows"
      >
        <li
          :for={{row, i} <- Enum.with_index(@rows)}
          class={[
            "final-row rounded-md px-1.5 text-sm",
            if(row.place == 1, do: "bg-gold/30", else: "bg-parchment-deep/50"),
            row.seat == @seat && "ring-2 ring-gold",
            @shifts[row.seat] != 0 && "stage-shift"
          ]}
          style={"--i: #{i}; --shift: #{@shifts[row.seat]}"}
          data-seat={row.seat}
          data-place={row.place}
          data-shift={@shifts[row.seat]}
          data-role="final-score"
        >
          <span class="w-4 text-center font-hand text-lg leading-none font-bold">
            {row.place}
          </span>
          <span
            class={[
              "grid size-5 place-items-center rounded-full font-hand text-xs font-bold text-ink ring-1 ring-black/25",
              seat_bg(row.seat)
            ]}
            aria-hidden="true"
          >
            {String.first(name(@names, row.seat))}
          </span>
          <span class="flex min-w-0 items-center gap-1">
            <span class="min-w-0 truncate font-semibold">{name(@names, row.seat)}</span>
            <.you_tag :if={row.seat == @seat} />
            <.bot_badge :if={@bots[row.seat] && row.seat != @seat} compact />
          </span>
          <%!-- Round 37 (item 3): one column per kind of final part, so they align. --%>
          <span :for={kind <- @cols} class="flex justify-end" data-col={kind}>
            <span
              :for={{^kind, n, vp} <- Enum.filter(row.parts, &(elem(&1, 2) > 0))}
              class="final-part inline-flex items-center rounded-full bg-parchment-light/80 px-1 text-xs font-bold tabular-nums ring-1 ring-ink/10"
              title={part_text(kind, n) <> " → #{vp} VP"}
              data-part={kind}
            >
              <.piece_icon name={part_icon(kind)} class={["size-3", part_ink(kind)]} />+{vp}
            </span>
          </span>
          <span class="flex items-center justify-end text-lg leading-none font-extrabold tabular-nums">
            <span
              class="final-count min-w-[3ch] text-right"
              style={"--n: #{row.vp}; --from: #{row.from_vp}"}
              data-role="final-vp"
              data-from={row.from_vp}
            ><span class="sr-only">{row.vp} VP</span></span>
          </span>
        </li>
      </ol>
    </section>
    """
  end

  @doc """
  The contextual button area at the game's end: Play again (`GameServer.play_again/2`,
  the same table again), Lobby, and Share as a small third button (the result as one
  line, app.js `quacks:share`).
  """
  attr :game, Game, required: true
  attr :names, :map, required: true
  attr :share_url, :string, default: nil

  def final_actions(assigns) do
    ~H"""
    <section
      class="flex gap-2 *:min-h-12 *:touch-manipulation"
      aria-label="Game over"
      data-role="game-over-actions"
    >
      <.button
        phx-click="lobby"
        variant={:secondary}
        class="flex-1 text-base"
        data-role="return-to-lobby"
      >
        Lobby
      </.button>
      <.button
        :if={@share_url}
        phx-click={
          JS.dispatch("quacks:share",
            detail: %{text: share_text(@game, @names), url: @share_url}
          )
        }
        variant={:secondary}
        class="shrink-0 px-3"
        aria-label="Share the result"
        data-role="share-result"
      >
        <.icon name="hero-share" class="size-5" />
      </.button>
      <.button
        phx-click="play_again"
        variant={:primary}
        class="w-1/2 text-base"
        data-role="play-again"
      >
        Play again
      </.button>
    </section>
    """
  end

  # Round 37 (item 3): the final parts' columns that some row has.
  defp final_columns(rows) do
    kinds = for row <- rows, {kind, _n, vp} <- row.parts, vp > 0, into: MapSet.new(), do: kind
    Enum.filter([:coins, :rubies, :pennies], &(&1 in kinds))
  end

  # Round 37 (item 3): how many places each row moved up from the round-9 order
  # (most VP first, then the lower seat) to the final one: the row starts there
  # and moves to its final place once the VP have counted up (app.css).
  defp shifts(rows) do
    before =
      rows
      |> Enum.sort_by(&{-&1.from_vp, &1.seat})
      |> Enum.with_index()
      |> Map.new(fn {row, i} -> {row.seat, i} end)

    rows
    |> Enum.with_index()
    |> Map.new(fn {row, i} -> {row.seat, before[row.seat] - i} end)
  end

  # Round 29 (F3): the chart marks this browser's own row.
  defp you_tag(assigns) do
    ~H"""
    <span
      class="shrink-0 rounded-full bg-gold px-1.5 text-[0.65rem] leading-4 font-bold tracking-wider text-ink uppercase"
      data-role="you"
    >
      you
    </span>
    """
  end

  @doc "What Share sends: the places and their VP, one line."
  @spec share_text(Game.t(), map) :: String.t()
  def share_text(game, names) do
    case Reveal.final_rows(game) do
      [%{seat: seat, vp: vp}] ->
        "#{name(names, seat)} brewed #{vp} VP in Quacks."

      rows ->
        places =
          Enum.map_join(rows, ", ", fn r -> "#{r.place}. #{name(names, r.seat)} #{r.vp} VP" end)

        "Quacks of Quedlinburg: #{places}."
    end
  end

  defp win_title([seat], seat, _names), do: "You win!"
  defp win_title([seat], _me, names), do: "#{name(names, seat)} wins!"

  defp win_title(seats, me, names) do
    if me in seats,
      do: "You share the win!",
      else: "#{Enum.map_join(seats, " and ", &name(names, &1))} share the win!"
  end

  defp part_text(:coins, n), do: "#{n} #{if n == 1, do: "coin", else: "coins"}"
  defp part_text(:rubies, n), do: "#{n} #{if n == 1, do: "ruby", else: "rubies"}"
  defp part_text(:pennies, _n), do: "Witch pennies"

  defp part_icon(:coins), do: :coin
  defp part_icon(:rubies), do: :ruby
  defp part_icon(:pennies), do: :penny

  defp part_ink(:coins), do: "text-gold"
  defp part_ink(:rubies), do: "text-ruby"
  defp part_ink(:pennies), do: "text-ink-soft"

  defp name(names, seat), do: Map.get(names, seat, Quacks.GameServer.default_name(seat))
end
