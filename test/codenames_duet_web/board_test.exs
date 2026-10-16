defmodule CodenamesDuetWeb.BoardTest do
  use ExUnit.Case, async: true

  alias CodenamesDuet.Words
  alias CodenamesDuetWeb.Board

  doctest CodenamesDuetWeb.Board

  test "every word of the list fits: at most 10 letters on its longest line" do
    for word <- Words.all() do
      {text, fit} = Board.fit(word)
      assert String.replace(text, "\u00AD", "") == word
      assert fit <= 10, "#{word}: #{fit}"
    end
  end

  test "the longest words break before a common ending" do
    assert Board.fit("advertisement") == {"advertise\u00ADment", 10}
    assert Board.fit("organization") == {"organ\u00ADization", 7}
    assert Board.fit("development") == {"develop\u00ADment", 8}
  end

  test "the log groups the guesses under their clue, newest clue first" do
    log =
      Enum.reverse([
        {:setup, [], 9},
        {:clue, 0, "sea", 2},
        {:guess, 1, 4, :green},
        {:guess, 1, 7, :neutral},
        {:turn_end, 1, :neutral, 8},
        {:clue, 1, "sky", 1},
        {:guess, 0, 3, :green}
      ])

    assert [
             %{word: "sky", guesses: [{0, 3, :green}], ending: nil},
             %{
               word: "sea",
               number: 2,
               guesses: [{1, 4, :green}, {1, 7, :neutral}],
               ending: :neutral
             }
           ] = Board.log_entries(log)
  end
end
