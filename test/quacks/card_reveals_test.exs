defmodule Quacks.CardRevealsTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Game.Fortune

  defp new(players), do: Game.new(seed: {1, 2, 3}, players: players, fortune: false)

  describe "reveals/1 (round 30)" do
    test "Less is More: every seat's 5 chips, the sum, the lowest takes a blue 2" do
      g =
        new(3)
        |> put(0, bag: List.duplicate({:white, 1}, 5))
        |> put(1, bag: List.duplicate({:green, 2}, 5))
        |> put(2, bag: List.duplicate({:white, 1}, 5))
        |> put(fortune_card: :p8)
        |> Fortune.resolve()

      assert %{0 => seat0, 1 => seat1, 2 => seat2} = Fortune.reveals(g)
      assert seat0.drew == List.duplicate({:white, 1}, 5)
      assert %{number: 5, best?: true, gains: [{:chip, {:blue, 2}}]} = seat0
      assert %{number: 10, best?: false, gains: [{:rubies, 1}]} = seat1
      assert %{number: 5, best?: true, gains: [{:chip, {:blue, 2}}]} = seat2
      refute seat0.choosing?
    end

    test "Less is More: a seat with fewer than 5 chips sums what it drew" do
      g =
        new(2)
        |> put(0, bag: [{:orange, 1}, {:white, 3}])
        |> put(1, bag: List.duplicate({:white, 1}, 5))
        |> put(fortune_card: :p8)
        |> Fortune.resolve()

      assert %{number: 4, best?: true} = Fortune.reveals(g)[0]
      assert %{number: 5, best?: false} = Fortune.reveals(g)[1]
    end

    test "Safety Procedure: the chips drawn on stopping and the one placed" do
      g =
        new(2)
        |> put(0, bag: [{:green, 1}, {:red, 1}], drawn: [], phase: :potions)
        |> put(fortune_card: :b7)
        |> Fortune.on_stop(0)

      assert %{0 => %{drew: drew, gains: [], choosing?: true, number: nil}} = Fortune.reveals(g)
      assert Enum.sort(drew) == [{:green, 1}, {:red, 1}]
      refute Map.has_key?(Fortune.reveals(g), 1)

      g = Fortune.step(g, 0, {:fortune, {:place, {:red, 1}}})
      assert %{gains: [{:placed, {:red, 1}}]} = Fortune.reveals(g)[0]
    end

    test "reveal_card?/1: the cards that draw chips for each seat" do
      assert Enum.filter(Quacks.Rules.Fortune.all(), &Fortune.reveal_card?(&1.id))
             |> Enum.map(& &1.id)
             |> Enum.sort() == [:b7, :p13, :p8]

      refute Fortune.reveal_card?(nil)
    end
  end

  describe "reveals/1 for the choice cards (round 35)" do
    test "Choices, Choices: a row per seat, what it took, or choosing" do
      g = new(3) |> put(fortune_card: :p1) |> Fortune.resolve()

      assert Enum.all?(Fortune.reveals(g), fn {_seat, row} -> row.choosing? end)

      {:ok, g} = Game.apply(g, 0, {:fortune, :rubies})
      {:ok, g} = Game.apply(g, 1, {:fortune, {:take, {:black, 1}}})
      rows = Fortune.reveals(g)

      assert %{drew: [], gains: [{:rubies, 3}], choosing?: false} = rows[0]
      assert %{gains: [{:chip, {:black, 1}}], choosing?: false} = rows[1]
      assert %{gains: [], choosing?: true} = rows[2]
      assert Fortune.choice_card?(:p1)
      refute Fortune.reveal_card?(:p1)
    end

    test "Boomberry Cleanse and Decisions, Decisions: VP, the white chip, the droplet" do
      g = new(2) |> put(fortune_card: :p6) |> Fortune.resolve()
      {:ok, g} = Game.apply(g, 0, {:fortune, :vp})
      {:ok, g} = Game.apply(g, 1, {:fortune, :remove_white})

      assert %{0 => %{gains: [{:vp, 4}]}, 1 => %{gains: [{:removed, {:white, 1}}]}} =
               Fortune.reveals(g)

      g = new(1) |> put(fortune_card: :p11) |> Fortune.resolve()
      {:ok, g} = Game.apply(g, 0, {:fortune, :droplet})
      assert %{0 => %{gains: [{:droplet, 2}]}} = Fortune.reveals(g)
    end

    test "a card with nothing to choose has no rows" do
      g = new(2) |> put(fortune_card: :p2) |> Fortune.resolve()
      assert Fortune.reveals(g) == %{}
    end
  end
end
