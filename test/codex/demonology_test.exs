defmodule Codex.DemonologyTest do
  @moduledoc "The 12 Demonology codex cards (Black)."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{CardRules, Stats}

  # P1 (Black) with Vandy Anadrose (the Demonology hero) in play, tech buildings, gold.
  defp table do
    game = black_blue() |> gold(0, 20) |> set_tech(0, [:tech_1, :tech_2, :tech_3], "Demonology")
    {game, v} = place(game, 0, "vandy-anadrose", :in_play)
    {game, v}
  end

  defp in_play(game, seat, slug),
    do: for(id <- Codex.Zones.in_play(game, seat), game.cards[id].card == slug, do: id)

  test "every Demonology card runs (none is manual)" do
    for slug <- Codex.Cards.codex("Demonology"), do: refute(CardRules.manual?(slug), slug)
  end

  test "Soul Stone: attached unit +1/+1; instead of dying, it loses its damage and the stone goes" do
    {game, _} = table()
    {game, u} = place(game, 0, "thieving-imp", :in_play)
    {game, ss} = place(game, 0, "soul-stone", :hand)
    game = ok!(game, {:play, ss, [u]})
    assert Stats.atk(game, u) == 3 and Stats.hp(game, u) == 3
    game = Codex.Effects.destroy(game, u)
    assert u in zone(game, 0, :in_play) and ss in zone(game, 0, :discard)
    assert game.cards[u].damage == 0
  end

  test "Dark Pact: 2 damage to a base, then that player draws 2 cards" do
    {game, _} = table()
    {game, dp} = place(game, 0, "dark-pact", :hand)
    n = length(hand(game, 1))
    game = ok!(game, {:play, dp, [{:building, 1, :base}]})
    assert game.sides[1].base_hp == 18 and length(hand(game, 1)) == n + 2
  end

  test "Shadow Blade: 3 damage to a patroller; if it dies, its controller discards at random" do
    {game, _} = table()
    {game, p} = spawn(game, 1, "tax-collector", :patrol, :elite)
    {game, sb} = place(game, 0, "shadow-blade", :hand)
    n = length(hand(game, 1))
    game = ok!(game, {:play, sb, [p]})
    assert p in zone(game, 1, :discard)
    assert length(hand(game, 1)) == n - 1
  end

  test "Metamorphosis: sacrifice your units; heroes max level, Demons, +2 runes, readiness, invisible" do
    {game, v} = table()
    game = Codex.Effects.level_up(game, v, 4)
    game = game |> end_turn() |> end_turn() |> gold(0, 20)
    {game, g} = place(game, 0, "garth-torken", :in_play)
    {game, u} = place(game, 0, "thieving-imp", :in_play)
    {game, m} = place(game, 0, "metamorphosis", :hand)
    game = ok!(game, {:play, m, []})
    assert u in zone(game, 0, :discard)
    assert game.cards[g].level == 7 and game.cards[g].plus == 2
    assert Stats.readiness?(game, g) and Stats.kw?(game, g, :invisible)
    assert Stats.subtype?(game, g, "Demon")
    # Vandy ("Queen of Demons") is not a Demon herself: she changes too.
    assert game.cards[v].plus == 2
  end

  test "Gargoyle: indestructible, can't attack or patrol; ① unlocks it until your upkeep" do
    {game, _} = table()
    {game, gar} = place(game, 0, "gargoyle", :in_play)
    assert attack_targets(game, gar) == []
    refute Enum.any?(legal(game), &match?({:patrol, ^gar, _}, &1))
    game = Codex.Effects.destroy(game, gar)
    assert gar in zone(game, 0, :in_play) and game.cards[gar].exhausted
    game = game |> end_turn() |> end_turn() |> gold(0, 5)
    game = ok!(game, {:ability, gar, :gargoyle, []})
    assert Stats.atk(game, gar) == 3 and Stats.kw?(game, gar, :flying)
    assert {:building, 1, :base} in attack_targets(game, gar)
    assert abilities(game, gar) == []
    game = Codex.Effects.destroy(game, gar)
    assert gar in zone(game, 0, :discard)
  end

  test "Twilight Baron: overpower; you can't play tech II or III units" do
    {game, _} = table()
    {game, b} = place(game, 0, "twilight-baron", :in_play)
    assert Stats.kw?(game, b, :overpower)
    {game, w} = place(game, 0, "voidblocker", :hand)
    assert plays(game, w) == []
  end

  test "Voidblocker: an opponent attacking it exhausts another of its ready units" do
    {game, _} = table()
    {game, vb} = place(game, 0, "voidblocker", :patrol, :squad_leader)
    game = end_turn(game)
    {game, a} = spawn(game, 1, "spectral-tiger", :in_play)
    {game, b} = spawn(game, 1, "overeager-cadet", :in_play)
    game = put_card(game, a, fatigued: false) |> put_card(b, fatigued: false)
    game = ok!(game, {:attack, a, vb})
    assert game.cards[b].exhausted
  end

  test "Blackhand Dozer: overpower; your damage leaves opposing bases at 6 at least" do
    {game, _} = table()
    {game, d} = place(game, 0, "blackhand-dozer", :in_play)
    game = put_in(game.sides[1].base_hp, 8)
    game = ok!(game, {:attack, d, {:building, 1, :base}})
    assert game.sides[1].base_hp == 6
  end

  test "Blackhand Dozer dies: the active player destroys one of your lowest tech units" do
    {game, _} = table()
    {game, d} = place(game, 0, "blackhand-dozer", :in_play)
    {game, imp} = place(game, 0, "thieving-imp", :in_play)
    game = Codex.Effects.destroy(game, d)
    assert imp in zone(game, 0, :discard)
  end

  test "Banefire Golem: upkeep: sacrifice a unit → 1 damage to each opposing unit, hero, building" do
    {game, _} = table()
    {game, _g} = place(game, 0, "banefire-golem", :in_play)
    {game, imp} = place(game, 0, "thieving-imp", :in_play)
    {game, u} = spawn(game, 1, "tax-collector", :in_play)
    game = game |> end_turn() |> end_turn()
    assert imp in zone(game, 0, :discard)
    assert game.cards[u].damage == 1 and game.sides[1].base_hp == 19
  end

  test "Terras Q: four Warlocks for the opponent; can't attack or patrol while they live" do
    {game, _} = table()
    {game, t} = place(game, 0, "terras-q-the-shackled", :hand)
    game = ok!(game, {:play, t, []})
    warlocks = in_play(game, 1, "warlock")
    assert length(warlocks) == 4 and Stats.resist(game, t) == 3
    game = game |> end_turn() |> end_turn()
    assert attack_targets(game, t) == []
    game = Enum.reduce(warlocks, game, &Codex.Effects.destroy(&2, &1))
    assert attack_targets(game, t) != []
  end

  test "Shrine of Forbidden Knowledge: upkeep 1 to your base; draw +1, hand +1; Demons pass units" do
    {game, _} = table()
    {game, _} = place(game, 0, "shrine-of-forbidden-knowledge", :in_play)
    {game, imp} = place(game, 0, "thieving-imp", :in_play)
    {game, _} = spawn(game, 1, "tax-collector", :patrol, :squad_leader)
    assert {:building, 1, :base} in attack_targets(game, imp)
    game = put_in(game.sides[0].zones.hand, [])
    game = end_turn(game)
    assert length(hand(game, 0)) == 3
    game = end_turn(game)
    assert game.sides[0].base_hp == 19
  end

  test "Zarramonde: played from hand, destroy a unit, hero, worker, upgrade or ongoing spell" do
    {game, _} = table()
    {game, u} = spawn(game, 1, "lawbringer-gryphon", :in_play)
    {game, z} = place(game, 0, "zarramonde-the-obliterator", :hand)
    assert [{:worker, 1}] in plays(game, z)
    game = ok!(game, {:play, z, [u]})
    assert u in zone(game, 1, :discard)
    assert Stats.kw?(game, z, :untargetable)
  end
end
