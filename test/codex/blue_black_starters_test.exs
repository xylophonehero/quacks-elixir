defmodule Codex.BlueBlackStartersTest do
  @moduledoc "The Blue and Black starting decks and the six Blue and Black heroes."
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.{Rules, Stats}

  # P1 (Blue) to act with gold.
  defp blue(gold \\ 20), do: blue_black() |> gold(0, gold)
  # P1 (Black) to act with gold.
  defp black(gold \\ 20), do: black_blue() |> gold(0, gold)

  defp hero(game, seat, slug), do: place(game, seat, slug, :in_play)

  defp in_play(game, seat, slug),
    do: for(id <- zone(game, seat, :in_play), game.cards[id].card == slug, do: id)

  describe "Blue starting deck" do
    test "Building Inspector: an opponent's first building each turn costs 1 more" do
      game = blue() |> add_workers(0, 8)
      {game, _} = spawn(game, 1, "building-inspector", :in_play)
      assert Rules.build_cost(game, 0, :tech_1) == 2
      game = ok!(game, {:build, :tech_1})
      assert game.sides[0].gold == 18
      assert Rules.build_cost(game, 0, :tower) == 3
    end

    test "Spectral Aven: a flying Illusion; it dies when a spell targets it" do
      game = black()
      {game, _} = hero(game, 0, "vandy-anadrose")
      {game, aven} = spawn(game, 1, "spectral-aven", :in_play)
      assert Stats.kw?(game, aven, :flying) and Stats.illusion?(game, aven)
      {game, d} = place(game, 0, "deteriorate", :hand)
      game = ok!(game, {:play, d, [aven]})
      assert aven in zone(game, 1, :discard)
      assert_conserved(game)
    end

    test "Bluecoat Musketeer: long-range while it has exactly 1 ATK" do
      {game, m} = place(blue(), 0, "bluecoat-musketeer", :in_play)
      assert Stats.kw?(game, m, :long_range)
      game = put_card(game, m, plus: 1)
      refute Stats.kw?(game, m, :long_range)
    end

    test "Traffic Director: untargetable; unstoppable when it attacks a building" do
      game = blue()
      {game, t} = place(game, 0, "traffic-director", :in_play)
      {game, p} = place(game, 1, "pestering-haunt", :patrol, :squad_leader)
      game = put_card(game, p, card: "thieving-imp")
      targets = attack_targets(game, t)
      assert {:building, 1, :base} in targets and p in targets
      assert Stats.kw?(game, t, :untargetable)
    end

    test "Porkhand Magistrate: 1 gold, ⤵ → disable another unit or hero; its controller draws" do
      game = blue()
      {game, pm} = place(game, 0, "porkhand-magistrate", :in_play)
      {game, u} = place(game, 1, "thieving-imp", :patrol, :elite)
      refute Enum.any?(abilities(game, pm), fn {_, t} -> t == [pm] end)
      hand = length(hand(game, 1))
      game = ok!(game, {:ability, pm, :magistrate, [u]})
      assert game.cards[u].exhausted and u in zone(game, 1, :in_play)
      assert length(hand(game, 1)) == hand + 1
      assert game.sides[0].gold == 19
      # It does not ready in its controller's next ready step.
      game = end_turn(game)
      assert game.cards[u].exhausted
      game = game |> end_turn() |> end_turn()
      refute game.cards[u].exhausted
    end

    test "Reputable Newsman: opponents can't play spells of the chosen cost" do
      game = blue()
      {game, n} = place(game, 0, "reputable-newsman", :hand)
      assert [:cost_0] in plays(game, n)
      game = ok!(game, {:play, n, [:cost_0]})
      game = game |> end_turn() |> gold(1, 10)
      {game, _} = hero(game, 1, "vandy-anadrose")
      {game, d} = place(game, 1, "deteriorate", :hand)
      {game, s} = place(game, 1, "summon-skeletons", :hand)
      assert plays(game, d) == []
      assert plays(game, s) == [[]]
    end

    test "Jail: an opposing unit played from hand goes to jail; the next one frees it" do
      game = blue()
      {game, jail} = place(game, 0, "jail", :hand)
      game = ok!(game, {:play, jail, []})
      game = game |> end_turn() |> gold(1, 10)
      {game, imp} = place(game, 1, "thieving-imp", :hand)
      game = ok!(game, {:play, imp, []})
      assert imp in game.trash
      {game, rogue} = place(game, 1, "poisonblade-rogue", :hand)
      game = ok!(game, {:play, rogue, []})
      assert rogue in game.trash and imp in zone(game, 1, :in_play)
      assert_conserved(game)
    end

    test "Jail destroyed: the jailed unit goes to its owner's discard pile" do
      game = blue()
      {game, jail} = place(game, 0, "jail", :in_play)
      game = game |> end_turn() |> gold(1, 10)
      {game, imp} = place(game, 1, "thieving-imp", :hand)
      game = ok!(game, {:play, imp, []})
      game = Codex.Effects.destroy(game, jail)
      assert imp in zone(game, 1, :discard)
      assert_conserved(game)
    end

    test "Lawful Search: draw a card" do
      game = blue()
      {game, _} = hero(game, 0, "bigby-hayes")
      {game, l} = place(game, 0, "lawful-search", :hand)
      n = length(hand(game, 0))
      game = ok!(game, {:play, l, []})
      assert length(hand(game, 0)) == n
    end

    test "Arrest: disable a patrolling unit (it is sidelined)" do
      game = blue()
      {game, _} = hero(game, 0, "bigby-hayes")
      {game, p} = place(game, 1, "thieving-imp", :patrol, :squad_leader)
      {game, a} = place(game, 0, "arrest", :hand)
      game = ok!(game, {:play, a, [p]})
      assert p in zone(game, 1, :in_play) and game.cards[p].exhausted
      assert game.cards[p].extra.disabled
    end

    test "Manufactured Truth: your tech 0/I unit is a copy of another until the end of turn" do
      game = blue()
      {game, _} = hero(game, 0, "bigby-hayes")
      {game, mine} = place(game, 0, "building-inspector", :in_play)
      {game, other} = place(game, 1, "jandra-the-negator", :in_play)
      {game, mt} = place(game, 0, "manufactured-truth", :hand)
      game = ok!(game, {:play, mt, [mine, other]})
      assert game.cards[mine].card == "jandra-the-negator"
      assert Stats.atk(game, mine) == 3 and Stats.kw?(game, mine, :overpower)
      game = ok!(game, :end_turn)
      assert game.cards[mine].card == "building-inspector"
    end
  end

  describe "Black starting deck" do
    test "Pestering Haunt: unstoppable, can't patrol, can't be sacrificed, at most 1 ATK" do
      game = black()
      {game, h} = place(game, 0, "pestering-haunt", :in_play)
      {game, _} = spawn(game, 1, "spectral-hound", :patrol, :squad_leader)
      assert {:building, 1, :base} in attack_targets(game, h)
      refute Enum.any?(legal(game), &match?({:patrol, ^h, _}, &1))
      game = put_card(game, h, plus: 2)
      assert Stats.atk(game, h) == 1
      refute Stats.sacrificable?(game, h)
    end

    test "Skeleton Javelineer: a javelin rune; remove it → long-range this turn" do
      game = black()
      {game, j} = place(game, 0, "skeleton-javelineer", :hand)
      game = ok!(game, {:play, j, []})
      assert game.cards[j].extra.javelin == 1
      game = ok!(game, {:ability, j, :javelin, []})
      assert Stats.kw?(game, j, :long_range)
      assert abilities(game, j) == []
    end

    test "Poisonblade Rogue: attacks with armor piercing and -1/-1 runes for damage" do
      game = black()
      {game, r} = place(game, 0, "poisonblade-rogue", :in_play)
      {game, p} = spawn(game, 1, "spectral-hound", :patrol, :squad_leader)
      game = put_card(game, p, card: "overeager-cadet")
      game = ok!(game, {:attack, r, p})
      # 2 damage as runes past the squad leader's armor: the 2/2 dies at 0 HP.
      assert p in zone(game, 1, :discard)
    end

    test "Thieving Imp: arrives: an opponent discards a card at random" do
      game = black()
      {game, imp} = place(game, 0, "thieving-imp", :hand)
      n = length(hand(game, 1))
      game = ok!(game, {:play, imp, []})
      assert length(hand(game, 1)) == n - 1
      assert length(zone(game, 1, :discard)) == 1
    end

    test "Jandra: dies from combat damage → destroy all your units but Demons" do
      game = black() |> end_turn() |> gold(1, 10)
      {game, j} = place(game, 0, "jandra-the-negator", :patrol, :squad_leader)
      {game, imp} = place(game, 0, "thieving-imp", :in_play)
      {game, haunt} = place(game, 0, "pestering-haunt", :in_play)
      {game, a} = spawn(game, 1, "spectral-tiger", :in_play)
      game = ok!(game, {:attack, a, j})
      assert j in zone(game, 0, :discard)
      assert haunt in zone(game, 0, :discard)
      assert imp in zone(game, 0, :in_play)
    end

    test "Graveyard: buries your units; ⤵ plays one; 4 buried → sacrificed" do
      game = black()
      {game, gy} = place(game, 0, "graveyard", :in_play)
      {game, imp} = place(game, 0, "thieving-imp", :in_play)
      game = Codex.Effects.destroy(game, imp)
      assert imp in game.trash and game.cards[gy].extra.holds == [imp]
      game = game |> end_turn() |> end_turn() |> gold(0, 10)
      game = ok!(game, {:ability, gy, :exhume, [imp]})
      assert imp in zone(game, 0, :in_play) and game.sides[0].gold == 7

      game =
        Enum.reduce(~w(poisonblade-rogue skeleton-javelineer pestering-haunt), game, fn slug, g ->
          {g, id} = place(g, 0, slug, :in_play)
          Codex.Effects.destroy(g, id)
        end)

      game = Codex.Effects.destroy(game, imp)
      assert gy in zone(game, 0, :discard)
      assert imp in zone(game, 0, :discard)
      assert_conserved(game)
    end

    test "Skeletal Archery: your Skeletons have long-range and anti-air" do
      game = black()
      {game, _} = place(game, 0, "skeletal-archery", :in_play)
      game = Codex.Effects.summon(game, 0, "skeleton")
      [sk] = in_play(game, 0, "skeleton")
      assert Stats.kw?(game, sk, :long_range) and Stats.kw?(game, sk, :anti_air)
    end

    test "Deteriorate: -1/-1 this turn" do
      game = black()
      {game, _} = hero(game, 0, "garth-torken")
      {game, u} = spawn(game, 1, "tax-collector", :in_play)
      {game, d} = place(game, 0, "deteriorate", :hand)
      game = ok!(game, {:play, d, [u]})
      assert {Stats.atk(game, u), Stats.hp(game, u)} == {1, 2}
      game = ok!(game, :end_turn)
      assert Stats.hp(game, u) == 3
    end

    test "Summon Skeletons: two 1/1 Skeletons" do
      game = black()
      {game, _} = hero(game, 0, "garth-torken")
      {game, s} = place(game, 0, "summon-skeletons", :hand)
      game = ok!(game, {:play, s, []})
      assert length(in_play(game, 0, "skeleton")) == 2
    end

    test "Sacrifice the Weak: each player sacrifices the lowest tech unit with the least ATK" do
      game = black()
      {game, _} = hero(game, 0, "garth-torken")
      {game, haunt} = place(game, 0, "pestering-haunt", :in_play)
      {game, rogue} = place(game, 0, "poisonblade-rogue", :in_play)
      {game, imp} = place(game, 0, "thieving-imp", :in_play)
      {game, c1} = spawn(game, 1, "overeager-cadet", :in_play)
      {game, c2} = spawn(game, 1, "tax-collector", :in_play)
      {game, s} = place(game, 0, "sacrifice-the-weak", :hand)
      game = ok!(game, {:play, s, []})
      # The Haunt can't be sacrificed: the Rogue (2 ATK) goes, not the Imp (2 ATK, later).
      assert haunt in zone(game, 0, :in_play) and imp in zone(game, 0, :in_play)
      assert rogue in zone(game, 0, :discard)
      assert c2 in zone(game, 1, :in_play) and c1 in zone(game, 1, :discard)
    end
  end

  describe "Blue heroes" do
    test "Bigby Hayes: stash keeps a card; level 3 sideline; level 5 ⤵ draw" do
      game = blue()
      {game, b} = hero(game, 0, "bigby-hayes")
      [keep | _] = hand(game, 0)
      game = ok!(game, {:ability, b, :stash, [keep]})
      refute Enum.any?(abilities(game, b), &match?({:stash, _}, &1))
      n = length(hand(game, 0))
      game = end_turn(game)
      assert keep in hand(game, 0)
      assert length(hand(game, 0)) == min(n + 2, 5)
      game = game |> end_turn() |> put_card(b, level: 5)
      {game, p} = place(game, 1, "thieving-imp", :patrol, :elite)
      assert {:sideline, [p]} in abilities(game, b)
      h = length(hand(game, 0))
      game = ok!(game, {:ability, b, :bigby_draw, []})
      assert length(hand(game, 0)) == h + 1
    end

    test "General Onimaru: frenzy 1, readiness at level 5, three Soldiers at max level" do
      game = blue()
      {game, o} = hero(game, 0, "general-onimaru")
      assert Stats.atk(game, o) == 3
      game = put_card(game, o, level: 5)
      assert Stats.readiness?(game, o)
      game = Codex.Effects.level_up(game, o, 3)
      soldiers = in_play(game, 0, "soldier")
      assert length(soldiers) == 3 and Stats.kw?(game, hd(soldiers), :sparkshot)
    end

    test "Sirus Quince: a Mirror Illusion on arrival, ② another (at most 2)" do
      game = blue()
      {game, q} = place(game, 0, "sirus-quince", :command)
      game = ok!(game, {:summon, q})
      assert length(in_play(game, 0, "mirror-illusion")) == 1
      game = ok!(game, {:ability, q, :mirror, []})
      assert length(in_play(game, 0, "mirror-illusion")) == 2
      assert abilities(game, q) == []
    end

    test "Sirus Quince level 3: ② a Mirror becomes an Illusion copy; trashed at end of turn" do
      game = blue()
      {game, q} = place(game, 0, "sirus-quince", :command)
      game = ok!(game, {:summon, q}) |> put_card(q, level: 3)
      [m] = in_play(game, 0, "mirror-illusion")
      {game, t} = spawn(game, 1, "jandra-the-negator", :in_play)
      game = ok!(game, {:ability, q, :mirror_copy, [m, t]})
      assert game.cards[m].card == "jandra-the-negator" and Stats.illusion?(game, m)
      game = ok!(game, :end_turn)
      assert m in game.trash
      assert_conserved(game)
    end

    test "Sirus Quince max level: a Mirror copies a unit that arrives; gone when it leaves" do
      game = blue()
      {game, q} = place(game, 0, "sirus-quince", :command)
      game = ok!(game, {:summon, q}) |> put_card(q, level: 5)
      [m] = in_play(game, 0, "mirror-illusion")
      {game, u} = place(game, 0, "bluecoat-musketeer", :hand)
      game = ok!(game, {:play, u, []})
      assert game.cards[m].card == "bluecoat-musketeer" and Stats.illusion?(game, m)
      game = ok!(game, {:free_mode, true}) |> ok!({:move, u, {0, :hand}, nil})
      assert m in game.trash
    end
  end

  describe "Black heroes" do
    test "Vandy Anadrose: sparkshot, resist 1 at level 3, fetch a Demonology spell" do
      game = black()
      {game, v} = hero(game, 0, "vandy-anadrose")
      assert Stats.kw?(game, v, :sparkshot)
      game = game |> put_card(v, level: 3, fatigued: false)
      assert Stats.resist(game, v) == 1
      [card | _] = hand(game, 0)
      spell = Enum.find(zone(game, 0, :codex), &(game.cards[&1].card == "dark-pact"))
      game = ok!(game, {:ability, v, :fetch, [card, spell]})
      assert spell in hand(game, 0) and card in zone(game, 0, :discard)
    end

    test "Vandy Anadrose max level: +2/+2 to a friendly and an opposing tech 0/I unit; they die at her upkeep" do
      game = black()
      {game, v} = hero(game, 0, "vandy-anadrose")
      {game, mine} = place(game, 0, "thieving-imp", :in_play)
      {game, theirs} = spawn(game, 1, "tax-collector", :in_play)
      game = Codex.Effects.level_up(game, v, 4)
      assert Stats.atk(game, theirs) == 4 and Stats.atk(game, mine) == 4
      game = game |> end_turn() |> end_turn()
      assert theirs in zone(game, 1, :discard) and mine in zone(game, 0, :discard)
    end

    test "Orpal Gloor: his combat damage is -1/-1 runes; level 4: sacrifice → a -1/-1 rune" do
      game = black()
      {game, o} = hero(game, 0, "orpal-gloor")
      game = put_card(game, o, fatigued: false)
      {game, u} = spawn(game, 1, "tax-collector", :in_play)
      game = ok!(game, {:attack, o, u})
      assert game.cards[u].minus == 1 and game.cards[u].damage == 0
      game = put_card(game, o, level: 4)
      {game, imp} = place(game, 0, "thieving-imp", :in_play)
      {game, rogue} = place(game, 0, "poisonblade-rogue", :in_play)
      # Not a Demon (the Imp is one).
      refute Enum.any?(abilities(game, o), fn {_, [sac, _]} -> sac == imp end)
      game = ok!(game, {:ability, o, :plague, [rogue, u]})
      assert game.cards[u].minus == 2 and rogue in zone(game, 0, :discard)
      assert abilities(game, o) == []
    end

    test "Garth Torken: ① a Skeleton once per turn; level 4: sacrifice a Skeleton → draw" do
      game = black()
      {game, g} = hero(game, 0, "garth-torken")
      game = ok!(game, {:ability, g, :skeleton, []})
      [sk] = in_play(game, 0, "skeleton")
      refute Enum.any?(abilities(game, g), &match?({:skeleton, _}, &1))
      game = put_card(game, g, level: 4)
      n = length(hand(game, 0))
      game = ok!(game, {:ability, g, :bone_draw, [sk]})
      assert length(hand(game, 0)) == n + 1 and sk in game.trash
    end

    test "Garth Torken max level: a tech I/II unit (cost 5 or less) from the discard pile" do
      game = black() |> set_tech(0, [:tech_1, :tech_2], "Necromancy")
      {game, g} = hero(game, 0, "garth-torken")
      {game, u} = place(game, 0, "necromancer", :discard)
      game = Codex.Effects.level_up(game, g, 6)
      assert u in zone(game, 0, :in_play)
    end
  end
end
