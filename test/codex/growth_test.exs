defmodule Codex.GrowthTest do
  @moduledoc "The 12 Growth codex cards (Green)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Rules, Stats}

  # P2 (Green) with Argagarg Garg (the Growth hero) in play, tech buildings, gold.
  defp table do
    game =
      red_green()
      |> end_turn()
      |> gold(1, 20)
      |> put_in([Access.key(:sides), 1, :tech_buildings], [:tech_1, :tech_2, :tech_3])
      |> put_in([Access.key(:sides), 1, :tech_spec], "Growth")

    {game, garg} = place(game, 1, "argagarg-garg", :in_play)
    {game, garg}
  end

  test "every Growth card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Growth"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Polymorph: Squirrel: a 1/1 Squirrel with no abilities until your next upkeep" do
    {game, _} = table()
    {game, u} = place(game, 0, "steam-tank", :in_play)
    {game, p} = place(game, 1, "polymorph-squirrel", :hand)
    game = ok!(game, {:play, p, [u]})
    assert {Stats.atk(game, u), Stats.hp(game, u)} == {1, 1}
    game = end_turn(game)
    assert {Stats.atk(game, u), Stats.hp(game, u)} == {1, 1}
    game = end_turn(game)
    assert game.cards[u].card == "steam-tank"
  end

  test "a polymorphed unit that dies goes to its owner's discard pile (it is not a token)" do
    {game, _} = table()
    {game, u} = place(game, 0, "steam-tank", :in_play)
    {game, p} = place(game, 1, "polymorph-squirrel", :hand)
    game = ok!(game, {:play, p, [u]})
    game = game |> free() |> ok!({:adjust_card, u, :damage, 1}) |> ok!({:free_mode, false})
    assert u in zone(game, 0, :discard)
    assert game.cards[u].card == "steam-tank"
  end

  test "Dinosize: +6 ATK / +6 armor this turn" do
    {game, _} = table()
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    {game, d} = place(game, 1, "dinosize", :hand)
    game = ok!(game, {:play, d, [u]})
    assert {Stats.atk(game, u), Stats.armor(game, u)} == {8, 6}
  end

  test "Spirit of the Panda: attach to a unit: +2/+2, attacks: gain 1; healing 1" do
    {game, _} = table()
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    {game, sp} = place(game, 1, "spirit-of-the-panda", :hand)
    game = ok!(game, {:play, sp, [u]})
    assert {Stats.atk(game, u), Stats.hp(game, u)} == {4, 4}
    gold = game.sides[1].gold
    game = ok!(game, {:attack, u, {:building, 0, :base}})
    assert game.sides[1].gold == gold + 1
    game = game |> free() |> ok!({:move, u, {1, :discard}, 0}) |> ok!({:free_mode, false})
    assert sp in zone(game, 1, :discard)
  end

  test "Stampede: an ultimate spell; +3 ATK / +3 armor; excess combat damage hits the base" do
    {game, g} = table()
    game = put_card(game, g, level: 5)
    {game, u} = place(game, 1, "oversized-rhinoceros", :in_play)
    game = game |> end_turn() |> end_turn() |> gold(1, 20)
    {game, d} = place(game, 0, "nautical-dog", :in_play)
    {game, st} = place(game, 1, "stampede", :hand)
    game = ok!(game, {:play, st, []})
    base = game.sides[0].base_hp
    game = ok!(game, {:attack, u, d})
    # 10 ATK on a 1/1: 9 excess to the base.
    assert game.sides[0].base_hp == base - 9
  end

  test "Galina Glimmer: legendary; upkeep: 1 gold for every two of your green units" do
    {game, _} = table()
    {game, gg} = place(game, 1, "galina-glimmer", :in_play)
    {game, _} = place(game, 1, "tiger-cub", :in_play)
    {game, g2} = spawn(game, 1, "galina-glimmer", :hand)
    game = ok!(game, {:play, g2, []})
    assert g2 in zone(game, 1, :discard)
    game = game |> gold(1, 0) |> end_turn() |> end_turn()
    # 5 workers + 1 (2 green units).
    assert game.sides[1].gold == 6
    assert gg
  end

  test "Artisan Mantis: arrives, repair 3 damage from a building" do
    {game, _} = table()
    game = put_in(game.sides[1].base_hp, 15)
    {game, m} = place(game, 1, "artisan-mantis", :hand)
    game = ok!(game, {:play, m, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 18
  end

  test "Blooming Ancient: a +1/+1 rune when another unit or hero of yours arrives; move one" do
    {game, _} = table()
    {game, b} = place(game, 1, "blooming-ancient", :in_play)
    {game, cub} = place(game, 1, "tiger-cub", :hand)
    game = ok!(game, {:play, cub, []})
    assert game.cards[b].plus == 1
    game = ok!(game, {:ability, b, :rune_move, [cub]})
    assert game.cards[cub].plus == 1
  end

  test "Blooming Elm: ⤵ → three +1/+1 runes on a unit without one; units with runes have overpower" do
    {game, _} = table()
    {game, e} = place(game, 1, "blooming-elm", :in_play)
    {game, cub} = place(game, 1, "tiger-cub", :in_play)
    game = ok!(game, {:ability, e, :elm, [cub]})
    assert game.cards[cub].plus == 3
    assert Stats.kw?(game, cub, :overpower)
  end

  test "Might of Leaf and Claw: a growth rune when your attacker deals combat damage; 5 runes: +5/+5" do
    {game, _} = table()
    {game, m} = place(game, 1, "might-of-leaf-and-claw", :in_play)
    {game, cub} = place(game, 1, "tiger-cub", :in_play)
    game = ok!(game, {:attack, cub, {:building, 0, :base}})
    assert game.cards[m].extra.growth == 1
    game = Codex.Zones.update_card(game, m, &%{&1 | extra: %{growth: 5}})
    assert Stats.atk(game, cub) == 7
  end

  test "Guargum: Growth spells are free and need no Growth hero" do
    {game, garg} = table()
    game = game |> free() |> ok!({:move, garg, {1, :command}, nil}) |> ok!({:free_mode, false})
    {game, _} = place(game, 1, "guargum-eternal-sentinel", :in_play)
    {game, d} = place(game, 1, "dinosize", :hand)
    assert Rules.cost(game, 1, d) == 0
    assert plays(game, d) != []
  end

  test "Oversized Rhinoceros and Giant Panda" do
    {game, _} = table()
    {game, p} = place(game, 1, "giant-panda", :hand)
    game = ok!(game, {:play, p, []})
    assert game.cards[p].exhausted
  end
end
