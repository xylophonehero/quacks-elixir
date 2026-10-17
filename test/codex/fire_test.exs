defmodule Codex.FireTest do
  @moduledoc "The 12 Fire codex cards (Red). Burning Volley is manual this round."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P1 (Red) with Jaina Stormborne (the Fire hero) in play, tech buildings, gold.
  defp table do
    game =
      red_green()
      |> gold(0, 20)
      |> put_in([Access.key(:sides), 0, :tech_buildings], [:tech_1, :tech_2, :tech_3])
      |> put_in([Access.key(:sides), 0, :tech_spec], "Fire")

    {game, jaina} = place(game, 0, "jaina-stormborne", :in_play)
    {game, jaina}
  end

  test "every Fire card runs except Burning Volley (manual)" do
    for slug <- Codex.Cards.codex("Fire") -- ["burning-volley"],
        do: refute(CardRules.manual?(slug), slug)

    assert CardRules.manual?("burning-volley")
  end

  test "Fire Dart: 3 damage to a unit or 2 to a building" do
    {game, _} = table()
    {game, u} = place(game, 1, "ironbark-treant", :in_play)
    {game, fd} = place(game, 0, "fire-dart", :hand)
    game = ok!(game, {:play, fd, [u]})
    assert u in zone(game, 1, :discard)
    {game, fd2} = spawn(game, 0, "fire-dart", :hand)
    game = ok!(game, {:play, fd2, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 18
  end

  test "Ember Sparks: 3 damage divided among 1-3 patrollers and/or buildings" do
    {game, _} = table()
    {game, p} = place(game, 1, "tiger-cub", :patrol, :elite)
    {game, es} = place(game, 0, "ember-sparks", :hand)
    base = {:building, 1, :base}
    assert [p, base, base] in plays(game, es)
    game = ok!(game, {:play, es, [p, base, base]})
    assert game.cards[p].damage == 1
    assert game.sides[1].base_hp == 18
  end

  test "Flame Arrow: 4 damage to a unit or hero, 3 to a building" do
    {game, _} = table()
    {game, fa} = place(game, 0, "flame-arrow", :hand)
    game = ok!(game, {:play, fa, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 17
  end

  test "Hotter Fire: red spells and abilities deal 1 more" do
    {game, j} = table()
    {game, _} = place(game, 0, "hotter-fire", :in_play)
    {game, fa} = place(game, 0, "flame-arrow", :hand)
    game = ok!(game, {:play, fa, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 16
    game = put_card(game, j, level: 4)
    game = ok!(game, {:ability, j, :jaina_1, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 14
  end

  test "Lobber: haste, ⤵ → 1 damage to a building; Firebat: 1 gold, ⤵ → 2 to a patroller or building" do
    {game, _} = table()
    {game, l} = place(game, 0, "lobber", :hand)
    game = ok!(game, {:play, l, []})
    game = ok!(game, {:ability, l, :lob, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 19
    {game, fb} = place(game, 0, "firebat", :in_play)
    game = ok!(game, {:ability, fb, :firebat, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 17
  end

  test "Bamstamper Lizzo: arrives, 3 damage to a unit" do
    {game, _} = table()
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    {game, bl} = place(game, 0, "bamstamper-lizzo", :hand)
    game = ok!(game, {:play, bl, [u]})
    assert u in zone(game, 1, :discard)
  end

  test "Doubleshot Archer: long-range; attacks: 3 damage to that opponent's base" do
    {game, _} = table()
    {game, a} = place(game, 0, "doubleshot-archer", :in_play)
    {game, d} = place(game, 1, "tiger-cub", :in_play)
    game = ok!(game, {:attack, a, d})
    assert game.sides[1].base_hp == 17
    assert game.cards[a].damage == 0
  end

  test "Molting Firebird damages a building: 1 damage to every opposing unit and hero" do
    {game, _} = table()
    {game, f} = place(game, 0, "molting-firebird", :in_play)
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    game = ok!(game, {:attack, f, {:building, 1, :base}})
    assert game.cards[u].damage == 1
  end

  test "Firehouse: ⤵ → 2 damage; if it destroys the target, it readies" do
    {game, _} = table()
    {game, fh} = place(game, 0, "firehouse", :in_play)
    {game, u} = place(game, 1, "tiger-cub", :in_play)
    game = ok!(game, {:ability, fh, :firehouse, [u]})
    assert u in zone(game, 1, :discard)
    refute game.cards[fh].exhausted
    game = ok!(game, {:ability, fh, :firehouse, [{:building, 1, :base}]})
    assert game.cards[fh].exhausted
  end

  test "Cinderblast Dragon: flying, resist 2 (its free Fire spell is not done)" do
    {game, _} = table()
    {game, d} = place(game, 0, "cinderblast-dragon", :hand)
    game = ok!(game, {:play, d, []})
    assert Stats.kw?(game, d, :flying)
    assert Stats.resist(game, d) == 2
  end
end
