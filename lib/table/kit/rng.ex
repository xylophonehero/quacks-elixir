defmodule Table.Kit.Rng do
  @moduledoc """
  A random state that the caller keeps and passes on. Every function takes the
  state and returns the result with the next state, so the same seed always gives
  the same results (replay, undo, bug bundles).

  The state is a plain `:rand` state of the `:exsss` algorithm. Only the `_s` API
  of `:rand` is used here: never `Enum.random/1`, `Enum.shuffle/1` or
  `:rand.uniform/1`, which use the process dictionary.

      iex> rng = Table.Kit.Rng.seed({1, 2, 3})
      iex> {a, _} = Table.Kit.Rng.uniform(6, rng)
      iex> {b, _} = Table.Kit.Rng.uniform(6, Table.Kit.Rng.seed({1, 2, 3}))
      iex> a == b and a in 1..6
      true
  """

  @typedoc "A `:rand` state (`:exsss`)."
  @type t :: :rand.state()

  @typedoc "The seed of a game: three integers."
  @type seed :: {integer, integer, integer}

  @doc "A new state from `seed`."
  @spec seed(seed) :: t
  def seed({a, b, c} = seed) when is_integer(a) and is_integer(b) and is_integer(c),
    do: :rand.seed_s(:exsss, seed)

  @doc """
  A random integer in `1..n` and the next state.

      iex> {n, _rng} = Table.Kit.Rng.uniform(10, Table.Kit.Rng.seed({4, 5, 6}))
      iex> n in 1..10
      true
  """
  @spec uniform(pos_integer, t) :: {pos_integer, t}
  def uniform(n, rng) when is_integer(n) and n > 0, do: :rand.uniform_s(n, rng)

  @doc "A random float in `0.0 =< x < 1.0` and the next state."
  @spec uniform(t) :: {float, t}
  def uniform(rng), do: :rand.uniform_s(rng)

  @doc """
  A random element of the non-empty `list` and the next state.

      iex> {x, _rng} = Table.Kit.Rng.pick([:a, :b, :c], Table.Kit.Rng.seed({1, 2, 3}))
      iex> x in [:a, :b, :c]
      true
  """
  @spec pick(nonempty_list(x), t) :: {x, t} when x: term
  def pick([_ | _] = list, rng) do
    {i, rng} = uniform(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end

  @doc """
  `enum` in a random order, and the next state. Each element gets a random float
  key and the list is sorted by key, so the order depends only on the state.

      iex> rng = Table.Kit.Rng.seed({1, 2, 3})
      iex> {a, _} = Table.Kit.Rng.shuffle(1..10, rng)
      iex> {b, _} = Table.Kit.Rng.shuffle(1..10, rng)
      iex> a == b and Enum.sort(a) == Enum.to_list(1..10)
      true
  """
  @spec shuffle(Enumerable.t(x), t) :: {[x], t} when x: term
  def shuffle(enum, rng) do
    {keyed, rng} =
      Enum.map_reduce(enum, rng, fn x, rng ->
        {u, rng} = uniform(rng)
        {{u, x}, rng}
      end)

    {keyed |> Enum.sort() |> Enum.map(&elem(&1, 1)), rng}
  end

  @doc """
  A new, independent stream: `n` jumps (`:rand.jump/1`) of `rng`. Use a fork for a
  side deal (a deck, a card row) so that the main stream does not move: the main
  game then gives the same draws with or without the side deal. Use a different
  `n` for each side deal.

      iex> rng = Table.Kit.Rng.seed({1, 2, 3})
      iex> Table.Kit.Rng.fork(rng, 2) == Table.Kit.Rng.fork(Table.Kit.Rng.fork(rng))
      true
  """
  @spec fork(t, pos_integer) :: t
  def fork(rng, n \\ 1) when is_integer(n) and n > 0,
    do: Enum.reduce(1..n, rng, fn _, rng -> :rand.jump(rng) end)
end
