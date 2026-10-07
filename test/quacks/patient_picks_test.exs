defmodule Quacks.PatientPicksTest do
  # Round 26: The Alchemists' patients picked before the game (A2: 3 patients are
  # drawn at setup and each player picks one of them; several may pick the same).
  # Not async: the games directory is app config, read when a game starts.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Quacks.{Game, GameServer, GameStore, Session}
  alias Quacks.Game.Essence
  alias Quacks.Rules.Alchemists

  @seed {7, 8, 9}

  defp new(opts),
    do: Game.new([seed: @seed, players: 2, expansions: [:alchemists]] ++ opts)

  describe "engine" do
    test "the seed alone says which 3 patients the game deals" do
      assert Essence.dealt(@seed) == new([]).patients
      assert length(Essence.dealt(@seed)) == 3
    end

    test "a pre-pick is the seat's patient action; the other seat still chooses" do
      [a, _b, _c] = Essence.dealt(@seed)
      g = new(patients: %{0 => a})

      assert g.phase == :patient_choice
      assert Game.player(g, 0).patient == a
      assert Game.legal_actions(g, 0) == []
      assert {:patient, _} = hd(Game.legal_actions(g, 1))
      assert {0, {:patient, a}} in g.log

      # The same game as the pick made in the game.
      {:ok, by_hand} = Game.apply(new([]), 0, {:patient, a})
      assert g == by_hand
    end

    test "every seat pre-picked: round 1 starts at once; two seats may share" do
      [a | _] = Essence.dealt(@seed)
      g = new(patients: %{0 => a, 1 => a})
      assert g.round == 1
      assert g.phase != :patient_choice
      assert Game.player(g, 1).patient == a
    end

    test ":random is one of the 3 dealt, the same for the same seed" do
      for seed <- [{1, 2, 3}, {4, 5, 6}, {7, 8, 9}] do
        g = Game.new(seed: seed, players: 1, expansions: [:alchemists], patients: %{0 => :random})
        assert Game.player(g, 0).patient in g.patients

        assert g ==
                 Game.new(
                   seed: seed,
                   players: 1,
                   expansions: [:alchemists],
                   patients: %{0 => :random}
                 )
      end
    end

    test "a patient that is not dealt, or a seat that is not there, raises" do
      [missing | _] = Alchemists.patients() -- Essence.dealt(@seed)
      assert_raise ArgumentError, fn -> new(patients: %{0 => missing}) end
      assert_raise ArgumentError, fn -> new(patients: %{5 => :random}) end
    end

    test "without The Alchemists the picks are ignored" do
      g = Game.new(seed: @seed, players: 1, patients: %{0 => :random})
      assert Game.player(g, 0).patient == nil
    end
  end

  describe "session" do
    test "undo and the bug-report bundle keep the picks" do
      s =
        Session.new(@seed, 2, expansions: [:alchemists], patients: %{0 => :random, 1 => :random})

      assert s.game.round == 1
      {:ok, s2} = Session.apply(s, 0, hd(Game.legal_actions(s.game, 0)))
      assert Session.undo(s2).game == s.game

      {:ok, back} =
        s2 |> Session.bundle() |> Jason.encode!() |> Jason.decode!() |> Session.from_bundle()

      assert back.game == s2.game
      assert back.patients == %{0 => :random, 1 => :random}
    end

    test "a bundle without patients (before round 26) still loads" do
      s = Session.new(@seed, 1, expansions: [:alchemists])
      bundle = s |> Session.bundle() |> update_in([:opts], &Map.delete(&1, :patients))
      assert {:ok, %Session{patients: %{}}} = Session.from_bundle(bundle)
    end

    test "encode_opts/decode_opts round-trip the picks" do
      opts = [expansions: [:alchemists], patients: %{0 => :random, 2 => :ear_worm}]

      decoded =
        opts
        |> Session.encode_opts()
        |> Jason.encode!()
        |> Jason.decode!()
        |> Session.decode_opts()

      assert decoded[:patients] == %{0 => :random, 2 => :ear_worm}
    end
  end

  describe "table" do
    setup do
      dir = Path.join("tmp", "test-games-#{System.unique_integer([:positive])}")
      Application.put_env(:quacks, :games_dir, dir)

      on_exit(fn ->
        Application.delete_env(:quacks, :games_dir)
        File.rm_rf!(dir)
      end)

      %{dir: dir}
    end

    defp shut_down(id) do
      pid = GenServer.whereis({:via, Registry, {Quacks.GameRegistry, id}})
      ref = Process.monitor(pid)
      :ok = DynamicSupervisor.terminate_child(Quacks.GameSupervisor, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}
    end

    test "the host's pick, a joiner at Random, a change, and the game", %{dir: _dir} do
      [a, b, _c] = Essence.dealt(@seed)

      {:ok, id} =
        GameServer.create(
          %{players: 3, bots: [2], expansions: [:alchemists], patient: a},
          "ann",
          @seed
        )

      {:ok, table} = GameServer.get(id)
      assert table.patients == Essence.dealt(@seed)
      assert table.patient_picks == %{0 => a}

      {:ok, 1} = GameServer.claim_seat(id, "bob", watch: false)
      {:ok, table} = GameServer.get(id)
      assert table.patient_picks == %{0 => a, 1 => :random}

      assert GameServer.pick_patient(id, 1, b) == :ok
      assert GameServer.pick_patient(id, 2, b) == {:error, :invalid}
      missing = hd(Alchemists.patients() -- table.patients)
      assert GameServer.pick_patient(id, 1, missing) == {:error, :invalid}

      {:ok, game} = GameServer.begin(id, "ann")
      assert Game.player(game, 0).patient == a
      assert Game.player(game, 1).patient == b
    end

    test "a pick for a patient the seed does not deal is Random" do
      [missing | _] = Alchemists.patients() -- Essence.dealt(@seed)

      {:ok, id} =
        GameServer.create(
          %{players: 1, expansions: [:alchemists], patient: missing},
          "ann",
          @seed
        )

      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.player(game, 0).patient in Essence.dealt(@seed)
    end

    test "no Alchemists: no patients, no picks" do
      {:ok, id} = GameServer.create(%{players: 2}, "ann", @seed)
      {:ok, table} = GameServer.get(id)
      assert table.patients == nil
      assert table.patient_picks == %{}
      assert GameServer.pick_patient(id, 0, :random) == {:error, :invalid}
    end

    test "a waiting table's picks survive a restore", %{dir: dir} do
      [_a, b, _c] = Essence.dealt(@seed)
      {:ok, id} = GameServer.create(%{players: 2, expansions: [:alchemists]}, "ann", @seed)
      {:ok, 1} = GameServer.claim_seat(id, "bob", watch: false)
      :ok = GameServer.pick_patient(id, 1, b)
      shut_down(id)
      {[^id], _log} = with_log(fn -> GameStore.restore(dir) end)

      {:ok, table} = GameServer.get(id)
      assert table.patient_picks == %{0 => :random, 1 => b}
      {:ok, game} = GameServer.begin(id, "ann")
      assert Game.player(game, 1).patient == b
    end

    test "a playing game's picks survive a restore", %{dir: dir} do
      [a | _] = Essence.dealt(@seed)

      {:ok, id} =
        GameServer.create(%{players: 1, expansions: [:alchemists], patient: a}, "ann", @seed)

      {:ok, %{game: before}} = GameServer.get(id)
      shut_down(id)
      {[^id], _log} = with_log(fn -> GameStore.restore(dir) end)
      {:ok, %{game: game}} = GameServer.get(id)
      assert game == before
      assert Game.player(game, 0).patient == a
    end

    test "Fill with bots seats a bot in every free seat and begins" do
      {:ok, id} = GameServer.create(%{players: 3, expansions: [:alchemists]}, "ann", @seed)
      assert GameServer.fill_bots(id, "bob") == {:error, :not_creator}
      {:ok, game} = GameServer.fill_bots(id, "ann")
      assert length(game.seats) == 3
      assert Game.player(game, 0).patient in Essence.dealt(@seed)
      {:ok, table} = GameServer.get(id)
      assert table.status == :playing
      assert map_size(table.bots) == 2
    end
  end
end
