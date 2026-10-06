defmodule Quacks.GameStoreTest do
  # Not async: the games directory is app config, read when a game starts.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Quacks.{Game, GameServer, GameStore, Session}

  setup do
    dir = Path.join("tmp", "test-games-#{System.unique_integer([:positive])}")
    Application.put_env(:quacks, :games_dir, dir)

    on_exit(fn ->
      Application.delete_env(:quacks, :games_dir)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  defp pid(id), do: GenServer.whereis({:via, Registry, {Quacks.GameRegistry, id}})

  # The pending debounced write, done now (as its timer would do it).
  defp flush_write(id) do
    pid = pid(id)
    %{write_timer: ref} = :sys.get_state(pid)
    send(pid, {:write, ref})
    :sys.get_state(pid)
  end

  # A deploy: the supervisor shuts the game down (`terminate/2` writes).
  defp shut_down(id) do
    pid = pid(id)
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(Quacks.GameSupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
  end

  defp restore(dir) do
    {ids, _log} = with_log(fn -> GameStore.restore(dir) end)
    ids
  end

  # The first legal action of `seat` (the fortune card's choice comes first).
  defp act(id, seat) do
    {:ok, %{game: g}} = GameServer.get(id)
    {:ok, _} = GameServer.apply(id, seat, hd(Game.legal_actions(g, seat) -- [:resume]))
  end

  defp file(dir, id), do: GameStore.path(dir, id)

  test "write and read back a game file; no dir writes nothing", %{dir: dir} do
    body = %{table: %{id: "abcdef", status: "waiting"}, extra: [1, 2]}
    assert GameStore.write(dir, "abcdef", body) == :ok
    assert GameStore.read(file(dir, "abcdef")) == {:ok, Jason.decode!(Jason.encode!(body))}
    refute File.exists?(file(dir, "abcdef") <> ".tmp")
    assert GameStore.write(nil, "abcdef", body) == :ok
    assert GameStore.delete(dir, "abcdef") == :ok
    refute File.exists?(file(dir, "abcdef"))
  end

  test "a playing game comes back after a shutdown: seats, tokens, names, game", %{dir: dir} do
    {:ok, id} = GameServer.start(2, {4, 5, 6}, %{black: 2}, %{overflow: false})
    {:ok, 0} = GameServer.claim_seat(id, "ann", watch: false)
    {:ok, 1} = GameServer.claim_seat(id, "bob", watch: false)
    :ok = GameServer.rename(id, 1, "Bea")
    :ok = GameServer.set_colour(id, 1, 5)
    {:ok, _} = GameServer.begin(id, "ann")
    act(id, 0)
    act(id, 1)
    act(id, 0)
    :ok = GameServer.ack(id, 0, :card, 1)
    {:ok, before} = GameServer.get(id)

    # no explicit write: the shutdown writes the pending change
    shut_down(id)
    assert {:error, :not_found} = GameServer.get(id)
    assert restore(dir) == [id]

    {:ok, after_} = GameServer.get(id)
    keys = [:status, :game, :seed, :players, :names, :colours, :seen, :sets, :rules, :founder]
    assert Map.take(after_, keys) == Map.take(before, keys)
    assert after_.names == %{0 => "Player 1", 1 => "Bea"}
    assert GameServer.claim_seat(id, "bob", watch: false) == {:ok, 1}
    assert GameServer.claim_seat(id, "ann", watch: false) == {:ok, 0}
    act(id, 1)
    # a second restore leaves the running game alone
    assert restore(dir) == []
  end

  test "a waiting table comes back with its settings, bots and host", %{dir: dir} do
    {:ok, id} = GameServer.start(4)
    {:ok, 0} = GameServer.claim_seat(id, "ann", watch: false)
    {:ok, 1} = GameServer.claim_seat(id, "bob", watch: false)

    {:ok, _} =
      GameServer.configure(id, "ann", %{
        players: 3,
        sets: %{green: 2},
        expansion: :herb_witches,
        expansions: [:alchemists],
        witches: %{copper: :c3, silver: nil, gold: nil}
      })

    {:ok, 2} = GameServer.add_bot(id, "ann")
    {:ok, before} = GameServer.get(id)
    shut_down(id)
    assert restore(dir) == [id]

    {:ok, table} = GameServer.get(id)
    assert Map.delete(table, :absent) == Map.delete(before, :absent)
    assert table.status == :waiting
    assert table.expansions == MapSet.new([:herb_witches, :alchemists])
    assert {:error, :not_creator} = GameServer.begin(id, "bob")
    assert {:ok, %Game{players: _}} = GameServer.begin(id, "ann")
  end

  test "a private table stays private after a restore", %{dir: dir} do
    {:ok, id} = GameServer.create(%{players: 3, public: false, name: "Ann"}, "ann")
    shut_down(id)
    assert restore(dir) == [id]

    assert {:ok, %{public: false, names: %{0 => "Ann"}}} = GameServer.get(id)
    refute Enum.any?(GameServer.games("bob"), &(&1.id == id))
    assert [%{id: ^id, mine: 0}] = Enum.filter(GameServer.games("ann"), &(&1.id == id))
  end

  test "bots play on after a restore" do
    id = "botsxx"
    session = Session.new({1, 2, 3}, 2)
    {:ok, session} = Session.apply(session, 0, :draw)

    body =
      session
      |> Session.bundle()
      |> Map.merge(%{names: ["Ann", "Rob"], bots: [1]})
      |> Map.put(:table, %{
        id: id,
        status: "playing",
        max_players: 2,
        seed: [1, 2, 3],
        opts: Session.encode_opts([]),
        tokens: %{"ann" => 0},
        names: [[0, "Ann"], [1, "Rob"]],
        colours: [[0, 0], [1, 1]],
        bots: [[1, "balanced"]],
        creator: "ann"
      })

    Phoenix.PubSub.subscribe(Quacks.PubSub, GameServer.topic(id))
    assert {:ok, ^id} = GameServer.start_from_bundle(body, restore: true)
    # the bot (seat 1) has drawn fewer times than the human: it draws
    assert_receive {:game, ^id, %Game{} = game}
    assert Enum.count(game.log, &match?({1, :draw}, &1)) == 1
  end

  test "a file that does not load is renamed .bad and the rest restore", %{dir: dir} do
    File.mkdir_p!(dir)
    File.write!(file(dir, "broken"), "{not json")
    File.write!(file(dir, "nosuch"), ~s({"table": {"id": "nosuch", "status": "playing"}}))
    {:ok, id} = GameServer.start(2)
    {:ok, 0} = GameServer.claim_seat(id, "ann", watch: false)
    shut_down(id)

    {ids, log} = with_log(fn -> GameStore.restore(dir) end)
    assert ids == [id]
    assert log =~ "broken.json"
    assert File.exists?(file(dir, "broken") <> ".bad")
    assert File.exists?(file(dir, "nosuch") <> ".bad")
    refute File.exists?(file(dir, "broken"))
  end

  test "a burst of changes is written once", %{dir: dir} do
    {:ok, id} = GameServer.start(1)
    {:ok, 0} = GameServer.claim_seat(id, "ann", watch: false)
    %{write_timer: ref} = :sys.get_state(pid(id))
    assert is_reference(ref)

    for _ <- 1..3, do: act(id, 0)
    # the same pending write, nothing on disk yet
    assert %{write_timer: ^ref} = :sys.get_state(pid(id))
    refute File.exists?(file(dir, id))

    assert %{write_timer: nil} = flush_write(id)
    assert {:ok, %{"log" => log}} = GameStore.read(file(dir, id))
    assert length(log) == 3

    # the timer's own message comes later and is stale now: no second write
    File.rm!(file(dir, id))
    send(pid(id), {:write, ref})
    :sys.get_state(pid(id))
    refute File.exists?(file(dir, id))

    # a read changes nothing, so it writes nothing
    {:ok, _} = GameServer.get(id)
    assert %{write_timer: nil} = :sys.get_state(pid(id))
  end

  test "a finished game keeps its file until every human saw the result", %{dir: dir} do
    {:ok, id} = GameServer.start(2)
    {:ok, 0} = GameServer.claim_seat(id, "ann", watch: false)
    {:ok, 1} = GameServer.add_bot(id, "ann")
    {:ok, _} = GameServer.begin(id, "ann")
    replace_session(id, finished_session())
    :ok = GameServer.ack(id, 0, :card, 9)
    flush_write(id)
    assert File.exists?(file(dir, id))
    assert %{expire_timer: nil} = :sys.get_state(pid(id))

    # the bot needs no ack; the human's ack of the final scoring starts the clock
    :ok = GameServer.ack(id, 0, :final, 9)
    assert %{expire_timer: timer} = :sys.get_state(pid(id))
    assert is_reference(timer)

    send(pid(id), :expire)
    :sys.get_state(pid(id))
    refute File.exists?(file(dir, id))
    # the game itself stays until it idles out, and writes no more
    :ok = GameServer.rename(id, 0, "Ann")
    assert %{write_timer: nil} = :sys.get_state(pid(id))
  end

  test "an idle game deletes its file", %{dir: dir} do
    {:ok, id} = GameServer.start(2)
    {:ok, 0} = GameServer.claim_seat(id, "ann", watch: false)
    flush_write(id)
    assert File.exists?(file(dir, id))

    pid = pid(id)
    ref = Process.monitor(pid)
    send(pid, :timeout)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    refute File.exists?(file(dir, id))
  end

  test "debug tables are not stored", %{dir: dir} do
    bundle = Session.bundle(Session.new({1, 2, 3}, 2))
    {:ok, id} = GameServer.start_from_bundle(bundle)
    {:ok, _} = GameServer.apply(id, 0, :draw)
    assert %{write_timer: nil, store: nil} = :sys.get_state(pid(id))
    refute File.exists?(file(dir, id))
  end

  # A 2-player session played to its end with the first legal action each time.
  defp finished_session do
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
    |> Enum.find(&Game.over?(&1.game))
  end

  defp replace_session(id, session),
    do: :sys.replace_state(pid(id), &%{&1 | session: session, bot_ticks: %{}, queued: %{}})
end
