defmodule Codex.RulesTest do
  @moduledoc """
  The rules mode of `Codex.Game` (`Codex.Rules`): the turn, workers, the win.
  The card rules are in `Codex.CardsRulesTest`.
  """
  use ExUnit.Case, async: true

  import Codex.TestHelpers

  alias Codex.Game

  describe "the turn" do
    test "a new game is P1's first main phase with its upkeep gold" do
      game = new()
      assert game.active == 0
      assert game.phase == :main
      refute game.free
      assert game.sides[0].turn == 1
      assert game.sides[1].turn == 0
      assert game.sides[0].gold == 4
      assert game.sides[1].gold == 0
      assert Game.status(game) == {:playing, [0]}
    end

    test "end turn: discard the hand, draw that many + 2 (max 5), then P2's upkeep" do
      game = new()
      [a, b, c | _] = hand(game, 0)
      # Hire one, so 4 cards are in the hand: the draw is 5 (capped).
      game = ok!(game, {:hire, a})
      game = end_turn(game)

      assert game.active == 1
      assert game.phase == :main
      assert game.sides[1].turn == 1
      # P2's upkeep: 5 workers.
      assert game.sides[1].gold == 5
      # P1 kept 3 gold, drew 5 (its deck had 5).
      assert game.sides[0].gold == 3
      assert length(hand(game, 0)) == 5
      # 4 discarded + 2 codex cards from the tech step.
      assert length(zone(game, 0, :discard)) == 6
      assert b in zone(game, 0, :discard) and c in zone(game, 0, :discard)
    end

    test "the draw is the hand size + 2: a small hand draws less" do
      game = new()
      # Put 4 hand cards into play with free mode, so 1 card is left in the hand.
      game = free(game)

      game =
        Enum.reduce(Enum.take(hand(game, 0), 4), game, &ok!(&2, {:move, &1, {0, :in_play}, nil}))

      game = end_turn(game)
      # 1 discarded → 3 drawn.
      assert length(hand(game, 0)) == 3
    end

    test "an empty deck in the draw phase: the discard pile is shuffled into a new deck" do
      game = new()
      # Turn 1: 5 discarded, 5 drawn (deck empty). Turn 2 of P1: 5 discarded, the deck is empty.
      game = game |> end_turn() |> end_turn()
      assert zone(game, 0, :deck) == []
      game = end_turn(game)
      assert length(hand(game, 0)) == 5
      # The discard pile had 12 (10 starters + 2 codex cards); 5 drawn.
      assert length(zone(game, 0, :deck)) == 7
      assert {:reshuffle, 0} in game.log
    end

    test "gold is capped at 20" do
      game = Enum.reduce(1..12, new(), fn _, g -> end_turn(g) end)
      assert game.sides[0].gold == 20
      assert game.sides[1].gold == 20
    end

    test "the ready step readies the active side's cards and ends arrival fatigue" do
      game = free(new())
      [a | _] = hand(game, 0)

      game =
        game
        |> ok!({:move, a, {0, :in_play}, nil})
        |> put_card(a, exhausted: true, fatigued: true)
        |> end_turn()

      # Not readied on the other side's turn.
      assert %{exhausted: true, fatigued: true} = game.cards[a]
      game = end_turn(game)
      assert %{exhausted: false, fatigued: false} = game.cards[a]
    end
  end

  describe "workers" do
    test "hire: pay 1 gold, the card goes face down to the workers" do
      game = new()
      [a | _] = hand(game, 0)
      game = ok!(game, {:hire, a})
      assert game.sides[0].gold == 3
      assert a in zone(game, 0, :workers)
      assert game.cards[a].face_down
      assert length(zone(game, 0, :workers)) == 5
    end

    test "at most one worker per turn; a new turn allows another" do
      game = new()
      [a, b | _] = hand(game, 0)
      game = ok!(game, {:hire, a})
      assert Game.apply(game, 0, {:hire, b}) == {:error, :worker_hired}
      refute Enum.any?(Game.legal_actions(game, 0), &match?({:hire, _}, &1))

      game = game |> end_turn() |> end_turn()
      [c | _] = hand(game, 0)
      game = ok!(game, {:hire, c})
      # 4 + 1 + 1 workers.
      assert length(zone(game, 0, :workers)) == 6
    end

    test "the new worker gives gold from the next upkeep" do
      game = new()
      [a | _] = hand(game, 0)
      game = game |> ok!({:hire, a}) |> end_turn() |> end_turn()
      # 3 left + 5 workers.
      assert game.sides[0].gold == 8
    end

    test "no gold, not in the hand, not the active side" do
      game = free(new()) |> ok!({:adjust, 0, :gold, -4})
      [a | _] = hand(game, 0)
      assert Game.apply(game, 0, {:hire, a}) == {:error, :no_gold}
      game = ok!(game, {:adjust, 0, :gold, 1})
      [b | _] = hand(game, 1)
      assert Game.apply(game, 0, {:hire, b}) == {:error, :not_in_hand}
    end
  end

  describe "free mode" do
    test "the sandbox actions need free mode" do
      game = new()
      [a | _] = hand(game, 0)
      assert Game.apply(game, 0, {:move, a, {0, :in_play}, nil}) == {:error, :free_mode_off}
      assert Game.apply(game, 0, {:adjust, 0, :gold, 1}) == {:error, :free_mode_off}
      assert {:free_mode, true} in Game.legal_actions(game, 0)
      refute :move in Game.legal_actions(game, 0)

      game = ok!(game, {:free_mode, true})
      assert :move in Game.legal_actions(game, 0)
      assert {:free_mode, false} in Game.legal_actions(game, 0)
      game = ok!(game, {:move, a, {1, :in_play}, nil})
      assert a in zone(game, 1, :in_play)
    end

    test "the rules actions work in free mode too" do
      game = free(new())
      [a | _] = hand(game, 0)
      game = ok!(game, {:hire, a})
      assert a in zone(game, 0, :workers)
    end
  end

  describe "the win" do
    test "a base at 0 HP ends the game" do
      game = free(new()) |> ok!({:adjust, 1, :base_hp, -20})
      assert game.phase == :over
      assert Game.status(game) == {:over, %{winner: 0}}
      assert Game.apply(game, 0, :end_turn) == {:error, :game_over}
      assert Codex.Rules.legal(game) == []
    end
  end

  test "legal actions: a hire per hand card and end turn" do
    game = new()
    legal = Game.legal_actions(game, 0)
    for id <- hand(game, 0), do: assert({:hire, id} in legal)
    assert :end_turn in legal
  end
end
