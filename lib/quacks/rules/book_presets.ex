defmodule Quacks.Rules.BookPresets do
  @moduledoc """
  Ready-made sets of ingredient books ("presets") for the spell book's Ingredient
  books page. Sources and reasons: `docs/research/book-presets.md`. Sets 1–4 are the
  rulebook's own sets; the other four are mixes that players recommend on the
  BoardGameGeek forums (round 25), each with its thread in the research note.
  "Random" is not a preset: the page rolls a random book per colour.

  `sets` uses the books form's shape (`QuacksWeb.SetupComponents.parse_sets/2`):
  orange 1 and "no locoweed" are left out, black is always in. `expansions` are the
  expansions a preset turns on. `source` says where the mix comes from.
  """

  @type id ::
          :beginner | :set2 | :set3 | :set4 | :combo | :big_bags | :ruby_heavy | :strategic
  @type preset :: %{
          id: id,
          name: String.t(),
          blurb: String.t(),
          sets: %{atom => 1..6},
          expansions: [:herb_witches | :alchemists],
          source: String.t()
        }

  @base %{green: 1, blue: 1, red: 1, yellow: 1, purple: 1, black: 1}
  @set fn n -> %{green: n, blue: n, red: n, yellow: n, purple: n, black: 1} end

  @presets [
    %{
      id: :beginner,
      name: "Beginner (Set 1)",
      blurb: "The rulebook's first game.",
      sets: @base,
      expansions: [],
      source: "Rulebook, Set 1"
    },
    %{
      id: :set2,
      name: "Set 2",
      blurb: "Safe pots, red held back, chips that grow your bag.",
      sets: @set.(2),
      expansions: [],
      source: "Rulebook, Set 2"
    },
    %{
      id: :set3,
      name: "Set 3",
      blurb: "Rubies on ruby spaces and a higher white limit.",
      sets: @set.(3),
      expansions: [],
      source: "Rulebook, Set 3"
    },
    %{
      id: :set4,
      name: "Set 4",
      blurb: "Pay rubies to move, chip upgrades, fast yellows.",
      sets: @set.(4),
      expansions: [],
      source: "Rulebook, Set 4"
    },
    # BGG thread 2311359 ("the most effective" of several groups' setups).
    %{
      id: :combo,
      name: "Combo mix",
      blurb: "Mandrakes raise the white limit, spiders reward exactly 7 white.",
      sets: %{green: 3, blue: 1, red: 1, yellow: 3, purple: 3, black: 1},
      expansions: [],
      source: "boardgamegeek.com/thread/2311359"
    },
    # BGG thread 2227558 ("I like big bags and I can not lie").
    %{
      id: :big_bags,
      name: "Big bags",
      blurb: "Greens and purples that put more chips in your bag.",
      sets: %{green: 2, blue: 2, red: 1, yellow: 3, purple: 2, black: 1},
      expansions: [],
      source: "boardgamegeek.com/thread/2227558"
    },
    # BGG thread 2227558 ("Ruby Heavy", and "Cheap As Chips" with yellow 4).
    %{
      id: :ruby_heavy,
      name: "Ruby heavy",
      blurb: "Rubies from green, blue and purple chips.",
      sets: %{green: 1, blue: 3, red: 2, yellow: 4, purple: 1, black: 1},
      expansions: [],
      source: "boardgamegeek.com/thread/2227558"
    },
    # BGG thread 2589332 ("possibly the most strategic and balanced setup").
    %{
      id: :strategic,
      name: "Strategic",
      blurb: "Plan next round's first chips, double a move, VP for pumpkins.",
      sets: %{orange: 2, green: 5, blue: 5, red: 2, yellow: 2, purple: 4, black: 2},
      expansions: [:herb_witches],
      source: "boardgamegeek.com/thread/2589332"
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
