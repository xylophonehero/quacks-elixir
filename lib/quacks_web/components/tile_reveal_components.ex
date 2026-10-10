defmodule QuacksWeb.TileRevealComponents do
  @moduledoc """
  The evaluation on the player tiles (`QuacksWeb.TileReveal`; round 27, the phone
  default since round 28). `tile_news/1` fills a tile's bottom line while a step
  plays and after a buy in the shop (`TileComponents.player_chip/1` swaps the line
  to the news and back, app.css `.tile-line`). `tile_stage/1` names the step,
  with Skip and Next (Step mode), in the bar where Stop and Draw sit (round 29). Nothing hangs
  outside a tile, so neither the tiles nor the pot move.
  """
  use Phoenix.Component

  import QuacksWeb.Icons, only: [ingredient_icon: 1, piece_icon: 1]
  import QuacksWeb.CoreComponents, only: [button: 1]
  import QuacksWeb.ChipComponents, only: [chip: 1, die: 1, die_face: 1, seat_bg: 1]

  alias Quacks.Rules.Fortune
  alias QuacksWeb.TileReveal

  attr :items, :list, required: true, doc: "`QuacksWeb.TileReveal.news/3`'s items"

  @doc """
  Round 28 (R2): the news on a tile's bottom line (`TileComponents.player_chip/1`
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

  # Round 29 (B2): a draw while the round brews. The newest (`age` 0) glows
  # once (`beat-glow`); the older ones are dimmer. Round 31: they overlap by 4 px
  # (the newest on top), so the line has room for the black and white counts.
  defp badge(%{badge: {:drew, chip, age, id}} = assigns) do
    assigns = assign(assigns, chip: chip, age: age, id: id)

    ~H"""
    <span
      id={"tile-draw-#{@id}"}
      class={[
        "tile-draw relative shrink-0 rounded-full ring-1 ring-black/40",
        @age > 0 && "-ml-2 opacity-70"
      ]}
      style={"z-index: #{10 - @age}"}
      data-gain="drew"
      data-age={@age}
    >
      <.chip chip={@chip} size={:xs} />
      <span :if={@age == 0} class="tile-draw-glow" aria-hidden="true"></span>
    </span>
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

  # Round 30: a chip from a card that draws chips (Flea Market: the traded chip
  # first; Less is More: the blue 2).
  defp badge(%{badge: {:card, card, traded, got}} = assigns) do
    assigns =
      assign(assigns, traded: traded, got: got, name: Fortune.card(card).name)

    ~H"""
    <span class="flex items-center gap-px" title={@name} data-gain="card">
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
  attr :close_label, :string, default: "Done", doc: "the button on the last step"
  attr :waiting, :boolean, default: false, doc: "the next step waits for other players"

  @doc """
  The steps that play on the tiles, in the bar where Stop and Draw sit (round 29).
  Round 35: the bar names the step on show (`reveal.index - 1`, the step the
  results stage shows), with its picture (`step_icon/1`) and "Step N of M" small.
  On the last step ("Round scored") the button closes (`close_label`). While the
  next step waits for other players (`waiting`), Next is off and says so. It keeps
  the bar's height (`min-h-12`), so the pot does not move.
  """
  def tile_stage(assigns) do
    %{slides: slides, index: index} = assigns.reveal
    count = length(slides)

    assigns =
      assign(assigns,
        slide: if(index > 0, do: Enum.at(slides, index - 1)),
        count: count,
        last: index >= count
      )

    ~H"""
    <section
      id="tile-stage"
      class="flex min-h-12 items-center gap-2 *:min-h-12 *:touch-manipulation"
      aria-label="Round results"
      data-role="tile-stage"
      data-kind={@slide && @slide.kind}
      data-index={@reveal.index}
    >
      <p class="flex min-w-0 flex-1 items-center gap-2 leading-tight" aria-live="polite">
        <span
          :if={@slide}
          id={"tile-step-icon-#{@reveal.index}"}
          class="tile-step-icon grid size-9 shrink-0 place-items-center"
          data-role="tile-step-icon"
        >
          <.step_icon slide={@slide} />
        </span>
        <span class="flex min-w-0 flex-col">
          <span class="truncate font-semibold text-parchment" data-role="tile-step">
            {if @slide, do: TileReveal.label(@slide), else: "Round results"}
          </span>
          <span class="text-tag text-parchment-dim tabular-nums">
            Step {max(@reveal.index, 1)} of {@count}
          </span>
        </span>
      </p>
      <.button
        :if={!@last}
        type="button"
        phx-click="reveal_close"
        variant={:secondary}
        class="shrink-0 px-3 sm:px-4"
        data-role="tile-skip"
      >
        Skip
      </.button>
      <.button
        :if={@mode == :step or @last or @waiting}
        type="button"
        phx-click="reveal_next"
        variant={:primary}
        class="w-1/3 shrink-0 sm:w-2/5"
        disabled={@waiting}
        data-role="tile-next"
      >
        {cond do
          @waiting -> "Waiting…"
          @last -> @close_label
          true -> "Next"
        end}
      </.button>
    </section>
    """
  end

  attr :rows, :list, required: true, doc: "`QuacksWeb.TileReveal.stage_rows/3`"
  attr :slide, :map, required: true, doc: "the step on show"
  attr :index, :integer, required: true, doc: "`reveal.index`: a new step gets new ids"
  attr :names, :map, required: true
  attr :seat, :integer, default: nil, doc: "this browser's seat"
  attr :collapsed, :boolean, default: false, doc: "a decision needs the board: one line"

  attr :note, :any,
    default: nil,
    doc: "`{title, hint}`: the decision, on the collapsed line in place of the step's"

  @doc """
  Round 35 (direction A): the results stage, a parchment panel in the band above
  the bar's buttons. One row per player for the step on show, in one column for
  every player count: the colour disc and initial (and the short name when it
  fits), the reason (`why`) and, at the row's end, the result (`got`), both as
  icons where possible. A row with no result fades. The bonus die rolls at the end
  of each roller's row. While a decision needs the pot or the test tubes
  (`collapsed`), only the title line shows. It floats over the pot's lower band
  (app.css `.results-stage`), so the pot never moves.
  """
  def results_stage(assigns) do
    ~H"""
    <section
      id="results-stage"
      class="results-stage"
      aria-label="Step results"
      data-role="results-stage"
      data-kind={@slide.kind}
      data-collapsed={@collapsed && "true"}
    >
      <header class="flex items-center gap-1.5 px-1 pb-0.5">
        <span class="grid size-6 shrink-0 place-items-center [&_.chip-token]:size-6!">
          <.step_icon slide={@slide} small />
        </span>
        <span
          class="font-hand text-lg leading-none font-bold whitespace-nowrap"
          data-role="stage-title"
        >
          {if @collapsed && @note, do: elem(@note, 0), else: TileReveal.label(@slide)}
        </span>
        <span class="ml-auto truncate text-xs text-ink-soft" data-role="stage-hint">
          {if @collapsed && @note, do: elem(@note, 1), else: hint(@slide)}
        </span>
      </header>
      <.stage_list
        :if={!@collapsed}
        id={"stage-rows-#{@index}"}
        rows={@rows}
        cols={TileReveal.columns(@rows)}
        names={@names}
        seat={@seat}
        row_role="stage-row"
        row_id={fn row -> "stage-row-#{@index}-#{row.seat}" end}
        row_attrs={
          fn row ->
            %{"data-none" => row.none && "true", "data-lead" => row.lead && "true"}
          end
        }
      >
        <:why :let={row}>
          <.cell :for={cell <- row.why} cell={cell} names={@names} />
        </:why>
        <:got :let={{row, col, i}}>
          <.cell :for={cell <- got_in(row.got, col, i)} cell={cell} names={@names} i={i} />
        </:got>
      </.stage_list>
    </section>
    """
  end

  # Round 37: a row's result in column `col` (the `i`-th); a row still choosing
  # shows "choosing…" in the first column.
  defp got_in(got, col, i) do
    Enum.filter(got, fn cell ->
      kind = TileReveal.cell_kind(cell)
      kind == col or (kind == :choosing and i == 0)
    end)
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "maps with `seat`, optional `none`, `lead`, `shift`"
  attr :cols, :list, required: true, doc: "the result columns, one cell each per row"
  attr :names, :map, required: true
  attr :seat, :integer, default: nil, doc: "this browser's seat (its row has a ring)"
  attr :you, :boolean, default: false, doc: "this browser's row says \"You\""
  attr :row_role, :string, required: true
  attr :row_id, :any, required: true, doc: "fn row -> the row's DOM id"
  attr :row_attrs, :any, default: nil, doc: "fn row -> more attributes for the row"
  attr :row_class, :any, default: nil, doc: "fn row -> more classes for the row"
  slot :why, required: true, doc: "the reason, `:let={row}`"
  slot :got, required: true, doc: "one result column, `:let={{row, col, index}}`"

  @doc """
  Round 37 (items 1-3): the one row layout of every results panel (the
  evaluation steps, the recap, the everyone-cards). A grid with one column each
  for the seat disc, the name, the reason and every result column (`cols`); each
  row is a subgrid of it (app.css `.stage-grid`), so the counts, chips and
  numbers of all rows stand in one line, whatever the names' lengths. Numbers
  are tabular. A long name takes two lines (round 41), so names that start the
  same stay apart; the row keeps its height. A row with `shift` (`Round scored`) moves from its old place to
  its new one (FLIP in CSS: `.stage-shift`, off for reduced motion).
  """
  def stage_list(assigns) do
    ~H"""
    <ol id={@id} class="stage-grid" style={"--cols: #{max(length(@cols), 1)}"} data-role="stage-rows">
      <li
        :for={row <- @rows}
        id={@row_id.(row)}
        class={[
          "stage-row rounded-md px-1 py-0.5",
          row[:none] && "opacity-45",
          row[:lead] && "bg-gold/35",
          row.seat == @seat && "ring-1 ring-gold-deep/70",
          row[:shift] not in [nil, 0] && "stage-shift",
          @row_class && @row_class.(row)
        ]}
        style={row[:shift] not in [nil, 0] && "--shift: #{row.shift}"}
        data-role={@row_role}
        data-seat={row.seat}
        data-shift={row[:shift]}
        {(@row_attrs && @row_attrs.(row)) || %{}}
      >
        <span
          class={[
            "grid size-5 shrink-0 place-items-center rounded-full text-[10px] leading-none font-extrabold text-ink ring-1 ring-black/40",
            seat_bg(row.seat)
          ]}
          aria-hidden="true"
          data-role="seat-disc"
        >
          {initial(name(@names, row.seat))}
        </span>
        <span
          class="stage-name line-clamp-2 text-xs leading-3 font-semibold break-words"
          title={name(@names, row.seat)}
          data-role="stage-name"
        >
          {if @you and row.seat == @seat, do: "You", else: name(@names, row.seat)}
        </span>
        <span class="flex min-w-0 items-center gap-1 text-sm" data-role="stage-why">
          {render_slot(@why, row)}
        </span>
        <span
          :for={{col, i} <- Enum.with_index(if(@cols == [], do: [nil], else: @cols))}
          class="stage-col flex items-center justify-end gap-1 text-base leading-none font-extrabold tabular-nums"
          data-role="stage-got"
          data-col={col}
        >
          {render_slot(@got, {row, col, i})}
        </span>
      </li>
    </ol>
    """
  end

  defp hint(%{kind: :die}), do: "furthest in the pot rolls"
  defp hint(%{kind: :book, book: :black}), do: "more black than neighbours"
  defp hint(%{kind: :space}), do: "coins · VP · ruby"
  defp hint(%{kind: :standings}), do: "this round · total"
  defp hint(%{kind: :shop}), do: "what everyone bought"
  defp hint(_slide), do: nil

  defp name(names, seat), do: Map.get(names || %{}, seat) || "Player #{seat + 1}"

  defp initial(name),
    do: name |> String.trim() |> String.first() |> Kernel.||("?") |> String.upcase()

  attr :cell, :any, required: true
  attr :names, :map, default: %{}
  attr :i, :integer, default: 0

  defp cell(%{cell: {:count, n, colour}} = assigns) do
    assigns = assign(assigns, n: n, colour: colour)

    ~H"""
    <span class="flex items-center gap-0.5 font-semibold" data-cell="count">
      {@n}<.chip chip={{@colour, nil}} size={:sm} />
    </span>
    """
  end

  defp cell(%{cell: {:beats, seats, how}} = assigns) do
    assigns = assign(assigns, seats: seats, how: how)

    ~H"""
    <span class="flex items-center gap-0.5 text-xs font-semibold" data-cell="beats">
      {if @how == :tie, do: "=", else: ">"}
      <%= if @how == :both do %>
        both
      <% else %>
        <span
          :for={s <- @seats}
          class={["size-2.5 rounded-full ring-1 ring-black/30", seat_bg(s)]}
          title={name(@names, s)}
        />
      <% end %>
    </span>
    """
  end

  defp cell(%{cell: {:chips, chips}} = assigns) do
    assigns = assign(assigns, chips: Enum.take(chips, 4), more: length(chips) > 4)

    ~H"""
    <span class="flex items-center gap-0.5" data-cell="chips">
      <.chip :for={chip <- @chips} chip={chip} size={:xs} />
      <span :if={@more} class="text-xs">…</span>
    </span>
    """
  end

  defp cell(%{cell: {:text, text}} = assigns) do
    assigns = assign(assigns, text: text)

    ~H"""
    <span class="truncate text-xs text-ink-soft italic" data-cell="text">{@text}</span>
    """
  end

  defp cell(%{cell: {:dice, faces}} = assigns) do
    assigns = assign(assigns, faces: Enum.with_index(faces))

    ~H"""
    <span class="flex items-center gap-1" data-cell="dice">
      <span :for={{face, n} <- @faces} class="stage-die" style={"--roll: #{n}"}>
        <.die face={face} />
      </span>
    </span>
    """
  end

  defp cell(%{cell: {:chip, colour}} = assigns) do
    assigns = assign(assigns, colour: colour)

    ~H"""
    <span class="stage-got" data-cell="chip" style={"--got: #{@i}"}>
      <.chip chip={{@colour, nil}} size={:sm} />
    </span>
    """
  end

  defp cell(%{cell: {kind, n}} = assigns) when kind in [:vp, :rubies, :droplet, :coins] do
    assigns = assign(assigns, kind: kind, n: n)

    ~H"""
    <span class="stage-got flex items-center gap-px" data-cell={@kind} style={"--got: #{@i}"}>
      <span :if={@kind != :coins}>+</span>{@n}<.piece_icon
        name={piece_name(@kind)}
        class={["size-4", piece_ink(@kind)]}
      />
    </span>
    """
  end

  defp cell(%{cell: {:gain, n}} = assigns) do
    assigns = assign(assigns, n: n)

    ~H"""
    <span class="flex items-center gap-px text-sm text-ink-soft" data-cell="gain">
      +{@n}<.piece_icon name={:vp} class="size-3.5 text-gold-deep" />
    </span>
    """
  end

  defp cell(%{cell: {:total, n}} = assigns) do
    assigns = assign(assigns, n: n)

    ~H"""
    <span class="flex items-center gap-0.5" data-cell="total">
      <span class="text-sm font-semibold text-ink-soft" aria-hidden="true">→</span>
      <span class="min-w-[3ch] text-right">{@n}</span>
    </span>
    """
  end

  defp cell(%{cell: {:rank, rank}} = assigns) do
    assigns = assign(assigns, rank: rank)

    ~H"""
    <span class="flex items-center gap-1 text-xs font-semibold" data-cell="rank">
      <.piece_icon :if={@rank == 0} name={:vp} class="size-4 text-gold-deep" />
      {ordinal(@rank + 1)}
    </span>
    """
  end

  defp cell(%{cell: :choosing} = assigns) do
    ~H"""
    <span class="animate-pulse font-sans text-xs font-semibold text-ink-soft" data-cell="choosing">
      choosing…
    </span>
    """
  end

  defp piece_name(:rubies), do: :ruby
  defp piece_name(:coins), do: :coin
  defp piece_name(kind), do: kind

  defp piece_ink(:rubies), do: "text-ruby"
  defp piece_ink(:droplet), do: "text-droplet"
  defp piece_ink(_kind), do: "text-gold-deep"

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n), do: "#{n}th"

  attr :slide, :map, required: true
  attr :small, :boolean, default: false

  # Round 31 (item 4): a book step is its chip (the value hidden); the die, the
  # coins, the VP and the rubies their piece icons.
  defp step_icon(%{slide: %{kind: :book, book: colour}} = assigns) do
    assigns = assign(assigns, colour: colour)

    ~H"""
    <span class="contents" data-book={@colour}>
      <.chip chip={{@colour, nil}} size={:md} />
    </span>
    """
  end

  defp step_icon(%{slide: slide} = assigns) do
    assigns = assign(assigns, icon: piece(slide))

    ~H"""
    <span class={[
      "grid place-items-center rounded-full ring-1",
      if(@small,
        do: "size-6 bg-ink/85 ring-black/30",
        else: "size-9 bg-black/30 ring-parchment/20"
      )
    ]}>
      <.piece_icon name={@icon} class={[if(@small, do: "size-4", else: "size-6"), ink(@icon)]} />
    </span>
    """
  end

  defp piece(%{kind: :die}), do: :die
  defp piece(%{kind: :space}), do: :coin
  defp piece(%{kind: :standings}), do: :vp
  defp piece(%{kind: :shop}), do: :bag
  defp piece(_slide), do: :pot

  defp ink(:die), do: "text-parchment-light"
  defp ink(:bag), do: "text-parchment-light"
  defp ink(:ruby), do: "text-ruby-light"
  defp ink(:pot), do: "text-parchment-light"
  defp ink(_gold), do: "text-gold"
end
