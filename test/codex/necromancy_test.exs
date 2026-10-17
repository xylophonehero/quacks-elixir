defmodule Codex.NecromancyTest do
  @moduledoc "The 12 Necromancy codex cards (Black)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P1 (Black) with Garth Torken (the Necromancy hero) in play, tech buildings, gold.
  defp table do
    game = black_blue() |> gold(0, 20) |> set_tech(0, [:tech_1, :tech_2, :tech_3], "Necromancy")
    {game, g} = place(game, 0, "garth-torken", :in_play)
    {game, g}
  end

  defp in_play(game, seat, slug),
    do: for(id <- Codex.Zones.in_play(game, seat), game.cards[id].card == slug, do: id)

  test "every Necromancy card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Necromancy"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Nether Drain: one hero loses two levels (no level up this turn), another gains two" do
    {game, g} = table()
    game = put_card(game, g, level: 4)
    {game, b} = place(game, 1, "bigby-hayes", :in_play)
    {game, nd} = place(game, 0, "nether-drain", :hand)
    game = ok!(game, {:play, nd, [g, b]})
    assert game.cards[g].level == 2 and game.cards[b].level == 3
    refute {:level_up, g} in legal(game)
  end

  test "Lich's Bargain: sacrifice a worker, 4 damage to your base, a Skeleton, a Zombie, a Horror" do
    {game, _} = table()
    {game, lb} = place(game, 0, "lich-s-bargain", :hand)
    workers = length(zone(game, 0, :workers))
    game = ok!(game, {:play, lb, []})
    assert length(zone(game, 0, :workers)) == workers - 1
    assert game.sides[0].base_hp == 16
    assert [_] = in_play(game, 0, "skeleton")
    assert [z] = in_play(game, 0, "zombie")
    assert [h] = in_play(game, 0, "horror")
    assert Stats.atk(game, z) == 2 and Stats.kw?(game, h, :deathtouch)
  end

  test "Doom Grasp: sacrifice a unit; if you do, destroy a tech 0-II unit or hero" do
    {game, _} = table()
    {game, mine} = place(game, 0, "thieving-imp", :in_play)
    {game, haunt} = place(game, 0, "pestering-haunt", :in_play)
    {game, u} = spawn(game, 1, "justice-juggernaut", :in_play)
    game = put_card(game, u, extra: %{crumbling: true})
    {game, dg} = place(game, 0, "doom-grasp", :hand)
    refute Enum.any?(plays(game, dg), fn [sac, _] -> sac == haunt end)
    game = ok!(game, {:play, dg, [mine, u]})
    assert mine in zone(game, 0, :discard) and u in zone(game, 1, :discard)
  end

  test "Death Rites: each of your units that dies this turn destroys an opposing lowest tech unit" do
    {game, g} = table()
    game = Codex.Effects.level_up(game, g, 6)
    game = game |> end_turn() |> end_turn() |> gold(0, 20)
    {game, mine} = place(game, 0, "thieving-imp", :in_play)
    {game, low} = spawn(game, 1, "overeager-cadet", :in_play)
    {game, high} = spawn(game, 1, "lawbringer-gryphon", :in_play)
    {game, dr} = place(game, 0, "death-rites", :hand)
    game = ok!(game, {:play, dr, []})
    game = Codex.Effects.destroy(game, mine)
    assert low in zone(game, 1, :discard) and high in zone(game, 1, :in_play)
    game = ok!(game, :end_turn)
    refute Map.has_key?(game.sides[0].effects, :death_rites)
  end

  test "Hooded Executioner: boost 3 to destroy each opponent's weakest unit" do
    {game, _} = table()
    # Both tech I: the Scribe (1 ATK) is weaker than the Cadet (2 ATK).
    {game, other} = spawn(game, 1, "overeager-cadet", :in_play)
    {game, weak} = spawn(game, 1, "scribe", :in_play)
    {game, he} = place(game, 0, "hooded-executioner", :hand)
    assert [:boost] in plays(game, he) and [:plain] in plays(game, he)
    game = ok!(game, {:play, he, [:boost]})
    assert game.sides[0].gold == 15
    assert weak in zone(game, 1, :discard) and other in zone(game, 1, :in_play)
  end

  test "Bone Collector: attacks: summon a Skeleton" do
    {game, _} = table()
    {game, bc} = place(game, 0, "bone-collector", :in_play)
    game = ok!(game, {:attack, bc, {:building, 1, :base}})
    assert [_] = in_play(game, 0, "skeleton")
  end

  test "Blackhand Resurrector: ⤵, sacrifice it → a dead hero returns at max level" do
    {game, g} = table()
    game = Codex.Effects.destroy(game, g)
    assert g in zone(game, 0, :command)
    {game, r} = place(game, 0, "blackhand-resurrector", :in_play)
    game = ok!(game, {:ability, r, :resurrect, [g]})
    assert g in zone(game, 0, :in_play) and game.cards[g].level == 7
    # Garth's "Max level:" triggers: the sacrificed Resurrector comes back from the discard pile.
    assert r in zone(game, 0, :in_play)
  end

  test "Skeletal Lord: Skeletons +1/+1; exhaust five Skeletons → a unit from hand into play" do
    {game, _} = table()
    {game, sl} = place(game, 0, "skeletal-lord", :in_play)
    game = Codex.Effects.summon(game, 0, "skeleton", 5)
    [sk | _] = in_play(game, 0, "skeleton")
    assert Stats.atk(game, sk) == 2
    {game, z} = place(game, 0, "zarramonde-the-obliterator", :hand)
    game = ok!(game, {:ability, sl, :rally, [z]})
    assert z in zone(game, 0, :in_play)
    assert Enum.all?(in_play(game, 0, "skeleton"), &game.cards[&1].exhausted)
    assert game.sides[0].gold == 20
  end

  test "Corpse Catapult: a corpse rune when your unit dies; ⤵, remove two → 6 damage to a building" do
    {game, _} = table()
    {game, cc} = place(game, 0, "corpse-catapult", :in_play)
    game = Codex.Effects.summon(game, 0, "skeleton", 2)
    game = Enum.reduce(in_play(game, 0, "skeleton"), game, &Codex.Effects.destroy(&2, &1))
    assert game.cards[cc].extra.corpse == 2
    game = ok!(game, {:ability, cc, :catapult, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 14 and game.cards[cc].extra.corpse == 0
  end

  test "Wight: unstoppable and deathtouch when it attacks a hero" do
    {game, _} = table()
    {game, w} = place(game, 0, "wight", :in_play)
    {game, _} = spawn(game, 1, "overeager-cadet", :patrol, :squad_leader)
    {game, b} = place(game, 1, "bigby-hayes", :in_play)
    game = put_card(game, b, level: 5)
    assert b in attack_targets(game, w)
    game = ok!(game, {:attack, w, b})
    assert b in zone(game, 1, :command)
  end

  test "Necromancer: long-range; another non-token unit of yours dies → a Skeleton" do
    {game, _} = table()
    {game, n} = place(game, 0, "necromancer", :in_play)
    {game, imp} = place(game, 0, "thieving-imp", :in_play)
    assert Stats.kw?(game, n, :long_range)
    game = Codex.Effects.destroy(game, imp)
    assert [sk] = in_play(game, 0, "skeleton")
    game = Codex.Effects.destroy(game, sk)
    assert in_play(game, 0, "skeleton") == []
  end

  test "Lord of Shadows: your black units are invisible" do
    {game, _} = table()
    {game, l} = place(game, 0, "lord-of-shadows", :in_play)
    {game, imp} = place(game, 0, "thieving-imp", :in_play)
    assert Stats.kw?(game, l, :invisible) and Stats.kw?(game, imp, :invisible)
  end
end
