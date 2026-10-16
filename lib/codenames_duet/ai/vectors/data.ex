defmodule CodenamesDuet.AI.Vectors.Data do
  @moduledoc """
  The word vectors of the Duet bot: `priv/games/codenames_duet/vectors.bin`, a
  subset of GloVe 6B 100d (PDDL, see `docs/CREDITS.md`). The file holds the 599
  board words and 17,528 clue words as 8-bit vectors, and the 300 nearest clue
  words of each board word. `docs/games/codenames_duet/build_vectors.py` makes
  it and documents the format.

  The first call reads the file into `:persistent_term` (about 3 MB); the later
  calls read it from there.

      iex> CodenamesDuet.AI.Vectors.Data.similarity("sea", "ocean") > 0.5
      true
  """

  @key {__MODULE__, :data}
  @scale 127

  @type t :: %{
          index: %{String.t() => non_neg_integer},
          words: tuple,
          clue: tuple,
          vectors: tuple,
          norms: tuple,
          neighbours: %{String.t() => [{String.t(), float}]}
        }

  @doc "The data (read once, then from `:persistent_term`)."
  @spec data() :: t
  def data do
    case :persistent_term.get(@key, nil) do
      nil ->
        data = load()
        :persistent_term.put(@key, data)
        data

      data ->
        data
    end
  end

  @doc "The 8-bit vector of `word` (a binary), or nil when the word is not in the data."
  @spec vector(String.t()) :: binary | nil
  def vector(word) do
    d = data()

    case Map.fetch(d.index, word) do
      {:ok, i} -> elem(d.vectors, i)
      :error -> nil
    end
  end

  @doc "True when `word` is in the clue vocabulary."
  @spec clue?(String.t()) :: boolean
  def clue?(word) do
    d = data()

    case Map.fetch(d.index, word) do
      {:ok, i} -> elem(d.clue, i)
      :error -> false
    end
  end

  @doc "The clue words, most frequent first."
  @spec clue_words() :: [String.t()]
  def clue_words do
    d = data()
    for i <- 0..(tuple_size(d.words) - 1), elem(d.clue, i), do: elem(d.words, i)
  end

  @doc "The nearest clue words of board word `word`, nearest first: `[{word, cosine}]`."
  @spec neighbours(String.t()) :: [{String.t(), float}]
  def neighbours(word), do: Map.get(data().neighbours, word, [])

  @doc """
  The index of `word` in the data, or of a simple form of it (`ships` → `ship`),
  or nil. The bot reads a clue that is not in the data through this.
  """
  @spec lookup(String.t()) :: non_neg_integer | nil
  def lookup(word) do
    index = data().index
    Enum.find_value([word | stems(word)], &Map.get(index, &1))
  end

  defp stems(word) do
    for {ending, add} <-
          [{"ies", "y"}, {"es", ""}, {"s", ""}, {"ing", ""}, {"ing", "e"}] ++
            [{"ed", ""}, {"ed", "e"}, {"ly", ""}, {"er", ""}],
        String.ends_with?(word, ending),
        String.length(word) - String.length(ending) >= 3,
        do: String.slice(word, 0, String.length(word) - String.length(ending)) <> add
  end

  @doc "The cosine similarity of two words (or nil when one is not in the data)."
  @spec similarity(String.t(), String.t()) :: float | nil
  def similarity(a, b) do
    with i when is_integer(i) <- lookup(a),
         j when is_integer(j) <- lookup(b),
         do: cosine(i, j)
  end

  @doc "The cosine similarity of the words at indexes `i` and `j`."
  @spec cosine(non_neg_integer, non_neg_integer) :: float
  def cosine(i, j) do
    d = data()
    dot(elem(d.vectors, i), elem(d.vectors, j), 0) / (elem(d.norms, i) * elem(d.norms, j))
  end

  # Four components a step: the vectors have 100 (a multiple of 4).
  defp dot(
         <<a1::signed-8, a2::signed-8, a3::signed-8, a4::signed-8, ra::binary>>,
         <<b1::signed-8, b2::signed-8, b3::signed-8, b4::signed-8, rb::binary>>,
         acc
       ),
       do: dot(ra, rb, acc + a1 * b1 + a2 * b2 + a3 * b3 + a4 * b4)

  defp dot(<<>>, <<>>, acc), do: acc

  # -- the file ------------------------------------------------------------------------

  defp load do
    bin =
      File.read!(Path.join([:code.priv_dir(:quacks), "games", "codenames_duet", "vectors.bin"]))

    <<"CDV1", count::little-32, dim::little-16, k::little-16, rest::binary>> = bin

    {entries, rest} = read_words(rest, count, [])
    words = entries |> Enum.map(&elem(&1, 1)) |> List.to_tuple()
    clue = entries |> Enum.map(&(Bitwise.band(elem(&1, 0), 1) == 1)) |> List.to_tuple()
    boards = for {flags, w} <- entries, Bitwise.band(flags, 2) == 2, do: w

    size = count * dim
    <<vec_bin::binary-size(size), rest::binary>> = rest
    vectors = for <<v::binary-size(dim) <- vec_bin>>, do: :binary.copy(v)

    norms =
      Enum.map(vectors, fn v -> :math.sqrt(dot(v, v, 0)) end)

    neighbours = read_neighbours(rest, board_order(boards), k, words)

    %{
      index: words |> Tuple.to_list() |> Enum.with_index() |> Map.new(),
      words: words,
      clue: clue,
      vectors: List.to_tuple(vectors),
      norms: List.to_tuple(norms),
      neighbours: neighbours
    }
  end

  # The neighbour lists follow the order of words.txt (`CodenamesDuet.Words.all/0`).
  defp board_order(boards) do
    set = MapSet.new(boards)
    Enum.filter(CodenamesDuet.Words.all(), &MapSet.member?(set, &1))
  end

  defp read_words(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp read_words(<<flags, len, word::binary-size(len), rest::binary>>, n, acc),
    do: read_words(rest, n - 1, [{flags, word} | acc])

  defp read_neighbours(bin, boards, k, words) do
    size = k * 3

    {map, _} =
      Enum.reduce(boards, {%{}, bin}, fn board,
                                         {map, <<list::binary-size(size), rest::binary>>} ->
        near = for <<i::little-16, s::signed-8 <- list>>, do: {elem(words, i), s / @scale}
        {Map.put(map, board, near), rest}
      end)

    map
  end
end
