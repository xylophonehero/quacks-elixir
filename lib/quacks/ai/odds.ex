defmodule Quacks.AI.Odds do
  @moduledoc """
  Exact explosion odds for the next draw. Draws are uniform over the bag, so the bot
  knows them from the open bag (it never reads the engine `rng`).
  """

  alias Quacks.Game
  alias Quacks.Game.{Fortune, Potions}
  alias Quacks.Player

  @doc """
  The chance that one draw from `bag` explodes a pot with white sum `sum` and white
  limit `limit`: the share of white chips `w` with `sum + w > limit`.

      iex> Quacks.AI.Odds.bust([{:white, 1}, {:white, 3}, {:green, 1}, {:white, 1}], 5, 7)
      0.25
  """
  @spec bust([Quacks.Rules.Chips.chip()], non_neg_integer, pos_integer) :: float
  def bust([], _sum, _limit), do: 0.0

  def bust(bag, sum, limit),
    do: Enum.count(bag, &match?({:white, w} when sum + w > limit, &1)) / length(bag)

  @doc """
  `bust/3` for `seat`'s next draw. 0 when the draw cannot explode: a B3 card draw or a
  green Set 5 starter chip (drawn first, never white).
  """
  @spec next_draw(Game.t(), Game.seat()) :: float
  def next_draw(game, seat) do
    p = Game.player(game, seat)

    if Fortune.safe_draw?(game, p) or p.starters != [],
      do: 0.0,
      else: bust(p.bag, Player.white_sum(p), Potions.explode_above(game, seat))
  end

  @doc """
  `next_draw/2` after the newest chip, a white `w`, went back in the bag (the flask,
  card B10).
  """
  @spec after_return(Game.t(), Game.seat(), pos_integer) :: float
  def after_return(game, seat, w) do
    p = Game.player(game, seat)
    bust([{:white, w} | p.bag], Player.white_sum(p) - w, Potions.explode_above(game, seat))
  end
end
