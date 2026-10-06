defmodule QuacksWeb.Reveal do
  @moduledoc """
  The reveal overlay's slides (round 14): what the round showed, one slide at a
  time. Pure functions over the game; the data comes from `QuacksWeb.Replay`'s
  lines (`beats/3`, `updates/2`) and the log, never from new engine data.

  A *moment* is a point of the game with something to reveal (`moment/1`):

  - `{:card, round}`: a new fortune teller card (the round's start): one slide;
  - `{:results, round}`: the evaluation (the shop phase began): every seat's bonus
    die, one slide per book and seat with a result, the scoring space, the other
    results (cards, essence, witches, ...) and the round summary;
  - `{:final, 9}`: the game is over: the final coins, rubies and pennies, then the
    podium.

  `slides/2` builds the slide list of the game's moment; `GameLive` shows it in
  the overlay and keeps `%{key, slides, index}` per browser.
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
    scoring: 3500,
    more: 3000,
    summary: 3500,
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
      {:card, round} -> [%{kind: :card, round: round, card: game.fortune_card}]
      {:results, round} -> results(game, seat, round)
      {:final, _} -> final(game)
      nil -> []
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
        %{kind: :die, seat: s, face: line.face, text: line.text, vp: line.vp, rubies: line.rubies}
      end

    books =
      for book <- @books, s <- seats, (mine = Enum.filter(lines[s], &(&1.kind == book))) != [] do
        book_slide(game, s, book, mine)
      end

    more =
      for s <- seats, line <- lines[s], line.kind in [:card, :essence, :other] do
        %{seat: s, kind: line.kind, text: line.text, vp: line.vp, rubies: line.rubies}
      end

    dice ++
      books ++
      [scoring(game, lines)] ++
      if(more == [], do: [], else: [%{kind: :more, rows: more}]) ++
      [summary(game, round)]
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
      compare: if(book == :black, do: black_counts(game, seat), else: [])
    }
  end

  # Black book I compares the black chips with `Evaluation.targets/2` (both
  # neighbours, or the players ranked above): `[{seat, count}]`, this seat first. The
  # standings are the ones before this round's results (`Replay.before/2`). Solo
  # has nobody to compare with.
  defp black_counts(%Game{seats: [_]}, _seat), do: []

  defp black_counts(game, seat) do
    targets = game |> before_results() |> Evaluation.targets(seat)
    for s <- [seat | targets], do: {s, blacks(game, s)}
  end

  # The game with every seat's VP and rubies as they were before the round's results.
  defp before_results(game) do
    Enum.reduce(game.seats, game, fn s, g ->
      %{vp: vp, rubies: rubies} = Replay.before(game, s)
      Game.update_player(g, s, &%{&1 | vp: vp, rubies: rubies})
    end)
  end

  defp blacks(game, seat),
    do: Enum.count(Game.player(game, seat).drawn, &match?({{:black, _}, _}, &1))

  # The scoring space of every seat: where its pot ended, the coins, VP and ruby it
  # paid (an exploded seat took the VP or the coins).
  defp scoring(game, lines) do
    rows =
      for s <- game.seats do
        p = Game.player(game, s)
        index = Game.scoring_index(game, s)
        space = lines[s] |> Enum.filter(&(&1.kind == :space))

        %{
          seat: s,
          space: index,
          coins: if(p.explosion_choice == :vp, do: 0, else: PotTrack.at(index).coins),
          vp: space |> Enum.map(& &1.vp) |> Enum.sum(),
          ruby: Enum.any?(space, &(&1.rubies > 0)),
          exploded: p.exploded?,
          choice: p.explosion_choice
        }
      end

    %{kind: :scoring, round: game.round, rows: rows}
  end

  defp summary(game, round) do
    rows = for s <- game.seats, do: %{seat: s, updates: Replay.updates(game, s)}
    %{kind: :summary, round: round, last: round == 9, rows: rows}
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

    [%{kind: :final, rows: rows}, %{kind: :podium, ranked: places}]
  end

  defp rotate(seats, seat) do
    {before, rest} = Enum.split_while(seats, &(&1 != seat))
    rest ++ before
  end
end
