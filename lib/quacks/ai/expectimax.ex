defmodule Quacks.AI.Expectimax do
  @moduledoc """
  Draw or stop by expected value (`docs/research/jev-plan.md` §3), the way the
  Quackulator solver does it: look `ev_depth` draws ahead over the open bag, solve the
  white chips exactly and treat every coloured chip as a safe mover of its value
  (no chip effects).

  The value of a pot is a round-dependent mix of what its scoring space pays:

      value(space, round) = coin_weight[round] * coins + vp + ruby_value * ruby

  An explosion pays the coins or the VP (the profile's explosion rule) and the ruby.
  `best/2` of a pot is `max(stop, draw)`; `draw` is the mean of `best/2` over every
  chip in the bag, one level less deep. Pots are memoised on the bag multiset, the
  position and the white sum.
  """

  alias Quacks.AI.Profile
  alias Quacks.Game
  alias Quacks.Game.Potions
  alias Quacks.Player
  alias Quacks.Rules.PotTrack

  # A pot: the white and coloured chips in the bag as `%{value => count}`, the index
  # of the newest chip and the white sum.
  @typep pot ::
           {%{pos_integer => pos_integer}, %{non_neg_integer => pos_integer}, non_neg_integer,
            non_neg_integer}

  @doc """
  The value of a stop now and the expected value of one more draw (then the best
  play, `ev_depth - 1` draws deep) for `seat`, in VP.
  """
  @spec ev(Game.t(), Game.seat(), Profile.t()) :: %{stop: float, draw: float}
  def ev(game, seat, profile) do
    p = Game.player(game, seat)
    ctx = context(game, seat, profile)
    pot = pot(p.bag, p.pot_index, Player.white_sum(p))
    {draw, _memo} = draw(pot, profile.ev_depth, ctx, %{})
    %{stop: stop(pot, ctx), draw: draw}
  end

  @doc "True when one more draw is worth more than a stop now."
  @spec draw?(Game.t(), Game.seat(), Profile.t()) :: boolean
  def draw?(game, seat, profile) do
    %{stop: stop, draw: draw} = ev(game, seat, profile)
    draw > stop
  end

  @doc """
  The value of the best play after the newest chip, a white `w`, goes back in the bag
  (the flask, card B10), against a stop now: `%{stop: now, after: best}`.
  """
  @spec after_return(Game.t(), Game.seat(), Profile.t(), pos_integer) ::
          %{stop: float, after: float, draw_after: float}
  def after_return(game, seat, profile, w) do
    p = Game.player(game, seat)
    ctx = context(game, seat, profile)
    sum = Player.white_sum(p)
    now = pot(p.bag, p.pot_index, sum)
    back = pot([{:white, w} | p.bag], return_index(p, w), sum - w)
    {draw, _memo} = draw(back, profile.ev_depth, ctx, %{})
    %{stop: stop(now, ctx), after: max(stop(back, ctx), draw), draw_after: draw}
  end

  @doc """
  The value in VP of a stop with the newest chip on `index` in `round`.

      iex> profile = Quacks.AI.Profile.get(:balanced)
      iex> Quacks.AI.Expectimax.space_value(8, 9, profile)
      3.8
  """
  @spec space_value(non_neg_integer, 1..9, Profile.t()) :: float
  def space_value(index, round, profile) do
    space = PotTrack.at(index + 1)
    profile.coin_weight[round] * space.coins + space.vp + ruby(space, profile)
  end

  # -- the search ---------------------------------------------------------------------

  defp context(game, seat, profile) do
    %{
      round: game.round,
      limit: Potions.explode_above(game, seat),
      profile: profile,
      vp?: game.round == 9 or game.round >= profile.explode_vp_from
    }
  end

  @spec pot([Quacks.Rules.Chips.chip()], non_neg_integer, non_neg_integer) :: pot
  defp pot(bag, index, sum) do
    {whites, coloured} = Enum.split_with(bag, &match?({:white, _}, &1))
    {count(whites), count(coloured), index, sum}
  end

  defp count(chips), do: Enum.frequencies_by(chips, &move/1)

  defp move({_colour, value}) when is_integer(value) and value > 0, do: value
  defp move(_chip), do: 0

  defp best(pot, 0, ctx, memo), do: {stop(pot, ctx), memo}

  defp best(pot, depth, ctx, memo) do
    key = {pot, depth}

    case memo do
      %{^key => value} ->
        {value, memo}

      _ ->
        {draw, memo} = draw(pot, depth, ctx, memo)
        value = max(stop(pot, ctx), draw)
        {value, Map.put(memo, key, value)}
    end
  end

  # One draw, then the best play `depth - 1` deep. An empty bag cannot draw.
  defp draw({whites, coloured, _index, _sum} = pot, depth, ctx, memo) do
    total = Enum.sum(Map.values(whites)) + Enum.sum(Map.values(coloured))

    if total == 0 do
      {stop(pot, ctx), memo}
    else
      outcomes =
        Enum.map(whites, fn {w, n} -> {n, {:white, w}} end) ++
          Enum.map(coloured, fn {v, n} -> {n, {:coloured, v}} end)

      Enum.reduce(outcomes, {0.0, memo}, fn {n, chip}, {acc, memo} ->
        {value, memo} = outcome(pot, chip, depth, ctx, memo)
        {acc + n / total * value, memo}
      end)
    end
  end

  defp outcome({whites, coloured, index, sum}, {:white, w}, depth, ctx, memo) do
    index = min(index + w, PotTrack.last())

    if sum + w > ctx.limit,
      do: {explosion(index, ctx), memo},
      else: best({take(whites, w), coloured, index, sum + w}, depth - 1, ctx, memo)
  end

  defp outcome({whites, coloured, index, sum}, {:coloured, v}, depth, ctx, memo) do
    index = min(index + v, PotTrack.last())
    best({whites, take(coloured, v), index, sum}, depth - 1, ctx, memo)
  end

  defp take(counts, v) do
    case counts do
      %{^v => 1} -> Map.delete(counts, v)
      %{^v => n} -> %{counts | v => n - 1}
    end
  end

  defp stop({_whites, _coloured, index, _sum}, ctx),
    do: space_value(index, ctx.round, ctx.profile)

  defp explosion(index, %{profile: profile} = ctx) do
    space = PotTrack.at(index + 1)

    if ctx.vp?,
      do: space.vp + ruby(space, profile),
      else: profile.coin_weight[ctx.round] * space.coins + ruby(space, profile)
  end

  defp ruby(%{ruby?: true}, profile), do: profile.ruby_value
  defp ruby(_space, _profile), do: 0.0

  # Where the pot ends after the newest white goes back: the chip before it, or `w`
  # spaces back from an empty pot. A chip in the overflow bowl was never on the pot.
  defp return_index(%Player{bowl: [_ | _], pot_index: index}, _w), do: index
  defp return_index(%Player{drawn: [_newest, {_chip, index} | _]}, _w), do: index
  defp return_index(%Player{pot_index: index}, w), do: max(index - w, 0)
end
