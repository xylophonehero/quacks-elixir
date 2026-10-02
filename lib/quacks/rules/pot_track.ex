defmodule Quacks.Rules.PotTrack do
  @moduledoc """
  The 54-space pot (cauldron) track, index 0..53.

  Numbers copied verbatim from `docs/research/rulebook.md` §1.1. ⚠️ That table is
  a fan transcription (two agreeing sources), not an official document.
  Index 53 is the spoon: 35 coins / 15 VP. Any index past 53 clamps to 53.
  """

  @last 53

  # {coins, vp, ruby?}
  @track {
    {0, 0, false},
    {1, 0, false},
    {2, 0, false},
    {3, 0, false},
    {4, 0, false},
    {5, 0, true},
    {6, 1, false},
    {7, 1, false},
    {8, 1, false},
    {9, 1, true},
    {10, 2, false},
    {11, 2, false},
    {12, 2, false},
    {13, 2, true},
    {14, 3, false},
    {15, 3, false},
    {15, 3, true},
    {16, 3, false},
    {16, 4, false},
    {17, 4, false},
    {17, 4, true},
    {18, 4, false},
    {18, 5, false},
    {19, 5, false},
    {19, 5, true},
    {20, 5, false},
    {20, 6, false},
    {21, 6, false},
    {21, 6, true},
    {22, 7, false},
    {22, 7, true},
    {23, 7, false},
    {23, 8, false},
    {24, 8, false},
    {24, 8, true},
    {25, 9, false},
    {25, 9, true},
    {26, 9, false},
    {26, 10, false},
    {27, 10, false},
    {27, 10, true},
    {28, 11, false},
    {28, 11, true},
    {29, 11, false},
    {29, 12, false},
    {30, 12, false},
    {30, 12, true},
    {31, 12, false},
    {31, 13, false},
    {32, 13, false},
    {32, 13, true},
    {33, 14, false},
    {33, 14, true},
    {35, 15, false}
  }

  @type space :: %{coins: non_neg_integer, vp: non_neg_integer, ruby?: boolean}

  @doc "Index of the last space (the spoon)."
  @spec last() :: 53
  def last, do: @last

  @doc "Payout of the space at `idx`. Indices past the spoon clamp to the spoon."
  @spec at(non_neg_integer) :: space
  def at(idx) when is_integer(idx) and idx >= 0 do
    {coins, vp, ruby?} = elem(@track, min(idx, @last))
    %{coins: coins, vp: vp, ruby?: ruby?}
  end
end
