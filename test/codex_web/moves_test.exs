defmodule CodexWeb.MovesTest do
  use ExUnit.Case, async: true

  alias CodexWeb.Moves

  describe "chips/2" do
    test "one legal target: the chip is the full action" do
      actions = [{:attack, 5, 9}, {:level_up, 5}, :end_turn]
      chips = Moves.chips(actions, 5)

      assert %{key: "attack", kind: :attack, hotkey: "a", do: {:attack, 5, 9}, one: 9} =
               Enum.find(chips, &(&1.key == "attack"))

      assert %{key: "level", hotkey: "l", do: {:level_up, 5}} =
               Enum.find(chips, &(&1.key == "level"))
    end

    test "two or more targets: the chip starts a target pick" do
      actions = [{:attack, 5, 9}, {:attack, 5, {:building, 1, :base}}]
      assert [%{key: "attack", target: {:attack, 5, nil}}] = Moves.chips(actions, 5)
    end

    test "a target list with a second step is a pick, not one action" do
      actions = [{:ability, 5, :rune_move, [7, 8]}, {:ability, 5, :rune_move, [7, 9]}]
      assert [%{kind: :ability, target: {:ability, 5, :rune_move}}] = Moves.chips(actions, 5)
    end

    test "patrol: the free slots; one slot acts at once" do
      assert [%{key: "patrol", hotkey: "p", patrol: [:elite, :lookout]}] =
               Moves.chips([{:patrol, 5, :elite}, {:patrol, 5, :lookout}], 5)

      assert [%{key: "patrol", do: {:patrol, 5, :elite}}] =
               Moves.chips([{:patrol, 5, :elite}], 5)
    end

    test "only the card's own actions" do
      assert Moves.chips([{:attack, 6, 9}, {:hire, 7}], 5) == []
    end
  end
end
