defmodule Codex.GameTest do
  use ExUnit.Case, async: true

  import Codex.TestHelpers, only: [end_turn: 1]

  alias Codex.{Cards, Game}

  doctest Codex.Game
  doctest Codex.Cards

  @seed {1, 2, 3}

  # The sandbox actions need free mode.
  defp new, do: free(elem(Game.new(%{}, @seed), 1))

  defp free(game) do
    {:ok, game} = Game.apply(game, 0, {:free_mode, true})
    game
  end

  defp ok!(game, action) do
    assert {:ok, game} = Game.apply(game, 0, action)
    game
  end

  defp zone(game, seat, zone), do: game.sides[seat].zones[zone]
  defp card(game, id), do: game.cards[id]

  # Every card is in exactly one zone.
  defp assert_conserved(game) do
    placed = Game.all_placed(game)
    assert Enum.sort(placed) == Enum.sort(Map.keys(game.cards))
  end

  describe "new/2 (first-game set-up)" do
    test "each side: 10-card deck with 5 drawn, 24 codex cards, a hero, workers" do
      game = new()

      for seat <- [0, 1] do
        assert length(zone(game, seat, :hand)) == 5
        assert length(zone(game, seat, :deck)) == 5
        assert length(zone(game, seat, :codex)) == 24
        assert [hero] = zone(game, seat, :command)
        assert card(game, hero).level == 1
        assert zone(game, seat, :discard) == []
        assert zone(game, seat, :in_play) == []
        assert zone(game, seat, :patrol) == Map.new(Game.patrol_slots(), &{&1, nil})
        # P1's first upkeep: 4 gold for 4 workers.
        assert game.sides[seat].gold == if(seat == 0, do: 4, else: 0)
        assert game.sides[seat].base_hp == 20
        assert game.sides[seat].tech_buildings == []

        starter =
          Enum.map(zone(game, seat, :hand) ++ zone(game, seat, :deck), &card(game, &1).card)

        assert Enum.sort(starter) == Enum.sort(Cards.starter())
      end

      assert card(game, hd(zone(game, 0, :command))).card == "troq-bashar"
      assert card(game, hd(zone(game, 1, :command))).card == "river-montoya"
      assert length(zone(game, 0, :workers)) == 4
      assert length(zone(game, 1, :workers)) == 5
      assert Enum.all?(zone(game, 1, :workers), &card(game, &1).face_down)

      codex = Enum.map(zone(game, 0, :codex), &card(game, &1).card)
      assert Enum.frequencies(codex) == Map.new(Cards.codex("Bashing"), &{&1, 2})

      assert game.trash == []
      assert game.active == 0
      assert map_size(game.cards) == 2 * (10 + 24 + 1) + 4 + 5
      assert_conserved(game)
    end

    test "the same seed deals the same hands; another seed shuffles" do
      assert new() == new()
      {:ok, other} = Game.new(%{}, {9, 9, 9})
      assert zone(other, 0, :hand) != zone(new(), 0, :hand)
    end

    test "status and table seats" do
      game = new()
      assert Game.status(game) == {:playing, [0]}
      assert Game.table_seats() == [0]
      {:ok, fresh} = Game.new(%{}, @seed)
      refute :undo in Game.legal_actions(fresh, 0)
      assert :undo in Game.legal_actions(game, 0)
    end
  end

  describe "move" do
    test "hand to in_play, at the end and at an index" do
      game = new()
      [a, b | _] = zone(game, 0, :hand)
      game = game |> ok!({:move, a, {0, :in_play}, nil}) |> ok!({:move, b, {0, :in_play}, 0})
      assert zone(game, 0, :in_play) == [b, a]
      refute a in zone(game, 0, :hand)
      assert [{:action, 0, {:move, ^b, {0, :in_play}, 0}} | _] = game.log
      assert_conserved(game)
    end

    test "into a patrol slot; a taken slot is an error" do
      game = new()
      [a, b | _] = zone(game, 0, :hand)
      game = ok!(game, {:move, a, {0, :patrol}, :elite})
      assert zone(game, 0, :patrol).elite == a
      assert Game.apply(game, 0, {:move, b, {0, :patrol}, :elite}) == {:error, :slot_taken}
      assert Game.apply(game, 0, {:move, b, {0, :patrol}, :middle}) == {:error, :invalid_slot}
      game = ok!(game, {:move, a, {0, :patrol}, :lookout})
      assert zone(game, 0, :patrol).elite == nil
      assert zone(game, 0, :patrol).lookout == a
      assert_conserved(game)
    end

    test "to the other side, to the trash, to the top of the deck" do
      game = new()
      [a, b, c | _] = zone(game, 0, :hand)

      game =
        game
        |> ok!({:move, a, {1, :in_play}, nil})
        |> ok!({:move, b, :trash, nil})
        |> ok!({:move, c, {0, :deck}, 0})

      assert zone(game, 1, :in_play) == [a]
      assert card(game, a).seat == 0
      assert game.trash == [b]
      assert hd(zone(game, 0, :deck)) == c
      assert_conserved(game)
    end

    test "leaving play clears damage, runes, exhaustion and levels" do
      game = new()
      [a | _] = zone(game, 0, :hand)
      [hero] = zone(game, 0, :command)

      game =
        game
        |> ok!({:move, a, {0, :in_play}, nil})
        |> ok!({:adjust_card, a, :damage, 1})
        |> ok!({:adjust_card, a, :plus, 1})
        |> ok!({:toggle, a, :exhausted})
        |> ok!({:move, hero, {0, :patrol}, :squad_leader})
        |> ok!({:adjust_card, hero, :level, 3})
        |> ok!({:move, a, {0, :patrol}, :elite})

      assert %{damage: 1, plus: 1, exhausted: true} = card(game, a)

      game = game |> ok!({:move, a, {0, :discard}, 0}) |> ok!({:move, hero, {0, :command}, nil})
      assert %{damage: 0, plus: 0, minus: 0, exhausted: false} = card(game, a)
      assert card(game, hero).level == 1
    end

    test "workers are face down; a card that leaves them is face up" do
      game = new()
      [a | _] = zone(game, 0, :hand)
      game = ok!(game, {:move, a, {0, :workers}, nil})
      assert card(game, a).face_down
      game = ok!(game, {:move, a, :trash, nil})
      refute card(game, a).face_down
    end

    test "errors change nothing" do
      game = new()
      [a | _] = zone(game, 0, :hand)

      for action <- [
            {:move, 999, {0, :hand}, nil},
            {:move, a, {2, :hand}, nil},
            {:move, a, {0, :graveyard}, nil},
            {:move, a, {0, :hand}, -1},
            {:move, a, {0, :hand}, :top}
          ] do
        assert {:error, _} = Game.apply(game, 0, action)
      end
    end
  end

  describe "draw and shuffle" do
    test "draw from the top of the deck" do
      game = new()
      [top | _] = deck = zone(game, 0, :deck)
      game = ok!(game, {:draw, 0, 2})
      assert length(zone(game, 0, :hand)) == 7
      assert List.last(zone(game, 0, :hand)) == Enum.at(deck, 1)
      assert top in zone(game, 0, :hand)
      assert length(zone(game, 0, :deck)) == 3
    end

    test "an empty deck takes the shuffled discard pile" do
      game = new()
      hand = zone(game, 0, :hand)
      game = Enum.reduce(hand, game, &ok!(&2, {:move, &1, {0, :discard}, 0}))
      game = ok!(game, {:draw, 0, 8})
      assert length(zone(game, 0, :hand)) == 8
      assert zone(game, 0, :discard) == []
      assert length(zone(game, 0, :deck)) == 2
      assert {:reshuffle, 0} in game.log
      assert_conserved(game)
    end

    test "nothing to draw, a bad count" do
      game = new()
      game = ok!(game, {:draw, 0, 10})
      assert zone(game, 0, :deck) == []
      assert Game.apply(game, 0, {:draw, 0, 1}) == {:error, :empty_deck}
      assert Game.apply(game, 0, {:draw, 0, 0}) == {:error, :invalid_count}
      assert Game.apply(game, 0, {:draw, 3, 1}) == {:error, :invalid_seat}
    end

    test "shuffle a list zone keeps its cards" do
      game = new()
      codex = zone(game, 1, :codex)
      game = ok!(game, {:shuffle, 1, :codex})
      assert Enum.sort(zone(game, 1, :codex)) == Enum.sort(codex)
      assert zone(game, 1, :codex) != codex
      assert Game.apply(game, 0, {:shuffle, 1, :patrol}) == {:error, :invalid_zone}
    end
  end

  describe "tokens and counters" do
    test "damage, runes and levels" do
      game = new()
      [a | _] = zone(game, 0, :hand)
      [hero] = zone(game, 1, :command)

      game =
        game
        |> ok!({:adjust_card, a, :damage, 2})
        |> ok!({:adjust_card, a, :minus, 1})
        |> ok!({:adjust_card, hero, :level, 4})

      assert %{damage: 2, minus: 1} = card(game, a)
      assert card(game, hero).level == 5
      # River Montoya's max level is 5.
      assert Game.apply(game, 0, {:adjust_card, hero, :level, 1}) == {:error, :out_of_range}
      assert Game.apply(game, 0, {:adjust_card, a, :level, 1}) == {:error, :not_a_hero}
      assert Game.apply(game, 0, {:adjust_card, a, :plus, -1}) == {:error, :out_of_range}
      assert Game.apply(game, 0, {:adjust_card, a, :plus, 0}) == {:error, :invalid_adjust}
      assert Game.apply(game, 0, {:adjust_card, a, :atk, 1}) == {:error, :invalid_adjust}
    end

    test "toggle exhausted and face down" do
      game = new()
      [a | _] = zone(game, 0, :hand)
      game = game |> ok!({:toggle, a, :exhausted}) |> ok!({:toggle, a, :face_down})
      assert %{exhausted: true, face_down: true} = card(game, a)
      game = ok!(game, {:toggle, a, :exhausted})
      refute card(game, a).exhausted
      assert Game.apply(game, 0, {:toggle, a, :damage}) == {:error, :invalid_toggle}
    end

    test "gold and base HP stay in 0..99" do
      game = new() |> ok!({:adjust, 0, :gold, 4}) |> ok!({:adjust, 1, :base_hp, -3})
      assert game.sides[0].gold == 8
      assert game.sides[1].base_hp == 17
      assert Game.apply(game, 0, {:adjust, 0, :gold, -9}) == {:error, :out_of_range}
      assert Game.apply(game, 0, {:adjust, 0, :base_hp, 80}) == {:error, :out_of_range}
      assert Game.apply(game, 0, {:adjust, 0, :workers, 1}) == {:error, :invalid_adjust}
    end

    test "build and remove a tech building" do
      game = new() |> ok!({:building, 0, :tech_1}) |> ok!({:building, 0, :tower})
      assert game.sides[0].tech_buildings == [:tech_1, :tower]
      game = ok!(game, {:building, 0, :tech_1})
      assert game.sides[0].tech_buildings == [:tower]
      assert Game.apply(game, 0, {:building, 0, :castle}) == {:error, :invalid_building}
    end
  end

  describe "end turn and undo" do
    test "end turn: the other side is active and its turn count goes up" do
      game = end_turn(new())
      assert game.active == 1
      assert game.sides[1].turn == 1
      game = end_turn(game)
      assert game.active == 0
      assert game.sides[0].turn == 2
    end

    test "undo restores the state before the last action" do
      game = new()
      [a | _] = zone(game, 0, :hand)
      after_move = ok!(game, {:move, a, {0, :in_play}, nil})
      after_draw = ok!(after_move, {:draw, 0, 1})

      undone = ok!(after_draw, :undo)
      assert %{undone | history: []} == %{after_move | history: []}
      undone = ok!(undone, {:undo})
      assert undone == game
      # The last undo turns free mode off again.
      undone = ok!(undone, :undo)
      refute undone.free
      assert Game.apply(undone, 0, :undo) == {:error, :nothing_to_undo}
    end

    test "the history keeps the last 50 states" do
      [a | _] = zone(new(), 0, :hand)
      game = Enum.reduce(1..61, new(), fn _, g -> ok!(g, {:toggle, a, :exhausted}) end)
      assert length(game.history) == Game.history_limit()
      game = Enum.reduce(1..50, game, fn _, g -> ok!(g, :undo) end)
      # 61 toggles, 50 undone: 11 toggles, so exhausted.
      assert game.cards[a].exhausted
      assert Game.apply(game, 0, :undo) == {:error, :nothing_to_undo}
    end

    test "only table seat 0 acts" do
      assert Game.apply(new(), 1, :end_turn) == {:error, :not_your_seat}
      assert Game.legal_actions(new(), 1) == []
    end
  end

  test "view: the decks are counts and their cards are not in it" do
    game = new()
    view = Game.view(game, 0)
    assert view.sides[0].zones.deck == 5
    assert length(view.sides[1].zones.hand) == 5
    for id <- zone(game, 0, :deck), do: refute(Map.has_key?(view.cards, id))
    for id <- zone(game, 1, :hand), do: assert(Map.has_key?(view.cards, id))
    assert view.undo
    refute Game.view(elem(Game.new(%{}, @seed), 1), 0).undo
  end

  describe "card conservation" do
    # Random actions (valid and invalid) from random seeds: after each one every
    # card is in exactly one zone, and undo goes back step by step.
    test "every card is in exactly one zone after random actions" do
      for seed <- 1..25 do
        rng = :rand.seed_s(:exsss, {seed, 7, 11})
        game = free(elem(Game.new(%{}, {seed, 1, 1}), 1))

        Enum.reduce(1..120, {game, rng}, fn _, {game, rng} ->
          {action, rng} = random_action(game, rng)

          game =
            case Game.apply(game, 0, action) do
              {:ok, next} -> next
              {:error, _} -> game
            end

          assert_conserved(game)
          {game, rng}
        end)
      end
    end

    test "undo after random actions gives back the earlier states" do
      game = free(elem(Game.new(%{}, {5, 6, 7}), 1))
      rng = :rand.seed_s(:exsss, {1, 1, 1})

      {games, _} =
        Enum.reduce(1..30, {[game], rng}, fn _, {[g | _] = acc, rng} ->
          {action, rng} = random_action(g, rng)

          case Game.apply(g, 0, action) do
            {:ok, next} when action not in [:undo] -> {[next | acc], rng}
            _ -> {acc, rng}
          end
        end)

      [last | earlier] = games

      Enum.reduce(earlier, last, fn want, g ->
        g = ok!(g, :undo)
        assert %{g | history: []} == %{want | history: []}
        g
      end)
    end
  end

  @zones [:hand, :discard, :codex, :command, :workers, :in_play, :deck, :patrol, :trash]

  defp random_action(game, rng) do
    {kind, rng} =
      pick([:move, :move, :move, :draw, :shuffle, :adjust_card, :toggle, :end_turn, :undo], rng)

    ids = Map.keys(game.cards)
    {id, rng} = pick(ids ++ [0], rng)
    {seat, rng} = pick([0, 1], rng)
    {zone, rng} = pick(@zones, rng)
    {slot, rng} = pick(Game.patrol_slots(), rng)
    {n, rng} = pick([0, 1, 2, 5], rng)

    {action(kind, id, seat, zone, slot, n), rng}
  end

  defp action(:move, id, _seat, :trash, _slot, _n), do: {:move, id, :trash, nil}
  defp action(:move, id, seat, :patrol, slot, _n), do: {:move, id, {seat, :patrol}, slot}
  defp action(:move, id, seat, zone, _slot, 5), do: {:move, id, {seat, zone}, nil}
  defp action(:move, id, seat, zone, _slot, n), do: {:move, id, {seat, zone}, n}
  defp action(:draw, _id, seat, _zone, _slot, n), do: {:draw, seat, n}
  defp action(:shuffle, _id, seat, zone, _slot, _n), do: {:shuffle, seat, zone}

  defp action(:adjust_card, id, _seat, _zone, _slot, n),
    do: {:adjust_card, id, Enum.at([:damage, :plus, :minus, :level], n - 1), 1}

  defp action(:toggle, id, _seat, _zone, _slot, _n), do: {:toggle, id, :exhausted}
  defp action(kind, _id, _seat, _zone, _slot, _n), do: kind

  defp pick(list, rng) do
    {i, rng} = :rand.uniform_s(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end
end
