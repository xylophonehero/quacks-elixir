defmodule Quacks.Rules.ScoringTrack do
  @moduledoc """
  The victory-point track and the rat tails printed between its spaces.

  Tail positions verified against a board photo, the 2024 rulebook rat example and the
  LeQuacks source: after VP 1, 4, 7, 10 and every even VP from 12 to 48 (23 tails).

  The printed track has the spaces 1..50 and loops: a marker that passes 50 goes on
  round from space 1 and its seal tile flips to "50" (rulebook: "0 / 50-seals"). So
  the tails repeat on each lap: there is a tail after `t + 50` for each printed `t`.
  See `docs/research/rat-tails.md`.
  """

  # A tail after VP `t` sits between the spaces `t` and `t + 1`.
  @tails [1, 4, 7, 10] ++ Enum.to_list(12..48//2)

  @lap 50

  @doc "The printed tails (one lap): a tail after `t` sits between spaces `t` and `t + 1`."
  @spec tails() :: [non_neg_integer]
  def tails, do: @tails

  @doc """
  Every tail after a VP in `from..(to - 1)`, on any lap, in ascending order.

      iex> Quacks.Rules.ScoringTrack.tails_between(46, 56)
      [46, 48, 51, 54]
      iex> Quacks.Rules.ScoringTrack.tails_between(12, 12)
      []
  """
  @spec tails_between(non_neg_integer, non_neg_integer) :: [non_neg_integer]
  def tails_between(from, to) when from >= to, do: []
  def tails_between(from, to), do: Enum.filter(from..(to - 1), &(rem(&1, @lap) in @tails))

  @doc """
  Rats for a player on `my_vp` behind a leader on `leader_vp`: the tails strictly
  between the two markers, on any lap. 0 when level with or ahead of the leader.

      iex> Quacks.Rules.ScoringTrack.rat_tails(3, 12)
      3
      iex> Quacks.Rules.ScoringTrack.rat_tails(12, 12)
      0
      iex> Quacks.Rules.ScoringTrack.rat_tails(51, 68)
      7
      iex> Quacks.Rules.ScoringTrack.rat_tails(39, 68)
      12
  """
  @spec rat_tails(non_neg_integer, non_neg_integer) :: non_neg_integer
  def rat_tails(my_vp, leader_vp), do: length(tails_between(my_vp, leader_vp))
end
