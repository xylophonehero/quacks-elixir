defmodule CodenamesDuet.AI.StagingGamesTest do
  @moduledoc """
  Regression tests from two real games on staging (2026-10-17): seat 0 a person,
  seat 1 the bot. The boards, the keys and the moves are the ones of the rooms.

  - YEXRA: the bot's first clue was "due 2"; its partner read it as "debt", an
    assassin on the bot's side, and the game was lost.
  - 3TVJP: the bot gave "dressing 2" four times, although its partner read it
    wrong each time.
  """
  use ExUnit.Case, async: true

  alias CodenamesDuet.AI.Vectors
  alias CodenamesDuet.AI.Vectors.Data
  alias CodenamesDuet.{Game, Key}

  @yexra_words ~w(breath winter company copper force soap wheel toe daughter back waste bone
                  paste door fall act current grass interest punishment camera debt business
                  hook church)
  @yexra_key %{
    0 => ~w(neutral green green green neutral neutral neutral neutral green green neutral green
         green green assassin neutral neutral neutral neutral neutral assassin neutral assassin
         neutral green)a,
    1 => ~w(neutral neutral assassin neutral neutral green green neutral green neutral neutral
         green neutral green green neutral green neutral green green neutral assassin assassin
         neutral neutral)a
  }

  @tvjp_words ~w(development mine worm blood wood tree sound bite stage fruit cup face
                 trousers idea scale operation cake bath division metal cow opinion machine drop
                 seed)
  @tvjp_key %{
    0 => ~w(assassin green neutral green neutral neutral green neutral neutral green green neutral
         green neutral neutral neutral neutral green green green neutral neutral assassin
         assassin neutral)a,
    1 => ~w(neutral neutral neutral neutral assassin neutral assassin neutral green green green
         neutral neutral green neutral green green green neutral neutral neutral neutral green
         assassin green)a
  }

  # The moves of room 3TVJP, oldest first (the engine adds the turn ends and the marks).
  @tvjp_moves [
    {1, {:clue, "tomato", 3}},
    {0, {:guess, 9}},
    {0, {:guess, 24}},
    {0, {:guess, 3}},
    {0, {:clue, "football", 2}},
    {1, {:guess, 10}},
    {1, {:guess, 18}},
    {1, :end_turn},
    {1, {:clue, "dressing", 2}},
    {0, {:guess, 12}},
    {0, {:clue, "gwar", 4}},
    {1, {:guess, 15}},
    {1, {:clue, "dressing", 2}},
    {0, {:guess, 15}},
    {0, {:guess, 7}},
    {0, {:clue, "meditation", 3}},
    {1, {:guess, 13}},
    {1, {:clue, "dressing", 2}},
    {0, {:guess, 14}},
    {0, {:clue, "chainsaw", 3}},
    {1, {:guess, 8}},
    {1, {:clue, "dressing", 2}}
  ]

  defp board(words, key) do
    {:ok, game} = Game.new(%{}, {1, 2, 3})
    %{game | words: words, key: key}
  end

  defp clue(game, seed) do
    {action, _} = Vectors.choose(Game.view(game, 1), Vectors.new({seed, 2, 3}))
    assert {:clue, word, number} = action
    {word, number}
  end

  describe "room YEXRA: the first clue" do
    test "the old clue \"due\" is not a clue word" do
      refute Data.clue?("due")
    end

    test "the clue is far from the bot's assassins, in the bot's vectors and in others" do
      game = board(@yexra_words, @yexra_key)
      assassins = for i <- Key.indexes(game.key[1], :assassin), do: Enum.at(game.words, i)
      greens = for i <- Key.indexes(game.key[1], :green), do: Enum.at(game.words, i)

      for seed <- 1..5 do
        {word, number} = clue(game, seed)
        refute word == "due"

        for set <- [:main, :glove], Data.lookup(word, set) do
          z = &Data.to_z(Data.similarity(word, &1, set), set)
          weakest = greens |> Enum.map(z) |> Enum.sort(:desc) |> Enum.at(number - 1)

          for a <- assassins do
            assert z.(a) < weakest,
                   "#{word} #{number}: #{a} (#{z.(a)}) is nearer than a target (#{weakest}) in #{set}"
          end
        end
      end
    end
  end

  describe "room 3TVJP: the bot's clues" do
    test "the bot never repeats a clue; after a wrong read it tries another clue" do
      {_game, given} =
        Enum.reduce(@tvjp_moves, {board(@tvjp_words, @tvjp_key), []}, fn
          {1, {:clue, old, n}}, {game, given} ->
            {word, _} = clue(game, 1)
            refute word in given, "the bot gave #{word} again (#{inspect(given)})"
            {apply!(game, 1, {:clue, old, n}), [old | given]}

          {seat, action}, {game, given} ->
            {apply!(game, seat, action), given}
        end)

      assert "dressing" in given
    end
  end

  defp apply!(game, seat, action) do
    {:ok, game} = Game.apply(game, seat, action)
    game
  end
end
