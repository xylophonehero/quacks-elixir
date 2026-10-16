defmodule Table.Kit.Dice do
  @moduledoc """
  Dice as data: a die is the list of its faces, in any terms the game uses. Each
  face has the same chance; put a face in two times to make it twice as likely.

      iex> bonus = [{:vp, 1}, {:vp, 1}, {:vp, 2}, :ruby, :droplet, :orange]
      iex> {face, _rng} = Table.Kit.Dice.roll(bonus, Table.Kit.Rng.seed({1, 2, 3}))
      iex> face in bonus
      true
  """

  alias Table.Kit.Rng

  @type t(face) :: nonempty_list(face)
  @type t :: t(term)

  @doc """
  A die with the faces `1..sides`.

      iex> Table.Kit.Dice.d(6)
      [1, 2, 3, 4, 5, 6]
  """
  @spec d(pos_integer) :: t(pos_integer)
  def d(sides) when is_integer(sides) and sides > 0, do: Enum.to_list(1..sides)

  @doc "Roll `die` one time: `{face, rng}`."
  @spec roll(t(x), Rng.t()) :: {x, Rng.t()} when x: term
  def roll(die, rng), do: Rng.pick(die, rng)

  @doc """
  Roll `die` `n` times: `{faces, rng}`, faces in the order rolled.

      iex> {faces, _rng} = Table.Kit.Dice.roll(Table.Kit.Dice.d(6), 3, Table.Kit.Rng.seed({1, 2, 3}))
      iex> length(faces)
      3
  """
  @spec roll(t(x), non_neg_integer, Rng.t()) :: {[x], Rng.t()} when x: term
  def roll(die, n, rng) when is_integer(n) and n >= 0,
    do: Enum.map_reduce(List.duplicate(die, n), rng, &roll/2)
end
