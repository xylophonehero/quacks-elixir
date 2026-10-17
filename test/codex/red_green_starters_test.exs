defmodule Codex.RedGreenStartersTest do
  @moduledoc "The Red and Green starting decks and the six Red and Green heroes."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{Game, Stats}

  # P1 (Red) to act with gold.
  defp red(gold \\ 20), do: red_green() |> gold(0, gold)
  # P2 (Green) to act with gold.
  defp green(gold \\ 20), do: red_green() |> end_turn() |> gold(1, gold)

  defp hero(game, seat, slug), do: place(game, seat, slug, :in_play)

  describe "Red starting deck" do
    test "Nautical Dog: frenzy 1; Mad Man: haste" do
      {game, dog} = place(red(), 0, "nautical-dog", :in_play)
      assert Stats.atk(game, dog) == 2
      {game, mad} = place(game, 0, "mad-man", :hand)
      game = ok!(game, {:play, mad, []})
      assert {:building, 1, :base} in attack_targets(game, mad)
    end

    test "Bombaster: 1 gold and sacrifice it → 2 damage to a patrolling unit" do
      game = red()
      {game, p} = place(game, 1, "tiger-cub", :patrol, :elite)
      {game, b} = place(game, 0, "bombaster", :in_play)
      assert {:blast, [p]} in abilities(game, b)
      game = ok!(game, {:ability, b, :blast, [p]})
      assert hd(zone(game, 0, :discard)) == b
      assert hd(zone(game, 1, :discard)) == p
      assert game.sides[0].gold == 19
    end

    test "Careless Musketeer: ⤵ → 1 damage to a unit or building and 1 to your base" do
      {game, m} = place(red(), 0, "careless-musketeer", :in_play)
      game = ok!(game, {:ability, m, :shoot, [{:building, 1, :base}]})
      assert game.sides[1].base_hp == 19
      assert game.sides[0].base_hp == 19
      assert game.cards[m].exhausted
    end

    test "an exhaust ability needs no arrival fatigue (Bloodburn too)" do
      {game, m} = place(red(), 0, "careless-musketeer", :hand)
      game = ok!(game, {:play, m, []})
      assert abilities(game, m) == []
    end

    test "Bloodrage Ogre: back to the hand at the end of its turn if it did not arrive or attack" do
      {game, o} = place(red(), 0, "bloodrage-ogre", :hand)
      game = ok!(game, {:play, o, []})
      game = end_turn(game)
      # It arrived: it stays. P2's turn does not count.
      assert o in zone(game, 0, :in_play)
      game = end_turn(game)
      # P1's turn 2: it neither arrived nor attacked.
      game = ok!(game, :end_turn)
      assert o in hand(game, 0)
    end

    test "Bloodrage Ogre stays when it attacked" do
      {game, o} = place(red(), 0, "bloodrage-ogre", :in_play)
      game = ok!(game, {:attack, o, {:building, 1, :base}})
      game = ok!(game, :end_turn)
      assert o in zone(game, 0, :in_play)
    end

    test "Makeshift Rambaster: haste, +2 ATK against buildings, can't patrol" do
      {game, r} = place(red(), 0, "makeshift-rambaster", :hand)
      game = ok!(game, {:play, r, []})
      refute Enum.any?(legal(game), &match?({:patrol, ^r, _}, &1))
      game = ok!(game, {:attack, r, {:building, 1, :base}})
      assert game.sides[1].base_hp == 17
    end

    test "Bloodburn: a blood rune when a unit dies (limit 4); ⤵, remove 2 → 1 damage" do
      game = red()
      {game, bb} = place(game, 0, "bloodburn", :in_play)
      {game, u} = place(game, 1, "tiger-cub", :in_play)
      {game, v} = place(game, 1, "merfolk-prospector", :in_play)

      game =
        game
        |> free()
        |> ok!({:adjust_card, u, :damage, 2})
        |> ok!({:adjust_card, v, :damage, 1})
        |> ok!({:free_mode, false})

      assert game.cards[bb].extra.blood == 2
      game = ok!(game, {:ability, bb, :burn, [{:building, 1, :base}]})
      assert game.sides[1].base_hp == 19
      assert game.cards[bb].extra.blood == 0
    end

    test "Scorch, Charge, Pillage" do
      {game, _} = hero(red(), 0, "captain-zane")
      {game, scorch} = place(game, 0, "scorch", :hand)
      game = ok!(game, {:play, scorch, [{:building, 1, :base}]})
      assert game.sides[1].base_hp == 18

      {game, u} = place(game, 0, "nautical-dog", :hand)
      game = ok!(game, {:play, u, []})
      {game, charge} = place(game, 0, "charge", :hand)
      game = ok!(game, {:play, charge, [u]})
      assert Stats.atk(game, u) == 3
      assert {:building, 1, :base} in attack_targets(game, u)

      game = put_in(game.sides[1].gold, 5)
      {game, pillage} = place(game, 0, "pillage", :hand)
      gold = game.sides[0].gold
      game = ok!(game, {:play, pillage, []})
      assert game.sides[1].base_hp == 17
      assert game.sides[1].gold == 4
      assert game.sides[0].gold == gold - 1 + 1
    end
  end

  describe "Green starting deck" do
    test "Merfolk Prospector: ⤵ → gain 1 gold" do
      {game, m} = place(green(5), 1, "merfolk-prospector", :in_play)
      game = ok!(game, {:ability, m, :prospect, []})
      assert game.sides[1].gold == 6
    end

    test "Young Treant: arrives, draw a card; can't attack" do
      {game, t} = place(green(), 1, "young-treant", :hand)
      n = length(hand(game, 1))
      game = ok!(game, {:play, t, []})
      assert length(hand(game, 1)) == n
      game = game |> end_turn() |> end_turn()
      assert attack_targets(game, t) == []
    end

    test "Playful Panda: arrives exhausted with a 0/1 Wisp" do
      {game, p} = place(green(), 1, "playful-panda", :hand)
      game = ok!(game, {:play, p, []})
      assert game.cards[p].exhausted
      assert Enum.any?(zone(game, 1, :in_play), &(game.cards[&1].card == "wisp"))
      assert_conserved(game)
    end

    test "Ironbark Treant: -2 ATK / +2 armor while patrolling" do
      game = green()
      {game, t} = place(game, 1, "ironbark-treant", :patrol, :elite)
      game = end_turn(game)
      # Patrolling in the elite slot: 3 - 2 + 1.
      assert Stats.atk(game, t) == 2
      assert Stats.armor(game, t) == 2
      {game, a} = place(game, 0, "nautical-dog", :in_play)
      game = ok!(game, {:attack, a, t})
      assert game.cards[t].damage == 0
    end

    test "Spore Shambler: arrives with two +1/+1 runes; moves one for 1 gold or ⤵" do
      {game, sp} = place(green(), 1, "spore-shambler", :hand)
      {game, cub} = place(game, 1, "tiger-cub", :in_play)
      game = ok!(game, {:play, sp, []})
      assert game.cards[sp].plus == 2
      game = ok!(game, {:ability, sp, :spore, [cub]})
      assert game.cards[cub].plus == 1
      assert game.cards[sp].plus == 1
    end

    test "Verdant Tree: healing 1; ⤵ → tech buildings build at once" do
      game = green()
      {extra, _} = Game.add_cards(game, 1, ["worker"])

      game =
        put_in(
          extra.sides[1].zones.workers,
          extra.sides[1].zones.workers ++ (Map.keys(extra.cards) -- Map.keys(game.cards))
        )

      {game, tree} = place(game, 1, "verdant-tree", :in_play)
      game = ok!(game, {:build, :tech_1})
      game = ok!(game, {:ability, tree, :instant_build, []})
      assert :tech_1 in game.sides[1].tech_buildings
    end

    test "Rich Earth: hire workers for free" do
      {game, _} = place(green(0), 1, "rich-earth", :in_play)
      [c | _] = hand(game, 1)
      game = ok!(game, {:hire, c})
      assert game.sides[1].gold == 0
    end

    test "Rampant Growth: +2 ATK / +2 armor this turn; Forest's Favor: a +1/+1 rune" do
      {game, _} = hero(green(), 1, "argagarg-garg")
      {game, cub} = place(game, 1, "tiger-cub", :in_play)
      {game, rg} = place(game, 1, "rampant-growth", :hand)
      game = ok!(game, {:play, rg, [cub]})
      assert {Stats.atk(game, cub), Stats.armor(game, cub)} == {4, 2}
      {game, ff} = place(game, 1, "forest-s-favor", :hand)
      game = ok!(game, {:play, ff, [cub]})
      assert game.cards[cub].plus == 1
    end
  end

  describe "Red heroes" do
    test "Captain Zane: haste; middle band, kills a scavenger: 1 gold" do
      game = red() |> end_turn()
      {game, p} = place(game, 1, "merfolk-prospector", :patrol, :scavenger)
      game = end_turn(game)
      {game, z} = hero(game, 0, "captain-zane")
      game = game |> put_card(z, level: 4) |> gold(0, 5)
      gold = game.sides[0].gold
      game = ok!(game, {:attack, z, p})
      # Zane's gold, and none for the scavenger's side (its own gold is P2's).
      assert game.sides[0].gold == gold + 1
    end

    test "Captain Zane, max level: shove a patroller, then 1 damage to it" do
      game = red() |> end_turn()
      {game, p} = place(game, 1, "tiger-cub", :patrol, :squad_leader)
      game = end_turn(game)
      {game, z} = hero(game, 0, "captain-zane")
      game = put_card(game, z, level: 5)
      game = ok!(game, {:level_up, z})
      assert zone(game, 1, :patrol).elite == p
      assert game.cards[p].damage == 1
    end

    test "Drakk Ramhorn: dies → 1 damage to each opposing base; middle band: frenzy 1" do
      {game, d} = hero(red(), 0, "drakk-ramhorn")
      {game, dog} = place(game, 0, "nautical-dog", :in_play)
      game = put_card(game, d, level: 4)
      # Frenzy 1 + Drakk's frenzy 1.
      assert Stats.atk(game, dog) == 3
      game = game |> free() |> ok!({:adjust_card, d, :damage, 3}) |> ok!({:free_mode, false})
      assert game.sides[1].base_hp == 19
    end

    test "Drakk Ramhorn, max level: the first unit from the hand each turn gets haste" do
      {game, d} = hero(red(), 0, "drakk-ramhorn")
      game = put_card(game, d, level: 6)
      {game, a} = place(game, 0, "bombaster", :hand)
      game = ok!(game, {:play, a, []})
      assert {:building, 1, :base} in attack_targets(game, a)
      {game, b} = place(game, 0, "nautical-dog", :hand)
      game = ok!(game, {:play, b, []})
      assert attack_targets(game, b) == []
    end

    test "Jaina Stormborne: sparkshot; level 4 ⤵ 1 damage; level 7 ⤵ 3 damage" do
      {game, j} = hero(red(), 0, "jaina-stormborne")
      assert Stats.kw?(game, j, :sparkshot)
      game = put_card(game, j, level: 4)
      game = ok!(game, {:ability, j, :jaina_1, [{:building, 1, :base}]})
      assert game.sides[1].base_hp == 19
      game = game |> end_turn() |> end_turn() |> put_card(j, level: 7)
      game = ok!(game, {:ability, j, :jaina_3, [{:building, 1, :base}]})
      assert game.sides[1].base_hp == 16
    end
  end

  describe "Green heroes" do
    test "Master Midori, middle band: units with no abilities cost 1 less and get +2/+2; max: flying on her turn" do
      {game, m} = hero(green(), 1, "master-midori")
      game = put_card(game, m, level: 5)
      {game, cub} = place(game, 1, "tiger-cub", :in_play)
      assert {Stats.atk(game, cub), Stats.hp(game, cub)} == {4, 4}
      {game, cub2} = spawn(game, 1, "tiger-cub", :hand)
      assert Codex.Rules.cost(game, 1, cub2) == 1
      game = put_card(game, m, level: 8)
      assert Stats.kw?(game, m, :flying)
    end

    test "Calamandra Moss: discard two cards → stealth; middle band: your units resist 1" do
      {game, c} = hero(green(), 1, "calamandra-moss")
      [a, b | _] = hand(game, 1)
      game = ok!(game, {:ability, c, :hide, [a, b]})
      assert Stats.stealth?(game, c)
      game = put_card(game, c, level: 3)
      {game, cub} = place(game, 1, "tiger-cub", :in_play)
      assert Stats.resist(game, cub) == 1
    end

    test "Calamandra Moss, max level: 4 gold, ⤵ → a Tiger from the codex into play" do
      {game, c} = hero(green(), 1, "calamandra-moss")
      game = put_card(game, c, level: 5)
      assert [{:tiger, [t]} | _] = Enum.filter(abilities(game, c), &match?({:tiger, _}, &1))
      game = ok!(game, {:ability, c, :tiger, [t]})
      assert t in zone(game, 1, :in_play)
      assert game.sides[1].gold == 16
    end

    test "Argagarg Garg: arrives with a Wisp; level 3 ⤵ +1/+1 armor; max: a Water Elemental" do
      game = green()
      [g] = for id <- zone(game, 1, :command), game.cards[id].card == "argagarg-garg", do: id
      game = ok!(game, {:summon, g})
      assert Enum.any?(zone(game, 1, :in_play), &(game.cards[&1].card == "wisp"))
      game = game |> end_turn() |> end_turn() |> gold(1, 20)
      game = Enum.reduce(1..2, game, fn _, g2 -> ok!(g2, {:level_up, g}) end)
      {game, cub} = place(game, 1, "tiger-cub", :in_play)
      game = ok!(game, {:ability, g, :argagarg, [cub]})
      assert {Stats.atk(game, cub), Stats.armor(game, cub)} == {3, 1}
      game = Enum.reduce(1..2, game, fn _, g2 -> ok!(g2, {:level_up, g}) end)
      assert Enum.any?(zone(game, 1, :in_play), &(game.cards[&1].card == "water-elemental"))
    end
  end
end
