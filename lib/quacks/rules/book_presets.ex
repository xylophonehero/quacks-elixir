defmodule Quacks.Rules.BookPresets do
  @moduledoc """
  Numbered ingredient sets and SolviKaaber's eight themed Reddit combinations.
  Sources and book/coin translations: `docs/research/book-presets.md`.
  Books never enable an expansion. Optional witch picks apply only while
  The Herb Witches is enabled. Random is a separate roll, not a fixed preset.
  """

  @type preset :: %{
          id: atom,
          name: String.t(),
          blurb: String.t(),
          sets: map,
          witches: map,
          source: String.t()
        }
  @set fn n -> %{green: n, blue: n, red: n, yellow: n, purple: n, black: 1} end
  @reddit "https://www.reddit.com/r/boardgames/comments/l2lnb0/comment/gk969b4/"
  @presets [
    %{
      id: :beginner,
      name: "Beginner (Set 1)",
      blurb: "The rulebook's first game.",
      sets: @set.(1),
      witches: %{},
      source: "Rulebook, Set 1"
    },
    %{
      id: :set2,
      name: "Set 2",
      blurb: "Safe pots, red held back, chips that grow your bag.",
      sets: @set.(2),
      witches: %{},
      source: "Rulebook, Set 2"
    },
    %{
      id: :set3,
      name: "Set 3",
      blurb: "Rubies on ruby spaces and a higher white limit.",
      sets: @set.(3),
      witches: %{},
      source: "Rulebook, Set 3"
    },
    %{
      id: :set4,
      name: "Set 4",
      blurb: "Pay rubies to move, chip upgrades, fast yellows.",
      sets: @set.(4),
      witches: %{},
      source: "Rulebook, Set 4"
    },
    %{
      id: :set5,
      name: "Set 5",
      blurb: "Plan first chips, pumpkin points and a second shop.",
      sets: Map.merge(@set.(5), %{orange: 2, black: 2, locoweed: 1}),
      witches: %{},
      source: "Rulebook, Set 5"
    },
    %{
      id: :set6,
      name: "Set 6",
      blurb: "Bonus rolls, ruby rewards and chips held for later.",
      sets: Map.merge(@set.(6), %{orange: 2, black: 3, locoweed: 2}),
      witches: %{},
      source: "Rulebook, Set 6"
    },
    %{
      id: :cherry_bombs,
      name: "All About Cherry Bombs",
      blurb: "Raise the white limit and make cherry bombs work for you.",
      sets: %{orange: 2, purple: 4, green: 3, yellow: 3, red: 4, blue: 6, black: 3, locoweed: 2},
      witches: %{gold: :g2, silver: :s3, copper: :c1},
      source: @reddit
    },
    %{
      id: :playing_safe,
      name: "Playing It Safe",
      blurb: "Protect your pot and plan the next round.",
      sets: %{orange: 2, purple: 5, green: 5, yellow: 1, red: 2, blue: 2, black: 2, locoweed: 1},
      witches: %{gold: :g4, silver: :s1, copper: :c3},
      source: @reddit
    },
    %{
      id: :big_pump,
      name: "Worship the Big Pump",
      blurb: "Build around pumpkins and their colourful companions.",
      sets: %{orange: 2, purple: 5, green: 2, yellow: 2, red: 1, blue: 5, black: 2, locoweed: 2},
      witches: %{gold: :g1, silver: :s4, copper: :c2},
      source: @reddit
    },
    %{
      id: :ruby_roulette,
      name: "Ruby Roulette",
      blurb: "Collect rubies, then spend them for bigger moves.",
      sets: %{orange: 2, purple: 1, green: 1, yellow: 6, red: 6, blue: 6, black: 1, locoweed: 2},
      witches: %{gold: :g3, silver: :s2, copper: :c4},
      source: @reddit
    },
    %{
      id: :points_galore,
      name: "Points Galore",
      blurb: "Turn chip draws and bonus rolls into victory points.",
      sets: %{orange: 2, purple: 3, green: 6, yellow: 5, red: 6, blue: 4, black: 3, locoweed: 2},
      witches: %{gold: :g1, silver: :s2, copper: :c2},
      source: @reddit
    },
    %{
      id: :upgrades,
      name: "Get Your Upgrades",
      blurb: "Grow your chips and put stronger ingredients in your bag.",
      sets: %{orange: 2, purple: 4, green: 2, yellow: 4, red: 5, blue: 1, black: 3, locoweed: 1},
      witches: %{gold: :g2, silver: :s4, copper: :c1},
      source: @reddit
    },
    %{
      id: :stars_align,
      name: "Let The Stars Align",
      blurb: "Line up chip order and ruby spaces for rewards.",
      sets: %{orange: 2, purple: 6, green: 4, yellow: 2, red: 3, blue: 3, black: 3, locoweed: 2},
      witches: %{gold: :g3, silver: :s2, copper: :c1},
      source: @reddit
    },
    %{
      id: :loser_strategy,
      name: "Loser Strategy",
      blurb: "Use rat tails and bonus rolls to catch the leaders.",
      sets: %{orange: 2, purple: 5, green: 6, yellow: 2, red: 2, blue: 6, black: 2, locoweed: 1},
      witches: %{gold: :g2, silver: :s4, copper: :c1},
      source: @reddit
    }
  ]

  @doc "Every preset in display order."
  @spec all() :: [preset]
  def all, do: @presets

  @doc "Find a preset by its atom or string id."
  @spec get(atom | String.t()) :: preset | nil
  def get(id), do: Enum.find(@presets, &(to_string(&1.id) == to_string(id)))

  @doc "Find the preset whose books exactly match the form's settings."
  @spec match(map) :: preset | nil
  def match(sets), do: Enum.find(@presets, &(&1.sets == sets))

  @doc "With Herb Witches enabled, themed presets also require their witch picks."
  @spec match(map, map, boolean) :: preset | nil
  def match(sets, witches, herb_witches?) do
    Enum.find(@presets, fn preset ->
      preset.sets == sets and
        (not herb_witches? or preset.witches == %{} or preset.witches == witches)
    end)
  end
end
