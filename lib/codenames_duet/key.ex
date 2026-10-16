defmodule CodenamesDuet.Key do
  @moduledoc """
  The two-sided key card (rulebook §1.3, §1.4): the colour of each of the 25 words
  for seat 0 and for seat 1. A colour is `:green` (agent), `:neutral` (bystander)
  or `:assassin`.

  Every key card has the same layout: the 25 pairs of `layout/0`. A new key puts
  these pairs on the 25 words in a random order.
  """

  alias Table.Kit.Rng

  @type color :: :green | :neutral | :assassin
  @type t :: %{0 => [color], 1 => [color]}

  # {seat 0 colour, seat 1 colour}, number of words (rulebook §1.4).
  @layout [
    {{:green, :green}, 3},
    {{:green, :neutral}, 5},
    {{:neutral, :green}, 5},
    {{:green, :assassin}, 1},
    {{:assassin, :green}, 1},
    {{:assassin, :assassin}, 1},
    {{:assassin, :neutral}, 1},
    {{:neutral, :assassin}, 1},
    {{:neutral, :neutral}, 7}
  ]

  @doc """
  The layout of every key card: `{{seat 0 colour, seat 1 colour}, count}`.

      iex> CodenamesDuet.Key.layout() |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      25
  """
  @spec layout() :: [{{color, color}, pos_integer}]
  def layout, do: @layout

  @doc "The 25 pairs of the layout, in the order of `layout/0` (not shuffled)."
  @spec pairs() :: [{color, color}]
  def pairs, do: Enum.flat_map(@layout, fn {pair, n} -> List.duplicate(pair, n) end)

  @doc "A key from 25 pairs: index `i` of each side is the colour of word `i`."
  @spec from_pairs([{color, color}]) :: t
  def from_pairs(pairs) when length(pairs) == 25,
    do: %{0 => Enum.map(pairs, &elem(&1, 0)), 1 => Enum.map(pairs, &elem(&1, 1))}

  @doc """
  A random key and the next random state.

      iex> {key, _rng} = CodenamesDuet.Key.deal(Table.Kit.Rng.seed({1, 2, 3}))
      iex> Enum.count(key[0], &(&1 == :green))
      9
  """
  @spec deal(Rng.t()) :: {t, Rng.t()}
  def deal(rng) do
    {pairs, rng} = Rng.shuffle(pairs(), rng)
    {from_pairs(pairs), rng}
  end

  @doc "The indexes of the words with `color` on `side`."
  @spec indexes([color], color) :: [non_neg_integer]
  def indexes(side, color),
    do: for({c, i} <- Enum.with_index(side), c == color, do: i)
end
