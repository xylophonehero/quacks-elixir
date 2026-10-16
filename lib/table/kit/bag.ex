defmodule Table.Kit.Bag do
  @moduledoc """
  A bag of items (chips, tiles, tokens) that a player draws from at random. The bag
  is a plain list; its order has no meaning to the game, but it sets which item a
  given random number takes, so keep the list as the functions here return it.

      iex> rng = Table.Kit.Rng.seed({1, 2, 3})
      iex> {item, bag, _rng} = Table.Kit.Bag.draw([:a, :b, :c], rng)
      iex> Enum.sort([item | bag])
      [:a, :b, :c]
  """

  alias Table.Kit.Rng

  @type t(item) :: [item]
  @type t :: t(term)

  @doc """
  Draw one random item: `{item, rest, rng}`, or `:empty` when the bag is empty.
  """
  @spec draw(t(x), Rng.t()) :: {x, t(x), Rng.t()} | :empty when x: term
  def draw([], _rng), do: :empty

  def draw(bag, rng) do
    {i, rng} = Rng.uniform(length(bag), rng)
    {item, rest} = List.pop_at(bag, i - 1)
    {item, rest, rng}
  end

  @doc """
  Draw up to `n` random items, one at a time, in the order drawn. When the bag has
  fewer than `n` items, all of them come out.

      iex> rng = Table.Kit.Rng.seed({1, 2, 3})
      iex> {drawn, rest, _rng} = Table.Kit.Bag.draw([1, 2, 3, 4], 9, rng)
      iex> {length(drawn), rest}
      {4, []}
  """
  @spec draw(t(x), non_neg_integer, Rng.t()) :: {[x], t(x), Rng.t()} when x: term
  def draw(bag, n, rng) when is_integer(n) and n >= 0 do
    {drawn, bag, rng} =
      Enum.reduce(1..min(n, length(bag))//1, {[], bag, rng}, fn _, {drawn, bag, rng} ->
        {item, bag, rng} = draw(bag, rng)
        {[item | drawn], bag, rng}
      end)

    {Enum.reverse(drawn), bag, rng}
  end

  @doc """
  Put `item` back into the bag.

      iex> Table.Kit.Bag.put([:b], :a)
      [:a, :b]
  """
  @spec put(t(x), x) :: t(x) when x: term
  def put(bag, item), do: [item | bag]

  @doc """
  Take out one `item` (the first equal one), or `:error` when it is not in the bag.

      iex> Table.Kit.Bag.take([:a, :b, :a], :a)
      {:ok, [:b, :a]}
      iex> Table.Kit.Bag.take([:a], :z)
      :error
  """
  @spec take(t(x), x) :: {:ok, t(x)} | :error when x: term
  def take(bag, item) do
    case Enum.find_index(bag, &(&1 == item)) do
      nil -> :error
      i -> {:ok, List.delete_at(bag, i)}
    end
  end

  @doc """
  How many of `item` are in the bag.

      iex> Table.Kit.Bag.count([:a, :b, :a], :a)
      2
  """
  @spec count(t(x), x) :: non_neg_integer when x: term
  def count(bag, item), do: Enum.count(bag, &(&1 == item))
end
