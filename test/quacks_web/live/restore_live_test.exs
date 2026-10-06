defmodule QuacksWeb.RestoreLiveTest do
  # Not async: the games directory is app config, read when a game starts.
  use QuacksWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Quacks.{GameServer, GameStore}

  setup do
    dir = Path.join("tmp", "test-games-#{System.unique_integer([:positive])}")
    Application.put_env(:quacks, :games_dir, dir)

    on_exit(fn ->
      Application.delete_env(:quacks, :games_dir)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  test "after a restart a reload lands in the same seat, no rejoin prompt", %{dir: dir} do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    {:ok, alice, _} = live(browser("alice"), ~p"/g/#{id}")
    {:ok, _bob, _} = live(browser("bob"), ~p"/g/#{id}")
    alice |> element("button", "Start game") |> render_click()

    # the deploy: the game stops (and writes its file), the pages go
    pid = GenServer.whereis({:via, Registry, {Quacks.GameRegistry, id}})
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(Quacks.GameSupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    {[^id], _log} = with_log(fn -> GameStore.restore(dir) end)

    {:ok, bob, _} = live(browser("bob"), ~p"/g/#{id}")
    assert has_element?(bob, "[data-role=my-seat]")
    refute has_element?(bob, "[data-role=spectator]")
    refute has_element?(bob, "[data-role=rejoin-form]")
    assert {:ok, %{absent: [0]}} = GameServer.get(id)
  end
end
