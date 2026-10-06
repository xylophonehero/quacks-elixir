defmodule Quacks.Rules.ScoringTrack do
  @moduledoc """
  The 0..50 victory-point track and the rat tails printed between its spaces.

  Tail positions verified against a board photo, the 2024 rulebook rat example and the
  LeQuacks source: after VP 1, 4, 7, 10 and every even VP from 12 to 48 (23 tails).
  See `docs/research/rat-tails.md`.
  """

  # A tail after VP `t` sits between the spaces `t` and `t + 1`.
  @tails [1, 4, 7, 10] ++ Enum.to_list(12..48//2)

  @doc "The VP a rat tail follows: a tail after `t` sits between spaces `t` and `t + 1`."
  @spec tails() :: [non_neg_integer]
  def tails, do: @tails

  @doc """
  Rats for a player on `my_vp` behind a leader on `leader_vp`: the tails strictly
  between the two markers. 0 when level with or ahead of the leader.

      iex> Quacks.Rules.ScoringTrack.rat_tails(3, 12)
      3
      iex> Quacks.Rules.ScoringTrack.rat_tails(12, 12)
      0
  """
  @spec rat_tails(non_neg_integer, non_neg_integer) :: non_neg_integer
  def rat_tails(my_vp, leader_vp), do: Enum.count(@tails, &(my_vp <= &1 and &1 < leader_vp))
end
