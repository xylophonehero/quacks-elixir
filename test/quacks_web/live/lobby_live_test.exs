defmodule QuacksWeb.LobbyLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "lobby-#{System.unique_integer()}")}
  end

  test "New game for 2 players creates a game with this browser in seat 0", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "New solo game"

    {:ok, game_view, _html} =
      view
      |> element("button", "New game for 2 players")
      |> render_click()
      |> follow_redirect(conn)

    # A purple fortune card may open the round with a choice instead of drawing,
    # so assert on any action button rather than "Draw a chip". If that choice is
    # the other seat's turn, this seat has no buttons and the banner says so.
    assert has_element?(game_view, "button[phx-click=action]") or
             has_element?(game_view, "[data-role=turn]", "Seat 2's turn")

    assert has_element?(game_view, "[data-role=waiting-for-players]", "1 of 2 seated")
  end

  test "a seed in the lobby URL seeds the new game", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?seed=1,2,3")

    {:ok, _game_view, html} =
      view |> element("button", "New solo game") |> render_click() |> follow_redirect(conn)

    assert html =~ "1,2,3"
  end

  test "lists open games with a Join button, live", %{conn: conn} do
    {:ok, id} = GameServer.start(3)
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#game-#{id}", "0 of 3 seated")
    assert has_element?(view, ~s(#game-#{id} a[href="/g/#{id}"]), "Join")

    {:ok, new_id} = GameServer.start(2)
    assert has_element?(view, "#game-#{new_id}")
  end
end
