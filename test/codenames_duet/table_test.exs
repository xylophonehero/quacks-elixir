defmodule CodenamesDuet.TableTest do
  @moduledoc """
  `CodenamesDuet.Table` as a `Table.Server` adapter. The game is not in the
  lobby yet (no board), so the room test adds it to the games config for a moment:
  not async.
  """
  use ExUnit.Case, async: false

  alias CodenamesDuet.{Game, Table}
  alias Elixir.Table.Server, as: Room

  @key "codenames_duet_test"

  setup do
    old = Application.fetch_env!(:quacks, Elixir.Table)
    games = Map.put(old[:games], @key, %{name: "Duet", game: Table})
    Application.put_env(:quacks, Elixir.Table, Keyword.put(old, :games, games))
    on_exit(fn -> Application.put_env(:quacks, Elixir.Table, old) end)
  end

  test "the callbacks go to the engine; one bot level: vectors" do
    {:ok, game} = Table.new(%{}, {1, 2, 3})
    assert Table.seats(game) == [0, 1]
    assert Table.status(game) == Game.status(game)
    assert Table.legal_actions(game, 0) == Game.legal_actions(game, 0)
    assert Table.view(game, 1) == Game.view(game, 1)
    assert {:ok, _} = Table.apply(game, 0, {:clue, "quokka", 1})
    assert Table.bot_levels() == [:vectors]
  end

  @tag rule: "§1.1"
  test "a room for two people: no bot seat, each seat its own view" do
    host = "host-#{System.unique_integer()}"

    assert {:error, :invalid_level} =
             Room.create(@key, %{opts: %{}, bots: 1, level: :random}, host)

    assert {:error, :invalid_bots} = Room.create(@key, %{opts: %{}, bots: 2}, host)
    assert {:ok, code} = Room.create(@key, %{opts: %{}, bots: 0, name: "Nick"}, host)

    assert {:ok, %{seat: 0, view: host_view}} = Room.join(@key, code, host)
    assert {:ok, %{seat: 1, view: guest_view}} = Room.join(@key, code, "guest")
    refute host_view.view.key == guest_view.view.key
    assert host_view.status == {:playing, [0, 1]}
  end

  test "a room with a bot partner: seat 1 is the bot, and it gives the first clue" do
    host = "host-#{System.unique_integer()}"
    assert {:ok, code} = Room.create(@key, %{opts: %{}, bots: 1, level: :vectors}, host)
    assert {:ok, %{seat: 0, seats: seats}} = Room.join(@key, code, host)
    assert %{bot: true, open: false} = seats[1]
    assert {:ok, %{seat: :spectator}} = Room.join(@key, code, "guest")

    game = await(code, :guess, 1)
    assert {:clue, 1, _word, n} = Enum.find(Enum.reverse(game.log), &match?({:clue, _, _, _}, &1))
    assert n >= 1
    assert game.phase == :guess
  end

  @tag rule: "§4.6"
  test "the bot guesses the human's clue, then gives its own" do
    host = "host-#{System.unique_integer()}"
    {:ok, code} = Room.create(@key, %{opts: %{}, bots: 1, level: :vectors}, host)
    [{pid, _}] = Registry.lookup(Elixir.Table.Registry, {@key, code})
    game = CodenamesDuet.Scenario.fixed() |> CodenamesDuet.Scenario.clue(0, "tennis", 1)
    :sys.replace_state(pid, &%{&1 | game: game})
    send(pid, :tick)

    # Index 6 is "golf", green on seat 0's side. Then the bot gives a clue.
    game = await(code, :guess, 1)
    assert {:guess, 1, 6, :green} in game.log
    assert Enum.count(game.log, &match?({:clue, 1, _, _}, &1)) == 1
  end

  # Waits until seat 0's view is `phase` with `giver` (the bot ticks at 0 ms in
  # tests, but a timer message can come a little later), then gives the game.
  defp await(code, phase, giver) do
    Phoenix.PubSub.subscribe(Quacks.PubSub, Room.seat_topic(@key, code, 0))
    game = Room.state(@key, code).game
    unless game.phase == phase and game.giver == giver, do: wait_view(phase, giver)
    Room.state(@key, code).game
  end

  defp wait_view(phase, giver) do
    receive do
      {:table_view, %{view: %{phase: ^phase, giver: ^giver}}} -> :ok
      {:table_view, _} -> wait_view(phase, giver)
    after
      2000 -> flunk("no view in #{phase} with giver #{giver}")
    end
  end
end
