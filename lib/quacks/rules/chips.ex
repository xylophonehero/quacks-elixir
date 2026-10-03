defmodule Quacks.Rules.Chips do
  @moduledoc """
  Chip data. A chip is a `{colour, value}` tuple.

  - Prices: `docs/research/rulebook.md` §4 (Set 1) and
    `docs/research/ingredient-sets-and-customisation.md` §1.1 (Sets 2–4).
  - Starting bag: §2.
  - Supply: §1. `Quacks.Game` tracks what is left on its `supply` field.
  - The Herb Witches (`docs/research/herb-witches.md` §1, §1.2): Sets 5–6 prices, the
    orange 6-chip, locoweed and the extra chips. The orange 6-chip (orange Set 2) and
    locoweed (books I and II) can be picked in every game (`set/3`).
  - The Alchemists (`docs/research/alchemists.md` §2): locoweed books IV, V and VI
    (A–D are III–VI; III needs the essence phase), in every game.
  """

  @type colour ::
          :white | :orange | :green | :blue | :red | :yellow | :purple | :black | :locoweed
  @typedoc "Locoweed has no printed value; the engine uses 1 (`herb-witches.md` §2.3)."
  @type chip :: {colour, 1 | 2 | 3 | 4 | 6}
  @typedoc "An expansion: `nil` (base game) or `:herb_witches`."
  @type expansion :: nil | :herb_witches

  # Coins per Ingredient Set 1..6 (research `ingredient-sets-and-customisation.md` §1.1,
  # `herb-witches.md` §1.2). Orange has one book. Black: the base book is I, then The
  # Herb Witches' books II and III (Sets 5 and 6 in the box). Locoweed has six books:
  # I–II from The Herb Witches, III–VI are The Alchemists' A–D (`alchemists.md` §2; III
  # needs the essence phase and is not playable yet, `Quacks.Game.new/1` refuses it).
  # ⚠️ Green Set 3 4-chip: 18 (A2, A4); A1 prints 21.
  @prices %{
    {:orange, 1} => [3, 3, 3, 3, 3, 3],
    {:orange, 6} => [22, 22, 22, 22, 22, 22],
    {:green, 1} => [4, 6, 6, 4, 5, 4],
    {:green, 2} => [8, 11, 11, 8, 9, 8],
    {:green, 4} => [14, 18, 18, 14, 16, 14],
    {:blue, 1} => [5, 5, 4, 5, 8, 5],
    {:blue, 2} => [10, 10, 8, 10, 15, 10],
    {:blue, 4} => [19, 19, 14, 20, 19, 18],
    {:red, 1} => [6, 4, 5, 7, 6, 7],
    {:red, 2} => [10, 8, 9, 11, 11, 11],
    {:red, 4} => [16, 14, 15, 17, 18, 17],
    {:yellow, 1} => [8, 9, 8, 8, 10, 8],
    {:yellow, 2} => [12, 13, 12, 12, 14, 12],
    {:yellow, 4} => [18, 19, 18, 18, 20, 18],
    {:purple, 1} => [9, 12, 10, 11, 9, 16],
    {:black, 1} => [10, 10, 9],
    {:locoweed, 1} => [8, 10, 11, 16, 10, 12]
  }

  # Chips that are in play only with their book: orange Set 2, a locoweed book.
  @book_only [{:orange, 6}, {:locoweed, 1}]

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

  # The Herb Witches box, added to the base supply (`herb-witches.md` §1, GeekUp counts
  # H3). ⚠️ H3 totals 154, the rulebook (H1) says 153 + 3 spares, H4 says 151. We use the
  # rulebook total 153: H3 minus one white 1 (a 5th starting bag still fits).
  @expansion_supply %{
    {:white, 1} => 5,
    {:white, 2} => 3,
    {:white, 3} => 2,
    {:orange, 1} => 12,
    {:orange, 6} => 20,
    {:green, 1} => 10,
    {:green, 2} => 5,
    {:green, 4} => 5,
    {:blue, 1} => 8,
    {:blue, 2} => 5,
    {:blue, 4} => 5,
    {:red, 1} => 6,
    {:red, 2} => 5,
    {:red, 4} => 5,
    {:yellow, 1} => 6,
    {:yellow, 2} => 5,
    {:yellow, 4} => 5,
    {:purple, 1} => 8,
    {:black, 1} => 8,
    {:locoweed, 1} => 25
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

  @typedoc """
  The Ingredient Set (1..6) of each colour with a choice of books. Orange is 1 or 2
  (2 adds the orange 6-chip); locoweed is `nil` (not in play), 1, 2, 4, 5 or 6.
  """
  @type sets :: %{optional(colour) => 1..6 | nil}

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

  @doc """
  The book of `colour` in play: `sets[colour]`, else the default: Set 1, and `nil`
  (no locoweed) for locoweed. The expansion changes no default.

      iex> Quacks.Rules.Chips.set(nil, %{}, :orange)
      1
      iex> Quacks.Rules.Chips.set(:herb_witches, %{}, :locoweed)
      nil
  """
  @spec set(expansion, sets, colour) :: 1..6 | nil
  def set(_expansion, sets, :locoweed), do: Map.get(sets, :locoweed)
  def set(_expansion, sets, colour), do: Map.get(sets, colour, 1)

  @doc """
  Every buyable chip, sorted. The orange 6-chip only with orange Set 2, locoweed only
  with a locoweed book (see `set/3`).
  """
  @spec shop(expansion, sets) :: [chip]
  def shop(expansion \\ nil, sets \\ %{}),
    do: Enum.sort((Map.keys(@prices) -- @book_only) ++ book_chips(expansion, sets))

  @doc """
  Number of chips of each kind in the box (§1). The expansion adds its chips; a base
  game with orange Set 2 or a locoweed book adds those chips (expansion counts).
  """
  @spec supply(expansion, sets) :: %{chip => pos_integer}
  def supply(expansion \\ nil, sets \\ %{})

  def supply(nil, sets),
    do: Map.merge(@supply, Map.take(@expansion_supply, book_chips(nil, sets)))

  def supply(:herb_witches, _sets),
    do: Map.merge(@supply, @expansion_supply, fn _, a, b -> a + b end)

  # The book-only chips that `sets` puts in play.
  defp book_chips(expansion, sets) do
    orange = if set(expansion, sets, :orange) == 2, do: [{:orange, 6}], else: []
    locoweed = if set(expansion, sets, :locoweed), do: [{:locoweed, 1}], else: []
    orange ++ locoweed
  end
end
