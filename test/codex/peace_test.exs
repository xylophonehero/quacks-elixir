defmodule Codex.PeaceTest do
  @moduledoc "The 12 Peace codex cards (Blue)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P1 (Blue) with General Onimaru (the Peace hero) in play, tech buildings, gold.
  defp table do
    game = blue_black() |> gold(0, 20) |> set_tech(0, [:tech_1, :tech_2, :tech_3], "Peace")
    {game, oni} = place(game, 0, "general-onimaru", :in_play)
    {game, oni}
  end

  test "every Peace card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Peace"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Boot Camp: exhaust a unit or non-Peace hero, a +1/+1 rune on it, draw a card" do
    {game, oni} = table()
    {game, u} = spawn(game, 1, "thieving-imp", :patrol, :elite)
    {game, bc} = place(game, 0, "boot-camp", :hand)
    refute [oni] in plays(game, bc)
    n = length(hand(game, 0))
    game = ok!(game, {:play, bc, [u]})
    assert game.cards[u].exhausted and game.cards[u].plus == 1
    assert u in zone(game, 1, :in_play)
    assert length(hand(game, 0)) == n
  end

  test "Elite Training: up to two of yours get +1 ATK, +1 armor, anti-air and sparkshot until your upkeep" do
    {game, oni} = table()
    {game, u} = place(game, 0, "overeager-cadet", :in_play)
    {game, et} = place(game, 0, "elite-training", :hand)
    game = ok!(game, {:play, et, [u, oni]})
    assert Stats.atk(game, u) == 3 and Stats.armor(game, u) == 1
    assert Stats.kw?(game, u, :anti_air) and Stats.kw?(game, oni, :sparkshot)
    game = end_turn(game)
    assert Stats.atk(game, u) == 3
    game = end_turn(game)
    assert Stats.atk(game, u) == 2 and not Stats.kw?(game, u, :anti_air)
  end

  test "General's Hammer: 3 damage to a building" do
    {game, _} = table()
    {game, gh} = place(game, 0, "general-s-hammer", :hand)
    game = ok!(game, {:play, gh, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 17
  end

  test "The Art of War: your Peace hero is unstoppable, swift, +2 ATK / +2 armor" do
    {game, oni} = table()
    game = Codex.Effects.level_up(game, oni, 7)
    game = game |> end_turn() |> end_turn() |> gold(0, 20)
    {game, _} = spawn(game, 1, "thieving-imp", :patrol, :squad_leader)
    {game, aw} = place(game, 0, "the-art-of-war", :hand)
    game = ok!(game, {:play, aw, [oni]})
    assert Stats.kw?(game, oni, :unstoppable) and Stats.swift?(game, oni)
    assert Stats.armor(game, oni) == 2
    assert {:building, 1, :base} in attack_targets(game, oni)
  end

  test "Overeager Cadet: a 2/2 for 0" do
    {game, _} = table()
    {game, c} = place(game, 0, "overeager-cadet", :hand)
    game = ok!(game, {:play, c, []})
    assert game.sides[0].gold == 20 and Stats.atk(game, c) == 2
  end

  test "Brave Knight: readiness; dies from combat damage → back to its owner's hand" do
    {game, _} = table()
    {game, k} = place(game, 0, "brave-knight", :in_play)
    assert Stats.readiness?(game, k)
    {game, p} = spawn(game, 1, "spectral-tiger", :patrol, :squad_leader)
    game = put_card(game, p, card: "terras-q-the-shackled")
    game = ok!(game, {:attack, k, p})
    assert k in hand(game, 0)
    # A spell kill is not combat damage.
    {game, k2} = spawn(game, 0, "brave-knight", :in_play)
    game = Codex.Effects.destroy(game, k2)
    assert k2 in zone(game, 0, :discard)
  end

  test "Drill Sergeant: a +1/+1 rune when you play a unit from hand; move a rune" do
    {game, _} = table()
    {game, d} = place(game, 0, "drill-sergeant", :in_play)
    {game, c} = place(game, 0, "overeager-cadet", :hand)
    game = ok!(game, {:play, c, []})
    assert game.cards[d].plus == 1
    game = ok!(game, {:ability, d, :rune_move, [c]})
    assert game.cards[d].plus == 0 and game.cards[c].plus == 1
  end

  test "Flagstone Spy: invisible; combat damage to a building steals 1 gold" do
    {game, _} = table()
    {game, spy} = place(game, 0, "flagstone-spy", :in_play)
    {game, _} = spawn(game, 1, "thieving-imp", :patrol, :squad_leader)
    game = put_in(game.sides[1].gold, 3) |> gold(0, 5)
    assert {:building, 1, :base} in attack_targets(game, spy)
    game = ok!(game, {:attack, spy, {:building, 1, :base}})
    assert game.sides[1].gold == 2 and game.sides[0].gold == 6
  end

  test "Debilitator Alpha: as squad leader, units attacking it get -1 ATK" do
    {game, _} = table()
    {game, da} = place(game, 0, "debilitator-alpha", :patrol, :squad_leader)
    game = end_turn(game)
    {game, a} = spawn(game, 1, "wight", :in_play)
    game = put_card(game, a, fatigued: false)
    game = ok!(game, {:attack, a, da})
    # 4 ATK - 1, then 1 armor: 2 damage.
    assert game.cards[da].damage == 2
  end

  test "Air Hammer: flying, +2 ATK against a damaged building" do
    {game, _} = table()
    {game, ah} = place(game, 0, "air-hammer", :in_play)
    game = put_in(game.sides[1].base_hp, 19)
    game = ok!(game, {:attack, ah, {:building, 1, :base}})
    assert game.sides[1].base_hp == 14
  end

  test "Flagstone Garrison: draw a card when you play a unit from hand" do
    {game, _} = table()
    {game, _} = place(game, 0, "flagstone-garrison", :in_play)
    {game, c} = place(game, 0, "overeager-cadet", :hand)
    n = length(hand(game, 0))
    game = ok!(game, {:play, c, []})
    assert length(hand(game, 0)) == n
  end

  test "Patriot Gryphon: unstoppable by units with 2 ATK or less; destroys a building → its ATK to the base" do
    {game, _} = table()
    {game, g} = place(game, 0, "patriot-gryphon", :in_play)
    {game, p} = spawn(game, 1, "thieving-imp", :patrol, :squad_leader)
    game = put_card(game, p, card: "lawbringer-gryphon")
    {game, small} = spawn(game, 1, "skeleton", :patrol, :elite)
    assert Stats.resist(game, g) == 2
    game = put_in(game.sides[1].tech_buildings, [:tech_1])
    targets = attack_targets(game, g)
    assert p in targets and {:building, 1, :tech_1} not in targets
    game = put_card(game, p, card: "skeleton")
    _ = small
    targets = attack_targets(game, g)
    assert {:building, 1, :tech_1} in targets
    game = ok!(game, {:attack, g, {:building, 1, :tech_1}})
    # 2 for the tech building, 6 from the Gryphon.
    assert game.sides[1].base_hp == 12
  end
end
