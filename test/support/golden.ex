defmodule Quacks.Golden do
  @moduledoc """
  Helpers for the golden tests (`Quacks.GoldenRngTest`, `Quacks.GoldenBundlesTest`):
  bots play a `Quacks.Session` to its end, a stable hash of a term, and the record
  switch. With `GOLDEN_RECORD=1` a golden test writes its fixture again from today's
  code; without it, it compares with the committed fixture.
  """

  alias Quacks.{AI, Game, Session}
  alias Quacks.AI.Profile

  @doc "True when the golden fixtures are written again (`GOLDEN_RECORD=1`)."
  def record?, do: System.get_env("GOLDEN_RECORD") not in [nil, "", "0"]

  @doc """
  Load every module of the app. `Quacks.Session.from_bundle/1` reads a bundle's
  atoms with `String.to_existing_atom/1`; in a fresh test VM (modules load lazily)
  an action atom such as `:chip_done` may not exist yet, and a valid bundle gives
  `{:error, :invalid}`. A release loads every module at boot, so it has them.
  """
  def load_atoms do
    {:ok, modules} = :application.get_key(:quacks, :modules)
    Enum.each(modules, &Code.ensure_loaded!/1)
  end

  @doc "Write `term` as a formatted Elixir term to `path` (for `Code.eval_file/1`)."
  def write_term!(path, term) do
    File.mkdir_p!(Path.dirname(path))
    text = inspect(term, limit: :infinity, printable_limit: :infinity)
    File.write!(path, [Code.format_string!(text), "\n"])
  end

  @doc "The term in `path` (written by `write_term!/2`)."
  def read_term!(path), do: path |> Code.eval_file() |> elem(0)

  @doc "A SHA-256 hash (hex) of a term, the same on every run."
  def hash(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Bots (`profile`, default `:balanced`) play every seat of `session` to the end. Each
  seat has its own rng (`AI.new_rng/2` of the session's seed); the seats act in seat
  order, the first seat with a legal action each step.
  """
  def play(%Session{} = session, profile \\ :balanced) do
    profile = Profile.get(profile)
    rngs = Map.new(session.game.seats, &{&1, AI.new_rng(session.seed, &1)})

    Enum.reduce_while(1..20_000, {session, rngs}, fn _, {s, rngs} ->
      next = Enum.find_value(s.game.seats, &decision(s.game, &1, profile, rngs[&1]))

      with {seat, action, rng} <- next,
           {:ok, s} <- Session.apply(s, seat, action) do
        {:cont, {s, Map.put(rngs, seat, rng)}}
      else
        _over -> {:halt, {s, rngs}}
      end
    end)
    |> elem(0)
  end

  defp decision(game, seat, profile, rng) do
    with [_ | _] <- Game.legal_actions(game, seat),
         {action, rng} <- AI.decide(game, seat, profile, rng),
         do: {seat, action, rng},
         else: (_none -> nil)
  end
end
