defmodule Quacks.BundleTest do
  @moduledoc "A session's bug-report bundle survives JSON (`Quacks.Session.bundle/1`)."
  use ExUnit.Case, async: true

  alias Quacks.{AI, Game, Session}
  alias Quacks.AI.Profile

  # Bots play every seat of `session` for up to `steps` actions.
  def play(session, steps) do
    profile = Profile.get(:balanced)
    rngs = Map.new(session.game.seats, &{&1, AI.new_rng(session.seed, &1)})

    Enum.reduce_while(1..steps, {session, rngs}, fn _, {s, rngs} ->
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

  # A stopped seat may only resume: the bot says `:none`.
  defp decision(game, seat, profile, rng) do
    with [_ | _] <- Game.legal_actions(game, seat),
         {action, rng} <- AI.decide(game, seat, profile, rng),
         do: {seat, action, rng},
         else: (_none -> nil)
  end

  defp round_trip(bundle), do: bundle |> Jason.encode!() |> Jason.decode!()

  test "a whole game with both expansions round-trips through JSON" do
    session =
      Session.new({7, 8, 9}, 3,
        sets: %{green: 2, locoweed: 1},
        rules: %{pot_side: :back, explode_above: 8},
        expansions: [:herb_witches, :alchemists]
      )
      |> play(5000)

    assert Game.over?(session.game)
    {:ok, rebuilt} = session |> Session.bundle() |> round_trip() |> Session.from_bundle()
    assert rebuilt.game == session.game
    assert rebuilt.actions == session.actions
    assert rebuilt.rules == session.rules and rebuilt.sets == session.sets
  end

  test "from_bundle at N is the replay of the first N actions" do
    session = Session.new({1, 2, 3}, 2) |> play(150)
    {:ok, at} = session |> Session.bundle() |> round_trip() |> Session.from_bundle(40)
    first = session.actions |> Enum.reverse() |> Enum.take(40) |> Enum.reverse()
    assert at.actions == first
    assert at.game == Session.replay({1, 2, 3}, 2, first)
  end

  test "a bundle with an unknown atom or an illegal action is refused" do
    bundle = Session.new({1, 2, 3}) |> Session.bundle() |> round_trip()

    assert {:error, :invalid} =
             Session.from_bundle(%{bundle | "log" => [[0, "no_such_atom_xyz"]]})

    assert {:error, :invalid} = Session.from_bundle(%{bundle | "log" => [[0, "end_round"]]})
    assert {:error, :invalid} = Session.from_bundle(%{"version" => 2})
  end
end
