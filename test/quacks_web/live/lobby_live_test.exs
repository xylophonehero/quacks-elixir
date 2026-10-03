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

    # The game waits for players; the creator may start it.
    assert has_element?(game_view, "[data-role=waiting-for-players]", "1 of 2 seated")
    assert has_element?(game_view, "button[phx-click=begin]", "Start game")
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

  test "the Options block sets house rules for the new game", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#options")
    |> render_change(%{"rules" => %{"explode_above" => "9", "rats" => "false"}})

    {:ok, game_view, _html} =
      view |> element("button", "New solo game") |> render_click() |> follow_redirect(conn)

    assert has_element?(game_view, "dd", "0 / 9")
    assert has_element?(game_view, "[data-role=house-rules]", "explodes above 9 · no rats")
  end

  test "a default game shows no house rules", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, game_view, _html} =
      view |> element("button", "New solo game") |> render_click() |> follow_redirect(conn)

    refute has_element?(game_view, "[data-role=house-rules]")
  end

  test "parse_rules keeps the default for a missing or bad value" do
    rules = QuacksWeb.LobbyLive.parse_rules(%{"explode_above" => "12", "die" => "no_orange"})
    assert rules == %{Quacks.Game.default_rules() | die: :no_orange}

    assert QuacksWeb.LobbyLive.parse_rules(%{"starting_rubies" => "0", "fortune" => "false"}) ==
             %{Quacks.Game.default_rules() | starting_rubies: 0, fortune: false}
  end
end
