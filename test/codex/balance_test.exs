defmodule Codex.BalanceTest do
  @moduledoc "The 12 Balance codex cards (Green)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P2 (Green) with Master Midori (the Balance hero) in play, tech buildings, gold.
  defp table do
    game =
      red_green()
      |> end_turn()
      |> gold(1, 20)
      |> put_in([Access.key(:sides), 1, :tech_buildings], [:tech_1, :tech_2, :tech_3])
      |> put_in([Access.key(:sides), 1, :tech_spec], "Balance")

    {game, midori} = place(game, 1, "master-midori", :in_play)
    {game, midori}
  end

  test "every Balance card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Balance"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Moment's Peace: until your next turn, your units can't patrol and opposing units can't attack you" do
    {game, _} = table()
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    {game, mp} = place(game, 1, "moment-s-peace", :hand)
    game = ok!(game, {:play, mp, []})
    refute Enum.any?(legal(game), &match?({:patrol, ^u, _}, &1))
    game = end_turn(game)
    {game, a} = place(game, 0, "nautical-dog", :in_play)
    assert attack_targets(game, a) == []
  end

  test "Nature Reclaims: trash an upgrade, ongoing spell or building card, then itself" do
    {game, _} = table()
    {game, up} = place(game, 0, "bloodburn", :in_play)
    {game, nr} = place(game, 1, "nature-reclaims", :hand)
    game = ok!(game, {:play, nr, [up]})
    assert up in game.trash and nr in game.trash
  end

  test "Circle of Life: sacrifice a green unit, a green unit one tech higher (cost ≤ 5) from the codex into play" do
    {game, _} = table()
    {game, cub} = place(game, 1, "tiger-cub", :in_play)
    {game, col} = place(game, 1, "circle-of-life", :hand)
    choices = plays(game, col)

    assert Enum.all?(choices, fn [u, c] ->
             u == cub and
               game.cards[c].card in ~w(gemscout-owl tiny-basilisk huntress centaur galina-glimmer giant-panda)
           end)

    [[^cub, c] | _] = choices
    game = ok!(game, {:play, col, [cub, c]})
    assert c in zone(game, 1, :in_play)
    assert cub in zone(game, 1, :discard)
  end

  test "Final Showdown: attach to your Balance hero: +3/+3, readiness, resist 1; the opponent gets two 3/3 Hunters" do
    {game, m} = table()
    game = put_card(game, m, level: 8)
    game = game |> end_turn() |> end_turn() |> gold(1, 20)
    {game, fs} = place(game, 1, "final-showdown", :hand)
    game = ok!(game, {:play, fs, [m]})
    assert {Stats.atk(game, m), Stats.hp(game, m)} == {7, 8}
    assert Stats.readiness?(game, m)
    assert Stats.resist(game, m) == 1
    hunters = for id <- zone(game, 0, :in_play), game.cards[id].card == "hunter", do: id
    assert length(hunters) == 2
    n = length(hand(game, 1))
    game = ok!(game, {:attack, m, {:building, 0, :base}})
    assert length(hand(game, 1)) == n + 1
  end

  test "Gemscout Owl: flying, can't attack, resist 1; upkeep: gain 1 gold" do
    {game, _} = table()
    {game, o} = place(game, 1, "gemscout-owl", :in_play)
    assert attack_targets(game, o) == []
    game = game |> gold(1, 0) |> end_turn() |> end_turn()
    # 5 workers + the Owl.
    assert game.sides[1].gold == 6
  end

  test "Tiny Basilisk: deathtouch; tech 0 units cannot attack it and it ignores tech 0 patrollers" do
    {game, _} = table()
    {game, b} = place(game, 1, "tiny-basilisk", :in_play)
    {game, _} = place(game, 0, "nautical-dog", :patrol, :squad_leader)
    assert {:building, 0, :base} in attack_targets(game, b)
    game = end_turn(game)
    {game, d} = place(game, 0, "mad-man", :in_play)
    refute b in attack_targets(game, d)
    {game, t} = spawn(game, 0, "steam-tank", :in_play)
    game = ok!(game, {:attack, t, b})
    # Deathtouch kills the 3/6 tank.
    assert t in zone(game, 0, :discard)
  end

  test "Fairie Dragon: arrives, may put a feather rune on a tech I or II unit: 3/1 with flying" do
    {game, _} = table()
    {game, u} = place(game, 1, "centaur", :in_play)
    {game, fd} = place(game, 1, "fairie-dragon", :hand)
    assert [nil] in plays(game, fd)
    game = ok!(game, {:play, fd, [u]})
    assert {Stats.atk(game, u), Stats.hp(game, u)} == {3, 1}
    assert Stats.kw?(game, u, :flying)
  end

  test "Dothram Horselord: upkeep, it joins the player with the most total ATK" do
    {game, _} = table()
    {game, h} = place(game, 1, "dothram-horselord", :in_play)
    game = end_turn(game)
    {game, _} = spawn(game, 0, "oversized-rhinoceros", :in_play)
    {game, _} = spawn(game, 0, "oversized-rhinoceros", :in_play)
    game = end_turn(game)
    # P2's upkeep: P1 has more total ATK.
    assert h in zone(game, 0, :in_play)
  end

  test "Wandering Mimic: flying while a unit or hero with flying is in play" do
    {game, _} = table()
    {game, m} = place(game, 1, "wandering-mimic", :in_play)
    refute Stats.kw?(game, m, :flying)
    {game, _} = place(game, 0, "shoddy-glider", :in_play)
    assert Stats.kw?(game, m, :flying)
  end

  test "Potent Basilisk: arrives, may destroy an upgrade or ongoing spell; untargetable" do
    {game, _} = table()
    {game, up} = place(game, 0, "bloodburn", :in_play)
    {game, pb} = place(game, 1, "potent-basilisk", :hand)
    game = ok!(game, {:play, pb, [up]})
    assert up in zone(game, 0, :discard)
    {game, wither} = spawn(game, 1, "wither", :hand)
    refute Enum.any?(plays(game, wither), &(&1 == [pb]))
  end

  test "Tyrannosaurus Rex: arrives, destroy up to two units, upgrades and/or workers" do
    {game, _} = table()
    {game, u} = place(game, 0, "nautical-dog", :in_play)
    {game, t} = place(game, 1, "tyrannosaurus-rex", :hand)
    workers = length(zone(game, 0, :workers))
    game = ok!(game, {:play, t, [u, {:worker, 0}]})
    assert u in zone(game, 0, :discard)
    assert length(zone(game, 0, :workers)) == workers - 1
  end
end
