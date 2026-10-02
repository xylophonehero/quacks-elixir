defmodule Quacks.Rules.Chips do
  @moduledoc """
  Chip data. A chip is a `{colour, value}` tuple.

  - Prices: `docs/research/rulebook.md` §4 (Set 1) and
    `docs/research/ingredient-sets-and-customisation.md` §1.1 (Sets 2–4).
  - Starting bag: §2.
  - Supply: §1. `Quacks.Game` tracks what is left on its `supply` field.
  """

  @type colour :: :white | :orange | :green | :blue | :red | :yellow | :purple | :black
  @type chip :: {colour, 1 | 2 | 3 | 4}

  # Coins per Ingredient Set 1..4 (research `ingredient-sets-and-customisation.md` §1.1).
  # Orange and black have one book for every set. ⚠️ Green Set 3 4-chip: 18 (A2, A4);
  # A1 prints 21.
  @prices %{
    {:orange, 1} => [3, 3, 3, 3],
    {:green, 1} => [4, 6, 6, 4],
    {:green, 2} => [8, 11, 11, 8],
    {:green, 4} => [14, 18, 18, 14],
    {:blue, 1} => [5, 5, 4, 5],
    {:blue, 2} => [10, 10, 8, 10],
    {:blue, 4} => [19, 19, 14, 20],
    {:red, 1} => [6, 4, 5, 7],
    {:red, 2} => [10, 8, 9, 11],
    {:red, 4} => [16, 14, 15, 17],
    {:yellow, 1} => [8, 9, 8, 8],
    {:yellow, 2} => [12, 13, 12, 12],
    {:yellow, 4} => [18, 19, 18, 18],
    {:purple, 1} => [9, 12, 10, 11],
    {:black, 1} => [10, 10, 10, 10]
  }

  @supply %{
    {:white, 1} => 20,
    {:white, 2} => 8,
    {:white, 3} => 4,
    {:orange, 1} => 20,
    {:green, 1} => 15,
    {:green, 2} => 10,
    {:green, 4} => 13,
    {:blue, 1} => 14,
    {:blue, 2} => 10,
    {:blue, 4} => 10,
    {:red, 1} => 12,
    {:red, 2} => 8,
    {:red, 4} => 10,
    {:yellow, 1} => 13,
    {:yellow, 2} => 6,
    {:yellow, 4} => 10,
    {:purple, 1} => 15,
    {:black, 1} => 18
  }

  @starting_bag [
    {:white, 1},
    {:white, 1},
    {:white, 1},
    {:white, 1},
    {:white, 2},
    {:white, 2},
    {:white, 3},
    {:orange, 1},
    {:green, 1}
  ]

  @doc "The 9 chips every player starts with (§2)."
  @spec starting_bag() :: [chip]
  def starting_bag, do: @starting_bag

  @typedoc "The Ingredient Set (1..4) of each colour with a choice of books."
  @type sets :: %{optional(colour) => 1..4}

  @doc """
  Price in coins of a buyable chip with the books in `sets` (a colour not in `sets`
  uses Set 1). Raises for white chips.
  """
  @spec price(chip, sets) :: pos_integer
  def price({colour, _} = chip, sets),
    do: Enum.at(Map.fetch!(@prices, chip), Map.get(sets, colour, 1) - 1)

  @doc "Price with Set 1 for every colour; `price(chip, %{})`."
  @spec price(chip) :: pos_integer
  def price(chip), do: price(chip, %{})

  @doc "Every buyable chip, sorted."
  @spec shop() :: [chip]
  def shop, do: @prices |> Map.keys() |> Enum.sort()

  @doc "Number of chips of each kind in the box (§1)."
  @spec supply() :: %{chip => pos_integer}
  def supply, do: @supply
end
