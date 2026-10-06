defmodule QuacksWeb.Reveal do
  @moduledoc """
  The reveal overlay's slides (round 14): what the round showed, one slide at a
  time. Pure functions over the game; the data comes from `QuacksWeb.Replay`'s
  lines (`beats/3`, `updates/2`) and the log, never from new engine data.

  A *moment* is a point of the game with something to reveal (`moment/1`):

  - `{:card, round}`: a new fortune teller card (the round's start): one slide;
  - `{:results, round}`: the evaluation (the shop phase began): every seat's bonus
    die, one slide per book and seat with a result, then one results slide (round
    18: a compact table, one row per seat in VP order: the space, coins, VP, ruby,
    die and pot chips; the other results in a closed "Details") and one standings
    slide (the totals; the rows glide from the old order to the new one);
  - `{:final, 9}`: the game is over: the final coins, rubies and pennies, then the
    podium.

  `slides/2` builds the slide list of the game's moment; `GameLive` shows it in
  the overlay and keeps `%{key, slides, index}` per browser. Every slide carries
  its `gains` (`%{seat => {vp, rubies}}`) and the `standings` after it (round 16:
  the running results strip), so the overlay needs no other state.
  """

  alias Quacks.Game
  alias Quacks.Game.Evaluation
  alias Quacks.Rules.PotTrack
  alias QuacksWeb.Replay

  @type moment :: {:card | :results | :final, 1..9}

  @type slide :: %{required(:kind) => atom, optional(atom) => term}

  # Book slides come in the board's order (round 4: green, black, purple).
  @books [:green, :black, :purple]

  # How long a slide stays in Auto mode at Normal speed, in ms.
  @durations %{
    card: 3500,
    die: 2600,
    book: 2600,
    results: 5000,
    standings: 3500,
    final: 3500,
    podium: 5000
  }

  # The speeds of the menu and their factor on the slide times and the CSS beats.
  @speeds [normal: 1.0, slow: 1.6, slower: 2.5]
  # The CSS beat step at Normal speed, ms (`--beat-ms`, app.css).
  @beat_ms 450

  @doc "The speeds of the menu's Speed setting, slowest last."
  @spec speeds() :: [atom]
  def speeds, do: Keyword.keys(@speeds)

  @doc "The factor of `speed` on the slide times and the CSS beats."
  @spec factor(atom) :: float
  def factor(speed), do: Keyword.fetch!(@speeds, speed)

  @doc "The CSS beat step of `speed` in ms (`--beat-ms` on `<html>`)."
  @spec beat_ms(atom) :: pos_integer
  def beat_ms(speed), do: round(@beat_ms * factor(speed))

  @doc """
  The game's moment, or nil: the results while the shop phase runs, the final
  scoring once the game is over, else the round's new card (when there is one).
  """
  @spec moment(Game.t()) :: moment | nil
  def moment(%Game{phase: :shopping, round: round}), do: {:results, round}
  def moment(%Game{phase: :over}), do: {:final, 9}
  def moment(%Game{phase: :patient_choice}), do: nil
  def moment(%Game{fortune_card: nil}), do: nil
  def moment(%Game{round: round}), do: {:card, round}

  @doc """
  The slides of the game's moment, as `seat` sees them (its own book lines
  first among equals). Empty without a moment.
  """
  @spec slides(Game.t(), Game.seat()) :: [slide]
  def slides(game, seat) do
    case moment(game) do
      {:card, round} ->
        running([%{kind: :card, round: round, card: game.fortune_card}], now(game))

      {:results, round} ->
        game |> results(seat, round) |> running(before_results(game))

      {:final, _} ->
        game |> final() |> then(fn slides -> running(slides, before_final(game, slides)) end)

      nil ->
        []
    end
  end

  @doc "How long `slide` stays in Auto mode, in ms, at speed `factor` (1, 1.6, 2.5)."
  @spec duration(slide, number) :: pos_integer
  def duration(%{kind: kind}, factor), do: round(Map.fetch!(@durations, kind) * factor)

  # -- the evaluation ------------------------------------------------------------------

  defp results(game, seat, round) do
    # Seat order, starting with this browser's seat.
    seats = rotate(game.seats, seat)
    lines = Map.new(game.seats, &{&1, Replay.beats(game, &1)})

    dice =
      for s <- game.seats, line <- lines[s], line.kind == :die do
        %{
          kind: :die,
          seat: s,
          face: line.face,
          text: line.text,
          vp: line.vp,
          rubies: line.rubies,
          gains: %{s => {line.vp, line.rubies}}
        }
      end

    books =
      for book <- @books, s <- seats, (mine = Enum.filter(lines[s], &(&1.kind == book))) != [] do
        book_slide(game, s, book, mine)
      end

    dice ++ books ++ [results_slide(game, lines, round), standings_slide(game, round)]
  end

  defp book_slide(game, seat, book, lines) do
    drawn = Game.player(game, seat).drawn
    marks = lines |> Enum.flat_map(& &1.marks) |> Enum.uniq()

    %{
      kind: :book,
      book: book,
      seat: seat,
      set: Map.get(game.sets, book, 1),
      chips: for({chip, index} <- Enum.reverse(drawn), index in marks, do: chip),
      lines: Enum.map(lines, & &1.text),
      vp: lines |> Enum.map(& &1.vp) |> Enum.sum(),
      rubies: lines |> Enum.map(& &1.rubies) |> Enum.sum(),
      droplet: Enum.count(marks, &(&1 == :droplet)),
      compare: if(book == :black, do: black_counts(game, seat), else: []),
      pot: pot_counts(game, seat)
    }
    |> then(&Map.put(&1, :gains, %{seat => {&1.vp, &1.rubies}}))
  end

  # The black, green and purple chips in `seat`'s pot this round.
  defp pot_counts(game, seat), do: pot_counts(game, seat, @books)

  defp pot_counts(game, seat, colours) do
    chips = Game.pot_chips(game, seat)
    for colour <- colours, do: {colour, Enum.count(chips, &match?({^colour, _}, &1))}
  end

  # The results table's chip columns: green, black, purple, and locoweed when it can
  # be in a bag (The Alchemists, or a locoweed book).
  defp table_colours(game) do
    if Game.expansion?(game, :alchemists) or game.sets[:locoweed] != nil,
      do: [:green, :black, :purple, :locoweed],
      else: [:green, :black, :purple]
  end

  # Black book I compares the black chips with `Evaluation.targets/2` (both
  # neighbours, or the players ranked above): `[{seat, count}]`, this seat first. The
  # standings are the ones before this round's results (`Replay.before/2`). Solo
  # has nobody to compare with.
  defp black_counts(%Game{seats: [_]}, _seat), do: []

  defp black_counts(game, seat) do
    targets = game |> before_game() |> Evaluation.targets(seat)
    for s <- [seat | targets], do: {s, blacks(game, s)}
  end

  # The game with every seat's VP and rubies as they were before the round's results.
  defp before_game(game) do
    Enum.reduce(before_results(game), game, fn {s, {vp, rubies}}, g ->
      Game.update_player(g, s, &%{&1 | vp: vp, rubies: rubies})
    end)
  end

  defp blacks(game, seat),
    do: Enum.count(Game.player(game, seat).drawn, &match?({{:black, _}, _}, &1))

  # The round's results in one slide (round 16, a table since round 18), one row per
  # seat in VP order: where its pot ended, the coins, the VP and ruby of the space
  # (an exploded seat took the VP or the coins), the bonus die faces, the update
  # chips, the chips in its pot, and the other results (cards, essence, witches,
  # ...) as lines for the "Details". `gains` is what this slide adds to the running
  # results: the space and the other results.
  defp results_slide(game, lines, round) do
    colours = table_colours(game)

    rows =
      for s <- standings_of(now(game)) do
        p = Game.player(game, s)
        index = Game.scoring_index(game, s)
        space = Enum.filter(lines[s], &(&1.kind == :space))
        extra = Enum.filter(lines[s], &(&1.kind in [:card, :essence, :other]))

        %{
          seat: s,
          space: index,
          coins: if(p.explosion_choice == :vp, do: 0, else: PotTrack.at(index).coins),
          vp: sum(space, :vp),
          ruby: Enum.any?(space, &(&1.rubies > 0)),
          exploded: p.exploded?,
          choice: p.explosion_choice,
          updates: Replay.updates(game, s),
          die: for(line <- lines[s], line.kind == :die, do: line.face),
          pot: pot_counts(game, s, colours),
          total: p.vp,
          extra: for(line <- extra, do: Map.take(line, [:kind, :text, :vp, :rubies])),
          gain: {sum(space ++ extra, :vp), sum(space ++ extra, :rubies)}
        }
      end

    %{
      kind: :results,
      round: round,
      rows: rows,
      gains: Map.new(rows, &{&1.seat, &1.gain})
    }
  end

  # The standings after the round (round 18): every seat's total VP and rubies, before
  # and after the round's results, with its rank before (`from_rank`) and after
  # (`rank`, 0 is first). The rows stay in seat order: the overlay moves each row to
  # its rank with CSS, from the old rank to the new one.
  defp standings_slide(game, round) do
    before = before_results(game)
    totals = now(game)
    from_ranks = ranks(before)
    to_ranks = ranks(totals)

    rows =
      for s <- game.seats do
        {from_vp, from_rubies} = before[s]
        {vp, rubies} = totals[s]

        %{
          seat: s,
          from_rank: from_ranks[s],
          rank: to_ranks[s],
          from_vp: from_vp,
          vp: vp,
          from_rubies: from_rubies,
          rubies: rubies
        }
      end

    %{kind: :standings, round: round, last: round == 9, rows: rows}
  end

  defp ranks(totals), do: totals |> standings_of() |> Enum.with_index() |> Map.new()

  defp sum(lines, key), do: lines |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

  # -- the running results (round 16) -------------------------------------------------

  # Every seat's `{vp, rubies}` now.
  defp now(game),
    do: Map.new(game.seats, &{&1, {Game.player(game, &1).vp, Game.player(game, &1).rubies}})

  # Every seat's `{vp, rubies}` before this round's results (`Replay.before/2`).
  defp before_results(game) do
    Map.new(game.seats, fn s ->
      %{vp: vp, rubies: rubies} = Replay.before(game, s)
      {s, {vp, rubies}}
    end)
  end

  # Before the final scoring: the final slide's VP taken off.
  defp before_final(game, [%{kind: :final, rows: rows} | _]) do
    Map.new(rows, fn row ->
      {row.seat, {row.vp - row.coins_vp - row.rubies_vp - row.pennies_vp, row.rubies}}
    end)
    |> then(&Map.merge(now(game), &1))
  end

  # Each slide gets `standings`: `[%{seat, vp, gain}]` after the slide, in VP order;
  # `gain` is the VP this slide added (0: nothing).
  defp running(slides, base) do
    slides
    |> Enum.map_reduce(base, fn slide, totals ->
      gains = Map.get(slide, :gains, %{})

      totals = Enum.reduce(gains, totals, &add_gain/2)

      rows =
        for s <- standings_of(totals) do
          %{seat: s, vp: elem(totals[s], 0), gain: gains |> Map.get(s, {0, 0}) |> elem(0)}
        end

      {slide |> Map.put_new(:gains, %{}) |> Map.put(:standings, rows), totals}
    end)
    |> elem(0)
  end

  defp add_gain({s, {vp, rubies}}, totals),
    do: Map.update(totals, s, {vp, rubies}, fn {v, r} -> {v + vp, r + rubies} end)

  # Seats in VP order: most VP first, a tie to fewer rubies, then the lower seat (the
  # order of `Quacks.Game.Evaluation.standings/1`).
  defp standings_of(totals) do
    totals
    |> Map.keys()
    |> Enum.sort_by(fn s ->
      {v, r} = totals[s]
      {-v, r, s}
    end)
  end

  # -- the final scoring ---------------------------------------------------------------

  defp final(game) do
    rows =
      for s <- game.seats do
        {coins, coins_vp, rubies, rubies_vp} =
          Enum.find_value(game.log, {0, 0, 0, 0}, fn
            {^s, {:final_conversion, c, cvp, r, rvp}} -> {c, cvp, r, rvp}
            _entry -> nil
          end)

        pennies =
          Enum.find_value(game.log, 0, fn
            {^s, {:pennies, vp}} -> vp
            _entry -> nil
          end)

        %{
          seat: s,
          coins: coins,
          coins_vp: coins_vp,
          rubies: rubies,
          rubies_vp: rubies_vp,
          pennies_vp: pennies,
          vp: Game.player(game, s).vp
        }
      end

    ranked = game |> Game.score() |> Enum.sort_by(fn {seat, vp} -> {-vp, seat} end)
    places = for {seat, vp} <- ranked, do: {seat, vp, 1 + Enum.count(ranked, &(elem(&1, 1) > vp))}

    gains = Map.new(rows, &{&1.seat, {&1.coins_vp + &1.rubies_vp + &1.pennies_vp, 0}})
    [%{kind: :final, rows: rows, gains: gains}, %{kind: :podium, ranked: places}]
  end

  defp rotate(seats, seat) do
    {before, rest} = Enum.split_while(seats, &(&1 != seat))
    rest ++ before
  end
end
