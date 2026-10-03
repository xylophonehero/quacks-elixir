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
            actions: [],
            game: nil

  @type t :: %__MODULE__{
          seed: {integer, integer, integer},
          players: 1..8,
          sets: Quacks.Rules.Chips.sets(),
          rules: Game.rules(),
          expansion: nil | :herb_witches,
          expansions: MapSet.t(Game.expansion()),
          actions: [{Game.seat(), Game.action()}],
          game: Game.t()
        }

  # The `Game.new/1` options a session passes on.
  @game_opts [:sets, :rules, :fortune, :expansion, :expansions]

  @doc """
  A new session. `opts`: `sets: %{green: 2}` picks Ingredient Sets, `rules:
  %{explode_above: 9}` sets house rules, `fortune: false` plays without Fortune
  Teller cards, `expansions: [:herb_witches, :alchemists]` turns expansions on
  (`expansion: :herb_witches` is the old alias; see `Quacks.Game.new/1`).
  """
  @spec new({integer, integer, integer}, 1..8,
          sets: map,
          rules: map,
          fortune: boolean,
          expansion: nil | :herb_witches,
          expansions: Enumerable.t(Game.expansion())
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
          replay(s.seed, s.players, rest, sets: s.sets, rules: s.rules, expansions: s.expansions)
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

  defp new_game(seed, players, opts),
    do: Game.new([seed: seed, players: players] ++ Keyword.take(opts, @game_opts))
end
