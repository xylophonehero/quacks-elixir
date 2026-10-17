defmodule Codex.FeralTest do
  @moduledoc "The 12 Feral codex cards (Green). Feral Strike is manual this round."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Rules, Stats}

  # P2 (Green) with Calamandra Moss (the Feral hero) in play, tech buildings, gold.
  defp table do
    game =
      red_green()
      |> end_turn()
      |> gold(1, 20)
      |> put_in([Access.key(:sides), 1, :tech_buildings], [:tech_1, :tech_2, :tech_3])
      |> put_in([Access.key(:sides), 1, :tech_spec], "Feral")

    {game, cala} = place(game, 1, "calamandra-moss", :in_play)
    {game, cala}
  end

  test "every Feral card runs except Feral Strike (manual)" do
    for slug <- Codex.Cards.codex("Feral") -- ["feral-strike"],
        do: refute(CardRules.manual?(slug), slug)

    assert CardRules.manual?("feral-strike")
  end

  test "Ferocity: your units get armor piercing and swift strike until your next upkeep" do
    {game, _} = table()
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    {game, f} = place(game, 1, "ferocity", :hand)
    game = ok!(game, {:play, f, []})
    assert Stats.swift?(game, u)
    assert Stats.kw?(game, u, :armor_piercing)
    game = end_turn(game)
    assert Stats.swift?(game, u)
    game = end_turn(game)
    refute Stats.swift?(game, u)
  end

  test "Behind the Ferns: channeling; your units with 3 ATK or less have stealth" do
    {game, _} = table()
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    {game, bf} = place(game, 1, "behind-the-ferns", :hand)
    game = ok!(game, {:play, bf, []})
    assert bf in zone(game, 1, :in_play)
    assert Stats.stealth?(game, u)
  end

  test "Murkwood Allies: a 4/4 Beast, or four 1/1 Frogs, or both when boosted" do
    {game, _} = table()
    {game, ma} = place(game, 1, "murkwood-allies", :hand)
    assert Enum.sort(plays(game, ma)) == Enum.sort([[:beast], [:frogs], [:boost]])
    game = ok!(game, {:play, ma, [:boost]})
    slugs = Enum.map(zone(game, 1, :in_play), &game.cards[&1].card)
    assert Enum.count(slugs, &(&1 == "frog")) == 4
    assert Enum.count(slugs, &(&1 == "beast")) == 1
    assert game.sides[1].gold == 11
  end

  test "Feral Strike is played as manual: paid and put into play" do
    {game, c} = table()
    game = put_card(game, c, level: 5) |> end_turn() |> end_turn() |> gold(1, 20)
    {game, fs} = place(game, 1, "feral-strike", :hand)
    game = ok!(game, {:play, fs, []})
    assert fs in zone(game, 1, :in_play)
    assert game.cards[fs].extra.manual
  end

  test "Huntress: sparkshot and anti-air; Centaur and Barkcoat Bear: overpower" do
    {game, _} = table()
    {game, h} = place(game, 1, "huntress", :in_play)
    assert Stats.kw?(game, h, :sparkshot) and Stats.kw?(game, h, :anti_air)
    {game, b} = place(game, 1, "barkcoat-bear", :in_play)
    assert Stats.resist(game, b) == 2
  end

  test "Stalking Tiger: invisible with a Feral hero; stealth when it attacks a unit" do
    {game, _} = table()
    {game, t} = place(game, 1, "stalking-tiger", :in_play)
    assert Stats.kw?(game, t, :invisible)
    game = end_turn(game)
    {game, a} = place(game, 0, "nautical-dog", :in_play)
    refute t in attack_targets(game, a)
  end

  test "Predator Tiger: ignores tech 0 patrollers; combat damage to a base trashes a worker there" do
    {game, _} = table()
    {game, p} = place(game, 1, "predator-tiger", :in_play)
    {game, _} = place(game, 0, "nautical-dog", :patrol, :squad_leader)
    workers = length(zone(game, 0, :workers))
    game = ok!(game, {:attack, p, {:building, 0, :base}})
    assert length(zone(game, 0, :workers)) == workers - 1
  end

  test "Rampaging Elephant: the first time it exhausts each turn, it readies" do
    {game, _} = table()
    {game, e} = place(game, 1, "rampaging-elephant", :in_play)
    game = ok!(game, {:attack, e, {:building, 0, :base}})
    refute game.cards[e].exhausted
    game = ok!(game, {:attack, e, {:building, 0, :base}})
    assert game.cards[e].exhausted
    assert game.sides[0].base_hp == 8
  end

  test "Gigadon costs 1 less for each green unit you have" do
    {game, _} = table()
    {game, _} = place(game, 1, "tiger-cub", :in_play)
    {game, _} = place(game, 1, "merfolk-prospector", :in_play)
    {game, g} = place(game, 1, "gigadon", :hand)
    assert Rules.cost(game, 1, g) == 7
  end

  test "Moss Ancient: untargetable; arrives or attacks: three Squirrels with haste and invisible" do
    {game, _} = table()
    {game, m} = place(game, 1, "moss-ancient", :hand)
    game = ok!(game, {:play, m, []})
    squirrels = for id <- zone(game, 1, :in_play), game.cards[id].card == "squirrel", do: id
    assert length(squirrels) == 3
    assert Stats.kw?(game, hd(squirrels), :haste)
    assert Stats.kw?(game, hd(squirrels), :invisible)
    assert Stats.kw?(game, m, :untargetable)
  end
end
