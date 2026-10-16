defmodule Hearts.GameTest do
  use ExUnit.Case, async: true

  import Hearts.Scenario

  alias Hearts.Game
  alias Table.Kit.PlayingCards

  doctest Game

  defp to_playing(game), do: play_until(game, &(&1.phase == :playing))

  defp all_hearts, do: for(rank <- 2..14, do: {rank, :hearts})

  # The last trick of a hand: each seat has one card; seat 0 leads.
  defp last_trick(hands, taken, fields \\ [], opts \\ %{}) do
    at_play(
      hands,
      [
        tricks: 12,
        hearts_broken: true,
        taken: Map.merge(%{0 => [], 1 => [], 2 => [], 3 => []}, taken)
      ] ++
        fields,
      opts
    )
  end

  defp play_trick(game, plays) do
    Enum.reduce(plays, game, fn {seat, text}, g -> apply!(g, seat, {:play, card(text)}) end)
  end

  describe "§1 players and cards" do
    @tag rule: ["§1.1", "§1.2"]
    test "4 players get 13 cards each, all 52 cards, no card twice" do
      game = new!()
      assert game.seats == [0, 1, 2, 3]
      assert Enum.all?(game.hands, fn {_, hand} -> length(hand) == 13 end)

      assert game.hands |> Map.values() |> Enum.concat() |> Enum.sort() ==
               Enum.sort(PlayingCards.deck())

      assert [{:deal, 1, :left, hands}] = events(game)
      assert hands == game.hands
    end

    @tag rule: "§1.2"
    test "the same seed deals the same hands; another seed deals other hands" do
      assert new!(%{}, {7, 8, 9}).hands == new!(%{}, {7, 8, 9}).hands
      refute new!(%{}, {7, 8, 9}).hands == new!(%{}, {7, 8, 10}).hands
    end

    @tag rule: "§1.3"
    test "3 players: no 2♦, 17 cards each" do
      game = new!(%{players: 3})
      assert game.seats == [0, 1, 2]
      assert Enum.all?(game.hands, fn {_, hand} -> length(hand) == 17 end)
      refute game.hands |> Map.values() |> Enum.concat() |> Enum.member?(card("2D"))
    end

    @tag rule: "§1.3"
    test "5 players: no 2♣ and no 2♦, 10 cards each" do
      game = new!(%{players: 5})
      assert Enum.all?(game.hands, fn {_, hand} -> length(hand) == 10 end)
      all = game.hands |> Map.values() |> Enum.concat()
      refute card("2C") in all
      refute card("2D") in all
    end

    @tag rule: "§1.4"
    test "left is the next seat, right the seat before, across two seats on" do
      assert Game.pass_target(0, :left, 4) == 1
      assert Game.pass_target(0, :right, 4) == 3
      assert Game.pass_target(0, :across, 4) == 2
      assert Game.pass_target(3, :left, 4) == 0
      assert Game.pass_target(0, :right, 3) == 2
    end
  end

  describe "§2 passing" do
    @tag rule: "§2.1"
    test "a seat chooses 3 cards in secret; the cards move only when all have chosen" do
      game = new!()
      assert Game.status(game) == {:playing, [0, 1, 2, 3]}
      assert length(Game.legal_actions(game, 0)) == 286

      pass = Enum.take(game.hands[0], 3)
      g = apply!(game, 0, {:pass, pass})

      assert g.hands == game.hands
      assert Game.status(g) == {:playing, [1, 2, 3]}
      assert Game.legal_actions(g, 0) == []
      assert hd(g.log) == {:pass_chosen, 0}
      assert Game.view(g, 0).pass == pass
      assert Game.view(g, 1).pass == nil
      assert Game.view(g, 1).passed == [0]
      assert Game.apply(g, 0, {:pass, Enum.take(game.hands[0], -3)}) == {:error, :already_passed}
    end

    @tag rule: "§2.1"
    test "a pass must be 3 different cards from the own hand" do
      game = new!()
      [a, b, c | _] = game.hands[0]
      other = hd(game.hands[1])

      assert Game.apply(game, 0, {:pass, [a, b]}) == {:error, :invalid_pass}
      assert Game.apply(game, 0, {:pass, [a, a, b]}) == {:error, :invalid_pass}
      assert Game.apply(game, 0, {:pass, [a, b, other]}) == {:error, :invalid_pass}
      assert Game.apply(game, 0, {:play, c}) == {:error, :invalid_action}
    end

    @tag rule: ["§2.1", "§2.2"]
    test "the cycle for 4 players is left, right, across, no pass" do
      game = new!(%{target: 10_000})

      for {hand_no, direction, offset} <- [
            {1, :left, 1},
            {2, :right, 3},
            {3, :across, 2},
            {5, :left, 1}
          ],
          reduce: game do
        g ->
          g = play_until(g, &(&1.hand_no == hand_no))
          assert Game.pass_direction(g) == direction
          passes = Map.new(g.seats, &{&1, Enum.take(g.hands[&1], 3)})
          g = Enum.reduce(passes, g, fn {seat, cards}, g -> apply!(g, seat, {:pass, cards}) end)

          for {seat, cards} <- passes do
            target = rem(seat + offset, 4)
            assert cards -- g.hands[target] == []
            assert Enum.all?(g.hands, fn {_, hand} -> length(hand) == 13 end)
          end

          assert {:pass, ^direction, _} = hd(Enum.reject(g.log, &match?({:pass_chosen, _}, &1)))
          g
      end
    end

    @tag rule: ["§2.2", "§2.4"]
    test "hand 4 has no pass: the play starts at once" do
      g = play_until(new!(%{target: 10_000}), &(&1.hand_no == 4))
      assert Game.pass_direction(g) == :none
      assert g.phase == :playing
      assert {:deal, 4, :none, _} = hd(g.log)
      assert [{:play, _}] = Game.legal_actions(g, g.turn)
    end

    @tag rule: "§2.3"
    test "the cycle for 3 and 5 players is left, right, no pass" do
      for players <- [3, 5] do
        game = new!(%{players: players})

        assert Enum.map(1..4, &Game.pass_direction(%{game | hand_no: &1})) ==
                 [:left, :right, :none, :left]
      end
    end
  end

  describe "§3 play of the cards" do
    @tag rule: "§3.1"
    test "after the pass, the holder of the 2♣ must lead it" do
      g = to_playing(new!())
      {:playing, [leader]} = Game.status(g)
      assert card("2C") in g.hands[leader]
      assert Game.legal_actions(g, leader) == [{:play, card("2C")}]
      other = hd(g.hands[leader] -- [card("2C")])
      assert Game.apply(g, leader, {:play, other}) == {:error, :must_lead_first_club}
    end

    @tag rule: "§3.1"
    test "5 players: the holder of the 3♣ leads it" do
      g = to_playing(new!(%{players: 5}))
      {:playing, [leader]} = Game.status(g)
      assert Game.legal_actions(g, leader) == [{:play, card("3C")}]
    end

    @tag rule: "§3.2"
    test "a player must follow suit if they can; if not, any card" do
      g =
        at_play(%{0 => "5C 9D", 1 => "7C AH", 2 => "AD 4D", 3 => "KC 2S"}, tricks: 1)
        |> apply!(0, {:play, card("5C")})

      assert Game.legal_actions(g, 1) == [{:play, card("7C")}]
      assert Game.apply(g, 1, {:play, card("AH")}) == {:error, :must_follow_suit}
      assert Game.apply(g, 2, {:play, card("AD")}) == {:error, :not_your_turn}
      assert Game.apply(g, 1, {:play, card("AD")}) == {:error, :not_in_hand}

      g = apply!(g, 1, {:play, card("7C")})
      assert Game.legal_actions(g, 2) == [{:play, card("4D")}, {:play, card("AD")}]
    end

    @tag rule: "§3.3"
    test "first trick: a player who cannot follow must not play a heart or the Q♠" do
      g = at_play(%{0 => "3C", 1 => "5H QS 9D"}, tricks: 0, turn: 1, trick: [{0, card("2C")}])
      assert Game.legal_actions(g, 1) == [{:play, card("9D")}]
      assert Game.apply(g, 1, {:play, card("5H")}) == {:error, :no_points_first_trick}
      assert Game.apply(g, 1, {:play, card("QS")}) == {:error, :no_points_first_trick}
    end

    @tag rule: "§3.3"
    test "first trick: a hand of only hearts and the Q♠ may play any of them" do
      g = at_play(%{0 => "3C", 1 => "5H QS AH"}, tricks: 0, turn: 1, trick: [{0, card("2C")}])

      assert Enum.sort(Game.legal_actions(g, 1)) ==
               Enum.sort(Enum.map(cards("5H QS AH"), &{:play, &1}))

      assert apply!(g, 1, {:play, card("QS")}).trick == [{0, card("2C")}, {1, card("QS")}]
    end

    @tag rule: "§3.3"
    test "first trick: with no_points_first_trick off, a heart is a legal discard" do
      g =
        at_play(%{0 => "3C", 1 => "5H 9D"}, [tricks: 0, turn: 1, trick: [{0, card("2C")}]], %{
          no_points_first_trick: false
        })

      assert {:play, card("5H")} in Game.legal_actions(g, 1)
    end

    @tag rule: "§3.4"
    test "a heart cannot be led before hearts are broken" do
      g = at_play(%{0 => "5H 9D QS"}, tricks: 1)
      assert Game.legal_actions(g, 0) == [{:play, card("9D")}, {:play, card("QS")}]
      assert Game.apply(g, 0, {:play, card("5H")}) == {:error, :hearts_not_broken}
    end

    @tag rule: "§3.4"
    test "a hand of only hearts can lead a heart before hearts are broken" do
      g = at_play(%{0 => "5H 9H"}, tricks: 1)
      assert Game.legal_actions(g, 0) == [{:play, card("5H")}, {:play, card("9H")}]
    end

    @tag rule: "§3.4"
    test "a heart discard breaks hearts; then hearts can be led" do
      g =
        at_play(%{0 => "9D 2H 5C", 1 => "5H 3H", 2 => "2D 4S", 3 => "3D 6S"}, tricks: 1)
        |> play_trick([{0, "9D"}, {1, "5H"}])

      assert g.hearts_broken
      assert {:hearts_broken, 1} in g.log
      g = play_trick(g, [{2, "2D"}, {3, "3D"}])
      assert g.turn == 0
      assert Game.legal_actions(g, 0) == [{:play, card("5C")}, {:play, card("2H")}]
    end

    @tag rule: "§3.5"
    test "the Q♠ can be led after the first trick and does not break hearts" do
      g = at_play(%{0 => "QS 5H 2D", 1 => "2S 3H", 2 => "3S 4H", 3 => "4S 6H"}, tricks: 1)
      assert {:play, card("QS")} in Game.legal_actions(g, 0)
      g = play_trick(g, [{0, "QS"}, {1, "2S"}, {2, "3S"}, {3, "4S"}])
      refute g.hearts_broken
      assert Game.legal_actions(g, 0) == [{:play, card("2D")}]
      refute Enum.any?(g.log, &match?({:hearts_broken, _}, &1))
    end

    @tag rule: "§3.5"
    test "with queen_breaks_hearts on, the Q♠ breaks hearts" do
      g =
        at_play(%{0 => "QS 5H 2D", 1 => "2S 3H"}, [tricks: 1], %{queen_breaks_hearts: true})
        |> apply!(0, {:play, card("QS")})

      assert g.hearts_broken
      assert {:hearts_broken, 0} in g.log
    end

    @tag rule: "§3.6"
    test "the highest card of the suit led wins; the winner leads next" do
      g =
        at_play(%{0 => "5C 9D", 1 => "7C AH", 2 => "AD 4D", 3 => "KC 2S"}, tricks: 1)
        |> play_trick([{0, "5C"}, {1, "7C"}, {2, "AD"}, {3, "KC"}])

      assert {:trick_won, 3, cards, 0} = hd(g.log)
      assert cards == cards("5C 7C AD KC")
      assert g.taken[3] == cards
      assert g.trick == []
      assert {g.leader, g.turn, g.tricks} == {3, 3, 2}
    end

    @tag rule: "§3.7"
    test "the hand ends when all cards are played" do
      g = new!(%{target: 10_000})
      g = finish_hand(g)
      assert g.hand_no == 2
      scored = Enum.filter(events(g), &match?({:hand_scored, _}, &1))
      assert [{:hand_scored, %{hand: 1}}] = scored
      assert Enum.count(events(g), &match?({:trick_won, _, _, _}, &1)) == 13
    end
  end

  describe "§4 scoring" do
    @tag rule: "§4.1"
    test "1 point per heart, 13 for the Q♠; a hand adds up to 26" do
      assert Game.points(cards("QS 2H 3H 2C JD")) == 15

      g =
        last_trick(%{0 => "AH", 1 => "3C", 2 => "4C", 3 => "5C"}, %{
          1 => [card("QS") | Enum.take(all_hearts(), 5)],
          2 => Enum.slice(all_hearts(), 5..11)
        })
        |> play_trick([{0, "AH"}, {1, "3C"}, {2, "4C"}, {3, "5C"}])

      assert {:hand_scored, %{points: points, moon: nil}} =
               Enum.find(g.log, &match?({:hand_scored, _}, &1))

      assert points == %{0 => 1, 1 => 18, 2 => 7, 3 => 0}
      assert Enum.sum(Map.values(points)) == 26
    end

    @tag rule: "§4.2"
    test "shooting the moon: the shooter gets 0 and each other player 26" do
      g =
        last_trick(%{0 => "AH", 1 => "3C", 2 => "4C", 3 => "5C"}, %{
          0 => [card("QS") | Enum.drop(all_hearts(), -1)]
        })
        |> play_trick([{0, "AH"}, {1, "3C"}, {2, "4C"}, {3, "5C"}])

      assert {:hand_scored, %{points: points, moon: 0}} =
               Enum.find(g.log, &match?({:hand_scored, _}, &1))

      assert points == %{0 => 0, 1 => 26, 2 => 26, 3 => 26}
    end

    @tag rule: "§4.2"
    test "moon: :subtract gives the shooter -26 and the others 0" do
      taken = %{0 => [card("QS") | all_hearts()]}
      assert Game.hand_points(taken, %{Game.defaults() | moon: :subtract}) == {%{0 => -26}, 0}

      taken = Map.merge(taken, %{1 => [], 2 => [], 3 => []})
      {points, 0} = Game.hand_points(taken, %{Game.defaults() | moon: :subtract})
      assert points == %{0 => -26, 1 => 0, 2 => 0, 3 => 0}
    end

    @tag rule: "§4.3"
    test "J♦ variant: the J♦ gives -10; the moon needs only the hearts and the Q♠" do
      opts = %{Game.defaults() | jack_of_diamonds: true}

      taken = %{
        0 => [card("QS") | Enum.take(all_hearts(), 3)],
        1 => [card("JD")],
        2 => [],
        3 => []
      }

      assert Game.hand_points(taken, opts) == {%{0 => 16, 1 => -10, 2 => 0, 3 => 0}, nil}

      moon = %{0 => [card("QS"), card("JD") | all_hearts()], 1 => [], 2 => [], 3 => []}
      assert Game.hand_points(moon, opts) == {%{0 => -10, 1 => 26, 2 => 26, 3 => 26}, 0}

      # off by default
      assert Game.hand_points(taken, Game.defaults()) == {%{0 => 16, 1 => 0, 2 => 0, 3 => 0}, nil}
    end

    @tag rule: "§4.4"
    test "the points of the hand are added to the totals" do
      g =
        last_trick(
          %{0 => "AH", 1 => "3C", 2 => "4C", 3 => "5C"},
          %{1 => [card("QS") | Enum.drop(all_hearts(), -1)]},
          scores: %{0 => 10, 1 => 20, 2 => 30, 3 => 40}
        )
        |> play_trick([{0, "AH"}, {1, "3C"}, {2, "4C"}, {3, "5C"}])

      assert g.scores == %{0 => 11, 1 => 45, 2 => 30, 3 => 40}
      assert {:hand_scored, %{totals: totals}} = Enum.find(g.log, &match?({:hand_scored, _}, &1))
      assert totals == g.scores
    end
  end

  describe "§5 end of the game" do
    defp end_hand(scores, opts \\ %{}) do
      last_trick(
        %{0 => "AH", 1 => "3C", 2 => "4C", 3 => "5C"},
        %{1 => [card("QS") | Enum.drop(all_hearts(), -1)]},
        [scores: scores],
        opts
      )
      |> play_trick([{0, "AH"}, {1, "3C"}, {2, "4C"}, {3, "5C"}])
    end

    @tag rule: ["§5.1", "§5.2"]
    test "at 100 or more the game ends; the lowest total wins" do
      g = end_hand(%{0 => 50, 1 => 76, 2 => 30, 3 => 40})
      assert g.scores[1] == 101
      assert Game.over?(g)
      assert Game.status(g) == {:over, %{0 => 51, 1 => 101, 2 => 30, 3 => 40}}
      assert g.winners == [2]
      assert hd(g.log) == {:game_over, [2], g.scores}
      assert Game.legal_actions(g, 0) == []
      assert Game.apply(g, 0, {:play, card("2C")}) == {:error, :game_over}
    end

    @tag rule: "§5.1"
    test "below the target the game goes on; the target is an option" do
      refute Game.over?(end_hand(%{0 => 50, 1 => 70, 2 => 30, 3 => 40}))
      assert Game.over?(end_hand(%{0 => 0, 1 => 30, 2 => 0, 3 => 0}, %{target: 50}))
    end

    @tag rule: "§5.2"
    test "a tie for the lowest total: all tied players win (ties: :share)" do
      g = end_hand(%{0 => 29, 1 => 90, 2 => 30, 3 => 30})
      assert g.winners == [0, 2, 3]
    end

    @tag rule: "§5.2"
    test "ties: :play_on plays another hand while the lowest total is tied" do
      g = end_hand(%{0 => 29, 1 => 90, 2 => 30, 3 => 30}, %{ties: :play_on})
      refute Game.over?(g)
      assert g.hand_no == 2

      g = end_hand(%{0 => 28, 1 => 90, 2 => 30, 3 => 30}, %{ties: :play_on})
      assert g.winners == [0]
    end

    @tag rule: "§5.3"
    test "when the game goes on, the next hand is dealt with the next pass" do
      g = end_hand(%{0 => 0, 1 => 0, 2 => 0, 3 => 0})
      assert {g.hand_no, g.phase, Game.pass_direction(g)} == {2, :passing, :right}
      assert Enum.all?(g.hands, fn {_, hand} -> length(hand) == 13 end)
      assert g.taken == %{0 => [], 1 => [], 2 => [], 3 => []}
      refute g.hearts_broken
      assert {:deal, 2, :right, _} = hd(g.log)
    end
  end

  describe "§6 options" do
    @tag rule: "§6"
    test "defaults and validation" do
      assert Game.defaults() == %{
               players: 4,
               no_points_first_trick: true,
               queen_breaks_hearts: false,
               moon: :add_to_others,
               jack_of_diamonds: false,
               target: 100,
               ties: :share
             }

      assert {:ok, %Game{options: %{players: 3}}} = Game.new([players: 3], {1, 2, 3})
      assert Game.new(%{players: 6}, {1, 2, 3}) == {:error, {:invalid_option, :players, 6}}
      assert Game.new(%{moon: :maybe}, {1, 2, 3}) == {:error, {:invalid_option, :moon, :maybe}}
      assert Game.new(%{colour: :red}, {1, 2, 3}) == {:error, {:unknown_option, :colour}}
      assert Game.new(%{}, :nope) == {:error, {:invalid_seed, :nope}}
    end
  end

  describe "view/2" do
    @tag rule: "§2.1"
    test "shows the own hand and hides the other hands and passes" do
      game = new!()
      view = Game.view(game, 2)
      assert view.hand == game.hands[2]
      assert view.hand_sizes == %{0 => 13, 1 => 13, 2 => 13, 3 => 13}
      assert [{:deal, 1, :left, hands}] = view.log
      assert hands == %{0 => 13, 1 => 13, 2 => game.hands[2], 3 => 13}
      assert length(view.legal_actions) == 286
    end

    @tag rule: "§2.1"
    test "after the pass, a seat sees only its own outgoing and incoming cards" do
      g = to_playing(new!())
      {:pass, :left, moves} = Enum.find(Game.view(g, 1).log, &match?({:pass, _, _}, &1))
      assert {2, [_, _, _]} = moves[1]
      assert {1, [_, _, _]} = moves[0]
      assert moves[2] == {3, 3}
      assert moves[3] == {0, 3}
    end

    @tag rule: "§2.1"
    test "a spectator sees no hand and has no actions" do
      view = Game.view(new!(), :spectator)
      assert view.hand == nil
      assert view.legal_actions == []
      assert [{:deal, 1, :left, hands}] = view.log
      assert Enum.all?(hands, fn {_, n} -> n == 13 end)
      assert Game.apply(new!(), :spectator, {:pass, []}) == {:error, :unknown_seat}
    end
  end
end
