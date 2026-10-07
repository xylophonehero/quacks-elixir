defmodule Quacks.WitchPicksTest do
  @moduledoc "Round 14 B: the host picks the herb witches (`witches:` in `Game.new/1`)."
  use ExUnit.Case, async: true

  alias Quacks.{Game, Session}
  alias Quacks.Rules.Witches

  @seed {1, 2, 3}

  test "a pick replaces the dealt witch of its colour; nil or left out is dealt" do
    dealt = Game.new(seed: @seed, expansions: [:herb_witches]).witches
    assert dealt == %{silver: :s2, copper: :c4, gold: :g4}

    picked =
      Game.new(
        seed: @seed,
        expansions: [:herb_witches],
        witches: %{copper: :c3, silver: nil}
      )

    assert picked.witches == %{dealt | copper: :c3}
  end

  test "a pick does not change the game's random stream" do
    plain = Game.new(seed: @seed, expansions: [:herb_witches])
    picked = Game.new(seed: @seed, expansions: [:herb_witches], witches: %{gold: :g1})
    assert plain.rng == picked.rng
    assert plain.fortune_card == picked.fortune_card
  end

  test "an unknown witch or colour raises; picks without the expansion do nothing" do
    assert_raise ArgumentError, fn ->
      Game.new(seed: @seed, expansions: [:herb_witches], witches: %{copper: :s1})
    end

    assert_raise ArgumentError, fn ->
      Game.new(seed: @seed, expansions: [:herb_witches], witches: %{bronze: :c1})
    end

    assert Game.new(seed: @seed, witches: %{copper: :c3}).witches == nil
  end

  test "the session keeps the picks through undo and the bug-report bundle" do
    s = Session.new(@seed, 2, expansions: [:herb_witches], witches: %{silver: :s3, gold: nil})
    assert s.witches == %{silver: :s3}
    assert s.game.witches.silver == :s3

    {:ok, s} = Session.apply(s, 0, :draw)
    assert Session.undo(s).game.witches.silver == :s3

    bundle = s |> Session.bundle() |> Jason.encode!() |> Jason.decode!()
    assert bundle["opts"]["witches"] == %{"silver" => "s3"}

    assert {:ok, back} = Session.from_bundle(bundle)
    assert back.witches == %{silver: :s3}
    assert back.game == s.game
  end

  test "an older bundle without witches still loads" do
    s = Session.new(@seed, 1, expansions: [:herb_witches])
    bundle = s |> Session.bundle() |> Jason.encode!() |> Jason.decode!()
    bundle = update_in(bundle["opts"], &Map.delete(&1, "witches"))
    assert {:ok, back} = Session.from_bundle(bundle)
    assert back.game.witches == s.game.witches
  end

  test "every id the pickers offer is a real witch of its colour" do
    for colour <- [:copper, :silver, :gold],
        id <- Witches.ids(colour),
        do: assert(Witches.card(id).colour == colour)
  end
end
