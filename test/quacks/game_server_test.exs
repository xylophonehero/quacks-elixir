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

  # Open a game for `players`, seat `tokens` and begin it with the first one.
  defp begun(players, tokens, seed \\ {1, 2, 3}) do
    {:ok, id} = GameServer.start(players, seed)
    for token <- tokens, do: {:ok, _} = GameServer.claim_seat(id, token)
    if players > 1, do: {:ok, _game} = GameServer.begin(id, hd(tokens))
    id
  end

  test "start gives a 6-letter id and a waiting table without a game" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    assert id =~ ~r/^[a-z]{6}$/
    {:ok, table} = GameServer.get(id)
    assert {table.status, table.game, table.players, table.max_players} == {:waiting, nil, 2, 2}
    assert table.seed == {1, 2, 3}
    assert table.names == %{} and table.creator == nil
    assert GameServer.apply(id, 0, :draw) == {:error, :not_started}
    assert GameServer.undo(id) == {:error, :not_started}
  end

  test "begin with fewer players than the maximum; then no new seats" do
    {:ok, id} = GameServer.start(4, {1, 2, 3})
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.claim_seat(id, "b")
    {:ok, %{creator: 0}} = GameServer.get(id)

    assert {:ok, game} = GameServer.begin(id, "a")
    assert game == Game.new(seed: {1, 2, 3}, players: 2)
    {:ok, table} = GameServer.get(id)
    assert {table.status, table.players, table.max_players} == {:playing, 2, 4}
    assert GameServer.claim_seat(id, "c") == {:error, :full}
    assert GameServer.claim_seat(id, "b") == {:ok, 1}
    assert GameServer.begin(id, "a") == {:error, :already_started}
    assert {:ok, _} = GameServer.apply(id, 1, :draw)
  end

  test "only the creator may begin, unless the creator left" do
    {:ok, id} = GameServer.start(3)
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.claim_seat(id, "b")
    assert GameServer.begin(id, "b") == {:error, :not_creator}
    assert GameServer.begin(id, "nobody") == {:error, :not_seated}

    :ok = GameServer.leave_seat(id, "a")
    assert {:ok, %{creator: nil}} = GameServer.get(id)
    assert {:ok, game} = GameServer.begin(id, "b")
    assert game.seats == [0]
  end

  test "leave_seat frees a seat while waiting; begin renumbers the seats" do
    {:ok, id} = GameServer.start(3)
    one = listener(id)
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.claim_seat(id, "b")
    {:ok, 2} = GameServer.claim_seat(id, "c")
    :ok = GameServer.rename(id, 2, "Cleo")

    :ok = GameServer.leave_seat(id, "b")
    assert_receive {:forwarded, ^one, {:names, ^id, %{0 => "Seat 1", 2 => "Cleo"}}}
    assert [_] = Enum.filter(GameServer.open_games(), &(&1.id == id))

    # the free seat goes to the next browser
    {:ok, 1} = GameServer.claim_seat(id, "d")
    :ok = GameServer.leave_seat(id, "d")

    {:ok, game} = GameServer.begin(id, "a")
    assert game.seats == [0, 1]
    assert GameServer.claim_seat(id, "c") == {:ok, 1}
    assert {:ok, %{names: %{0 => "Seat 1", 1 => "Cleo"}}} = GameServer.get(id)
    assert_receive {:forwarded, ^one, {:game, ^id, ^game}}

    # once playing, leaving changes nothing
    :ok = GameServer.leave_seat(id, "c")
    assert GameServer.claim_seat(id, "c") == {:ok, 1}
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
    id = begun(2, ["a", "b"])
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
    solo = begun(1, ["a"])
    {:ok, _} = GameServer.apply(solo, 0, :draw)
    assert {:ok, game} = GameServer.undo(solo)
    assert game == Game.new(seed: {1, 2, 3}, players: 1)

    duo = begun(2, ["a", "b"])
    {:ok, _} = GameServer.apply(duo, 0, :draw)
    assert GameServer.undo(duo) == {:error, :not_solo}
  end

  test "open games are the waiting ones with a free seat" do
    {:ok, open} = GameServer.start(2)
    {:ok, full} = GameServer.start(1)
    {:ok, 0} = GameServer.claim_seat(full, "a")
    playing = begun(2, ["a"])

    ids = Enum.map(GameServer.open_games(), & &1.id)
    assert open in ids
    refute full in ids
    refute playing in ids
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
