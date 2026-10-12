defmodule Quacks.Scenarios.Script do
  @moduledoc """
  The driver of a scenario (`Quacks.Scenarios`): it plays a real `Quacks.Session` with
  `Quacks.Game.apply/3` and marks the steps on the way.

  Nothing is set by hand. The scenario finds what it needs by the seed: `search/2`
  tries seeds until the script reaches its goal (the card on top of the deck, the
  chip drawn, the witch called). So the log is a normal replay bundle: undo, seek and
  `/debug/replay` work on it.

  Seat 0 is "you"; the other seats are bots. Every seat plays with the real bot
  (`Quacks.AI`, balanced) unless the `me:` policy of `play/3` picks seat 0's action.
  """

  alias Quacks.{AI, Game, Session}
  alias Quacks.AI.Profile

  defstruct session: nil, rngs: %{}, games: %{}, steps: [], bots: []

  @typedoc """
  A step: `label` ("reveal", "resolve", ...), `at` (the number of log actions to
  replay), `note` (one line for the step bar), `check` (an engine assertion on the
  game at `at`: `true`, or a failure message), `sees` (CSS selectors the game page
  shows at that step) and `taps` (`{selector, sees}`: a tap on the page at that step
  and what the page shows after it, e.g. the card's tap).
  """
  @type step :: %{
          label: String.t(),
          at: non_neg_integer,
          note: String.t() | nil,
          check: (Game.t() -> true | String.t()),
          sees: [String.t()],
          taps: [{String.t(), [String.t()]}]
        }
  @type t :: %__MODULE__{
          session: Session.t(),
          rngs: %{Game.seat() => :rand.state()},
          games: %{non_neg_integer => Game.t()},
          steps: [step],
          bots: [Game.seat()]
        }

  @max_actions 3000

  @doc "A new script: `players` seats (seat 0 is you, the rest are bots); `opts` as `Session.new/3`."
  @spec new({integer, integer, integer}, 1..8, keyword) :: t
  def new(seed, players, opts \\ []) do
    session = Session.new(seed, players, opts)
    seats = session.game.seats

    %__MODULE__{
      session: session,
      rngs: Map.new(seats, &{&1, AI.new_rng(seed, &1)}),
      games: %{0 => session.game},
      bots: seats -- [0]
    }
  end

  @doc "The game now."
  @spec game(t) :: Game.t()
  def game(%__MODULE__{session: s}), do: s.game

  @doc "The game after `at` actions."
  @spec game_at(t, non_neg_integer) :: Game.t()
  def game_at(%__MODULE__{games: games}, at), do: Map.fetch!(games, at)

  @doc "The number of actions so far."
  @spec at(t) :: non_neg_integer
  def at(%__MODULE__{session: s}), do: length(s.actions)

  @doc "Apply one action. An illegal action throws `{:miss, reason}` (`search/2` tries the next seed)."
  @spec act(t, Game.seat(), Game.action()) :: t
  def act(%__MODULE__{} = s, seat, action) do
    case Session.apply(s.session, seat, action) do
      {:ok, session} ->
        %{s | session: session, games: Map.put(s.games, length(session.actions), session.game)}

      {:error, reason} ->
        throw({:miss, {:illegal, seat, action, reason}})
    end
  end

  @doc """
  Mark a step at the current action (or at `at:`). Options: `note:`, `check:` (a
  function of the game: `true`, `false` or a failure message), `sees:` (CSS
  selectors) and `taps:` (see `t:step/0`).
  """
  @spec mark(t, String.t(), keyword) :: t
  def mark(%__MODULE__{} = s, label, opts \\ []) do
    step = %{
      label: label,
      at: Keyword.get(opts, :at, at(s)),
      note: opts[:note],
      check: Keyword.get(opts, :check, fn _g -> true end),
      sees: Keyword.get(opts, :sees, []),
      taps: Keyword.get(opts, :taps, [])
    }

    %{s | steps: s.steps ++ [step]}
  end

  @doc """
  Play until `until` (a function of the game, or of the script with `script: true`)
  is true. Each turn the first seat (seat 0 first) with something to do acts. Seat
  0 uses `me` (a function of game and legal actions; nil leaves it to the bot); the
  other seats are bots, or follow `others` (same shape) when it gives an action.
  Throws `{:miss, reason}` when the game ends or stalls first.
  """
  @spec play(t, (Game.t() -> boolean), keyword) :: t
  def play(%__MODULE__{} = s, until, opts \\ []) do
    me = opts[:me] || fn _g, _legal -> nil end
    others = opts[:others] || fn _g, _seat, _legal -> nil end
    goal = if opts[:script], do: until, else: fn s -> until.(game(s)) end
    loop(s, goal, me, others, 0)
  end

  defp loop(s, goal, me, others, n) do
    g = game(s)

    cond do
      goal.(s) -> s
      n > @max_actions -> throw({:miss, :too_long})
      Game.over?(g) -> throw({:miss, :game_over})
      true -> s |> turn(g, me, others) |> loop(goal, me, others, n + 1)
    end
  end

  defp turn(s, g, me, others) do
    pick =
      Enum.find_value(g.seats, fn seat ->
        with [_ | _] = legal <- Game.legal_actions(g, seat),
             {action, rng} <- choose(s, g, seat, legal, me, others) do
          {seat, action, rng}
        else
          _none -> nil
        end
      end)

    case pick do
      nil -> throw({:miss, :stalled})
      {seat, action, rng} -> s |> act(seat, action) |> put_in([Access.key(:rngs), seat], rng)
    end
  end

  defp choose(s, g, 0, legal, me, _others) do
    case me.(g, legal) do
      nil -> bot(s, g, 0)
      action -> {action, s.rngs[0]}
    end
  end

  defp choose(s, g, seat, legal, _me, others) do
    case others.(g, seat, legal) do
      nil -> bot(s, g, seat)
      action -> {action, s.rngs[seat]}
    end
  end

  defp bot(s, g, seat) do
    case AI.decide(g, seat, Profile.get(:balanced), s.rngs[seat]) do
      :none -> nil
      {action, rng} -> {action, rng}
    end
  end

  @doc """
  Run `script` (a function of a seed that returns a script) for seeds `{n, 26, 10}`,
  `n` from 1, until one does not throw `{:miss, _}` and passes every step's check.
  `{:ok, script}`, or `{:error, {:no_seed, last_reason}}` after `tries` seeds; a
  failed check is `{:check, label, message}`.
  """
  @spec search((tuple -> t), pos_integer) :: {:ok, t} | {:error, term}
  def search(script, tries \\ 60) do
    Enum.reduce_while(1..tries, {:error, {:no_seed, nil}}, fn n, _acc ->
      try do
        s = script.({n, 26, 10})

        case failures(s) do
          [] -> {:halt, {:ok, s}}
          [{step, message} | _] -> {:cont, {:error, {:no_seed, {:check, step.label, message}}}}
        end
      catch
        {:miss, reason} -> {:cont, {:error, {:no_seed, reason}}}
      end
    end)
  end

  @doc "The replay bundle of the script (`Session.bundle/1` plus names, bots and seat 0)."
  @spec bundle(t) :: map
  def bundle(%__MODULE__{session: session, bots: bots}) do
    names =
      for seat <- 0..(session.players - 1), do: if(seat == 0, do: "You", else: "Bot #{seat}")

    Map.merge(Session.bundle(session), %{names: names, bots: bots, seat: 0})
  end

  @doc """
  The steps whose check fails, as `{step, message}`; empty when all pass.
  """
  @spec failures(t) :: [{step, String.t()}]
  def failures(%__MODULE__{steps: steps} = s) do
    for step <- steps, message = failure(step, game_at(s, step.at)), do: {step, message}
  end

  defp failure(step, game) do
    case step.check.(game) do
      true -> nil
      false -> "the check failed"
      message when is_binary(message) -> message
    end
  end
end
