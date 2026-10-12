defmodule Quacks.Rules.BookPresetsTest do
  use ExUnit.Case, async: true
  alias Quacks.Rules.{BookPresets, Books, Witches}
  alias QuacksWeb.SetupComponents

  test "all fourteen presets are legal with expansions disabled" do
    presets = BookPresets.all()
    assert length(presets) == 14
    assert length(Enum.uniq_by(presets, & &1.id)) == 14

    for preset <- presets do
      form = Map.new(preset.sets, fn {colour, set} -> {to_string(colour), to_string(set)} end)
      assert SetupComponents.parse_sets(form, false) == preset.sets
      for {colour, set} <- preset.sets, do: assert(set in Books.sets(colour))
      for {colour, witch} <- preset.witches, do: assert(witch in Witches.ids(colour))
    end

    for id <- ~w(combo big_bags ruby_heavy strategic), do: assert(BookPresets.get(id) == nil)
  end

  test "numbered sets retain original books and add complete sets five and six" do
    for n <- 1..6 do
      preset = BookPresets.get(if(n == 1, do: "beginner", else: "set#{n}"))
      for colour <- [:green, :blue, :red, :yellow, :purple], do: assert(preset.sets[colour] == n)
      assert preset.sets.black == if(n <= 4, do: 1, else: n - 3)
      assert preset.sets[:locoweed] == if(n <= 4, do: nil, else: n - 4)
      assert preset.witches == %{}
    end

    assert BookPresets.match(SetupComponents.default_sets()).id == :beginner
  end

  test "the eight Reddit combinations have exact books and coins" do
    assert BookPresets.get(:cherry_bombs).sets == %{
             orange: 2,
             purple: 4,
             green: 3,
             yellow: 3,
             red: 4,
             blue: 6,
             black: 3,
             locoweed: 2
           }

    assert BookPresets.get(:cherry_bombs).witches == %{gold: :g2, silver: :s3, copper: :c1}

    assert BookPresets.get(:playing_safe).sets == %{
             orange: 2,
             purple: 5,
             green: 5,
             yellow: 1,
             red: 2,
             blue: 2,
             black: 2,
             locoweed: 1
           }

    assert BookPresets.get(:playing_safe).witches == %{gold: :g4, silver: :s1, copper: :c3}

    assert BookPresets.get(:big_pump).sets == %{
             orange: 2,
             purple: 5,
             green: 2,
             yellow: 2,
             red: 1,
             blue: 5,
             black: 2,
             locoweed: 2
           }

    assert BookPresets.get(:big_pump).witches == %{gold: :g1, silver: :s4, copper: :c2}

    assert BookPresets.get(:ruby_roulette).sets == %{
             orange: 2,
             purple: 1,
             green: 1,
             yellow: 6,
             red: 6,
             blue: 6,
             black: 1,
             locoweed: 2
           }

    assert BookPresets.get(:ruby_roulette).witches == %{gold: :g3, silver: :s2, copper: :c4}

    assert BookPresets.get(:points_galore).sets == %{
             orange: 2,
             purple: 3,
             green: 6,
             yellow: 5,
             red: 6,
             blue: 4,
             black: 3,
             locoweed: 2
           }

    assert BookPresets.get(:points_galore).witches == %{gold: :g1, silver: :s2, copper: :c2}

    assert BookPresets.get(:upgrades).sets == %{
             orange: 2,
             purple: 4,
             green: 2,
             yellow: 4,
             red: 5,
             blue: 1,
             black: 3,
             locoweed: 1
           }

    assert BookPresets.get(:upgrades).witches == %{gold: :g2, silver: :s4, copper: :c1}

    assert BookPresets.get(:stars_align).sets == %{
             orange: 2,
             purple: 6,
             green: 4,
             yellow: 2,
             red: 3,
             blue: 3,
             black: 3,
             locoweed: 2
           }

    assert BookPresets.get(:stars_align).witches == %{gold: :g3, silver: :s2, copper: :c1}

    assert BookPresets.get(:loser_strategy).sets == %{
             orange: 2,
             purple: 5,
             green: 6,
             yellow: 2,
             red: 2,
             blue: 6,
             black: 2,
             locoweed: 1
           }

    assert BookPresets.get(:loser_strategy).witches == %{gold: :g2, silver: :s4, copper: :c1}
  end
end
