defmodule Codex.StarterTest do
  @moduledoc """
  Rules mode with the 10 neutral starting cards: playing cards, patrol,
  attacks and combat, the slot bonuses, keywords and the minor spells.
  """
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{Game, Stats}

  # P1 to act, with gold to spend.
  defp table(gold \\ 10), do: new() |> gold(0, gold)

  # P2's turn (P1's cards are now "patrolling"), with gold.
  defp p2_turn(game, gold \\ 10), do: game |> ok!(:end_turn) |> gold(1, gold)

  describe "playing units" do
    test "pay the cost; the unit arrives with arrival fatigue and cannot attack" do
      {game, id} = place(table(), 0, "older-brother", :hand)
      game = ok!(game, {:play, id, []})
      assert id in zone(game, 0, :in_play)
      assert game.sides[0].gold == 8
      assert game.cards[id].fatigued
      assert attack_targets(game, id) == []
    end

    test "haste: Timely Messenger attacks the turn it arrives" do
      {game, id} = place(table(), 0, "timely-messenger", :hand)
      game = ok!(game, {:play, id, []})
      assert {:building, 1, :base} in attack_targets(game, id)
    end

    test "not enough gold" do
      {game, id} = place(table(1), 0, "fruit-ninja", :hand)
      refute Enum.any?(legal(game), &match?({:play, ^id, _}, &1))
      assert Game.apply(game, 0, {:play, id, []}) == {:error, :no_gold}
    end

    test "a tech I unit needs a finished tech I building" do
      {game, id} = place(table(), 0, "iron-man", :hand)
      refute Enum.any?(legal(game), &match?({:play, ^id, _}, &1))
      game = game |> free() |> ok!({:building, 0, :tech_1}) |> ok!({:free_mode, false})
      assert {:play, id, []} in legal(game)
    end

    test "Brick Thief arrives: 1 damage to a building, and repairs one of its own" do
      {game, id} = place(table(), 0, "brick-thief", :hand)
      game = put_in(game.sides[0].base_hp, 18)
      game = ok!(game, {:play, id, [{:building, 1, :base}]})
      assert game.sides[1].base_hp == 19
      assert game.sides[0].base_hp == 19
    end
  end

  describe "spells" do
    test "a spell needs a hero of yours in play" do
      {game, spark} = place(table(), 0, "spark", :hand)
      {game, _} = place(game, 1, "older-brother", :patrol, :elite)
      refute Enum.any?(legal(game), &match?({:play, ^spark, _}, &1))
      {game, _hero} = place(game, 0, "troq-bashar", :in_play)
      assert Enum.any?(legal(game), &match?({:play, ^spark, _}, &1))
    end

    test "Spark: 1 damage to a patroller; the spell goes to the discard pile" do
      {game, spark} = place(table(), 0, "spark", :hand)
      {game, _} = place(game, 0, "troq-bashar", :in_play)
      {game, target} = place(game, 1, "tenderfoot", :patrol, :elite)
      game = ok!(game, {:play, spark, [target]})
      assert game.cards[target].damage == 1
      assert hd(zone(game, 0, :discard)) == spark
      assert game.sides[0].gold == 9
    end

    test "Spark needs a patroller" do
      {game, spark} = place(table(), 0, "spark", :hand)
      {game, _} = place(game, 0, "troq-bashar", :in_play)
      {game, _} = place(game, 1, "tenderfoot", :in_play)
      refute Enum.any?(legal(game), &match?({:play, ^spark, _}, &1))
    end

    test "Bloom: +1/+1 rune on a friendly force without one; Wither: -1/-1 rune" do
      {game, bloom} = place(table(), 0, "bloom", :hand)
      {game, wither} = place(game, 0, "wither", :hand)
      {game, hero} = place(game, 0, "troq-bashar", :in_play)
      {game, unit} = place(game, 0, "older-brother", :in_play)
      game = ok!(game, {:play, bloom, [unit]})
      assert game.cards[unit].plus == 1
      assert Stats.atk(game, unit) == 3
      refute Enum.any?(legal(game), &(match?({:play, _, [^unit]}, &1) and elem(&1, 1) == bloom))
      # Wither on a card with a +1/+1 rune: the runes destroy each other.
      game = ok!(game, {:play, wither, [unit]})
      assert %{plus: 0, minus: 0} = game.cards[unit]
      assert hero
    end

    test "Wither kills a 1-HP unit" do
      {game, wither} = place(table(), 0, "wither", :hand)
      {game, _} = place(game, 0, "troq-bashar", :in_play)
      {game, target} = place(game, 1, "timely-messenger", :in_play)
      game = ok!(game, {:play, wither, [target]})
      assert hd(zone(game, 1, :discard)) == target
      assert game.cards[target].minus == 0
    end

    test "Flagbearer: a spell that can target an opposing flagbearer must target one" do
      {game, wither} = place(table(), 0, "wither", :hand)
      {game, _} = place(game, 0, "troq-bashar", :in_play)
      {game, flag} = place(game, 1, "granfalloon-flagbearer", :in_play)
      {game, _other} = place(game, 1, "older-brother", :in_play)
      targets = for {:play, ^wither, [t]} <- legal(game), do: t
      assert targets == [flag]
    end

    test "resist: Brick Thief and the lookout slot cost 1 more gold to target" do
      {game, wither} = place(table(3), 0, "wither", :hand)
      {game, _} = place(game, 0, "troq-bashar", :in_play)
      {game, thief} = place(game, 1, "brick-thief", :patrol, :lookout)
      # Wither costs 2, + resist 1 + lookout 1 = 4: not with 3 gold.
      refute {:play, wither, [thief]} in legal(game)
      game = gold(game, 0, 4)
      game = ok!(game, {:play, wither, [thief]})
      assert game.sides[0].gold == 0
    end
  end

  describe "patrol" do
    test "a ready unit moves to an empty slot; sideline takes it out" do
      {game, a} = place(table(), 0, "older-brother", :in_play)
      game = ok!(game, {:patrol, a, :squad_leader})
      assert zone(game, 0, :patrol).squad_leader == a
      game = ok!(game, {:sideline, a})
      assert a in zone(game, 0, :in_play)
    end

    test "an exhausted unit cannot patrol; a just played one can" do
      {game, a} = place(table(), 0, "older-brother", :in_play)
      game = put_card(game, a, exhausted: true)
      refute Enum.any?(legal(game), &match?({:patrol, ^a, _}, &1))
      {game, b} = place(game, 0, "tenderfoot", :hand)
      game = ok!(game, {:play, b, []})
      assert {:patrol, b, :elite} in legal(game)
    end

    test "the other side's turn: it is a patroller" do
      {game, a} = place(table(), 0, "older-brother", :in_play)
      game = ok!(game, {:patrol, a, :elite})
      refute Stats.patrolling?(game, a)
      game = ok!(game, :end_turn)
      assert Stats.patrolling?(game, a)
      # Elite: +1 ATK while patrolling.
      assert Stats.atk(game, a) == 3
    end
  end

  describe "attacks" do
    # P1 sets up patrollers, then it is P2's turn with an attacker ready.
    defp defend(slots) do
      game =
        Enum.reduce(slots, table(), fn {slot, slug}, game ->
          {game, id} = place(game, 0, slug, :patrol, slot)
          Process.put({:id, slot}, id)
          game
        end)

      {game, attacker} = place(game, 1, "older-brother", :in_play)
      {p2_turn(game), attacker}
    end

    test "the squad leader must be attacked first" do
      {game, a} = defend(squad_leader: "tenderfoot", elite: "older-brother")
      assert attack_targets(game, a) == [Process.get({:id, :squad_leader})]
    end

    test "without a squad leader, any patroller (but no other target)" do
      {game, a} = defend(elite: "tenderfoot", lookout: "older-brother")

      assert Enum.sort(attack_targets(game, a)) ==
               Enum.sort([Process.get({:id, :elite}), Process.get({:id, :lookout})])
    end

    test "no patrollers: any unit, hero or building" do
      {game, a} = defend([])
      {game, other} = place(game, 0, "fruit-ninja", :in_play)
      targets = attack_targets(game, a)
      assert other in targets
      assert {:building, 0, :base} in targets
    end

    test "combat: both deal damage; the squad leader's armor absorbs 1; death goes to the discard pile" do
      {game, a} = defend(squad_leader: "older-brother")
      sl = Process.get({:id, :squad_leader})
      game = ok!(game, {:attack, a, sl})
      # Older Brother 2/2 on 2/2: the SL takes 2 - 1 armor = 1; the attacker takes 2 and dies.
      assert game.cards[sl].damage == 1
      assert hd(zone(game, 1, :discard)) == a
      assert game.cards[a].damage == 0
    end

    test "attack the base; the attacker exhausts" do
      {game, a} = defend([])
      game = ok!(game, {:attack, a, {:building, 0, :base}})
      assert game.sides[0].base_hp == 18
      assert game.cards[a].exhausted
      assert attack_targets(game, a) == []
    end

    test "a base at 0 HP: the attacker's side wins" do
      {game, a} = defend([])
      game = put_in(game.sides[0].base_hp, 2)
      game = ok!(game, {:attack, a, {:building, 0, :base}})
      assert Game.status(game) == {:over, %{winner: 1}}
    end

    test "scavenger: 1 gold when it dies patrolling; technician: a card" do
      {game, a} = defend(scavenger: "timely-messenger")
      gold = game.sides[0].gold
      game = ok!(game, {:attack, a, Process.get({:id, :scavenger})})
      assert game.sides[0].gold == gold + 1

      {game, a} = defend(technician: "timely-messenger")
      hand = length(hand(game, 0))
      game = ok!(game, {:attack, a, Process.get({:id, :technician})})
      assert length(hand(game, 0)) == hand + 1
    end

    test "an attacker from the patrol zone exhausts and leaves the patrol zone" do
      {game, a} = place(table(), 0, "older-brother", :in_play)
      game = game |> ok!(:end_turn) |> ok!(:end_turn)
      game = ok!(game, {:patrol, a, :elite})
      game = ok!(game, {:attack, a, {:building, 1, :base}})
      assert a in zone(game, 0, :in_play)
    end
  end

  describe "keywords" do
    test "frenzy 1: Fruit Ninja +1 ATK on its own turn only" do
      {game, n} = place(table(), 0, "fruit-ninja", :in_play)
      assert Stats.atk(game, n) == 3
      game = ok!(game, :end_turn)
      assert Stats.atk(game, n) == 2
    end

    test "healing 1: Helpful Turtle heals 1 damage from your units and heroes in your upkeep" do
      {game, _turtle} = place(table(), 0, "helpful-turtle", :in_play)
      {game, u} = place(game, 0, "older-brother", :in_play)
      game = put_card(game, u, damage: 1)
      game = game |> ok!(:end_turn) |> ok!(:end_turn)
      assert game.cards[u].damage == 0
    end
  end

  describe "random legal play" do
    # Random legal actions from random seeds: no crash, every card in one zone.
    test "every card stays in exactly one zone" do
      for seed <- 1..12 do
        rng = :rand.seed_s(:exsss, {seed, 3, 5})
        game = new({seed, 9, 9})

        Enum.reduce_while(1..250, {game, rng}, fn _, {game, rng} ->
          case rules_actions(game) do
            [] ->
              {:halt, nil}

            actions ->
              {i, rng} = :rand.uniform_s(length(actions), rng)
              action = Enum.at(actions, i - 1)
              game = ok!(game, action)
              assert_conserved(game)
              {:cont, {game, rng}}
          end
        end)
      end
    end
  end

  defp rules_actions(game),
    do:
      for(a <- legal(game), is_tuple(a) or a == :end_turn, not match?({:free_mode, _}, a), do: a)
end
