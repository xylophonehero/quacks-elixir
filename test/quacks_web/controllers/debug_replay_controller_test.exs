defmodule QuacksWeb.DebugReplayControllerTest do
  @moduledoc "`/debug/replay`: gated, loads a bundle, and the menu's scrubber steps it."
  # DEBUG_TOKEN is application config: not async.
  use QuacksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Quacks.{BugReports, GameServer}

  setup do
    on_exit(fn -> Application.put_env(:quacks, :debug_token, nil) end)
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, 0} = GameServer.claim_seat(id, "reporter")
    for _ <- 1..3, do: {:ok, _} = GameServer.apply(id, 0, :draw)
    {:ok, bundle} = GameServer.bundle(id)
    %{bundle: bundle |> Map.put(:seat, 0) |> Jason.encode!() |> Base.url_encode64(padding: false)}
  end

  defp conn, do: init_test_session(build_conn(), player_token: "debugger")

  test "closed without DEBUG_TOKEN, and with a wrong token", %{bundle: bundle} do
    assert conn() |> get(~p"/debug/replay?#{[bundle: bundle]}") |> response(404)
    Application.put_env(:quacks, :debug_token, "right")
    assert conn() |> get(~p"/debug/replay?#{[bundle: bundle, token: "wrong"]}") |> response(404)
  end

  test "with the token a bundle loads at N and the scrubber steps it", %{bundle: bundle} do
    Application.put_env(:quacks, :debug_token, "right")
    conn = get(conn(), ~p"/debug/replay?#{[bundle: bundle, at: 1, token: "right"]}")
    "/g/" <> id = redirected_to(conn)

    {:ok, view, _html} = live(conn(), ~p"/g/#{id}")
    assert has_element?(view, "[data-role=scrub-position]", "Action 1 of 3")
    assert has_element?(view, "[data-role=seek-back]:not([disabled])")

    view |> element("[data-role=seek-forward]") |> render_click()
    assert has_element?(view, "[data-role=scrub-position]", "Action 2 of 3")
    {:ok, %{game: game}} = GameServer.get(id)
    assert length(game.players[0].drawn) == 2

    view |> element("[data-role=freeze-bots]", "Unfreeze bots") |> render_click()
    assert has_element?(view, "[data-role=freeze-bots]", "Freeze bots")
  end

  test "an issue number loads its bundle from GitHub", %{bundle: bundle} do
    Application.put_env(:quacks, :debug_token, "right")
    json = bundle |> Base.url_decode64!(padding: false)

    Req.Test.stub(BugReports, fn conn ->
      Req.Test.json(conn, %{
        body: "<details><summary>Replay bundle</summary>\n\n```json\n#{json}\n```\n</details>"
      })
    end)

    conn = get(conn(), ~p"/debug/replay?#{[issue: 5, token: "right"]}")
    "/g/" <> id = redirected_to(conn)
    {:ok, %{debug: %{at: 3, total: 3}}} = GameServer.get(id)
  end

  test "a bad bundle is a 422" do
    Application.put_env(:quacks, :debug_token, "right")

    assert conn()
           |> get(~p"/debug/replay?#{[bundle: "not json", token: "right"]}")
           |> response(422)
  end
end
