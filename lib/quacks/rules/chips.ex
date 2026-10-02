defmodule Quacks.Rules.Chips do
  @moduledoc """
  Chip data. A chip is a `{colour, value}` tuple.

  - Prices: `docs/research/rulebook.md` §4 (Ingredient Set 1).
  - Starting bag: §2.
  - Supply: §1. ⚠️ Not enforced by the engine in slice 1: a solo player cannot
    exhaust any colour in 9 rounds (max 2 chips of different colours per round).
  """

  @type colour :: :white | :orange | :green | :blue | :red | :yellow | :purple | :black
  @type chip :: {colour, 1 | 2 | 3 | 4}

  @prices %{
    {:orange, 1} => 3,
    {:green, 1} => 4,
    {:green, 2} => 8,
    {:green, 4} => 14,
    {:blue, 1} => 5,
    {:blue, 2} => 10,
    {:blue, 4} => 19,
    {:red, 1} => 6,
    {:red, 2} => 10,
    {:red, 4} => 16,
    {:yellow, 1} => 8,
    {:yellow, 2} => 12,
    {:yellow, 4} => 18,
    {:purple, 1} => 9,
    {:black, 1} => 10
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

  @doc "Price in coins of a buyable chip (§4). Raises for white chips."
  @spec price(chip) :: pos_integer
  def price(chip), do: Map.fetch!(@prices, chip)

  @doc "Every buyable chip, sorted."
  @spec shop() :: [chip]
  def shop, do: @prices |> Map.keys() |> Enum.sort()

  @doc "Number of chips of each kind in the box (§1)."
  @spec supply() :: %{chip => pos_integer}
  def supply, do: @supply
end
