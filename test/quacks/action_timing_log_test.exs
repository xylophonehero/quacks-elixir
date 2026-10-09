defmodule Quacks.ActionTimingLogTest do
  use QuacksWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  setup do
    for module <- [Quacks.GameServer, QuacksWeb.Telemetry],
        do: Logger.put_module_level(module, :debug)

    on_exit(fn ->
      Enum.each([Quacks.GameServer, QuacksWeb.Telemetry], &Logger.delete_module_level/1)
    end)
  end

  test "each applied action and each LiveView event logs its time" do
    {:ok, id} = GameServer.start(1, {1, 2, 3})
    conn = init_test_session(build_conn(), player_token: "solo")
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")

    log =
      capture_log([level: :debug], fn ->
        view |> element("button[data-slot=draw]") |> render_click()
      end)

    assert log =~
             ~r/action game=#{id} seat=0 action=draw result=ok engine_ms=[\d.]+ total_ms=[\d.]+/

    assert log =~ ~r/live_event view=GameLive event=action ms=[\d.]+/
  end
end
