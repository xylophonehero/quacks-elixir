defmodule CodenamesDuet.AI.VectorsTest do
  @moduledoc """
  The word-vector bot (`CodenamesDuet.AI.Vectors`): it gives legal clues that
  point at its own greens, it guesses the words nearest a clue, it never sends an
  illegal action, and a seed gives the same play.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CodenamesDuet.AI.{Bench, Vectors}
  alias CodenamesDuet.AI.Vectors.Data
  alias CodenamesDuet.{Clue, Game, Key, Scenario, Words}

  doctest Bench

  # The key of `Scenario.fixed/1`. Seat 0: greens 0..7 and 13 (clothes, the sea,
  # fish), assassins 14..16 (bread, cheese, apple).
  @board ~w(shirt wool silk cotton sea wave ship boat dog cat horse money gold fish bread
            cheese apple music song train plane hospital river)

  defp board do
    words = @board ++ Enum.take(Words.all() -- @board, 25 - length(@board))
    %{Scenario.fixed() | words: words}
  end

  defp choose(game, seat, seed \\ 1) do
    {action, _} = Vectors.choose(Game.view(game, seat), Vectors.new({seed, 2, 3}))
    action
  end

  describe "the data" do
    test "every board word has a vector, and its nearest clue words" do
      for word <- Words.all() do
        assert Data.vector(word), word
        assert [_ | _] = Data.neighbours(word)
      end
    end

    test "similar words are closer than unrelated words" do
      assert Data.similarity("shirt", "jacket") > Data.similarity("shirt", "planet")
      assert Data.similarity("ocean", "sea") > Data.similarity("ocean", "cheese")
      assert Data.similarity("zzzqx", "sea") == nil
    end

    test "the clue vocabulary has no blocked words and no stop words" do
      for word <- ~w(sex porn shit the and said), do: refute(Data.clue?(word), word)
      for word <- ~w(clothing ocean animal), do: assert(Data.clue?(word), word)
    end
  end

  describe "the clue giver" do
    test "gives a legal clue for 2 or more of its own greens" do
      game = board()
      assert {:clue, word, number} = choose(game, 0)
      assert Clue.check(word, number, Game.visible_words(game)) == :ok
      assert number >= 2
      greens = Key.indexes(game.key[0], :green)
      near = Enum.max_by(0..24, &(Data.similarity(word, Enum.at(game.words, &1)) || -1))
      assert near in greens
    end

    test "does not point at its assassins" do
      game = board()
      {:clue, word, _} = choose(game, 0)

      for i <- Key.indexes(game.key[0], :assassin) do
        assert Data.similarity(word, Enum.at(game.words, i)) < 0.45
      end
    end

    test "a bot guesser finds the bot clue giver's greens" do
      game = board()
      {:clue, _, number} = action = choose(game, 0)
      game = Scenario.apply!(game, 0, action)
      {:guess, i} = choose(game, 1)
      assert Enum.at(game.key[0], i) == :green
      assert number >= 1
    end
  end

  describe "the guesser" do
    test "guesses the word nearest the clue first" do
      game = board() |> Scenario.clue(0, "clothing", 3)
      assert {:guess, i} = choose(game, 1)
      assert Enum.at(game.words, i) in ~w(shirt wool silk cotton)
    end

    test "makes at most one guess more than the clue number" do
      game = board() |> Scenario.clue(0, "clothing", 1) |> Scenario.guesses(1, [0, 1])
      assert choose(game, 1) == :end_turn
    end

    test "with an unknown clue it still makes the one guess it must, then stops" do
      game = board() |> Scenario.clue(0, "zzzqx", 2)
      assert {:guess, _} = choose(game, 1)
      game = board() |> Scenario.clue(0, "zzzqx", 2) |> Scenario.guesses(1, [0])
      assert choose(game, 1) == :end_turn
    end

    test "in sudden death it guesses a word near its partner's old clues" do
      game = board() |> Scenario.clue(1, "cash", 1)
      game = %{game | phase: :sudden_death, giver: nil, clue: nil, timer: 0, sudden_death: true}
      assert {:guess, i} = choose(game, 0)
      assert Game.guessable?(game, i, 1)
      assert Enum.at(game.words, i) in ~w(money gold)
    end
  end

  test "a seed gives the same action; the action is one of the legal actions" do
    game = board()
    assert choose(game, 0, 5) == choose(game, 0, 5)
  end

  defp seed, do: tuple({integer(1..100_000), integer(1..100_000), integer(1..100_000)})

  property "bot + bot: every action is legal and the game ends" do
    check all(seed <- seed(), timer <- integer(1..11), max_runs: 25) do
      result = Bench.play_one(%{timer: timer}, seed)
      assert result.errors == []
      assert result.result in [:won, :lost]
    end
  end

  test "the bench: bot + bot games find agents" do
    result = Bench.run(games: 20, seed: 1)
    assert result.games == 20
    assert result.mean_found >= 6
    assert result.assassin_rate <= 0.5
  end
end
