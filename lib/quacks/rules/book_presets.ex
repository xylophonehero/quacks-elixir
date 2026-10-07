defmodule Quacks.Rules.BookPresets do
  @moduledoc """
  Ready-made sets of ingredient books ("presets") for the spell book's Ingredient
  books page. Source and reasons: `docs/research/book-presets.md`. Sets 1–4 and the
  Herb Witches' Set 5 are the rulebooks' own sets; Ruby hoard, Explosive and
  Alchemists are mixes of our own design (no rulebook or community source names
  one). "Random" is not a preset: the page rolls a random book per colour.

  `sets` uses the books form's shape (`QuacksWeb.SetupComponents.parse_sets/2`):
  orange 1 and "no locoweed" are left out, black is always in. `expansions` are the
  expansions a preset turns on.
  """

  @type id :: :beginner | :set2 | :set3 | :set4 | :rubies | :explosive | :alchemists | :herb
  @type preset :: %{
          id: id,
          name: String.t(),
          blurb: String.t(),
          sets: %{atom => 1..6},
          expansions: [:herb_witches | :alchemists]
        }

  @base %{green: 1, blue: 1, red: 1, yellow: 1, purple: 1, black: 1}
  @set fn n -> %{green: n, blue: n, red: n, yellow: n, purple: n, black: 1} end

  @presets [
    %{
      id: :beginner,
      name: "Beginner (Set 1)",
      blurb: "The rulebook's first game.",
      sets: @base,
      expansions: []
    },
    %{
      id: :set2,
      name: "Set 2",
      blurb: "Safe pots, red held back, chips that grow your bag.",
      sets: @set.(2),
      expansions: []
    },
    %{
      id: :set3,
      name: "Set 3",
      blurb: "Rubies on ruby spaces and a higher white limit.",
      sets: @set.(3),
      expansions: []
    },
    %{
      id: :set4,
      name: "Set 4",
      blurb: "Pay rubies to move, chip upgrades, fast yellows.",
      sets: @set.(4),
      expansions: []
    },
    %{
      id: :rubies,
      name: "Ruby hoard",
      blurb: "Many ways to collect rubies.",
      sets: %{@base | blue: 3, purple: 2},
      expansions: []
    },
    %{
      id: :explosive,
      name: "Explosive",
      blurb: "Push your luck: whites help you, explosions hurt less.",
      sets: %{green: 3, blue: 2, red: 4, yellow: 3, purple: 3, black: 1},
      expansions: []
    },
    %{
      id: :alchemists,
      name: "Alchemists",
      blurb: "Set 1 with the colour-counting locoweed.",
      sets: Map.put(@base, :locoweed, 4),
      expansions: [:alchemists]
    },
    %{
      id: :herb,
      name: "Herb Witches (Set 5)",
      blurb: "Set 5, its locoweed and the orange 6 pumpkin.",
      sets: %{orange: 2, green: 5, blue: 5, red: 5, yellow: 5, purple: 5, black: 2, locoweed: 1},
      expansions: [:herb_witches]
    }
  ]

  @doc "Every preset, in the order the page shows them."
  @spec all() :: [preset]
  def all, do: @presets

  @doc """
  The preset with the id `id` (an atom or the page's string), or nil.

      iex> Quacks.Rules.BookPresets.get("set3").sets.blue
      3
      iex> Quacks.Rules.BookPresets.get("nope")
      nil
  """
  @spec get(id | String.t()) :: preset | nil
  def get(id), do: Enum.find(@presets, &(to_string(&1.id) == to_string(id)))

  @doc """
  The preset whose books are exactly `sets` (the books form's shape), or nil
  ("Custom").

      iex> Quacks.Rules.BookPresets.match(%{green: 1, blue: 1, red: 1, yellow: 1, purple: 1, black: 1}).id
      :beginner
  """
  @spec match(map) :: preset | nil
  def match(sets), do: Enum.find(@presets, &(&1.sets == sets))
end
