defmodule Codex.AnarchyTest do
  @moduledoc "The 12 Anarchy codex cards (Red)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P1 (Red) with Captain Zane (the Anarchy hero) in play, tech buildings, gold.
  defp table do
    game = red_green() |> gold(0, 20) |> put_in_tech([:tech_1, :tech_2, :tech_3], "Anarchy")
    {game, zane} = place(game, 0, "captain-zane", :in_play)
    {game, zane}
  end

  defp put_in_tech(game, b, spec),
    do:
      game
      |> put_in([Access.key(:sides), 0, :tech_buildings], b)
      |> put_in([Access.key(:sides), 0, :tech_spec], spec)

  test "every Anarchy card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Anarchy"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Chaos Mirror: swap the printed ATK of two forces until the end of the turn" do
    {game, _} = table()
    {game, a} = place(game, 0, "nautical-dog", :in_play)
    {game, b} = place(game, 1, "tiger-cub", :in_play)
    {game, cm} = place(game, 0, "chaos-mirror", :hand)
    game = ok!(game, {:play, cm, [a, b]})
    # Dog: printed 2 + frenzy 1; Cub: printed 1.
    assert {Stats.atk(game, a), Stats.atk(game, b)} == {3, 1}
    game = end_turn(game)
    assert Stats.atk(game, b) == 2
  end

  test "Detonate: trash an opposing worker, then trash itself" do
    {game, _} = table()
    {game, d} = place(game, 0, "detonate", :hand)
    workers = length(zone(game, 1, :workers))
    game = ok!(game, {:play, d, [{:worker, 1}]})
    assert length(zone(game, 1, :workers)) == workers - 1
    assert d in game.trash
    assert_conserved(game)
  end

  test "Surprise Attack: two 3/1 Sharks with haste and ephemeral" do
    {game, _} = table()
    {game, sa} = place(game, 0, "surprise-attack", :hand)
    game = ok!(game, {:play, sa, []})
    sharks = for id <- zone(game, 0, :in_play), game.cards[id].card == "shark", do: id
    assert length(sharks) == 2
    assert {:building, 1, :base} in attack_targets(game, hd(sharks))
    game = end_turn(game)
    assert Enum.all?(sharks, &(&1 in game.trash))
  end

  test "Maximum Anarchy: an ultimate spell; destroy all units and heroes" do
    {game, zane} = table()
    game = put_card(game, zane, level: 6)
    {game, a} = place(game, 0, "nautical-dog", :in_play)
    {game, b} = place(game, 1, "tiger-cub", :in_play)
    game = game |> end_turn() |> end_turn() |> gold(0, 20)
    {game, ma} = place(game, 0, "maximum-anarchy", :hand)
    game = ok!(game, {:play, ma, []})
    assert zane in zone(game, 0, :command)
    assert a in zone(game, 0, :discard) and b in zone(game, 1, :discard)
  end

  test "Calypso Vystari: ⤵ sideline a patroller, only after you played a spell this turn" do
    {game, _} = table()
    {game, c} = place(game, 0, "calypso-vystari", :in_play)
    {game, p} = place(game, 1, "tiger-cub", :patrol, :squad_leader)
    assert abilities(game, c) == []
    {game, sa} = place(game, 0, "surprise-attack", :hand)
    game = ok!(game, {:play, sa, []})
    game = ok!(game, {:ability, c, :sideline, [p]})
    assert p in zone(game, 1, :in_play)
  end

  test "Gunpoint Taxman kills a patroller: steal 1 gold" do
    {game, _} = table()
    {game, t} = place(game, 0, "gunpoint-taxman", :in_play)
    {game, p} = place(game, 1, "merfolk-prospector", :patrol, :elite)
    game = put_in(game.sides[1].gold, 3) |> gold(0, 5)
    game = ok!(game, {:attack, t, p})
    assert game.sides[1].gold == 2
    assert game.sides[0].gold == 6
  end

  test "Disguised Monkey: haste, arrives with stealth: past the patrollers" do
    {game, _} = table()
    {game, _} = place(game, 1, "tiger-cub", :patrol, :squad_leader)
    {game, m} = place(game, 0, "disguised-monkey", :hand)
    game = ok!(game, {:play, m, []})
    assert {:building, 1, :base} in attack_targets(game, m)
  end

  test "Chameleon Lizzo: haste, stealth, back to the hand at the end of the turn" do
    {game, _} = table()
    {game, l} = place(game, 0, "chameleon-lizzo", :hand)
    game = ok!(game, {:play, l, []})
    game = end_turn(game)
    assert l in hand(game, 0)
  end

  test "Marauder: boost 3 to trash an opposing worker" do
    {game, _} = table()
    {game, m} = place(game, 0, "marauder", :hand)
    assert [:plain] in plays(game, m) and [:boost] in plays(game, m)
    workers = length(zone(game, 1, :workers))
    game = ok!(game, {:play, m, [:boost]})
    assert game.sides[0].gold == 14
    assert length(zone(game, 1, :workers)) == workers - 1
  end

  test "Steam Tank: +4 ATK against buildings" do
    {game, _} = table()
    {game, t} = place(game, 0, "steam-tank", :in_play)
    game = ok!(game, {:attack, t, {:building, 1, :base}})
    assert game.sides[1].base_hp == 13
  end

  test "Sanatorium: 1 gold, ⤵ → draw, put up to two tech 0-II units from the hand into play with haste and ephemeral" do
    {game, _} = table()
    {game, san} = place(game, 0, "sanatorium", :in_play)
    {game, u} = place(game, 0, "steam-tank", :hand)
    game = ok!(game, {:ability, san, :sanatorium, [u, nil]})
    assert u in zone(game, 0, :in_play)
    assert {:building, 1, :base} in attack_targets(game, u)
    game = end_turn(game)
    # Ephemeral: it died at the end of the turn (the discard pile may be in the deck now).
    refute u in zone(game, 0, :in_play)
    assert u in zone(game, 0, :discard) or u in zone(game, 0, :deck)
  end

  test "Pirate Gunship: flying, haste, long-range, resist 2, obliterate 2" do
    {game, _} = table()
    {game, g} = place(game, 0, "pirate-gunship", :hand)
    game = ok!(game, {:play, g, []})
    assert Stats.resist(game, g) == 2
    {game, d} = place(game, 1, "tiger-cub", :in_play)
    game = ok!(game, {:attack, g, {:building, 1, :base}})
    # Obliterate 2 destroyed the cub; the base took 7.
    assert d in zone(game, 1, :discard)
    assert game.sides[1].base_hp == 13
  end
end
