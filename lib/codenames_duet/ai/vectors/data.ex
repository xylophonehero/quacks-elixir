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

  @scale 127

  @typedoc """
  A vector set: `:main` (`vectors.bin`, the bot's), another atom (`<name>.bin` in
  the same folder: `:glove` is the bench's proxy guesser), or a file path.
  """
  @type set :: atom | Path.t()

  @type t :: %{
          index: %{String.t() => non_neg_integer},
          words: tuple,
          clue: tuple,
          vectors: tuple,
          norms: tuple,
          neighbours: %{String.t() => binary},
          stats: {float, float}
        }

  @doc "The data of `set` (read once, then from `:persistent_term`)."
  @spec data(set) :: t
  def data(set \\ :main) do
    case :persistent_term.get({__MODULE__, set}, nil) do
      nil ->
        data = load(path(set))
        :persistent_term.put({__MODULE__, set}, data)
        data

      data ->
        data
    end
  end

  @doc "The 8-bit vector of `word` (a binary), or nil when the word is not in the data."
  @spec vector(String.t(), set) :: binary | nil
  def vector(word, set \\ :main) do
    d = data(set)

    case Map.fetch(d.index, word) do
      {:ok, i} -> elem(d.vectors, i)
      :error -> nil
    end
  end

  @doc "True when `word` is in the clue vocabulary."
  @spec clue?(String.t(), set) :: boolean
  def clue?(word, set \\ :main) do
    d = data(set)

    case Map.fetch(d.index, word) do
      {:ok, i} -> elem(d.clue, i)
      :error -> false
    end
  end

  @doc "The clue words, most frequent first."
  @spec clue_words(set) :: [String.t()]
  def clue_words(set \\ :main) do
    d = data(set)
    for i <- 0..(tuple_size(d.words) - 1), elem(d.clue, i), do: elem(d.words, i)
  end

  @doc "The nearest clue words of board word `word`, nearest first: `[{word, cosine}]`."
  @spec neighbours(String.t(), set) :: [{String.t(), float}]
  def neighbours(word, set \\ :main) do
    d = data(set)

    case Map.fetch(d.neighbours, word) do
      {:ok, list} -> for <<i::little-16, s::signed-8 <- list>>, do: {elem(d.words, i), s / @scale}
      :error -> []
    end
  end

  @doc """
  The index of `word` in the data, or of a simple form of it (`ships` → `ship`),
  or nil. The bot reads a clue that is not in the data through this.
  """
  @spec lookup(String.t(), set) :: non_neg_integer | nil
  def lookup(word, set \\ :main) do
    index = data(set).index
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
  @spec similarity(String.t(), String.t(), set) :: float | nil
  def similarity(a, b, set \\ :main) do
    with i when is_integer(i) <- lookup(a, set),
         j when is_integer(j) <- lookup(b, set),
         do: cosine(i, j, set)
  end

  @doc """
  How near the words at indexes `i` and `j` are, in standard deviations above
  the mean cosine of two board words. Each vector set has its own scale; this
  one is the same for all sets (0: as near as two random board words).
  """
  @spec z(non_neg_integer, non_neg_integer, set) :: float
  def z(i, j, set \\ :main) do
    {mean, sd} = data(set).stats
    (cosine(i, j, set) - mean) / sd
  end

  @doc "A cosine of `set` as a `z/3` value."
  @spec to_z(float, set) :: float
  def to_z(cosine, set \\ :main) do
    {mean, sd} = data(set).stats
    (cosine - mean) / sd
  end

  @doc "The cosine similarity of the words at indexes `i` and `j`."
  @spec cosine(non_neg_integer, non_neg_integer, set) :: float
  def cosine(i, j, set \\ :main) do
    d = data(set)
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

  defp path(:main), do: path(:vectors)
  defp path(set) when is_atom(set), do: Path.join(dir(), "#{set}.bin")
  defp path(file) when is_binary(file), do: file

  defp dir, do: Path.join([:code.priv_dir(:quacks), "games", "codenames_duet"])

  defp load(file) do
    bin = File.read!(file)

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

    boards = board_order(boards)
    neighbours = read_neighbours(rest, boards, k)
    index = words |> Tuple.to_list() |> Enum.with_index() |> Map.new()
    vectors = List.to_tuple(vectors)
    norms = List.to_tuple(norms)

    %{
      index: index,
      words: words,
      clue: clue,
      vectors: vectors,
      norms: norms,
      neighbours: neighbours,
      stats: stats(Enum.map(boards, &index[&1]), vectors, norms)
    }
  end

  # The mean and the standard deviation of the cosine of two board words: each
  # board word against the next 40 (in words.txt order).
  defp stats(boards, vectors, norms) do
    n = length(boards)
    t = List.to_tuple(boards)

    sims =
      for a <- 0..(n - 1), b <- 1..40 do
        i = elem(t, a)
        j = elem(t, rem(a + b, n))
        dot(elem(vectors, i), elem(vectors, j), 0) / (elem(norms, i) * elem(norms, j))
      end

    mean = Enum.sum(sims) / length(sims)
    var = Enum.sum(Enum.map(sims, &((&1 - mean) * (&1 - mean)))) / length(sims)
    {mean, :math.sqrt(var)}
  end

  # The neighbour lists follow the order of words.txt (`CodenamesDuet.Words.all/0`).
  defp board_order(boards) do
    set = MapSet.new(boards)
    Enum.filter(CodenamesDuet.Words.all(), &MapSet.member?(set, &1))
  end

  defp read_words(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp read_words(<<flags, len, word::binary-size(len), rest::binary>>, n, acc),
    do: read_words(rest, n - 1, [{flags, word} | acc])

  defp read_neighbours(bin, boards, k) do
    size = k * 3

    {map, _} =
      Enum.reduce(boards, {%{}, bin}, fn board,
                                         {map, <<list::binary-size(size), rest::binary>>} ->
        # ponytail: kept packed (3 bytes each) and decoded per call; as tuples the
        # 599 × 300 lists took ~16 MB and the 256 MB staging VM was OOM-killed.
        {Map.put(map, board, :binary.copy(list)), rest}
      end)

    map
  end
end
