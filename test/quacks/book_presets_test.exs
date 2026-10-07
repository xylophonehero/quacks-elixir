defmodule Quacks.Rules.BookPresetsTest do
  use ExUnit.Case, async: true

  alias Quacks.Rules.{BookPresets, Books}
  alias QuacksWeb.SetupComponents

  doctest BookPresets

  test "6 to 8 presets with unique ids, each a legal set of books" do
    presets = BookPresets.all()
    assert length(presets) in 6..8
    assert presets |> Enum.map(& &1.id) |> Enum.uniq() |> length() == length(presets)

    for preset <- presets do
      alchemists? = :alchemists in preset.expansions
      form = Map.new(preset.sets, fn {colour, set} -> {to_string(colour), to_string(set)} end)
      # The books form keeps every pick: each book exists and is allowed.
      assert SetupComponents.parse_sets(form, alchemists?) == preset.sets, preset.name

      for {colour, set} <- preset.sets, do: assert(set in Books.sets(colour))
    end
  end

  test "Sets 1 to 4, then the researched mixes; each names its source" do
    assert Enum.map(BookPresets.all(), & &1.id) ==
             [:beginner, :set2, :set3, :set4, :combo, :big_bags, :ruby_heavy, :strategic]

    for preset <- BookPresets.all() do
      assert preset.source =~ ~r/^(Rulebook, Set [1-4]|boardgamegeek\.com\/thread\/\d+)$/
    end

    # The home-made mixes of round 22 are gone.
    for id <- ~w(rubies explosive alchemists herb), do: assert(BookPresets.get(id) == nil)
    assert BookPresets.get(:strategic).expansions == [:herb_witches]
  end

  test "Beginner is the default game's books" do
    assert BookPresets.match(SetupComponents.default_sets()).id == :beginner
    assert BookPresets.match(%{green: 2}) == nil
  end
end
