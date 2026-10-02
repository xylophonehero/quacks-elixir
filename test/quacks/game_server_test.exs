defmodule Quacks.GameServerTest do
  use ExUnit.Case, async: true

  alias Quacks.{Game, GameServer}

  # A process that subscribes to the game and forwards everything to the test.
  defp listener(id) do
    test = self()

    pid =
      spawn_link(fn ->
        Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))
        send(test, {:subscribed, self()})
        forward(test)
      end)

    assert_receive {:subscribed, ^pid}
    pid
  end

  defp forward(test) do
    receive do
      msg -> send(test, {:forwarded, self(), msg}) && forward(test)
    end
  end

  test "start gives a 6-letter id and the game behind it" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    assert id =~ ~r/^[a-z]{6}$/
    {:ok, table} = GameServer.get(id)
    assert table.players == 2
    assert table.seed == {1, 2, 3}
    assert table.game == Game.new(seed: {1, 2, 3}, players: 2)
    assert table.names == %{}
  end

  test "an unknown id is :not_found" do
    assert GameServer.get("nosuch") == {:error, :not_found}
    assert GameServer.apply("nosuch", 0, :draw) == {:error, :not_found}
  end

  test "seats fill in join order; a known token keeps its seat; then the game is full" do
    {:ok, id} = GameServer.start(2)
    assert GameServer.claim_seat(id, "a") == {:ok, 0}
    assert GameServer.claim_seat(id, "b") == {:ok, 1}
    assert GameServer.claim_seat(id, "a") == {:ok, 0}
    assert GameServer.claim_seat(id, "c") == {:error, :full}
    assert {:ok, %{names: %{0 => "Seat 1", 1 => "Seat 2"}}} = GameServer.get(id)
  end

  test "apply broadcasts the new game to every subscriber" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    one = listener(id)
    two = listener(id)

    assert {:ok, game} = GameServer.apply(id, 1, :draw)
    assert length(game.players[1].drawn) == 1
    assert_receive {:forwarded, ^one, {:game, ^id, ^game}}
    assert_receive {:forwarded, ^two, {:game, ^id, ^game}}

    assert {:error, {:illegal_action, :end_round, :potions}} =
             GameServer.apply(id, 0, :end_round)

    refute_receive {:forwarded, _, {:game, _, _}}
  end

  test "claiming a seat and renaming broadcast the names" do
    {:ok, id} = GameServer.start(2)
    one = listener(id)
    {:ok, 0} = GameServer.claim_seat(id, "a")
    assert_receive {:forwarded, ^one, {:names, ^id, %{0 => "Seat 1"}}}

    :ok = GameServer.rename(id, 0, "  Nick  ")
    assert_receive {:forwarded, ^one, {:names, ^id, %{0 => "Nick"}}}

    :ok = GameServer.rename(id, 0, "   ")
    assert_receive {:forwarded, ^one, {:names, ^id, %{0 => "Seat 1"}}}
  end

  test "undo works in solo only" do
    {:ok, solo} = GameServer.start(1, {1, 2, 3})
    {:ok, _} = GameServer.apply(solo, 0, :draw)
    assert {:ok, game} = GameServer.undo(solo)
    assert game == Game.new(seed: {1, 2, 3}, players: 1)

    {:ok, duo} = GameServer.start(2, {1, 2, 3})
    {:ok, _} = GameServer.apply(duo, 0, :draw)
    assert GameServer.undo(duo) == {:error, :not_solo}
  end

  test "open games are the ones with a free seat" do
    {:ok, open} = GameServer.start(2)
    {:ok, full} = GameServer.start(1)
    {:ok, 0} = GameServer.claim_seat(full, "a")

    ids = Enum.map(GameServer.open_games(), & &1.id)
    assert open in ids
    refute full in ids
  end

  test "an idle game stops on the timeout" do
    {:ok, id} = GameServer.start(1)
    [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)
    ref = Process.monitor(pid)
    send(pid, :timeout)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert GameServer.get(id) == {:error, :not_found}
  end
end
