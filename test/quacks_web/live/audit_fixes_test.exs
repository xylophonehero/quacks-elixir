defmodule QuacksWeb.AuditFixesTest do
  @moduledoc "The 2026-10-04 audit fixes: a gone game, the live region, lean player sheets."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice-#{id}"), id)
    bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {id, alice, bob}
  end

  # The game process stops, as after a crash or the idle timeout.
  defp stop_server(id) do
    [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
  end

  describe "a game whose server is gone" do
    test "a move goes to the lobby with a flash, without a crash" do
      {:ok, id} = GameServer.start(1, {10, 11, 12})
      view = open(browser("solo-#{id}"), id)
      stop_server(id)

      view |> element("button", "Draw a chip") |> render_click()
      flash = assert_redirect(view, ~p"/")
      assert flash["error"] == "This game has ended."
    end

    test "a seat change broadcast after the stop also goes to the lobby" do
      {id, alice, _bob} = duo()
      stop_server(id)

      send(alice.pid, {:names, id, %{}})
      assert_redirect(alice, ~p"/")
    end

    test "the waiting room's rename goes to the lobby" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      view = open(browser("host-#{id}"), id)
      stop_server(id)

      view |> form("#rename-form", name: "Nick") |> render_change()
      assert_redirect(view, ~p"/")
    end
  end

  test "a visually hidden live region says the newest event" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = open(browser("solo-#{id}"), id)
    assert has_element?(view, "#announcer.sr-only[aria-live=polite]")

    view |> element("button", "Draw a chip") |> render_click()
    assert has_element?(view, "#announcer", ~r/^Drew \w+ \d/)
  end

  test "a player sheet renders its body only while it is open" do
    {_id, alice, _bob} = duo()
    sheet = "#sheet-player-1[data-on-hide]"
    assert has_element?(alice, sheet)
    refute has_element?(alice, "#{sheet} [data-role=player-card]")

    alice |> element(~s([data-role=player-chip][data-seat="1"])) |> render_click()
    assert has_element?(alice, "#{sheet} [data-role=player-card]")
    refute has_element?(alice, "#sheet-player-0 [data-role=player-card]")

    render_click(alice, "close_player", %{"seat" => 1})
    refute has_element?(alice, "[data-role=player-card]")
  end
end
