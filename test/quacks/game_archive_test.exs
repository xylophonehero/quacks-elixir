defmodule Quacks.GameArchiveTest do
  @moduledoc """
  The archive of finished games (`Quacks.GameStore.archive/4`): the server writes
  `<dir>/finished/quacks/<id>.json` once, when its game ends, and the archive keeps the
  newest files only.
  """
  # Not async: the games directory is app config, read when a game starts.
  use ExUnit.Case, async: false

  alias Quacks.{Game, GameServer, GameStore, Session}

  setup do
    %{dir: Quacks.GameHelpers.games_dir()}
  end

  # A 2-player session played to its end with the first legal action (stop when it
  # can): every session on the way, the last one over.
  defp sessions do
    Stream.iterate(Session.new({1, 2, 3}, 2), fn s ->
      g = s.game

      {seat, [action | _]} =
        g.seats
        |> Enum.map(&{&1, Game.legal_actions(g, &1) -- [:resume]})
        |> Enum.find(fn {_seat, actions} -> actions != [] end)

      action = if :stop in Game.legal_actions(g, seat), do: :stop, else: action
      {:ok, s} = Session.apply(s, seat, action)
      s
    end)
    |> Enum.reduce_while([], fn s, acc ->
      if Game.over?(s.game), do: {:halt, Enum.reverse([s | acc])}, else: {:cont, [s | acc]}
    end)
  end

  # A stored table of "ann" (seat 0) and "bob" (seat 1) at `session`.
  defp restored(session, dir) do
    id = "arc#{System.unique_integer([:positive])}"

    body =
      session
      |> Session.bundle()
      |> Map.merge(%{names: ["Ann", "Bob"], bots: []})
      |> Map.put(:table, %{
        id: id,
        status: "playing",
        max_players: 2,
        seed: [1, 2, 3],
        opts: Session.encode_opts([]),
        tokens: %{"ann" => 0, "bob" => 1},
        names: [[0, "Ann"], [1, "Bob"]],
        colours: [[0, 0], [1, 1]],
        bots: [],
        creator: "ann"
      })

    {:ok, ^id} = GameServer.start_from_bundle(body, restore: true, dir: dir)
    id
  end

  defp archive_file(dir, id), do: Path.join(GameStore.finished_dir(dir, "quacks"), id <> ".json")

  test "the last action writes the archive file, with seats, scores and winners", %{dir: dir} do
    all = sessions()
    [last, before | _] = Enum.reverse(all)
    [{seat, action} | _] = last.actions

    id = restored(before, dir)
    refute File.exists?(archive_file(dir, id))

    {:ok, game} = GameServer.apply(id, seat, action)
    assert Game.over?(game)

    body = dir |> archive_file(id) |> File.read!() |> Jason.decode!()
    scores = Game.score(last.game)
    standings = Game.standings(last.game)

    assert %{
             "format" => 1,
             "game" => "quacks",
             "id" => ^id,
             "players" => 2,
             "app_version" => version
           } = body

    assert version =~ ~r/^\S+ \(\S+\)$/
    assert {:ok, _at, 0} = DateTime.from_iso8601(body["finished_at"])
    assert body["standings"] == standings
    assert hd(body["winners"]) == hd(standings)

    assert [
             %{"seat" => 0, "name" => "Ann", "human" => true, "bot" => nil, "vp" => vp0},
             %{"seat" => 1, "name" => "Bob", "human" => true, "vp" => vp1}
           ] = body["seats"]

    assert {vp0, vp1} == {scores[0], scores[1]}

    # The bundle replays to the same finished game: the archive changes nothing.
    assert {:ok, replayed} = Session.from_bundle(body["bundle"])
    assert replayed.game == last.game
    assert body["bundle"]["names"] == ["Ann", "Bob"]
  end

  test "a game restored when it is over already is not archived again", %{dir: dir} do
    last = List.last(sessions())
    id = restored(last, dir)
    :ok = GameServer.rename(id, 0, "Anna")
    {:ok, _} = GameServer.get(id)
    refute File.exists?(archive_file(dir, id))
  end

  test "prune keeps the newest files within the count and the size", %{dir: dir} do
    fdir = GameStore.finished_dir(dir, "quacks")
    File.mkdir_p!(fdir)

    for i <- 1..5 do
      path = Path.join(fdir, "g#{i}.json")
      File.write!(path, String.duplicate("x", 100))
      File.touch!(path, 1_700_000_000 + i)
    end

    assert [_, _] = GameStore.prune(fdir, 3, 10_000)
    assert fdir |> File.ls!() |> Enum.sort() == ["g3.json", "g4.json", "g5.json"]

    # 250 bytes hold two files of 100
    assert [gone] = GameStore.prune(fdir, 3, 250)
    assert Path.basename(gone) == "g3.json"
    assert fdir |> File.ls!() |> Enum.sort() == ["g4.json", "g5.json"]
  end

  test "a nil directory archives nothing" do
    assert GameStore.archive(nil, "quacks", "x", %{}) == :ok
  end
end
