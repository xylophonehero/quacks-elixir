defmodule Quacks.GameFileTest do
  @moduledoc """
  Game files (`Quacks.GameStore`) from before a refactor still load, and a restored
  game plays on as if it never stopped (architecture review §5.4).

  - G2: two game files the server wrote on 2026-10-16 with The Herb Witches given
    as the old `expansion` option (`Session.encode_opts/1`):
    `herb_witches_bots.json` (playing: 1 human, 2 bots, 2 draws into round 1) and
    `herb_witches_waiting.json` (a waiting table). #79 removes `expansion`; the
    files must still restore, keep the expansion and play.
  - G4: a stored game with 2 bots restores and its bots play the same actions as
    the same game that was never stored, and their rngs end in the same state
    (they come back from the file).

  Record the files again (only when its format is meant to change) with
  `GOLDEN_RECORD=1 mix test test/quacks/game_file_test.exs`.
  """
  # Not async: the games directory is app config, read when a game starts.
  use ExUnit.Case, async: false

  import Quacks.GameHelpers, only: [play_human: 3]

  alias Quacks.{AI, Game, GameServer, GameStore, Golden, Session}

  @file_path Path.expand("../fixtures/game_files/herb_witches_bots.json", __DIR__)
  @waiting_path Path.expand("../fixtures/game_files/herb_witches_waiting.json", __DIR__)

  setup do
    %{dir: Quacks.GameHelpers.games_dir()}
  end

  # 3 seats: the human "ann" in seat 0, bots in 1 and 2; The Herb Witches as the
  # old single `expansion`. The human draws twice (the bots step with each draw).
  defp started(seed) do
    {:ok, id} = GameServer.start(3, seed, %{}, %{fortune: false}, :herb_witches)
    {:ok, 0} = GameServer.claim_seat(id, "ann", watch: false)
    {:ok, 1} = GameServer.add_bot(id, "ann")
    {:ok, 2} = GameServer.add_bot(id, "ann")
    {:ok, _game} = GameServer.begin(id, "ann")
    {:ok, _} = GameServer.apply(id, 0, :draw)
    {:ok, _} = GameServer.apply(id, 0, :draw)
    id
  end

  # A deploy: the supervisor shuts the game down (`terminate/2` writes its file).
  defp shut_down(id) do
    pid = GenServer.whereis({:via, Registry, {Quacks.GameRegistry, id}})
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(Quacks.GameSupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
  end

  defp stored_file(dir, id) do
    shut_down(id)
    {:ok, body} = GameStore.read(GameStore.path(dir, id))
    body
  end

  # Rounds 1 to 8: the bots act only when the human acts, or in their own part of a
  # phase, so two runs give the same log. (Round 9 has bot ticks beside the human.)
  defp before_round_9(game), do: game.round >= 9

  defp to_round_9(game) do
    log = Enum.reverse(game.log)
    Enum.take(log, Enum.find_index(log, &(&1 == {:round_end, 8})) + 1)
  end

  test "G2: a game file written before the refactors restores and plays one action", %{
    dir: dir
  } do
    if Golden.record?() do
      body = stored_file(dir, started({61, 62, 63}))
      File.mkdir_p!(Path.dirname(@file_path))
      File.write!(@file_path, [Jason.encode_to_iodata!(body, pretty: true), "\n"])
    end

    body = @file_path |> File.read!() |> Jason.decode!()
    assert body["table"]["opts"]["expansion"] == "herb_witches"
    assert body["table"]["bot_rngs"] |> length() == 2
    id = body["table"]["id"]

    assert {:ok, ^id} = GameServer.start_from_bundle(body, restore: true, dir: dir)

    {:ok, table} = GameServer.get(id)
    assert table.status == :playing
    assert :herb_witches in table.game.expansions
    assert table.bots == %{1 => :expert, 2 => :expert}

    # the same actions as the file
    {:ok, bundle} = GameServer.bundle(id)
    assert Jason.decode!(Jason.encode!(bundle))["log"] == body["log"]

    # the human plays on: one more draw in the actions
    assert GameServer.claim_seat(id, "ann", watch: false) == {:ok, 0}
    assert {:ok, %Game{}} = GameServer.apply(id, 0, :draw)
    {:ok, bundle} = GameServer.bundle(id)

    assert [0, "draw"] in Enum.drop(
             Jason.decode!(Jason.encode!(bundle))["log"],
             length(body["log"])
           )

    shut_down(id)
  end

  test "G2: a waiting table's file from before the refactors keeps its expansion", %{dir: dir} do
    if Golden.record?() do
      {:ok, id} = GameServer.start(3, {64, 65, 66})
      {:ok, 0} = GameServer.claim_seat(id, "ann", watch: false)
      {:ok, _} = GameServer.configure(id, "ann", %{expansion: :herb_witches})
      {:ok, 1} = GameServer.add_bot(id, "ann")
      body = stored_file(dir, id)
      File.write!(@waiting_path, [Jason.encode_to_iodata!(body, pretty: true), "\n"])
    end

    body = @waiting_path |> File.read!() |> Jason.decode!()
    assert body["table"]["status"] == "waiting"
    assert body["table"]["opts"]["expansion"] == "herb_witches"
    id = body["table"]["id"]

    assert {:ok, ^id} = GameServer.start_from_bundle(body, restore: true, dir: dir)
    assert {:ok, %{status: :waiting, expansions: expansions}} = GameServer.get(id)
    assert :herb_witches in expansions

    # the game begins with The Herb Witches and plays
    {:ok, 2} = GameServer.add_bot(id, "ann")
    assert {:ok, %Game{} = game} = GameServer.begin(id, "ann")
    assert :herb_witches in game.expansions
    assert {:ok, %Game{}} = GameServer.apply(id, 0, hd(Game.legal_actions(game, 0)))
    shut_down(id)
  end

  test "G4: restored bots play the same actions as bots that never stopped", %{dir: dir} do
    # The same game twice, from one game file with 2 `:balanced` bots (their rngs pick
    # among the fortune cards' answers; the `:expert` bots of today never use theirs).
    # One of them stops in round 4 and comes back from its new game file.
    seed = {71, 72, 73}
    stored = with_bots(seed, "g4stored")
    plain = with_bots(seed, "g4plain")
    # (each `play_human/3` call starts the human's own rng again, so both games
    # play in the same two parts)
    play_human(stored, 0, &(&1.round >= 4))
    play_human(plain, 0, &(&1.round >= 4))

    body = stored_file(dir, stored)
    fresh = for seat <- [1, 2], do: [seat, rng_pair(:rand.export_seed_s(AI.new_rng(seed, seat)))]
    assert length(body["table"]["bot_rngs"]) == 2
    # the bots used their rngs before the stop: the file must bring them back
    assert body["table"]["bot_rngs"] != fresh
    assert {:ok, ^stored} = GameServer.start_from_bundle(body, restore: true, dir: dir)

    a = play_human(stored, 0, &before_round_9/1)
    b = play_human(plain, 0, &before_round_9/1)
    assert a.round == 9 and b.round == 9
    # rounds 1 to 8 (round 9's bot ticks may run on beside the human)
    {la, lb} = {to_round_9(a), to_round_9(b)}
    assert List.last(la) == {:round_end, 8}
    at = Enum.find_index(Enum.zip(la, lb), fn {x, y} -> x != y end) || 0

    assert la == lb,
           "the logs part at #{at}: #{inspect(Enum.slice(la, at, 6))} / #{inspect(Enum.slice(lb, at, 6))}"

    # and the bots' rngs are where they would be (their next files say so)
    assert stored_file(dir, stored)["table"]["bot_rngs"] ==
             stored_file(dir, plain)["table"]["bot_rngs"]
  end

  defp rng_pair({:exsss, [s0 | s1]}), do: [s0, s1]

  # A playing game of 3 seats with the fortune cards, from a game file: "ann" in
  # seat 0, `:balanced` bots in 1 and 2, no action yet.
  defp with_bots(seed, id) do
    body =
      Session.new(seed, 3)
      |> Session.bundle()
      |> Map.merge(%{names: ["Ann", "Bo", "Cy"], bots: [1, 2]})
      |> Map.put(:table, %{
        id: id,
        status: "playing",
        max_players: 3,
        seed: Tuple.to_list(seed),
        opts: Session.encode_opts([]),
        tokens: %{"ann" => 0},
        names: [[0, "Ann"], [1, "Bo"], [2, "Cy"]],
        colours: [[0, 0], [1, 1], [2, 2]],
        bots: [[1, "balanced"], [2, "balanced"]],
        creator: "ann"
      })

    {:ok, ^id} = GameServer.start_from_bundle(body, restore: true)
    id
  end
end
