defmodule Quacks.DebugReplayTest do
  @moduledoc "Debug tables rebuilt from a bundle (`GameServer.start_from_bundle/2`)."
  use ExUnit.Case, async: true

  alias Quacks.{Game, GameServer, Session}

  # A bundle from a solo-human game with a bot in seat 1, `draws` draws in.
  defp bundle(draws \\ 3) do
    {:ok, id} = GameServer.start(2, {4, 5, 6}, %{}, %{fortune: false})
    {:ok, 0} = GameServer.claim_seat(id, "human")
    {:ok, 1} = GameServer.add_bot(id, "human")
    :ok = GameServer.rename(id, 0, "Ann")
    {:ok, _} = GameServer.begin(id, "human")
    for _ <- 1..draws, do: {:ok, _} = GameServer.apply(id, 0, :draw)
    {:ok, bundle} = GameServer.bundle(id)
    bundle |> Map.put(:seat, 0) |> Jason.encode!() |> Jason.decode!()
  end

  defp replay_prefix(bundle, n) do
    {:ok, s} = Session.from_bundle(bundle)
    prefix = s.actions |> Enum.reverse() |> Enum.take(n) |> Enum.reverse()
    Session.replay(s.seed, s.players, prefix, rules: s.rules, sets: s.sets)
  end

  test "a debug table at N is the replay of the bundle's first N actions" do
    bundle = bundle()
    total = length(bundle["log"])
    {:ok, id} = GameServer.start_from_bundle(bundle, at: 2, token: "dev", seat: 0)
    {:ok, table} = GameServer.get(id)

    assert table.status == :playing
    assert table.game == replay_prefix(bundle, 2)
    assert table.names == %{0 => "Ann", 1 => bundle["names"] |> Enum.at(1)}
    assert table.bots == %{1 => :balanced}
    assert table.debug == %{at: 2, total: total, frozen: true}
    assert {:ok, 0} = GameServer.claim_seat(id, "dev")
    assert {:error, :full} = GameServer.claim_seat(id, "someone else")

    assert {:ok, game} = GameServer.seek(id, 99)
    assert game == replay_prefix(bundle, total)
    assert {:ok, _} = GameServer.seek(id, 1)
    {:ok, %{game: game, debug: %{at: 1}}} = GameServer.get(id)
    assert game == replay_prefix(bundle, 1)
  end

  test "the seat the browser takes is no bot (round 29)" do
    bundle = bundle()
    {:ok, id} = GameServer.start_from_bundle(bundle, token: "dev", seat: 1)
    {:ok, table} = GameServer.get(id)

    assert table.bots == %{}
    assert {:ok, 1} = GameServer.claim_seat(id, "dev")
  end

  test "frozen bots do not act until unfrozen" do
    bundle = bundle()
    # Seat 0 has drawn; the bot may draw now.
    {:ok, id} = GameServer.start_from_bundle(bundle, token: "dev", seat: 0)
    Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))
    {:ok, %{game: before}} = GameServer.get(id)
    assert :draw in Game.legal_actions(before, 1)

    {:ok, _} = GameServer.apply(id, 0, :draw)
    assert_receive {:game, ^id, after_draw}
    refute_receive {:game, ^id, _}, 50
    {:ok, %{game: ^after_draw}} = GameServer.get(id)

    :ok = GameServer.set_frozen(id, false)
    assert_receive {:game, ^id, _}
    assert_receive {:game, ^id, %Game{} = game}, 500
    assert length(game.log) > length(after_draw.log)
  end

  test "a normal table is not a debug table; a bad bundle is refused" do
    {:ok, id} = GameServer.start(1)
    assert {:error, :not_debug} = GameServer.seek(id, 1)
    assert {:error, :not_debug} = GameServer.set_frozen(id, false)
    assert {:error, :not_started} = GameServer.bundle(id)
    assert {:error, :invalid} = GameServer.start_from_bundle(%{"version" => 1})
  end
end
