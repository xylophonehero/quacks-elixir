defmodule Quacks.Session do
  @moduledoc """
  A game plus the `{seed, players, sets, rules, expansions, [{seat, action}]}` that built
  it. Undo = replay minus the last action, whichever seat made it.
  """

  import Kernel, except: [apply: 2, apply: 3]
  alias Quacks.Game

  defstruct seed: nil,
            players: 1,
            sets: %{},
            rules: %{},
            expansion: nil,
            expansions: MapSet.new(),
            witches: %{},
            actions: [],
            game: nil

  @type t :: %__MODULE__{
          seed: {integer, integer, integer},
          players: 1..8,
          sets: Quacks.Rules.Chips.sets(),
          rules: Game.rules(),
          expansion: nil | :herb_witches,
          expansions: MapSet.t(Game.expansion()),
          witches: %{optional(atom) => atom},
          actions: [{Game.seat(), Game.action()}],
          game: Game.t()
        }

  # The `Game.new/1` options a session passes on.
  @game_opts [:sets, :rules, :fortune, :expansion, :expansions, :witches]

  @doc """
  A new session. `opts`: `sets: %{green: 2}` picks Ingredient Sets, `rules:
  %{explode_above: 9}` sets house rules, `fortune: false` plays without Fortune
  Teller cards, `expansions: [:herb_witches, :alchemists]` turns expansions on
  (`expansion: :herb_witches` is the old alias; see `Quacks.Game.new/1`),
  `witches: %{copper: :c3}` picks herb witches (the rest are dealt).
  """
  @spec new({integer, integer, integer}, 1..8,
          sets: map,
          rules: map,
          fortune: boolean,
          expansion: nil | :herb_witches,
          expansions: Enumerable.t(Game.expansion()),
          witches: map | nil
        ) :: t
  def new(seed, players \\ 1, opts \\ []) do
    game = new_game(seed, players, opts)

    %__MODULE__{
      seed: seed,
      players: players,
      sets: game.sets,
      rules: game.rules,
      expansion: game.expansion,
      expansions: game.expansions,
      witches: picks(opts[:witches]),
      game: game
    }
  end

  @doc "`apply/3` for seat 0."
  @spec apply(t, Game.action()) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{} = s, action), do: apply(s, 0, action)

  @spec apply(t, Game.seat(), Game.action()) :: {:ok, t} | {:error, term}
  def apply(%__MODULE__{} = s, seat, action) do
    with {:ok, game} <- Game.apply(s.game, seat, action),
         do: {:ok, %{s | game: game, actions: [{seat, action} | s.actions]}}
  end

  @spec undo(t) :: t
  def undo(%__MODULE__{actions: []} = s), do: s

  def undo(%__MODULE__{actions: [_ | rest]} = s),
    do: %{
      s
      | actions: rest,
        game:
          replay(s.seed, s.players, rest,
            sets: s.sets,
            rules: s.rules,
            expansions: s.expansions,
            witches: s.witches
          )
    }

  @doc "Rebuild a game from its actions (newest first). `opts` as in `new/3`."
  @spec replay({integer, integer, integer}, 1..8, [{Game.seat(), Game.action()}], keyword) ::
          Game.t()
  def replay(seed, players, actions, opts \\ []) do
    Enum.reduce(Enum.reverse(actions), new_game(seed, players, opts), fn {seat, action}, game ->
      {:ok, game} = Game.apply(game, seat, action)
      game
    end)
  end

  @doc """
  The session as plain, JSON-ready data, for a bug report: `%{version: 1, seed,
  players, opts: %{sets, rules, expansions, witches}, log}` (`witches`: the picked
  herb witches, `%{"copper" => "c3"}`; older bundles have none). `log` holds `[seat, action]`
  pairs, oldest first. An action is encoded as JSON like this: an atom is a
  string, a tuple is an array, a list is `{"l": [...]}`, a map is `{"m": [[k,
  v], ...]}` and a string is `{"s": "..."}`. `from_bundle/2` reads it back.
  """
  @spec bundle(t) :: map
  def bundle(%__MODULE__{} = s) do
    %{
      version: 1,
      seed: Tuple.to_list(s.seed),
      players: s.players,
      opts: %{
        sets: encode_map(s.sets),
        rules: encode_map(s.rules),
        expansions: s.expansions |> Enum.sort() |> Enum.map(&Atom.to_string/1),
        witches: encode_map(s.witches)
      },
      log:
        s.actions |> Enum.reverse() |> Enum.map(fn {seat, action} -> [seat, encode(action)] end)
    }
  end

  @doc """
  The session a `bundle/1` describes, with atom or string keys (decoded JSON).
  `at` replays only the first `at` actions of its log (nil: all). An unknown
  atom, an illegal action or a bad shape gives `{:error, :invalid}`.
  """
  @spec from_bundle(map, non_neg_integer | nil) :: {:ok, t} | {:error, :invalid}
  def from_bundle(bundle, at \\ nil) do
    %{"version" => 1, "seed" => [_, _, _] = seed, "players" => players, "opts" => opts} =
      b = bundle |> Jason.encode!() |> Jason.decode!()

    log = if at, do: Enum.take(b["log"], at), else: b["log"]
    actions = Enum.reduce(log, [], fn [seat, action], acc -> [{seat, decode(action)} | acc] end)

    game_opts = [
      sets: decode_map(opts["sets"]),
      rules: decode_map(opts["rules"]),
      expansions: Enum.map(opts["expansions"], &String.to_existing_atom/1),
      witches: decode_map(opts["witches"] || %{})
    ]

    s = new(List.to_tuple(seed), players, game_opts)
    game = replay(s.seed, players, actions, game_opts)
    {:ok, %{s | actions: actions, game: game}}
  rescue
    _error in [MatchError, ArgumentError, FunctionClauseError, CaseClauseError, KeyError] ->
      {:error, :invalid}
  end

  defp encode(atom) when is_atom(atom) and atom not in [nil, true, false],
    do: Atom.to_string(atom)

  defp encode(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&encode/1)
  defp encode(list) when is_list(list), do: %{l: Enum.map(list, &encode/1)}
  defp encode(%MapSet{} = set), do: %{l: set |> Enum.sort() |> Enum.map(&encode/1)}

  defp encode(map) when is_map(map),
    do: %{m: map |> Enum.sort() |> Enum.map(fn {k, v} -> [encode(k), encode(v)] end)}

  defp encode(string) when is_binary(string), do: %{s: string}
  defp encode(term), do: term

  defp decode(string) when is_binary(string), do: String.to_existing_atom(string)
  defp decode(list) when is_list(list), do: list |> Enum.map(&decode/1) |> List.to_tuple()
  defp decode(%{"l" => list}), do: Enum.map(list, &decode/1)
  defp decode(%{"m" => pairs}), do: Map.new(pairs, fn [k, v] -> {decode(k), decode(v)} end)
  defp decode(%{"s" => string}), do: string
  defp decode(term), do: term

  # Sets and rules: a JSON object with atom keys as strings.
  defp encode_map(map), do: Map.new(map, fn {key, value} -> {key, encode(value)} end)

  defp decode_map(map),
    do: Map.new(map, fn {key, value} -> {String.to_existing_atom(key), decode(value)} end)

  # Only the colours picked (nil: dealt), so a bundle names only real picks.
  defp picks(nil), do: %{}
  defp picks(witches), do: for({colour, id} <- witches, id != nil, into: %{}, do: {colour, id})

  defp new_game(seed, players, opts),
    do: Game.new([seed: seed, players: players] ++ Keyword.take(opts, @game_opts))
end
