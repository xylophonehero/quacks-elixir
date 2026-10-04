defmodule QuacksWeb.BugReportLiveTest do
  @moduledoc "\"Report a problem\": the bug button and its dialog (`QuacksWeb.BugReportComponents`)."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp send_report(view, text) do
    browser = Jason.encode!(%{ua: "UA", viewport: "1x1", online: true, errors: ["e"]})

    view
    |> form("#bug-report-form-0", report: %{text: text})
    |> render_submit(%{report: %{browser: browser}})
  end

  test "a player sends a report from the game; the toast names the file" do
    {:ok, id} = GameServer.start(1)
    {:ok, view, _html} = live(browser("a"), ~p"/g/#{id}")

    assert has_element?(view, "header [aria-label='Report a problem']")
    assert has_element?(view, "dialog#bug-report-0 textarea[name='report[text]']")

    send_report(view, "")
    assert has_element?(view, "[data-role=report-error]", "write what went wrong")

    send_report(view, "Chips vanished")
    assert has_element?(view, "#flash-info", "Thanks. Saved locally.")
    refute render(view) =~ "bug-reports/"
    assert has_element?(view, "dialog#bug-report-1")
    refute has_element?(view, "dialog#bug-report-0")

    view
    |> form("#bug-report-form-1", report: %{text: "Again"})
    |> render_submit()

    assert has_element?(view, "[data-role=report-error]", "One report a minute")
  end

  test "the configure screen has the button; a spectator has none" do
    {:ok, id} = GameServer.start(2)
    {:ok, host, _html} = live(browser("a"), ~p"/g/#{id}")
    assert has_element?(host, "[aria-label='Report a problem']")

    {:ok, _guest, _html} = live(browser("b"), ~p"/g/#{id}")
    {:ok, _game} = GameServer.begin(id, "a")
    {:ok, watcher, _html} = live(browser("c"), ~p"/g/#{id}")
    refute has_element?(watcher, "[aria-label='Report a problem']")
  end
end
