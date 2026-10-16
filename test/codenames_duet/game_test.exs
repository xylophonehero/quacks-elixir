defmodule CodenamesDuet.GameTest do
  use ExUnit.Case, async: true

  import CodenamesDuet.Scenario

  alias CodenamesDuet.{Clue, Game, Key, Words}

  doctest Game
  doctest Key
  doctest Words
  doctest Clue

  defp counts(side), do: Enum.frequencies(side)

  describe "§1 players, words and the key" do
    @tag rule: "§1.1"
    test "2 seats, cooperative: one result for both" do
      game = new!()
      assert game.seats == [0, 1]
      lost = fixed() |> clue(0) |> apply!(1, {:guess, 15})
      assert {:over, %{result: :lost}} = Game.status(lost)
      assert Game.view(lost, 0).result == Game.view(lost, 1).result
    end

    @tag rule: "§1.2"
    test "25 different words from the word list; the first event is the set-up" do
      game = new!()
      assert length(game.words) == 25
      assert length(Enum.uniq(game.words)) == 25
      assert Enum.all?(game.words, &(&1 in Words.all()))
      assert [{:setup, words, 9}] = events(game)
      assert words == game.words
    end

    @tag rule: "§1.2"
    test "the same seed deals the same words and key; another seed others" do
      a = new!(%{}, {7, 8, 9})
      assert {a.words, a.key} == {new!(%{}, {7, 8, 9}).words, new!(%{}, {7, 8, 9}).key}
      b = new!(%{}, {7, 8, 10})
      refute a.words == b.words
      refute a.key == b.key
    end

    @tag rule: "§1.3"
    test "each side: 9 green, 3 assassins, 13 bystanders" do
      for n <- 1..30 do
        game = new!(%{}, {n, 2, 3})

        for side <- [0, 1] do
          assert counts(game.key[side]) == %{green: 9, assassin: 3, neutral: 13}
        end
      end
    end

    @tag rule: "§1.4"
    test "the overlaps follow the layout: 15 greens in all" do
      expected = Map.new(Key.layout())

      for n <- 1..30 do
        game = new!(%{}, {1, n, 3})
        pairs = Enum.zip(game.key[0], game.key[1])
        assert Enum.frequencies(pairs) == expected
        assert Enum.count(pairs, fn {a, b} -> a == :green or b == :green end) == 15
      end

      assert expected == %{
               {:green, :green} => 3,
               {:green, :neutral} => 5,
               {:neutral, :green} => 5,
               {:green, :assassin} => 1,
               {:assassin, :green} => 1,
               {:assassin, :assassin} => 1,
               {:assassin, :neutral} => 1,
               {:neutral, :assassin} => 1,
               {:neutral, :neutral} => 7
             }
    end

    @tag rule: "§1.5"
    test "9 timer tokens; the timer option takes 1..11" do
      assert new!().timer == 9
      assert new!(%{timer: 11}).timer == 11
      assert new!(timer: 10).timer == 10
      assert {:error, {:invalid_option, :timer, 12}} = Game.new(%{timer: 12}, {1, 2, 3})
      assert {:error, {:invalid_option, :timer, 0}} = Game.new(%{timer: 0}, {1, 2, 3})
    end

    @tag rule: "§1.6"
    test "a seat sees only its own side; a spectator sees no side; the log has no key" do
      game = fixed()
      assert Game.view(game, 0).key == game.key[0]
      assert Game.view(game, 1).key == game.key[1]
      assert Game.view(game, :spectator).key == nil
      assert Game.view(game, :spectator).legal_actions == []
      assert Game.view(game, 0).revealed_key == nil
      refute inspect(Game.view(new!(), 0).log) =~ "green"
    end

    @tag rule: "§1.6"
    test "when the game is over, the whole key shows" do
      game = fixed() |> clue(0) |> apply!(1, {:guess, 15})
      assert Game.view(game, 0).revealed_key == game.key
    end
  end

  describe "§2 turns" do
    @tag rule: "§2.1"
    test "either seat can give the first clue" do
      game = fixed()
      assert Game.status(game) == {:playing, [0, 1]}
      assert [{:clue, :word, 0..9}] = Game.legal_actions(game, 0)
      assert [{:clue, :word, 0..9}] = Game.legal_actions(game, 1)

      game = clue(game, 1, "weather", 2)
      assert Game.status(game) == {:playing, [0]}
      assert game.giver == 1
      assert [{:clue, 1, "weather", 2}] = events(game)
    end

    @tag rule: "§2.2"
    test "a turn is one clue, then guesses by the other seat" do
      game = fixed() |> clue(0)
      assert {:error, :not_your_turn} = Game.apply(game, 0, {:guess, 1})
      assert {:error, :invalid_action} = Game.apply(game, 1, {:clue, "again", 1})
      assert Game.legal_actions(game, 0) == []
      assert {:guess, 0} in Game.legal_actions(game, 1)
    end

    @tag rule: "§2.3"
    test "the seats alternate: the guesser gives the next clue" do
      game = fixed() |> turn(0, [0])
      assert Game.status(game) == {:playing, [1]}
      game = turn(game, 1, [8])
      assert Game.status(game) == {:playing, [0]}
    end

    @tag rule: "§2.4"
    test "a done side never gives a clue again; the partner gives all clues" do
      game = fixed() |> clue(1) |> guesses(0, Enum.take(greens(1), 8))
      refute 1 in game.done
      game = guesses(game, 0, [14])
      assert {:side_done, 1} in game.log
      assert game.done == [1]
      # seat 0 was the guesser: seat 0 gives the next clue as usual
      assert Game.status(game) == {:playing, [0]}
      game = turn(game, 0, [3])
      assert Game.status(game) == {:playing, [0]}
      game = turn(game, 0, [4])
      assert Game.status(game) == {:playing, [0]}
    end
  end

  describe "§3 clues" do
    @tag rule: "§3.1"
    test "one word and a number from 0 to 9" do
      game = fixed()

      for n <- 0..9, do: assert({:ok, _} = Game.apply(game, 0, {:clue, "weather", n}))

      for n <- [10, -1, :unlimited, "2", nil] do
        assert {:error, {:invalid_clue, :invalid_number}} =
                 Game.apply(game, 0, {:clue, "weather", n})
      end
    end

    @tag rule: "§3.2"
    test "a visible word is refused, in any case and with spaces" do
      game = fixed()

      for word <- ["alpha", "ALPHA", " Alpha "] do
        assert {:error, {:invalid_clue, {:visible_word, "alpha"}}} =
                 Game.apply(game, 0, {:clue, word, 1})
      end
    end

    @tag rule: "§3.2"
    test "a covered word is fine; one bystander mark keeps a word visible" do
      # alpha (0) is found; hotel (7) is a bystander for seat 1 only
      game = fixed() |> turn(0, [0]) |> clue(1) |> guesses(0, [7])
      assert 0 in Map.keys(game.agents)
      assert game.bystanders[7] == [1]
      assert {:ok, _} = Game.apply(game, 0, {:clue, "alpha", 1})

      assert {:error, {:invalid_clue, {:visible_word, "hotel"}}} =
               Game.apply(game, 0, {:clue, "hotel", 1})
    end

    @tag rule: "§3.2"
    test "a word marked from both sides is covered: no longer visible" do
      # sierra (18) is a bystander on both sides
      game = fixed() |> clue(0) |> guesses(1, [18]) |> clue(1) |> guesses(0, [18])
      assert game.bystanders[18] == [0, 1]
      refute "sierra" in Game.visible_words(game)
      refute Game.guessable?(game, 18, 0) or Game.guessable?(game, 18, 1)
      assert {:ok, _} = Game.apply(game, 0, {:clue, "sierra", 1})
    end

    @tag rule: "§3.3"
    test "simple word forms and parts of 4+ letters are refused" do
      assert Clue.conflict?("apples", "apple")
      assert Clue.conflict?("apple", "apples")
      assert Clue.conflict?("baked", "bake")
      assert Clue.conflict?("earth", "earthquake")
      assert Clue.conflict?("rawhide", "hide")
      refute Clue.conflict?("ear", "earthquake")
      refute Clue.conflict?("hearth", "earthquake")
      refute Clue.conflict?("weather", "storm")
      assert {:error, {:visible_word, "rainbow"}} = Clue.check("rain", 2, ["storm", "rainbow"])
    end

    @tag rule: "§3.4"
    test "one word: letters, an inside hyphen or apostrophe, 30 letters at most" do
      for word <- ["x-ray", "o'clock", "Michelangelo", "crêpe"],
          do: assert(Clue.check(word, 1, []) == :ok)

      for word <- ["two words", "", "  ", "r2d2", "-ray", "hello!", 42] do
        assert Clue.check(word, 1, []) == {:error, :not_one_word}
      end

      assert Clue.check(String.duplicate("a", 31), 1, []) == {:error, :too_long}
    end

    @tag rule: "§3.6"
    test "an invalid clue is refused and nothing changes (no token)" do
      game = fixed()
      assert {:error, {:invalid_clue, _}} = Game.apply(game, 0, {:clue, "two words", 1})
      assert game.timer == 9
    end
  end

  describe "§4 guesses" do
    @tag rule: "§4.1"
    test "the clue giver's side decides the guess" do
      # foxtrot (5) is green for seat 0 and a bystander for seat 1
      a = fixed() |> clue(0) |> apply!(1, {:guess, 5})
      assert a.agents == %{5 => 1}
      b = fixed() |> clue(1) |> apply!(0, {:guess, 5})
      assert b.agents == %{}
      assert b.bystanders == %{5 => [1]}
    end

    @tag rule: "§4.2"
    test "green: an agent covers it and the guesser goes on, past the clue number" do
      game = fixed() |> clue(0, "quokka", 1) |> guesses(1, [3, 4, 5])
      assert game.phase == :guess
      assert game.agents == %{3 => 1, 4 => 1, 5 => 1}
      assert {:guess, 1, 3, :green} in game.log
    end

    @tag rule: "§4.2"
    test "a word green on both sides is found for both sides" do
      game = fixed() |> clue(0) |> apply!(1, {:guess, 0})
      assert Game.greens_left(game, 0) == 8
      assert Game.greens_left(game, 1) == 8
      assert Game.found(game) == 1
    end

    @tag rule: "§4.3"
    test "bystander: marked for the clue giver's side, the turn ends, one token" do
      game = fixed() |> clue(0) |> apply!(1, {:guess, 8})
      assert game.bystanders == %{8 => [0]}
      assert game.timer == 8
      assert game.phase == :clue
      assert Game.status(game) == {:playing, [1]}
      assert [_, {:guess, 1, 8, :neutral}, {:turn_end, 1, :neutral, 8}] = events(game)
    end

    @tag rule: "§4.4"
    test "assassin of the clue giver's side: both lose, no more actions" do
      game = fixed() |> clue(0) |> guesses(1, [0, 16])
      assert {:over, %{result: :lost, reason: :assassin, score: nil}} = Game.status(game)
      assert {:game_over, :lost, :assassin} = hd(game.log)
      assert Game.legal_actions(game, 0) == [] and Game.legal_actions(game, 1) == []
      assert {:error, :game_over} = Game.apply(game, 1, {:guess, 1})
    end

    @tag rule: "§4.4"
    test "an assassin of the guesser's own side is not one for this guess" do
      # 14 is an assassin for seat 0, green for seat 1
      game = fixed() |> clue(1) |> apply!(0, {:guess, 14})
      assert game.agents == %{14 => 0}
      refute Game.over?(game)
    end

    @tag rule: "§4.5"
    test "a word marked from one side: not again on that side's turns, yes on the other's" do
      # hotel (7): bystander for seat 1, green for seat 0
      game = fixed() |> clue(1) |> apply!(0, {:guess, 7})
      game = turn(game, 0, [0])
      game = clue(game, 1)
      assert {:error, :not_guessable} = Game.apply(game, 0, {:guess, 7})
      refute {:guess, 7} in Game.legal_actions(game, 0)
      game = turn(%{game | phase: :clue, giver: 0, clue: nil}, 0, [7])
      assert game.agents[7] == 1
    end

    @tag rule: "§4.6"
    test "the guesser stops only after a guess, also after a 0 clue" do
      game = fixed() |> clue(0, "quokka", 0)
      refute :end_turn in Game.legal_actions(game, 1)
      assert {:error, :must_guess} = Game.apply(game, 1, :end_turn)
      game = apply!(game, 1, {:guess, 0})
      assert :end_turn in Game.legal_actions(game, 1)
      game = apply!(game, 1, :end_turn)
      assert game.timer == 8
      assert game.stops == 1
      assert {:turn_end, 1, :stopped, 8} = hd(game.log)
    end

    @tag rule: "§4.7"
    test "any open word can be guessed, not only words of the clue" do
      game = fixed() |> clue(0)
      assert length(Game.legal_actions(game, 1)) == 25
    end

    @tag rule: "§4.8"
    test "the clue giver's last green found: the turn ends with a token" do
      game = fixed() |> clue(0) |> guesses(1, greens(0))
      assert game.done == [0]
      assert game.timer == 8
      assert {:turn_end, 1, :side_done, 8} = hd(game.log)
      assert Game.status(game) == {:playing, [1]}
    end
  end

  describe "§5 the timer" do
    @tag rule: "§5.1"
    test "each turn uses exactly one token, by a bystander or a stop" do
      game = fixed() |> turn(0, [0, 1])
      assert game.timer == 8
      game = turn(game, 1, [18])
      assert game.timer == 7
      assert game.bystanders[18] == [1]
    end

    @tag rule: "§5.2"
    test "the tokens are the turns: the 9th turn ends the clues" do
      game =
        Enum.reduce(0..8, fixed(), fn n, game ->
          giver = rem(n, 2)
          assert {:playing, seats} = Game.status(game)
          assert giver in seats
          turn(game, giver, [Enum.at([0, 8, 1, 9, 2, 10, 3, 11, 4], n)])
        end)

      assert game.timer == 0
      assert game.phase == :sudden_death
      assert {:error, :invalid_action} = Game.apply(game, 0, {:clue, "quokka", 1})
    end

    @tag rule: "§5.3"
    test "the winning turn takes no token" do
      game = all_but_last()
      timer = game.timer
      game = guesses(game, 0, [14])
      assert game.result == :won
      assert game.timer == timer
    end
  end

  # Every green but 14 found in 3 turns (3 stops, timer 6); seat 0 is done, so
  # seat 1 gives every clue (§2.4); seat 1's 4th clue is on.
  defp all_but_last do
    fixed()
    |> turn(0, [0, 1, 2, 3, 4, 5, 6, 7, 13])
    |> turn(1, [8, 9, 10, 11])
    |> turn(1, [12])
    |> clue(1)
  end

  describe "§6 end of the game" do
    @tag rule: "§6.1"
    test "all 15 greens found: both win at once" do
      game = guesses(all_but_last(), 0, [14])
      assert Game.found(game) == 15
      assert {:over, %{result: :won, reason: :all_found}} = Game.status(game)
      assert {:game_over, :won, :all_found} = hd(game.log)
    end

    @tag rule: "§6.2"
    test "an assassin loses even with tokens left" do
      game = fixed() |> clue(1) |> apply!(0, {:guess, 13})
      assert game.result == :lost
      assert game.timer == 9
    end

    defp to_sudden_death(opts \\ %{}) do
      game = fixed(Map.merge(%{timer: 1}, opts)) |> turn(0, [0])
      assert game.phase == :sudden_death
      game
    end

    @tag rule: "§6.3"
    test "sudden death: no clues; each seat with words to guess can guess, in any order" do
      game = to_sudden_death()
      assert {:sudden_death, [0, 1]} = hd(game.log)
      assert Game.status(game) == {:playing, [0, 1]}
      refute Enum.any?(Game.legal_actions(game, 0), &match?({:clue, _, _}, &1))
      assert {:error, :invalid_action} = Game.apply(game, 0, :end_turn)
      # seat 1 guesses on seat 0's side, twice in a row
      game = game |> apply!(1, {:guess, 3}) |> apply!(1, {:guess, 4})
      # seat 0 guesses on seat 1's side
      game = apply!(game, 0, {:guess, 8})
      assert game.agents == %{0 => 1, 3 => 1, 4 => 1, 8 => 0}
    end

    @tag rule: "§6.3"
    test "sudden death: a bystander loses" do
      game = to_sudden_death() |> apply!(1, {:guess, 18})
      assert {:over, %{result: :lost, reason: :sudden_death}} = Game.status(game)
    end

    @tag rule: "§6.3"
    test "sudden death: an assassin loses" do
      game = to_sudden_death() |> apply!(0, {:guess, 17})
      assert game.result == :lost
    end

    @tag rule: "§6.3"
    test "sudden death: a seat whose partner's side is done is not a guesser; the last green wins" do
      game = to_sudden_death() |> guesses(1, [1, 2, 3, 4, 5, 6, 7, 13])
      assert game.done == [0]
      assert Game.status(game) == {:playing, [0]}
      assert {:error, :not_your_turn} = Game.apply(game, 1, {:guess, 8})
      game = guesses(game, 0, [8, 9, 10, 11, 12, 14])
      # score: 0 tokens, 1 stop, −1 for sudden death (§6.4)
      assert {:over, %{result: :won, score: 0}} = Game.status(game)
    end

    @tag rule: "§6.3"
    test "sudden death: a word marked from the partner's side cannot be guessed" do
      game = fixed(%{timer: 2}) |> clue(0) |> guesses(1, [18]) |> turn(1, [8])
      assert game.phase == :sudden_death
      assert {:error, :not_guessable} = Game.apply(game, 1, {:guess, 18})
      assert {:ok, %{result: :lost}} = Game.apply(game, 0, {:guess, 18})
    end

    @tag rule: "§6.4"
    test "score: 3 per token left after the winning turn, 1 per stop, −1 for sudden death" do
      # 3 turns, all stops; the 4th turn wins with 6 tokens in the bank
      game = guesses(all_but_last(), 0, [14])
      assert game.stops == 3
      assert Game.score(game) == 3 * 5 + 3
      assert Game.view(game, 0).score == 18
      lost = fixed() |> clue(0) |> apply!(1, {:guess, 15})
      assert Game.score(lost) == nil
    end
  end

  describe "§8 options" do
    @tag rule: "§8"
    test "the defaults; unknown options and a bad seed are refused" do
      assert Game.defaults() == %{timer: 9}
      assert {:error, {:unknown_option, :players}} = Game.new(%{players: 3}, {1, 2, 3})
      assert {:error, {:invalid_seed, :x}} = Game.new(%{}, :x)
      assert {:error, :unknown_seat} = Game.apply(new!(), 2, {:clue, "quokka", 1})
      assert {:error, :invalid_action} = Game.apply(new!(), 0, :dance)
    end
  end
end
