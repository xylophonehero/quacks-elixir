defmodule Quacks.ChipEffectsTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game
  alias Quacks.Rules.Chips

  @seed {1, 2, 3}

  defp new, do: Game.new(seed: @seed, fortune: false, rules: %{supply: :limited})

  defp new(players),
    do: Game.new(seed: @seed, players: players, fortune: false, rules: %{supply: :limited})

  # Draw `chip` with `others` left in the bag: put `chip` where the rng will pick it.
  defp force_draw_leaving(game, chip, others) do
    {i, _} = :rand.uniform_s(length(others) + 1, game.rng)
    apply!(put(game, bag: List.insert_at(others, i - 1, chip)), :draw)
  end

  # Run step B on a hand-built pot without the die and without the space's VP:
  # the exploded "buy" path on pot index 0 (scoring space 1: 1 coin, 0 VP, no ruby).
  defp chip_actions(chips) do
    new()
    |> exploded(0, chips)
    |> apply!({:explosion_choice, :buy})
  end

  defp resolved(chips), do: me(chip_actions(chips))

  # Hand-build `seat`'s pot at index 0 and leave the player at the explosion choice.
  defp exploded(game, seat, chips),
    do:
      put(game, seat,
        phase: :explosion_choice,
        exploded?: true,
        drawn: placed(chips),
        pot_index: 0
      )

  # Step B for every seat of a multiplayer game: each seat's pot hand-built, all
  # exploded, all choosing to buy (no die, no VP).
  defp chip_actions_for(pots) do
    g = new(length(pots))

    g =
      pots
      |> Enum.with_index()
      |> Enum.reduce(g, fn {chips, seat}, g -> exploded(g, seat, chips) end)

    Enum.reduce(g.seats, g, &apply!(&2, &1, {:explosion_choice, :buy}))
  end

  # Give hand-built pot chips (newest first) a position each, so `drawn` has its shape.
  defp placed(chips), do: chips |> Enum.reverse() |> Enum.with_index(1) |> Enum.reverse()

  defp shop(round, coins), do: put(new(), phase: :buy, round: round, coins: coins)

  defp buyable?(game, chip), do: {:buy, [chip]} in Game.legal_actions(game)

  test "red moves 0, 1 or 2 extra spaces by the oranges already in the pot" do
    assert me(force_draws(new(), [{:red, 2}])).pot_index == 2
    assert me(force_draws(new(), [{:orange, 1}, {:red, 2}])).pot_index == 1 + 2 + 1
    assert me(force_draws(new(), [{:orange, 1}, {:orange, 1}, {:red, 1}])).pot_index == 2 + 1 + 1
    three = List.duplicate({:orange, 1}, 3)
    assert me(force_draws(new(), three ++ [{:red, 4}])).pot_index == 3 + 4 + 2
    # the red chip itself is not an orange; a later orange does not act retroactively
    assert me(force_draws(new(), [{:red, 1}, {:orange, 1}])).pot_index == 2
  end

  test "the recorded position of a red chip includes the orange bonus" do
    g = force_draws(new(), [{:orange, 1}, {:red, 2}])
    assert me(g).drawn == [{{:red, 2}, 1 + 2 + 1}, {{:orange, 1}, 1}]
    assert Game.scoring_index(g) == 5
  end

  test "mandrake: the returned white leaves a gap; the next chip counts from the yellow" do
    g = new() |> force_draws([{:white, 3}, {:yellow, 1}]) |> apply!(:return_white)
    g = force_draws(g, [{:white, 1}])
    assert me(g).drawn == [{{:white, 1}, 5}, {{:yellow, 1}, 4}]
    assert Game.pot_chips(g) == [{:white, 1}, {:yellow, 1}]
  end

  test "a chip placed through a blue chip continues from the blue chip's space" do
    g = force_draws(new(), [{:white, 3}, {:blue, 1}])
    g = put(g, phase: :blue_choice, bag: [], pending: [{:white, 1}, {:orange, 1}])
    g = apply!(g, {:place, {:white, 1}})
    assert me(g).drawn == [{{:white, 1}, 5}, {{:blue, 1}, 4}, {{:white, 3}, 3}]
    assert {0, {:returned, {:orange, 1}}} in g.log
  end

  test "yellow after white offers to return the white; its space stays empty" do
    g = force_draws(new(), [{:white, 3}, {:yellow, 1}])
    assert Game.phase(g, 0) == :yellow_choice
    assert Game.legal_actions(g) == [:return_white, :keep]
    assert me(g).pot_index == 4

    kept = apply!(g, :keep)
    assert Game.phase(kept, 0) == :potions
    assert me(kept).drawn == [{{:yellow, 1}, 4}, {{:white, 3}, 3}]
    assert Game.white_sum(kept) == 3

    returned = apply!(g, :return_white)
    assert Game.phase(returned, 0) == :potions
    assert me(returned).drawn == [{{:yellow, 1}, 4}]
    assert me(returned).bag == [{:white, 3}]
    assert me(returned).pot_index == 4
    assert Game.white_sum(returned) == 0
    refute :use_flask in Game.legal_actions(returned)
  end

  test "yellow after a coloured chip, or as the first chip, has no effect" do
    assert Game.phase(force_draws(new(), [{:white, 3}, {:orange, 1}, {:yellow, 1}]), 0) ==
             :potions

    assert Game.phase(force_draws(new(), [{:yellow, 2}]), 0) == :potions
  end

  test "blue draws its value in extra chips, fewer when the bag is short" do
    g = force_draw_leaving(new(), {:blue, 4}, [{:white, 1}, {:orange, 1}])
    assert Game.phase(g, 0) == :blue_choice
    assert Enum.sort(me(g).pending) == [{:orange, 1}, {:white, 1}]
    assert me(g).bag == []
    assert me(g).drawn == [{{:blue, 4}, 4}]
    assert Game.legal_actions(g) == [{:place, {:orange, 1}}, {:place, {:white, 1}}, :return_all]

    one = force_draw_leaving(new(), {:blue, 1}, [{:white, 1}, {:orange, 1}])
    assert length(me(one).pending) == 1 and length(me(one).bag) == 1

    empty = force_draws(new(), [{:blue, 2}])
    assert Game.phase(empty, 0) == :potions
    assert me(empty).pending == []
  end

  test "blue: returning all puts every extra chip back in the bag" do
    g = put(new(), phase: :blue_choice, bag: [{:green, 1}], pending: [{:white, 1}, {:white, 1}])
    assert Game.legal_actions(g) == [{:place, {:white, 1}}, :return_all]

    g = apply!(g, :return_all)
    assert Game.phase(g, 0) == :potions
    assert me(g).pending == []
    assert Enum.sort(me(g).bag) == [{:green, 1}, {:white, 1}, {:white, 1}]
  end

  test "blue -> white chain counts for the explosion and chains chip actions" do
    pot = force_draws(new(), [{:white, 3}, {:white, 2}, {:white, 2}, {:blue, 1}])
    assert Game.white_sum(pot) == 7

    g = put(pot, phase: :blue_choice, bag: [], pending: [{:white, 1}, {:orange, 1}])
    boom = apply!(g, {:place, {:white, 1}})
    assert Game.phase(boom, 0) == :explosion_choice
    assert me(boom).exploded?
    assert hd(me(boom).drawn) == {{:white, 1}, me(pot).pot_index + 1}
    assert me(boom).bag == [{:orange, 1}]
    assert me(boom).pending == []
    assert me(boom).pot_index == me(pot).pot_index + 1

    # placing a red chains its own on-draw effect (one orange already in the pot)
    red =
      put(pot,
        phase: :blue_choice,
        drawn: [{{:orange, 1}, 1}],
        pot_index: 1,
        pending: [{:red, 1}]
      )

    red = apply!(red, {:place, {:red, 1}})
    assert Game.phase(red, 0) == :potions
    assert me(red).pot_index == 1 + 1 + 1

    # the flask undoes a white placed through a blue chip too
    safe = force_draws(new(), [{:white, 3}, {:blue, 1}])
    flask = put(safe, phase: :blue_choice, bag: [], pending: [{:white, 1}])
    flask = apply!(flask, {:place, {:white, 1}})
    assert :use_flask in Game.legal_actions(flask)
    flask = apply!(flask, :use_flask)
    assert me(flask).pot_index == me(safe).pot_index
    assert me(flask).drawn == me(safe).drawn
  end

  test "green gives a ruby only for the last or next-to-last chip" do
    assert resolved([{:green, 1}, {:white, 1}]).rubies == 2
    assert resolved([{:white, 1}, {:green, 4}]).rubies == 2
    assert resolved([{:green, 2}, {:green, 1}, {:white, 1}]).rubies == 3
    assert resolved([{:white, 1}, {:white, 1}, {:green, 1}]).rubies == 1
  end

  test "purple tiers: 1 VP; 1 VP + ruby; 2 VP + droplet" do
    one = resolved([{:purple, 1}, {:white, 1}])
    assert {one.vp, one.rubies, one.droplet} == {1, 1, 0}

    two = resolved([{:purple, 1}, {:white, 1}, {:purple, 1}])
    assert {two.vp, two.rubies, two.droplet} == {1, 2, 0}

    three = resolved(List.duplicate({:purple, 1}, 3))
    assert {three.vp, three.rubies, three.droplet} == {2, 1, 1}

    four = resolved(List.duplicate({:purple, 1}, 4))
    assert {four.vp, four.rubies, four.droplet} == {2, 1, 1}
  end

  test "black (solo house rule): any black chip moves the droplet 1, no ruby" do
    p = resolved([{:black, 1}, {:white, 2}])
    assert {p.droplet, p.rubies, p.vp} == {1, 1, 0}
    assert resolved([{:black, 1}, {:black, 1}]).droplet == 1
    assert resolved([{:white, 1}]).droplet == 0
  end

  test "black with 2 players: equal count (1+) -> droplet; more than the opponent -> droplet + ruby" do
    more = chip_actions_for([[{:black, 1}, {:white, 1}], [{:white, 1}]])
    assert {me(more, 0).droplet, me(more, 0).rubies} == {1, 2}
    assert {me(more, 1).droplet, me(more, 1).rubies} == {0, 1}
    assert {0, {:black, :droplet_ruby}} in more.log
    refute Enum.any?(more.log, &match?({1, {:black, _}}, &1))

    equal = chip_actions_for([[{:black, 1}, {:white, 1}], [{:white, 1}, {:black, 1}]])
    assert {me(equal, 0).droplet, me(equal, 0).rubies} == {1, 1}
    assert {me(equal, 1).droplet, me(equal, 1).rubies} == {1, 1}
    assert {0, {:black, :droplet}} in equal.log and {1, {:black, :droplet}} in equal.log

    # 0 = 0 is no tie: a droplet needs at least one black chip (Nick's ruling).
    none = chip_actions_for([[{:white, 1}], [{:white, 1}]])
    assert {me(none, 0).droplet, me(none, 1).droplet} == {0, 0}
    refute Enum.any?(none.log, &match?({_, {:black, _}}, &1))
  end

  test "black with 3 players: more than one neighbour -> droplet; more than both -> droplet + ruby" do
    g = chip_actions_for([[{:black, 1}, {:black, 1}], [{:black, 1}], [{:white, 1}]])
    assert {me(g, 0).droplet, me(g, 0).rubies} == {1, 2}
    assert {me(g, 1).droplet, me(g, 1).rubies} == {1, 1}
    assert {me(g, 2).droplet, me(g, 2).rubies} == {0, 1}
    assert {0, {:black, :droplet_ruby}} in g.log
    assert {1, {:black, :droplet}} in g.log
  end

  test "the log records green rubies only when a green chip scored" do
    assert {0, {:green_rubies, 2}} in chip_actions([{:green, 2}, {:green, 1}, {:white, 1}]).log
    assert {0, {:green_rubies, 1}} in chip_actions([{:white, 1}, {:green, 1}]).log
    log = chip_actions([{:white, 1}, {:white, 1}, {:green, 1}]).log
    refute Enum.any?(log, &match?({_, {:green_rubies, _}}, &1))
  end

  test "the log records the purple tier and its payoff" do
    assert {0, {:purple, 1, :vp1}} in chip_actions([{:purple, 1}, {:white, 1}]).log
    assert {0, {:purple, 2, :vp1_ruby}} in chip_actions([{:purple, 1}, {:purple, 1}]).log
    assert {0, {:purple, 3, :vp2_droplet}} in chip_actions(List.duplicate({:purple, 1}, 4)).log
    refute Enum.any?(chip_actions([{:white, 1}]).log, &match?({_, {:purple, _, _}}, &1))
  end

  test "the log records the black house rule once, however many black chips" do
    log = chip_actions([{:black, 1}, {:black, 1}]).log
    assert Enum.count(log, &(&1 == {0, {:black, :droplet}})) == 1
    refute {0, {:black, :droplet}} in chip_actions([{:white, 1}]).log
  end

  test "chip actions resolve before the scoring space, even when exploded for VP" do
    # pot index 4 -> scoring space 5: 5 coins, 0 VP, ruby
    g = put(new(), phase: :explosion_choice, exploded?: true, pot_index: 4)
    g = put(g, drawn: placed([{:green, 1}, {:purple, 1}, {:black, 1}]))
    g = apply!(g, {:explosion_choice, :vp})
    assert {me(g).vp, me(g).rubies, me(g).droplet, Game.phase(g, 0)} == {1, 1 + 1 + 1, 1, :shop}
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

    out = put(shop(1, 20), supply: Map.put(new().supply, {:orange, 1}, 0))
    refute buyable?(out, {:orange, 1})
    refute {:buy, [{:green, 1}, {:orange, 1}]} in Game.legal_actions(out)
    assert buyable?(out, {:green, 1})
  end

  test "the default infinite supply is the box, never counted down, never empty" do
    g = Game.new(seed: @seed, fortune: false)
    assert g.rules.supply == :infinite and g.supply == Chips.supply()

    # even a box at 0 sells, and nothing is counted down
    empty = Map.new(g.supply, fn {chip, _} -> {chip, 0} end)
    g = put(g, phase: :buy, coins: 20, supply: empty)
    assert buyable?(g, {:orange, 1})
    g = apply!(g, {:buy, [{:orange, 1}, {:red, 2}]})
    assert g.supply == empty
    assert {:orange, 1} in me(g).bag and {:red, 2} in me(g).bag

    g = apply!(put(g, phase: :rubies, round: 5), :end_round)
    assert Enum.count(me(g).bag, &(&1 == {:white, 1})) == 5 and g.supply == empty
  end

  test "the orange die face and the round-6 white chip come from the supply" do
    g = apply!(put(new(), phase: :rubies, round: 5), :end_round)
    assert g.supply[{:white, 1}] == 15
    assert Enum.count(me(g).bag, &(&1 == {:white, 1})) == 5

    none = put(g, supply: Map.put(g.supply, {:white, 1}, 0), phase: :rubies, round: 5)
    assert me(apply!(none, :end_round)).bag == me(g).bag
  end
end
