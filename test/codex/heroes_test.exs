defmodule Codex.HeroesTest do
  @moduledoc "Rules mode: heroes (summon, levels, bands, abilities, death)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{Game, Stats}

  defp table(gold \\ 10), do: gold(new(), 0, gold)
  defp hero(game, seat), do: find_hero(game, seat)

  defp find_hero(game, seat) do
    Enum.find(Map.keys(game.cards), fn id ->
      game.cards[id].seat == seat and game.cards[id].level != nil
    end)
  end

  describe "summon" do
    test "2 gold: the hero arrives at level 1 with arrival fatigue" do
      game = table()
      h = hero(game, 0)
      assert {:summon, h} in legal(game)
      game = ok!(game, {:summon, h})
      assert h in zone(game, 0, :in_play)
      assert game.sides[0].gold == 8
      assert %{level: 1, fatigued: true} = game.cards[h]
      assert attack_targets(game, h) == []
      # 1-hero mode: no second summon while it is in play.
      refute {:summon, h} in legal(game)
    end

    test "not with less than 2 gold" do
      game = table(1)
      refute {:summon, hero(game, 0)} in legal(game)
    end
  end

  describe "levels" do
    test "1 gold per level; the middle band heals all damage; no level above max" do
      game = table(20)
      h = hero(game, 0)
      game = game |> ok!({:summon, h}) |> put_card(h, damage: 2)

      game = Enum.reduce(1..3, game, fn _, g -> ok!(g, {:level_up, h}) end)
      assert %{level: 4, damage: 2} = game.cards[h]
      # Troq Bashar's middle band is level 5: 3/4, healed.
      game = ok!(game, {:level_up, h})
      assert %{level: 5, damage: 0} = game.cards[h]
      assert {Stats.atk(game, h), Stats.hp(game, h)} == {3, 4}

      game = Enum.reduce(1..3, game, fn _, g -> ok!(g, {:level_up, h}) end)
      assert game.cards[h].level == 8
      refute {:level_up, h} in legal(game)
      assert game.sides[0].gold == 20 - 2 - 7
    end
  end

  describe "Troq Bashar" do
    test "level 5: attacks deal 1 damage to the opposing base too" do
      {game, h} = place(table(), 0, "troq-bashar", :in_play)
      game = put_card(game, h, level: 5)
      game = ok!(game, {:attack, h, {:building, 1, :base}})
      # 3 ATK + 1 from the ability.
      assert game.sides[1].base_hp == 16
    end

    test "level 8: readiness, it does not exhaust but attacks once per turn" do
      {game, h} = place(table(), 0, "troq-bashar", :in_play)
      game = put_card(game, h, level: 8)
      game = ok!(game, {:attack, h, {:building, 1, :base}})
      refute game.cards[h].exhausted
      assert attack_targets(game, h) == []
      # It can still patrol.
      assert {:patrol, h, :squad_leader} in legal(game)
    end
  end

  describe "River Montoya" do
    defp river(level) do
      game = new() |> ok!(:end_turn) |> gold(1, 10)
      {game, h} = place(game, 1, "river-montoya", :in_play)
      {game, p} = place(game, 0, "older-brother", :patrol, :squad_leader)
      {put_card(game, h, level: level), h, p}
    end

    test "level 3: exhaust to sideline a tech 0 or tech I patroller" do
      {game, h, p} = river(3)
      assert {:ability, h, :sideline, [p]} in legal(game)
      game = ok!(game, {:ability, h, :sideline, [p]})
      assert p in zone(game, 0, :in_play)
      assert game.cards[h].exhausted
    end

    test "not below level 3, not with arrival fatigue" do
      {game, h, _p} = river(2)
      refute Enum.any?(legal(game), &match?({:ability, ^h, _, _}, &1))
      {game, h, _p} = river(3)
      game = put_card(game, h, fatigued: true)
      refute Enum.any?(legal(game), &match?({:ability, ^h, _, _}, &1))
    end

    test "max level: your tech 0 units cost 1 less" do
      {game, h, _p} = river(5)
      {game, u} = place(game, 1, "older-brother", :hand)
      game = gold(game, 1, 1)
      assert {:play, u, []} in legal(game)
      assert h
    end
  end

  describe "hero death" do
    defp duel do
      game = table(20)
      p1 = hero(game, 0)
      game = game |> ok!({:summon, p1}) |> ok!(:end_turn) |> gold(1, 20)
      p2 = hero(game, 1)
      game = ok!(game, {:summon, p2})
      {game, p1, p2}
    end

    test "a dead hero goes to the command zone at level 1; the opposing hero gets 2 levels" do
      {game, p1, p2} = duel()
      game = put_card(game, p1, level: 3, damage: 2)
      game = put_card(game, p2, damage: 1)
      # P1's hero dies (a spell or combat; here damage by hand is enough).
      game = game |> free() |> ok!({:adjust_card, p1, :damage, 2}) |> ok!({:free_mode, false})

      assert p1 in zone(game, 0, :command)
      assert game.cards[p1].level == 1
      # River Montoya 1 → 3: her middle band, healed.
      assert %{level: 3, damage: 0} = game.cards[p2]
    end

    test "it cannot be summoned until after its owner's next turn" do
      {game, p1, _p2} = duel()
      game = game |> free() |> ok!({:adjust_card, p1, :damage, 3}) |> ok!({:free_mode, false})
      game = game |> ok!(:end_turn) |> gold(0, 10)
      refute {:summon, p1} in legal(game)
      game = game |> ok!(:end_turn) |> ok!(:end_turn) |> gold(0, 10)
      assert {:summon, p1} in legal(game)
    end
  end

  test "a hero in combat: it dies and the attacker's hero levels" do
    {game, p1} = place(table(), 0, "troq-bashar", :in_play)
    game = put_card(game, p1, level: 1)
    game = game |> ok!(:end_turn) |> gold(1, 10)
    {game, p2} = place(game, 1, "river-montoya", :in_play)
    {game, unit} = place(game, 1, "older-brother", :in_play)
    game = put_card(game, p1, damage: 2)
    game = ok!(game, {:attack, unit, p1})
    assert p1 in zone(game, 0, :command)
    assert game.cards[p2].level == 3
    assert Game.status(game) == {:playing, [0]}
  end
end
