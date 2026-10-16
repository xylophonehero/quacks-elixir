defmodule CodenamesDuet.Game do
  @moduledoc """
  The Codenames Duet engine: pure functions over a `%CodenamesDuet.Game{}` struct.

  Rules: `docs/games/codenames_duet/rulebook.md` (the § numbers below refer to it).
  Glossary: `docs/games/codenames_duet/CONTEXT.md`.

  The API follows the draft `Table.Game` contract (#78), as `Hearts.Game` does:

  - `new(opts, seed)` deals 25 words and a key.
  - `legal_actions(game, seat)` lists the actions of a seat.
  - `apply(game, seat, action)` returns `{:ok, game} | {:error, reason}`.
  - `status(game)` is `{:playing, seats_to_act} | {:over, result}`.
  - `view(game, seat | :spectator)` is what one seat may see.

  ## Actions

  - `{:clue, word, number}`: the clue giver gives a clue (§3). `legal_actions/2`
    cannot list every word, so for a clue giver it gives the one template
    `{:clue, :word, 0..9}`; check a word with `CodenamesDuet.Clue.check/3` or
    `visible_words/1`.
  - `{:guess, index}`: touch word `index` (0..24, row by row) (§4, §6.3).
  - `:end_turn`: the guesser stops after one or more guesses (§4.6).

  Randomness (the words and the key) uses only the `:rand` state in `game.rng`.

      iex> {:ok, game} = CodenamesDuet.Game.new(%{}, {1, 2, 3})
      iex> CodenamesDuet.Game.status(game)
      {:playing, [0, 1]}
      iex> length(game.words)
      25
  """

  alias CodenamesDuet.{Clue, Key, Words}
  alias Table.Kit.Rng

  @defaults %{timer: 9}
  @seats [0, 1]
  @greens 15

  @type seat :: 0 | 1
  @type index :: 0..24
  @type action :: {:clue, String.t(), non_neg_integer} | {:guess, index} | :end_turn
  @type phase :: :clue | :guess | :sudden_death | :over

  @typedoc """
  One entry of `game.log` (newest first). No event holds a key colour that is not
  public on the table.

  - `{:setup, words, timer}`: the 25 words and the tokens in the time bank.
  - `{:clue, giver, word, number}`
  - `{:guess, guesser, index, :green | :neutral | :assassin}`: the colour on the
    side that decides the guess (§4.1, §6.3); the table marks it, so it is public.
  - `{:side_done, seat}`: all green words of `seat`'s side are found (§2.4).
  - `{:turn_end, guesser, :neutral | :stopped | :side_done, timer_left}` (§5.1).
  - `{:sudden_death, guessers}` (§6.3).
  - `{:game_over, :won | :lost, :all_found | :assassin | :sudden_death}`.
  """
  @type event :: tuple()

  @type t :: %__MODULE__{
          options: map(),
          seed: {integer, integer, integer},
          rng: :rand.state(),
          seats: [seat],
          words: [String.t()],
          key: Key.t(),
          phase: phase,
          timer: non_neg_integer,
          giver: seat | nil,
          clue: {String.t(), non_neg_integer} | nil,
          guesses: non_neg_integer,
          turn: non_neg_integer,
          agents: %{index => seat},
          bystanders: %{index => [seat]},
          done: [seat],
          stops: non_neg_integer,
          sudden_death: boolean,
          result: :won | :lost | nil,
          reason: atom | nil,
          log: [event]
        }

  defstruct [
    :options,
    :seed,
    :rng,
    :giver,
    :clue,
    :result,
    :reason,
    seats: @seats,
    words: [],
    key: %{},
    phase: :clue,
    timer: 9,
    guesses: 0,
    turn: 0,
    agents: %{},
    bystanders: %{},
    done: [],
    stops: 0,
    sudden_death: false,
    log: []
  ]

  @doc "The default options (rulebook §8)."
  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc """
  A new game: 25 random words (§1.2) and a random key (§1.4). `opts` is a map or
  keyword list of the options in `defaults/0`; `seed` is a `{int, int, int}` tuple.
  """
  @spec new(map() | keyword(), {integer, integer, integer}) :: {:ok, t} | {:error, term}
  def new(opts \\ %{}, seed)

  def new(opts, seed) when is_list(opts), do: new(Map.new(opts), seed)

  def new(opts, {a, b, c} = seed)
      when is_map(opts) and is_integer(a) and is_integer(b) and is_integer(c) do
    with {:ok, options} <- validate(opts) do
      rng = Rng.seed(seed)
      {words, rng} = Rng.shuffle(Words.all(), rng)
      words = Enum.take(words, 25)
      {key, rng} = Key.deal(rng)

      game = %__MODULE__{
        options: options,
        seed: seed,
        rng: rng,
        words: words,
        key: key,
        timer: options.timer
      }

      {:ok, log(game, {:setup, words, options.timer})}
    end
  end

  def new(_opts, seed), do: {:error, {:invalid_seed, seed}}

  defp validate(opts) do
    Enum.reduce_while(opts, {:ok, @defaults}, fn {key, value}, {:ok, acc} ->
      cond do
        not Map.has_key?(@defaults, key) -> {:halt, {:error, {:unknown_option, key}}}
        valid_option?(key, value) -> {:cont, {:ok, Map.put(acc, key, value)}}
        true -> {:halt, {:error, {:invalid_option, key, value}}}
      end
    end)
  end

  defp valid_option?(:timer, n), do: is_integer(n) and n in 1..11

  # -- Queries ----------------------------------------------------------------

  @doc "The other seat."
  @spec partner(seat) :: seat
  def partner(seat) when seat in @seats, do: 1 - seat

  @doc """
  `{:playing, seats}` with the seats that can act now, or `{:over, result}` with
  `result`, `reason`, `timer` and `score` (nil unless won, §6.4).
  """
  @spec status(t) :: {:playing, [seat]} | {:over, map()}
  def status(%__MODULE__{phase: :over} = game),
    do:
      {:over, %{result: game.result, reason: game.reason, timer: game.timer, score: score(game)}}

  def status(%__MODULE__{phase: :clue} = game), do: {:playing, clue_givers(game)}
  def status(%__MODULE__{phase: :guess, giver: giver}), do: {:playing, [partner(giver)]}
  def status(%__MODULE__{phase: :sudden_death} = game), do: {:playing, guessers(game)}

  @doc "True when the game has ended."
  @spec over?(t) :: boolean
  def over?(%__MODULE__{phase: phase}), do: phase == :over

  @doc """
  The seats that can give the next clue: both at the start (§2.1), else the seat
  whose turn it is (§2.3), never a seat whose side is done (§2.4).
  """
  @spec clue_givers(t) :: [seat]
  def clue_givers(%__MODULE__{phase: :clue, giver: nil} = game), do: @seats -- game.done
  def clue_givers(%__MODULE__{phase: :clue, giver: giver}), do: [giver]
  def clue_givers(%__MODULE__{}), do: []

  @doc "In sudden death: the seats that still have words to guess (§6.3)."
  @spec guessers(t) :: [seat]
  def guessers(%__MODULE__{} = game),
    do: Enum.filter(@seats, &(greens_left(game, partner(&1)) > 0))

  @doc "The number of green words on `side` that are not found yet."
  @spec greens_left(t, seat) :: non_neg_integer
  def greens_left(%__MODULE__{} = game, side) do
    game.key[side] |> Key.indexes(:green) |> Enum.count(&(not Map.has_key?(game.agents, &1)))
  end

  @doc "The number of green words found (of 15)."
  @spec found(t) :: non_neg_integer
  def found(%__MODULE__{agents: agents}), do: map_size(agents)

  @doc """
  The words that are still visible for clues (§3.2): not covered by an agent and
  not marked as a bystander from both sides.
  """
  @spec visible_words(t) :: [String.t()]
  def visible_words(%__MODULE__{} = game) do
    for {word, i} <- Enum.with_index(game.words), not covered?(game, i), do: word
  end

  defp covered?(game, i),
    do: Map.has_key?(game.agents, i) or length(Map.get(game.bystanders, i, [])) == 2

  @doc """
  True when a guess of word `i` is still open on `side` (the side that decides the
  guess): not an agent, and not marked as a bystander from `side` (§4.5).
  """
  @spec guessable?(t, index, seat) :: boolean
  def guessable?(%__MODULE__{} = game, i, side) do
    is_integer(i) and i in 0..24 and not Map.has_key?(game.agents, i) and
      side not in Map.get(game.bystanders, i, [])
  end

  defp guessable(game, side), do: Enum.filter(0..24, &guessable?(game, &1, side))

  @doc """
  The actions `seat` can take now (see the module doc). A clue giver gets the
  template `{:clue, :word, 0..9}`.
  """
  @spec legal_actions(t, seat | :spectator) :: [action | {:clue, :word, Range.t()}]
  def legal_actions(%__MODULE__{phase: :clue} = game, seat) do
    if seat in clue_givers(game), do: [{:clue, :word, 0..Clue.max_number()}], else: []
  end

  def legal_actions(%__MODULE__{phase: :guess, giver: giver} = game, seat) do
    if seat == partner(giver) do
      guesses = game |> guessable(giver) |> Enum.map(&{:guess, &1})
      if game.guesses > 0, do: guesses ++ [:end_turn], else: guesses
    else
      []
    end
  end

  def legal_actions(%__MODULE__{phase: :sudden_death} = game, seat) do
    if seat in guessers(game),
      do: game |> guessable(partner(seat)) |> Enum.map(&{:guess, &1}),
      else: []
  end

  def legal_actions(%__MODULE__{}, _seat), do: []

  @doc """
  The score of a won game (§6.4), else nil: 3 per token left after the winning
  turn, 1 per stop after a correct guess, −1 for sudden death.
  """
  @spec score(t) :: integer | nil
  def score(%__MODULE__{result: :won} = game) do
    3 * max(game.timer - 1, 0) + game.stops - if(game.sudden_death, do: 1, else: 0)
  end

  def score(%__MODULE__{}), do: nil

  @doc """
  What `seat` may see (or `:spectator`): the words, its own side of the key (§1.6),
  the marks on the table, the timer, the clue and the log. The other side of the
  key shows only when the game is over (`revealed_key`).
  """
  @spec view(t, seat | :spectator) :: map()
  def view(%__MODULE__{} = game, viewer) do
    {_, acting} = status(game)

    %{
      viewer: viewer,
      phase: game.phase,
      options: game.options,
      seats: game.seats,
      words: game.words,
      key: Map.get(game.key, viewer),
      greens_left: if(viewer in @seats, do: greens_left(game, viewer)),
      revealed_key: if(game.phase == :over, do: game.key),
      agents: game.agents,
      bystanders: game.bystanders,
      found: found(game),
      timer: game.timer,
      turn: game.turn,
      giver: game.giver,
      clue: game.clue,
      guesses: game.guesses,
      done: game.done,
      acting: if(is_list(acting), do: acting, else: []),
      sudden_death: game.sudden_death,
      result: game.result,
      reason: game.reason,
      score: score(game),
      legal_actions: legal_actions(game, viewer),
      log: game.log
    }
  end

  # -- Actions ----------------------------------------------------------------

  @doc """
  Applies `action` for `seat`. Returns `{:ok, game}` or `{:error, reason}`; on an
  error nothing changes.
  """
  @spec apply(t, seat, action) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{phase: :over}, _seat, _action), do: {:error, :game_over}

  def apply(%__MODULE__{} = game, seat, action) do
    if seat in @seats, do: do_apply(game, seat, action), else: {:error, :unknown_seat}
  end

  defp do_apply(%__MODULE__{phase: :clue} = game, seat, {:clue, word, number}) do
    with true <- seat in clue_givers(game) || {:error, :not_your_turn},
         :ok <- Clue.check(word, number, visible_words(game)) do
      {:ok, give_clue(game, seat, Clue.normalize(word), number)}
    else
      {:error, :not_your_turn} -> {:error, :not_your_turn}
      {:error, reason} -> {:error, {:invalid_clue, reason}}
    end
  end

  defp do_apply(%__MODULE__{phase: :guess, giver: giver} = game, seat, {:guess, i}) do
    cond do
      seat != partner(giver) -> {:error, :not_your_turn}
      not guessable?(game, i, giver) -> {:error, :not_guessable}
      true -> {:ok, guess(game, seat, i)}
    end
  end

  defp do_apply(%__MODULE__{phase: :guess, giver: giver} = game, seat, :end_turn) do
    cond do
      seat != partner(giver) -> {:error, :not_your_turn}
      game.guesses == 0 -> {:error, :must_guess}
      true -> {:ok, end_turn(game, :stopped)}
    end
  end

  defp do_apply(%__MODULE__{phase: :sudden_death} = game, seat, {:guess, i}) do
    cond do
      seat not in guessers(game) -> {:error, :not_your_turn}
      not guessable?(game, i, partner(seat)) -> {:error, :not_guessable}
      true -> {:ok, sudden_death_guess(game, seat, i)}
    end
  end

  defp do_apply(_game, _seat, _action), do: {:error, :invalid_action}

  defp give_clue(game, seat, word, number) do
    %{game | phase: :guess, giver: seat, clue: {word, number}, guesses: 0, turn: game.turn + 1}
    |> log({:clue, seat, word, number})
  end

  defp guess(%__MODULE__{giver: giver} = game, seat, i) do
    color = Enum.at(game.key[giver], i)
    game = %{game | guesses: game.guesses + 1} |> log({:guess, seat, i, color})

    case color do
      :green -> game |> find(seat, i) |> after_find()
      :neutral -> game |> mark(i, giver) |> end_turn(:neutral)
      :assassin -> finish(game, :lost, :assassin)
    end
  end

  defp after_find(%__MODULE__{phase: :over} = game), do: game

  defp after_find(%__MODULE__{giver: giver} = game) do
    if giver in game.done, do: end_turn(game, :side_done), else: game
  end

  defp sudden_death_guess(game, seat, i) do
    color = Enum.at(game.key[partner(seat)], i)
    game = log(game, {:guess, seat, i, color})

    case color do
      :green -> find(game, seat, i)
      _ -> finish(game, :lost, :sudden_death)
    end
  end

  # Covers word `i` with an agent (§4.2), logs the sides that are now done (§2.4)
  # and ends the game when all 15 are found (§6.1).
  defp find(game, seat, i) do
    game = %{game | agents: Map.put(game.agents, i, seat)}

    game =
      Enum.reduce(@seats, game, fn side, game ->
        if side not in game.done and greens_left(game, side) == 0,
          do: %{game | done: game.done ++ [side]} |> log({:side_done, side}),
          else: game
      end)

    if found(game) == @greens, do: finish(game, :won, :all_found), else: game
  end

  defp mark(game, i, side),
    do: %{game | bystanders: Map.update(game.bystanders, i, [side], &Enum.sort([side | &1]))}

  # Ends the turn and uses one timer token (§5.1): the next clue giver is the
  # guesser, unless the guesser's side is done (§2.3, §2.4); no token left starts
  # the sudden death (§6.3).
  defp end_turn(%__MODULE__{giver: giver} = game, how) do
    guesser = partner(giver)
    stops = if how == :neutral, do: game.stops, else: game.stops + 1
    timer = game.timer - 1

    game =
      %{game | timer: timer, stops: stops, clue: nil, guesses: 0}
      |> log({:turn_end, guesser, how, timer})

    cond do
      timer == 0 ->
        %{game | phase: :sudden_death, sudden_death: true, giver: nil}
        |> then(&log(&1, {:sudden_death, guessers(&1)}))

      guesser in game.done ->
        %{game | phase: :clue}

      true ->
        %{game | phase: :clue, giver: guesser}
    end
  end

  defp finish(game, result, reason) do
    %{game | phase: :over, result: result, reason: reason}
    |> log({:game_over, result, reason})
  end

  defp log(game, event), do: %{game | log: [event | game.log]}
end
