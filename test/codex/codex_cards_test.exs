defmodule Codex.CodexCardsTest do
  @moduledoc """
  Rules mode: the tech step, tech buildings and add-ons, and the 24 Bashing and
  Finesse codex cards.
  """
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{Game, Stats}

  defp table(gold \\ 20), do: gold(new(), 0, gold)

  # P1 with its hero in play (spells need one), at `level`.
  defp with_hero(game, seat, level) do
    slug = if seat == 0, do: "troq-bashar", else: "river-montoya"
    {game, h} = place(game, seat, slug, :in_play)
    {put_card(game, h, level: level), h}
  end

  defp built(game, seat, buildings) do
    put_in(game.sides[seat].tech_buildings, buildings)
  end

  defp workers(game, seat, n) do
    {extra, _} = Game.add_cards(game, seat, List.duplicate("worker", n))
    ids = for id <- Map.keys(extra.cards) -- Map.keys(game.cards), do: id
    put_in(extra.sides[seat].zones.workers, game.sides[seat].zones.workers ++ ids)
  end

  defp plays(game, id), do: for({:play, ^id, t} <- legal(game), do: t)

  describe "the tech step" do
    test "after the draw: 2 codex cards go face down... into the discard pile" do
      game = ok!(new(), :end_turn)
      assert game.phase == :tech
      assert game.active == 0
      techs = for {:tech, ids} <- legal(game), do: ids
      assert Enum.all?(techs, &(length(&1) == 2))
      # 12 distinct cards: 66 pairs + 12 doubles.
      assert length(techs) == 78

      [a, b] = hd(techs)
      game = ok!(game, {:tech, [a, b]})
      assert a in zone(game, 0, :discard) and b in zone(game, 0, :discard)
      assert length(zone(game, 0, :codex)) == 22
      assert game.active == 1
      assert game.phase == :main
    end

    test "with 10 workers: 0, 1 or 2 cards" do
      game = new() |> workers(0, 6) |> ok!(:end_turn)
      assert {:tech, []} in legal(game)
      assert Enum.any?(legal(game), &match?({:tech, [_]}, &1))
      game = ok!(game, {:tech, []})
      assert game.active == 1
    end
  end

  describe "buildings" do
    test "tech I: 6 workers and 1 gold; it finishes at the end of the turn" do
      game = table()
      refute {:build, :tech_1} in legal(game)
      game = workers(game, 0, 2)
      game = ok!(game, {:build, :tech_1})
      assert game.sides[0].pending == [:tech_1]
      assert game.sides[0].gold == 19
      # One tech building a turn.
      refute {:build, :tech_2} in legal(game)
      game = end_turn(game)
      assert game.sides[0].tech_buildings == [:tech_1]
    end

    test "tech II needs 8 workers and tech I; tech III needs 10 and tech II" do
      game = table() |> workers(0, 4) |> built(0, [:tech_1])
      assert {:build, :tech_2} in legal(game)
      refute {:build, :tech_3} in legal(game)
      game = game |> workers(0, 2) |> built(0, [:tech_1, :tech_2])
      assert {:build, :tech_3} in legal(game)
    end

    test "one add-on: Tower or Surplus" do
      game = ok!(table(), {:build, :tower})
      refute {:build, :surplus} in legal(game)
      assert game.sides[0].gold == 17
    end

    test "Surplus: draw a card in the upkeep" do
      game = table() |> built(0, [:surplus]) |> end_turn() |> end_turn()
      # 5 drawn at the end of the turn, + 1 in the upkeep.
      assert length(hand(game, 0)) == 6
    end

    test "a destroyed tech building: the base takes 2; it is rebuilt for 0 gold" do
      game = table() |> workers(1, 1) |> built(1, [:tech_1])
      {game, _} = with_hero(game, 0, 1)
      {game, wb} = place(game, 0, "wrecking-ball", :hand)
      game = put_in(game.sides[1].building_damage, %{tech_1: 3})
      game = ok!(game, {:play, wb, [{:building, 1, :tech_1}]})
      assert game.sides[1].tech_buildings == []
      assert game.sides[1].base_hp == 18
      game = end_turn(game) |> gold(1, 0)
      assert {:build, :tech_1} in legal(game)
    end

    test "Tower: 1 damage to each attacker" do
      game = table() |> built(0, [:tower]) |> end_turn()
      {game, a} = place(game, 1, "older-brother", :in_play)
      game = ok!(game, {:attack, a, {:building, 0, :base}})
      assert game.cards[a].damage == 1
    end

    test "a tech II unit needs tech II" do
      {game, rhino} = place(table(), 0, "regular-sized-rhinoceros", :hand)
      assert plays(game, rhino) == []
      game = built(game, 0, [:tech_1, :tech_2])
      assert plays(game, rhino) == [[]]
    end
  end

  describe "Bashing" do
    test "Wrecking Ball: 2 damage to a building" do
      {game, _} = with_hero(table(), 0, 1)
      {game, wb} = place(game, 0, "wrecking-ball", :hand)
      game = ok!(game, {:play, wb, [{:building, 1, :base}]})
      assert game.sides[1].base_hp == 18
    end

    test "The Boot destroys a tech 0 or I unit; not a hero" do
      {game, _} = with_hero(table(), 0, 1)
      {game, boot} = place(game, 0, "the-boot", :hand)
      {game, u} = place(game, 1, "older-brother", :in_play)
      {game, h2} = with_hero(game, 1, 1)
      refute [h2] in plays(game, boot)
      game = ok!(game, {:play, boot, [u]})
      assert hd(zone(game, 1, :discard)) == u
    end

    test "Intimidate: -4 ATK this turn" do
      {game, _} = with_hero(table(), 0, 1)
      {game, i} = place(game, 0, "intimidate", :hand)
      {game, u} = place(game, 1, "older-brother", :in_play)
      game = ok!(game, {:play, i, [u]})
      assert Stats.atk(game, u) == -2
      game = end_turn(game)
      assert Stats.atk(game, u) == 2
    end

    test "Final Smash: an ultimate spell; destroy tech 0, bounce tech I, steal tech II" do
      {game, h} = with_hero(table(), 0, 8)
      {game, t0} = place(game, 1, "older-brother", :in_play)
      {game, t1} = place(game, 1, "nimble-fencer", :in_play)
      {game, t2} = place(game, 1, "cloud-sprite", :in_play)
      # Max level only now: not at the start of the turn.
      {game, fs} = place(game, 0, "final-smash", :hand)
      assert plays(game, fs) == []
      game = game |> end_turn() |> end_turn() |> gold(0, 20)
      {game, fs} = place(game, 0, "final-smash", :hand)
      assert [t0, t1, t2] in plays(game, fs)
      game = ok!(game, {:play, fs, [t0, t1, t2]})
      assert hd(zone(game, 1, :discard)) == t0
      assert t1 in hand(game, 1)
      assert t2 in zone(game, 0, :in_play)
      assert game.cards[t2].fatigued
      assert h
    end

    test "Iron Man and Revolver Ocelot (tech I); sparkshot hits a neighbour patroller" do
      game = table() |> built(0, [:tech_1])
      {game, oc} = place(game, 0, "revolver-ocelot", :in_play)
      game = end_turn(game)
      {game, a} = place(game, 1, "tenderfoot", :patrol, :squad_leader)
      {game, b} = spawn(game, 1, "tenderfoot", :patrol, :elite)
      game = end_turn(game)
      game = ok!(game, {:attack, oc, a})
      assert game.cards[b].damage == 1
    end

    test "Hired Stomper arrives: 3 damage to a unit" do
      game = table() |> built(0, [:tech_1, :tech_2])
      {game, st} = place(game, 0, "hired-stomper", :hand)
      {game, u} = place(game, 1, "older-brother", :in_play)
      game = ok!(game, {:play, st, [u]})
      assert hd(zone(game, 1, :discard)) == u
    end

    test "Sneaky Pig: haste, stealth the turn it arrives: it sneaks past patrollers" do
      game = table() |> built(0, [:tech_1, :tech_2]) |> end_turn()
      {game, _} = place(game, 1, "older-brother", :patrol, :squad_leader)
      game = end_turn(game) |> gold(0, 20)
      {game, pig} = place(game, 0, "sneaky-pig", :hand)
      game = ok!(game, {:play, pig, []})
      assert {:building, 1, :base} in attack_targets(game, pig)
    end

    test "Eggship flies over ground patrollers; a ground unit cannot attack it" do
      game = table() |> built(0, [:tech_1, :tech_2])
      {game, egg} = place(game, 0, "eggship", :in_play)
      game = end_turn(game)
      {game, _} = place(game, 1, "older-brother", :patrol, :squad_leader)
      {game, g} = place(game, 1, "tenderfoot", :in_play)
      refute egg in attack_targets(game, g)
      game = end_turn(game)
      assert {:building, 1, :base} in attack_targets(game, egg)
    end

    test "Harvest Reaper: overpower; Trojan Duck: obliterate 2 and 4 damage to a building" do
      game = table() |> built(0, [:tech_1, :tech_2, :tech_3])
      {game, duck} = place(game, 0, "trojan-duck", :hand)
      game = ok!(game, {:play, duck, [{:building, 1, :base}]})
      assert game.sides[1].base_hp == 16
      {game, reaper} = place(game, 0, "harvest-reaper", :in_play)
      game = end_turn(game)
      {game, sl} = place(game, 1, "tenderfoot", :patrol, :squad_leader)
      {game, u1} = place(game, 1, "older-brother", :in_play)
      {game, u2} = place(game, 1, "timely-messenger", :in_play)
      game = end_turn(game)
      # Reaper 6 ATK on a 1/2 squad leader with 1 armor: 3 excess to the base.
      base = game.sides[1].base_hp
      game = ok!(game, {:attack, reaper, sl})
      assert game.sides[1].base_hp == base - 3
      # Duck: obliterate the 2 lowest-tech units first.
      game = ok!(game, {:attack, duck, {:building, 1, :base}})
      assert u1 in zone(game, 1, :discard) and u2 in zone(game, 1, :discard)
    end
  end

  describe "Finesse" do
    defp p2(game), do: game |> end_turn() |> gold(1, 20)

    test "Harmony: each spell makes a Dancer (limit 3); stop the music flips them" do
      {game, _} = with_hero(p2(table()), 1, 1)
      {game, harmony} = place(game, 1, "harmony", :hand)
      game = ok!(game, {:play, harmony, []})
      assert harmony in zone(game, 1, :in_play)
      {game, discord} = place(game, 1, "discord", :hand)
      game = ok!(game, {:play, discord, []})
      dancers = for id <- zone(game, 1, :in_play), game.cards[id].card == "dancer", do: id
      assert length(dancers) == 1
      game = ok!(game, {:ability, harmony, :stop_music, []})
      assert hd(zone(game, 1, :discard)) == harmony
      assert Enum.all?(dancers, &(game.cards[&1].card == "angry-dancer"))
    end

    test "Harmony is sacrificed without its Finesse hero (channeling)" do
      {game, h} = with_hero(p2(table()), 1, 1)
      {game, harmony} = place(game, 1, "harmony", :hand)
      game = ok!(game, {:play, harmony, []})
      game = game |> free() |> ok!({:adjust_card, h, :damage, 3}) |> ok!({:free_mode, false})
      assert harmony in zone(game, 1, :discard)
    end

    test "Discord: the opponent's tech 0 and I units get -2/-1 this turn" do
      {game, _} = with_hero(p2(table()), 1, 1)
      {game, u} = place(game, 0, "tenderfoot", :in_play)
      {game, d} = place(game, 1, "discord", :hand)
      game = ok!(game, {:play, d, []})
      # Tenderfoot 1/2 → -1/1.
      assert {Stats.atk(game, u), Stats.hp(game, u)} == {-1, 1}
    end

    test "Two Step: two units +2/+2; lose one and Two Step is sacrificed" do
      {game, _} = with_hero(p2(table()), 1, 1)
      {game, a} = place(game, 1, "tenderfoot", :in_play)
      {game, b} = place(game, 1, "older-brother", :in_play)
      {game, ts} = place(game, 1, "two-step", :hand)
      game = ok!(game, {:play, ts, [a, b]})
      assert Stats.atk(game, a) == 3
      assert Stats.hp(game, b) == 4
      game = game |> free() |> ok!({:move, a, {1, :discard}, 0}) |> ok!({:free_mode, false})
      assert ts in zone(game, 1, :discard)
    end

    test "Appel Stomp: sideline a patroller, draw, back on top of the deck" do
      {game, _} = with_hero(p2(table()), 1, 5)
      game = game |> end_turn() |> end_turn() |> gold(1, 20)
      {game, stomp} = place(game, 1, "appel-stomp", :hand)
      {game, p} = place(game, 0, "older-brother", :patrol, :squad_leader)
      n = length(hand(game, 1))
      game = ok!(game, {:play, stomp, [p]})
      assert p in zone(game, 0, :in_play)
      assert length(hand(game, 1)) == n
      assert hd(zone(game, 1, :deck)) == stomp
    end

    test "Nimble Fencer: your Virtuosos have haste" do
      game = p2(table()) |> built(1, [:tech_1])
      {game, _} = place(game, 1, "nimble-fencer", :in_play)
      {game, t} = place(game, 1, "tenderfoot", :hand)
      game = ok!(game, {:play, t, []})
      assert {:building, 0, :base} in attack_targets(game, t)
    end

    test "Star-Crossed Starlet: 1 damage in its upkeep, +1 ATK per damage" do
      game = p2(table())
      {game, s} = place(game, 1, "star-crossed-starlet", :in_play)
      game = game |> end_turn() |> end_turn()
      assert game.cards[s].damage == 1
      assert Stats.atk(game, s) == 4
    end

    test "Grounded Guide: your other units +1 ATK, Virtuosos +2/+1" do
      game = p2(table())
      {game, _} = place(game, 1, "grounded-guide", :in_play)
      {game, t} = place(game, 1, "tenderfoot", :in_play)
      {game, o} = place(game, 1, "older-brother", :in_play)
      assert {Stats.atk(game, t), Stats.hp(game, t)} == {3, 3}
      assert Stats.atk(game, o) == 3
    end

    test "Maestro: Virtuosos cost 0 and get ⤵ → 2 damage to a building" do
      game = p2(table()) |> built(1, [:tech_1]) |> gold(1, 0)
      {game, _} = place(game, 1, "maestro", :in_play)
      {game, v} = place(game, 1, "tenderfoot", :in_play)
      {game, t} = spawn(game, 1, "tenderfoot", :hand)
      assert plays(game, t) == [[]]
      game = ok!(game, {:ability, v, :wreck, [{:building, 0, :base}]})
      assert game.sides[0].base_hp == 18
      assert game.cards[v].exhausted
    end

    test "Backstabber: invisible, not attackable unless it patrols" do
      game = p2(table())
      {game, bs} = place(game, 1, "backstabber", :in_play)
      game = end_turn(game)
      {game, a} = place(game, 0, "older-brother", :in_play)
      refute bs in attack_targets(game, a)
    end

    test "Leaping Lizard: anti-air, it can attack a flier" do
      game = table()
      {game, sprite} = spawn(game, 0, "cloud-sprite", :in_play)
      game = p2(game)
      {game, lizard} = place(game, 1, "leaping-lizard", :in_play)
      assert sprite in attack_targets(game, lizard)
    end

    test "Blademaster: swift strike, the defender that dies deals no damage" do
      game = p2(table())
      {game, _} = place(game, 1, "blademaster", :in_play)
      {game, a} = place(game, 1, "older-brother", :in_play)
      {game, d} = place(game, 0, "older-brother", :in_play)
      game = ok!(game, {:attack, a, d})
      assert hd(zone(game, 0, :discard)) == d
      assert game.cards[a].damage == 0
    end
  end
end
