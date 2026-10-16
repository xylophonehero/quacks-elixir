defmodule CodenamesDuet.Clue do
  @moduledoc """
  The checks on a clue that the engine can do (rulebook §3.1, §3.3, §3.4). The
  players judge the rest (§3.5): the meaning, and word forms that these simple
  rules do not find.
  """

  @max_number 9
  @max_length 30
  @endings ~w(ing es ed er s d)
  @one_word ~r/^\p{L}+(?:['-]\p{L}+)*$/u

  @type reason :: :not_one_word | :too_long | {:visible_word, String.t()} | :invalid_number

  @doc "The highest clue number (§3.1)."
  @spec max_number() :: pos_integer
  def max_number, do: @max_number

  @doc """
  The clue word as the engine keeps it: trimmed, in lower case.

      iex> CodenamesDuet.Clue.normalize("  Weather ")
      "weather"
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(word), do: word |> String.trim() |> String.downcase()

  @doc """
  `:ok`, or `{:error, reason}` when the clue `{word, number}` is invalid against
  the `visible` words of the board.

      iex> CodenamesDuet.Clue.check("weather", 2, ["storm", "rainbow"])
      :ok
      iex> CodenamesDuet.Clue.check("rain", 2, ["storm", "rainbow"])
      {:error, {:visible_word, "rainbow"}}
  """
  @spec check(term, term, [String.t()]) :: :ok | {:error, reason}
  def check(word, number, visible) do
    cond do
      not is_integer(number) or number not in 0..@max_number ->
        {:error, :invalid_number}

      not is_binary(word) or not Regex.match?(@one_word, String.trim(word)) ->
        {:error, :not_one_word}

      String.length(String.trim(word)) > @max_length ->
        {:error, :too_long}

      hit = Enum.find(visible, &conflict?(normalize(word), normalize(&1))) ->
        {:error, {:visible_word, hit}}

      true ->
        :ok
    end
  end

  @doc """
  True when `clue` is a visible word, a simple form of it, or a part of it (§3.3).
  Both words are in lower case.

      iex> CodenamesDuet.Clue.conflict?("apples", "apple")
      true
      iex> CodenamesDuet.Clue.conflict?("earth", "earthquake")
      true
      iex> CodenamesDuet.Clue.conflict?("ear", "earthquake")
      false
  """
  @spec conflict?(String.t(), String.t()) :: boolean
  def conflict?(clue, word) do
    not MapSet.disjoint?(forms(clue), forms(word)) or contains?(clue, word) or
      contains?(word, clue)
  end

  defp contains?(long, short), do: String.length(short) >= 4 and String.contains?(long, short)

  defp forms(word) do
    stems =
      for ending <- @endings,
          String.ends_with?(word, ending),
          String.length(word) - String.length(ending) >= 3,
          do: String.slice(word, 0, String.length(word) - String.length(ending))

    MapSet.new([word | stems])
  end
end
