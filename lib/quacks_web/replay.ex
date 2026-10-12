defmodule QuacksWeb.Replay do
  @moduledoc """
  The step-B replay in the round results (`docs/research/animations.md` §3 B2).
  Pure functions over the game's log: no state, no timers.

  Each result line of a seat gets a *beat*, a number the CSS turns into an
  `animation-delay` (`--beat`). The lines come in engine order (bonus die → chip
  actions → scoring space). The bonus dice of the whole table come first, one
  after the other in seat order; then every seat's other lines start together. A die line takes two beats: the die rolls first, its
  text shows when it lands. Each line also names what it concerns on the pot
  (`marks`): the chips by their space index, `:droplet`, `:ring` (the scoring
  space) or `:essence` (the Alchemists' flask marker). The pot lights those up on
  the same beat.
  """

  alias Quacks.Game
  alias QuacksWeb.GameText

  @typedoc "What a line concerns on the pot: a chip's space index or a marker."
  @type mark :: non_neg_integer | :droplet | :ring | :essence

  @type kind :: :die | :green | :black | :purple | :space | :essence | :card | :other

  @type line :: %{
          beat: non_neg_integer,
          text: String.t(),
          kind: kind,
          vp: non_neg_integer,
          rubies: non_neg_integer,
          face: term | nil,
          marks: [mark],
          book: {atom, pos_integer} | nil
        }

  @doc """
  This round's result lines for `seat`, oldest first, numbered from beat `from`.
  """
  @spec beats(Game.t(), Game.seat(), non_neg_integer) :: [line]
  def beats(game, seat, from \\ 0) do
    # Step A first, for the whole table: the bonus dice roll one after the other in
    # seat order (two beats each), then every seat's other lines start together.
    {dice, rest} = game |> round_entries(seat) |> Enum.split_with(&bonus_die?/1)
    {before, all} = dice_slots(game, seat)

    number(game, seat, dice, from + 2 * before) ++ number(game, seat, rest, from + 2 * all)
  end

  defp number(game, seat, entries, from) do
    entries
    |> Enum.map_reduce(from, fn entry, beat ->
      line = line(game, seat, entry, beat)
      {line, beat + span(line)}
    end)
    |> elem(0)
  end

  defp bonus_die?(entry), do: match?({:bonus_die, _face}, entry)

  # `{dice of the seats before seat, dice of the whole table}` this round.
  defp dice_slots(game, seat) do
    counts =
      Enum.map(game.seats, fn s -> {s, game |> round_entries(s) |> Enum.count(&bonus_die?/1)} end)

    before = counts |> Enum.take_while(fn {s, _n} -> s != seat end) |> Enum.map(&elem(&1, 1))
    {Enum.sum(before), counts |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
  end

  defp span(%{kind: :die}), do: 2
  defp span(_line), do: 1

  @doc "The first free beat after `lines` (`from` when there are none)."
  @spec next_beat([line], non_neg_integer) :: non_neg_integer
  def next_beat(lines, from \\ 0)
  def next_beat([], from), do: from
  def next_beat(lines, _from), do: lines |> List.last() |> then(&(&1.beat + span(&1)))

  @doc """
  `%{mark => beat}`: on which beat each pot mark lights up (its first line). A die
  line lights its marks one beat late, when the die lands.
  """
  @spec highlights([line]) :: %{mark => non_neg_integer}
  def highlights(lines) do
    for line <- lines, mark <- line.marks, reduce: %{} do
      acc -> Map.put_new(acc, mark, line.beat + span(line) - 1)
    end
  end

  @typedoc """
  What moves on the pot on a line's beat: a ruby that flies to the ruby counter, or
  a "+N VP" tag that floats up. `at` is the mark it starts from; `n` numbers the
  rubies of one line (they leave one after the other).
  """
  @type effect :: %{
          kind: :ruby | :vp,
          at: mark,
          beat: non_neg_integer,
          n: non_neg_integer,
          text: String.t()
        }

  @doc """
  The rubies and VP tags of `lines` on the pot (scoring sequence). Black, green,
  purple and scoring-space lines only: a black ruby leaves the droplet, a green or
  purple one its newest chip, the space's own ruby and VP the scoring space. The die
  shows its face in its own strip; card and essence lines have no piece to start
  from. At most 3 rubies per line.
  """
  @spec pot_effects([line]) :: [effect]
  def pot_effects(lines) do
    for %{kind: kind} = line <- lines,
        kind in [:black, :green, :purple, :space],
        effect <- rubies(line) ++ vp_tag(line),
        do: effect
  end

  defp rubies(line) do
    for n <- 0..(min(line.rubies, 3) - 1)//1,
        do: %{kind: :ruby, at: source(line), beat: line.beat, n: n, text: "+1"}
  end

  defp vp_tag(%{vp: 0}), do: []

  defp vp_tag(line),
    do: [%{kind: :vp, at: source(line), beat: line.beat, n: 0, text: "+#{line.vp} VP"}]

  defp source(%{kind: :space}), do: :ring

  defp source(%{kind: :black, marks: marks}),
    do: if(:droplet in marks, do: :droplet, else: hd(marks ++ [:ring]))

  defp source(%{marks: marks}), do: Enum.find(marks, :ring, &is_integer/1)

  @typedoc "An update chip on a name card: what it shows, and on which beat it lands."
  @type update :: %{
          kind: :exploded | :stopped | :vp | :rubies | :droplet,
          text: String.t(),
          beat: non_neg_integer
        }

  @doc """
  The update chips of `seat`'s name card for the round that just ended, in beat
  order: first how the brew ended ("exploded" or "stopped", beat 0), then the VP,
  the rubies and the droplet moves of the round, each a sum that lands on the beat
  of its last line (so it is complete when it shows). Nothing gained, no chip.
  """
  @spec updates(Game.t(), Game.seat()) :: [update]
  def updates(game, seat) do
    lines = beats(game, seat)
    ended = if Game.player(game, seat).exploded?, do: :exploded, else: :stopped

    sums = [
      sum(lines, :vp, & &1.vp, &"+#{&1} VP"),
      sum(lines, :rubies, & &1.rubies, &"+#{&1}"),
      sum(lines, :droplet, &Enum.count(&1.marks, fn mark -> mark == :droplet end), &"+#{&1}")
    ]

    [%{kind: ended, text: Atom.to_string(ended), beat: 0} | Enum.reject(sums, &is_nil/1)]
    |> Enum.sort_by(& &1.beat)
  end

  defp sum(lines, kind, count, text) do
    case for(line <- lines, (n = count.(line)) > 0, do: {n, line.beat + span(line) - 1}) do
      [] ->
        nil

      parts ->
        %{
          kind: kind,
          text: text.(parts |> Enum.map(&elem(&1, 0)) |> Enum.sum()),
          beat: parts |> List.last() |> elem(1)
        }
    end
  end

  @doc """
  `seat`'s VP and rubies before this round's result lines: the values its counters
  show until their beat while the replay plays (they tick to the real values then).
  """
  @spec before(Game.t(), Game.seat()) :: %{vp: non_neg_integer, rubies: non_neg_integer}
  def before(game, seat) do
    lines = beats(game, seat)
    p = Game.player(game, seat)

    %{
      vp: max(p.vp - (lines |> Enum.map(& &1.vp) |> Enum.sum()), 0),
      rubies: max(p.rubies - (lines |> Enum.map(& &1.rubies) |> Enum.sum()), 0)
    }
  end

  @doc "The beat the last update chip of any seat lands on (the end of the replay)."
  @spec last_beat(Game.t()) :: non_neg_integer
  def last_beat(game) do
    game.seats
    |> Enum.flat_map(&updates(game, &1))
    |> Enum.map(& &1.beat)
    |> Enum.max(fn -> 0 end)
  end

  # The log entries of `seat` since the round began that are results.
  defp round_entries(game, seat) do
    game.log
    |> Enum.take_while(&(not match?({:round_end, _}, &1)))
    |> Enum.reverse()
    |> Enum.flat_map(fn
      {^seat, entry} -> if gain(entry), do: [entry], else: []
      _other -> []
    end)
  end

  defp line(game, seat, entry, beat) do
    {vp, rubies} = gain(entry)
    {kind, marks} = concerns(entry, Game.player(game, seat).drawn)

    %{
      beat: beat,
      text: GameText.label(entry),
      kind: kind,
      vp: vp,
      rubies: rubies,
      face: face(entry),
      marks: marks,
      book: book(entry)
    }
  end

  # The book a line comes from (round 20: the reveal's evaluation slides), or nil.
  defp book({:effect, {colour, set}, _detail}), do: {colour, set}
  defp book(_entry), do: nil

  defp face({:bonus_die, face}), do: face
  defp face({:effect, {:green, _}, {:bonus_die, face}}), do: face
  defp face(_entry), do: nil

  # The kind of a line and its marks; `drawn` is `[{chip, index}]`, newest first.
  defp concerns({:bonus_die, face}, _drawn), do: {:die, die_marks(face)}

  defp concerns({:effect, {:green, _}, {:bonus_die, face}}, drawn),
    do: {:die, last_two(drawn, :green) ++ die_marks(face)}

  defp concerns({:green_rubies, _}, drawn), do: {:green, last_two(drawn, :green)}
  defp concerns({:effect, {:green, _}, _}, drawn), do: {:green, last_two(drawn, :green)}
  defp concerns({:purple, 3, _}, drawn), do: {:purple, all(drawn, :purple) ++ [:droplet]}
  defp concerns({:purple, _, _}, drawn), do: {:purple, all(drawn, :purple)}
  defp concerns({:effect, {:purple, _}, _}, drawn), do: {:purple, all(drawn, :purple)}
  defp concerns({:black, _}, drawn), do: {:black, all(drawn, :black) ++ [:droplet]}

  defp concerns({:effect, {:black, _}, payoff}, drawn) when payoff in [:droplet, :droplet_ruby],
    do: {:black, all(drawn, :black) ++ [:droplet]}

  defp concerns({:effect, {:black, _}, _}, drawn), do: {:black, all(drawn, :black)}

  defp concerns({:pot_ruby, _}, _drawn), do: {:space, [:ring]}
  defp concerns({:pot_vp, _, _}, _drawn), do: {:space, [:ring]}
  defp concerns({:essence, _, _}, _drawn), do: {:essence, [:essence]}
  defp concerns({:essence_vp, _}, _drawn), do: {:essence, [:essence]}
  defp concerns({:essence_bonus, _}, _drawn), do: {:essence, [:essence]}
  defp concerns({:fortune, _, _}, _drawn), do: {:card, []}
  defp concerns(_entry, _drawn), do: {:other, []}

  defp die_marks(:droplet), do: [:droplet]
  defp die_marks(_face), do: []

  # Green books read the last two chips (the rule of `Evaluation`'s `last_two/2`).
  defp last_two(drawn, colour), do: drawn |> Enum.take(2) |> all(colour)
  defp all(drawn, colour), do: for({{^colour, _}, index} <- drawn, do: index)

  @doc """
  `{vp, rubies}` a log entry gave, or nil when it is not a result. The bonus die
  always counts as a result, whatever its face; so does the hawkmoth's droplet.
  """
  @spec gain(term) :: {non_neg_integer, non_neg_integer} | nil
  def gain({:bonus_die, {:vp, n}}), do: {n, 0}
  def gain({:bonus_die, :ruby}), do: {0, 1}
  def gain({:bonus_die, _face}), do: {0, 0}
  def gain({:green_rubies, n}), do: {0, n}
  def gain({:purple, 1, _}), do: {1, 0}
  def gain({:purple, 2, _}), do: {1, 1}
  def gain({:purple, 3, _}), do: {2, 0}
  def gain({:black, :droplet}), do: {0, 0}
  def gain({:black, :droplet_ruby}), do: {0, 1}
  def gain({:pot_ruby, _index}), do: {0, 1}
  def gain({:tube, _glass, {:vp, n}}), do: {n, 0}
  def gain({:tube, _glass, :ruby}), do: {0, 1}
  def gain({:tube, _glass, _bonus}), do: {0, 0}
  def gain({:pot_vp, vp, _index}), do: {vp, 0}
  def gain({:bowl, _chips, vp}), do: {vp, 0}
  def gain({:effect, {:green, 6}, {:bonus_die, face}}), do: gain({:bonus_die, face})
  def gain({:effect, {:purple, 2}, {:trade, 1}}), do: {1, 1}
  def gain({:effect, {:purple, 2}, {:trade, 2}}), do: {3, 0}
  def gain({:effect, {:purple, 2}, {:trade, 3}}), do: {6, 1}
  def gain({:effect, _book, {:vp, n}}), do: {n, 0}
  def gain({:effect, _book, {:rubies, n}}), do: {0, n}
  def gain({:effect, _book, :ruby}), do: {0, 1}
  def gain({:effect, _book, :droplet_ruby}), do: {0, 1}
  def gain({:witch, _id, {:vp, n}}), do: {n, 0}
  def gain({:witch, _id, {:rubies, n}}), do: {0, n}
  def gain({:fortune, _id, {:vp, n}}), do: {n, 0}
  def gain({:fortune, _id, :ruby}), do: {0, 1}
  def gain({:fortune, _id, :rubies}), do: {0, 3}
  def gain({:fortune, _id, {:rats_back, n}}), do: {0, n}
  # Every other card outcome shows too (what the card did), worth nothing here.
  def gain({:fortune, _id, outcome}) when outcome != :skip, do: {0, 0}
  def gain({:essence, _space, _parts}), do: {0, 0}
  def gain({:essence_vp, n}), do: {n, 0}
  def gain({:essence_bonus, {:vp, n}}), do: {n, 0}
  def gain({:essence_bonus, {:rubies, n}}), do: {0, n}
  def gain({:essence_bonus, _term}), do: {0, 0}
  def gain(_entry), do: nil
end
