defmodule Quacks.ChipEffectsTest do
  use ExUnit.Case, async: true

  alias Quacks.Game
  alias Quacks.Rules.Chips

  @seed {1, 2, 3}

  defp new, do: Game.new(seed: @seed)

  defp apply!(game, action) do
    {:ok, game} = Game.apply(game, action)
    game
  end

  # Draw exactly these chips, in order, by replacing the bag before each draw.
  defp force_draws(game, chips), do: Enum.reduce(chips, game, &apply!(%{&2 | bag: [&1]}, :draw))

  # Draw `chip` with `others` left in the bag: put `chip` where the rng will pick it.
  defp force_draw_leaving(game, chip, others) do
    {i, _} = :rand.uniform_s(length(others) + 1, game.rng)
    apply!(%{game | bag: List.insert_at(others, i - 1, chip)}, :draw)
  end

  # Run step B on a hand-built pot without the die and without the space's VP:
  # the exploded "buy" path on pot index 0 (scoring space 1: 1 coin, 0 VP, no ruby).
  defp chip_actions(drawn) do
    %{new() | phase: :explosion_choice, exploded?: true, drawn: drawn, pot_index: 0}
    |> apply!({:explosion_choice, :buy})
  end

  defp shop(round, coins), do: %{new() | phase: :buy_chips, round: round, coins: coins}

  defp buyable?(game, chip), do: {:buy, [chip]} in Game.legal_actions(game)

  test "red moves 0, 1 or 2 extra spaces by the oranges already in the pot" do
    assert force_draws(new(), [{:red, 2}]).pot_index == 2
    assert force_draws(new(), [{:orange, 1}, {:red, 2}]).pot_index == 1 + 2 + 1
    assert force_draws(new(), [{:orange, 1}, {:orange, 1}, {:red, 1}]).pot_index == 2 + 1 + 1
    three = List.duplicate({:orange, 1}, 3)
    assert force_draws(new(), three ++ [{:red, 4}]).pot_index == 3 + 4 + 2
    # the red chip itself is not an orange; a later orange does not act retroactively
    assert force_draws(new(), [{:red, 1}, {:orange, 1}]).pot_index == 2
  end

  test "yellow after white offers to return the white; its space stays empty" do
    g = force_draws(new(), [{:white, 3}, {:yellow, 1}])
    assert g.phase == :yellow_choice
    assert Game.legal_actions(g) == [:return_white, :keep]
    assert g.pot_index == 4

    kept = apply!(g, :keep)
    assert kept.phase == :potions
    assert kept.drawn == [{:yellow, 1}, {:white, 3}]
    assert Game.white_sum(kept) == 3

    returned = apply!(g, :return_white)
    assert returned.phase == :potions
    assert returned.drawn == [{:yellow, 1}]
    assert returned.bag == [{:white, 3}]
    assert returned.pot_index == 4
    assert Game.white_sum(returned) == 0
    refute :use_flask in Game.legal_actions(returned)
  end

  test "yellow after a coloured chip, or as the first chip, has no effect" do
    assert force_draws(new(), [{:white, 3}, {:orange, 1}, {:yellow, 1}]).phase == :potions
    assert force_draws(new(), [{:yellow, 2}]).phase == :potions
  end

  test "blue draws its value in extra chips, fewer when the bag is short" do
    g = force_draw_leaving(new(), {:blue, 4}, [{:white, 1}, {:orange, 1}])
    assert g.phase == :blue_choice
    assert Enum.sort(g.pending) == [{:orange, 1}, {:white, 1}]
    assert g.bag == []
    assert g.drawn == [{:blue, 4}]
    assert Game.legal_actions(g) == [{:place, {:orange, 1}}, {:place, {:white, 1}}, :return_all]

    one = force_draw_leaving(new(), {:blue, 1}, [{:white, 1}, {:orange, 1}])
    assert length(one.pending) == 1 and length(one.bag) == 1

    empty = force_draws(new(), [{:blue, 2}])
    assert empty.phase == :potions
    assert empty.pending == []
  end

  test "blue: returning all puts every extra chip back in the bag" do
    g = %{new() | phase: :blue_choice, bag: [{:green, 1}], pending: [{:white, 1}, {:white, 1}]}
    assert Game.legal_actions(g) == [{:place, {:white, 1}}, :return_all]

    g = apply!(g, :return_all)
    assert g.phase == :potions
    assert g.pending == []
    assert Enum.sort(g.bag) == [{:green, 1}, {:white, 1}, {:white, 1}]
  end

  test "blue -> white chain counts for the explosion and chains chip actions" do
    pot = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 2}, {:blue, 1}])
    assert Game.white_sum(pot) == 7

    g = %{pot | phase: :blue_choice, bag: [], pending: [{:white, 1}, {:orange, 1}]}
    boom = apply!(g, {:place, {:white, 1}})
    assert boom.phase == :explosion_choice
    assert boom.exploded?
    assert hd(boom.drawn) == {:white, 1}
    assert boom.bag == [{:orange, 1}]
    assert boom.pending == []
    assert boom.pot_index == pot.pot_index + 1

    # placing a red chains its own on-draw effect (one orange already in the pot)
    red = %{pot | phase: :blue_choice, drawn: [{:orange, 1}], pot_index: 1, pending: [{:red, 1}]}
    red = apply!(red, {:place, {:red, 1}})
    assert red.phase == :potions
    assert red.pot_index == 1 + 1 + 1

    # the flask undoes a white placed through a blue chip too
    safe = force_draws(new(), [{:white, 3}, {:blue, 1}])
    flask = %{safe | phase: :blue_choice, bag: [], pending: [{:white, 1}]}
    flask = apply!(flask, {:place, {:white, 1}})
    assert :use_flask in Game.legal_actions(flask)
    flask = apply!(flask, :use_flask)
    assert flask.pot_index == safe.pot_index
    assert flask.drawn == safe.drawn
  end

  test "green gives a ruby only for the last or next-to-last chip" do
    assert chip_actions([{:green, 1}, {:white, 1}]).rubies == 2
    assert chip_actions([{:white, 1}, {:green, 4}]).rubies == 2
    assert chip_actions([{:green, 2}, {:green, 1}, {:white, 1}]).rubies == 3
    assert chip_actions([{:white, 1}, {:white, 1}, {:green, 1}]).rubies == 1
  end

  test "purple tiers: 1 VP; 1 VP + ruby; 2 VP + droplet" do
    one = chip_actions([{:purple, 1}, {:white, 1}])
    assert {one.vp, one.rubies, one.droplet} == {1, 1, 0}

    two = chip_actions([{:purple, 1}, {:white, 1}, {:purple, 1}])
    assert {two.vp, two.rubies, two.droplet} == {1, 2, 0}

    three = chip_actions(List.duplicate({:purple, 1}, 3))
    assert {three.vp, three.rubies, three.droplet} == {2, 1, 1}

    four = chip_actions(List.duplicate({:purple, 1}, 4))
    assert {four.vp, four.rubies, four.droplet} == {2, 1, 1}
  end

  test "black (solo house rule): any black chip moves the droplet 1, no ruby" do
    g = chip_actions([{:black, 1}, {:white, 2}])
    assert {g.droplet, g.rubies, g.vp} == {1, 1, 0}
    assert chip_actions([{:black, 1}, {:black, 1}]).droplet == 1
    assert chip_actions([{:white, 1}]).droplet == 0
  end

  test "chip actions resolve before the scoring space, even when exploded for VP" do
    # pot index 4 -> scoring space 5: 5 coins, 0 VP, ruby
    g = %{new() | phase: :explosion_choice, exploded?: true, pot_index: 4}
    g = %{g | drawn: [{:green, 1}, {:purple, 1}, {:black, 1}]}
    g = apply!(g, {:explosion_choice, :vp})
    assert {g.vp, g.rubies, g.droplet, g.phase} == {1, 1 + 1 + 1, 1, :spend_rubies}
  end

  test "yellow is in the shop from round 2 and purple from round 3" do
    refute buyable?(shop(1, 20), {:yellow, 1})
    refute buyable?(shop(1, 20), {:purple, 1})
    assert buyable?(shop(2, 20), {:yellow, 1})
    refute buyable?(shop(2, 20), {:purple, 1})
    assert buyable?(shop(3, 20), {:purple, 1})
    assert buyable?(shop(1, 20), {:black, 1})
  end

  test "a fresh game takes its starting bag from the supply" do
    g = new()
    assert g.supply[{:white, 1}] == 20 - 4
    assert g.supply[{:white, 2}] == 8 - 2
    assert g.supply[{:orange, 1}] == 19
    assert g.supply[{:green, 1}] == 14
    assert g.supply[{:black, 1}] == Chips.supply()[{:black, 1}]
  end

  test "buying takes from the supply; an empty supply blocks the buy" do
    g = apply!(shop(1, 20), {:buy, [{:orange, 1}, {:red, 2}]})
    assert g.supply[{:orange, 1}] == 18
    assert g.supply[{:red, 2}] == 7

    out = %{shop(1, 20) | supply: Map.put(new().supply, {:orange, 1}, 0)}
    refute buyable?(out, {:orange, 1})
    refute {:buy, [{:green, 1}, {:orange, 1}]} in Game.legal_actions(out)
    assert buyable?(out, {:green, 1})
  end

  test "the orange die face and the round-6 white chip come from the supply" do
    g = apply!(%{new() | phase: :spend_rubies, round: 5}, :end_round)
    assert g.supply[{:white, 1}] == 15
    assert Enum.count(g.bag, &(&1 == {:white, 1})) == 5

    none = %{g | supply: Map.put(g.supply, {:white, 1}, 0), phase: :spend_rubies, round: 5}
    assert apply!(none, :end_round).bag == g.bag
  end
end
