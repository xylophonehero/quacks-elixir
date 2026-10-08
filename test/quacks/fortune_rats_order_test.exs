defmodule Quacks.FortuneRatsOrderTest do
  use ExUnit.Case, async: true

  import Quacks.GameHelpers

  alias Quacks.Game

  # Rulebook §3: the Fortune Teller card first, then the rat tails (round 28).
  defp round_start(vps, card) do
    g = Game.new(seed: {1, 2, 3}, players: length(vps), fortune: false)

    vps
    |> Enum.with_index()
    |> Enum.reduce(g, fn {vp, seat}, g -> put(g, seat, vp: vp) end)
    |> put(round: 3, fortune_deck: List.wrap(card))
    |> Game.start_round()
  end

  test "VP from a purple choice counts for the rat tails" do
    # 5 and 3 VP; seat 0 takes Boomberry Cleanse's 4 VP (9), seat 1 a white chip out
    g = round_start([5, 3], :p6)
    assert g.phase == :fortune_choice
    g = g |> apply!(0, {:fortune, :vp}) |> apply!(1, {:fortune, :remove_white})

    assert g.phase == :potions
    assert me(g, 0).vp == 9 and me(g, 0).rat_stone == 0
    # the tails at 4 and 7 lie between 3 and 9 (with 5 it was only the one at 4)
    assert me(g, 1).rat_stone == 2
    assert me(g, 1).pot_index == me(g, 1).droplet + 2
    assert {1, {:rats, 2}} in g.log
  end

  test "Infestation and Good Start still act on the rats placed before them" do
    g = round_start([5, 3], :p7)
    assert me(g, 1).rat_stone == 2

    g = round_start([5, 3], :p9)
    assert Game.legal_actions(g, 1) == [{:fortune, {:rats_back, 1}}, {:fortune, :skip}]
  end

  test "a round without a card places the rats at once" do
    g = round_start([5, 3], nil)
    assert g.phase == :potions and me(g, 1).rat_stone == 1
  end
end
