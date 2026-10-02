defmodule Quacks.Rules.ScoringTrack do
  @moduledoc """
  The 0..50 victory-point track and the rat tails printed between its spaces.

  ⚠️ Rulebook §1.2: the tail positions are reconstructed (after VP 1, 3 and every even
  VP from 6 to 50), not copied from an official document. Verify against the board.
  """

  # A tail after VP `t` sits between the spaces `t` and `t + 1`.
  @tails [1, 3] ++ Enum.to_list(6..50//2)

  @doc """
  Rats for a player on `my_vp` behind a leader on `leader_vp`: the tails strictly
  between the two markers. 0 when level with or ahead of the leader.

      iex> Quacks.Rules.ScoringTrack.rat_tails(3, 12)
      4
      iex> Quacks.Rules.ScoringTrack.rat_tails(12, 12)
      0
  """
  @spec rat_tails(non_neg_integer, non_neg_integer) :: non_neg_integer
  def rat_tails(my_vp, leader_vp), do: Enum.count(@tails, &(my_vp <= &1 and &1 < leader_vp))
end
