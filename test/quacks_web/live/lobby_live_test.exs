defmodule QuacksWeb.LobbyLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "lobby-#{System.unique_integer()}")}
  end

  test "the lobby has one New game button; it opens the configure screen", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    refute html =~ "New solo game"

    {:ok, game_view, _html} =
      view |> element("button", "New game") |> render_click() |> follow_redirect(conn)

    # The game waits for players; the creator (host) sets it up and may start it.
    assert has_element?(game_view, "[data-role=waiting-for-players]", "1 of 2 seated")
    assert has_element?(game_view, "[data-role=count]", "2")
    assert has_element?(game_view, "#books button[popovertarget=book-picker-green]")
    assert has_element?(game_view, "[data-role=copy-link]", "Copy link")
    assert has_element?(game_view, "button[phx-click=begin]", "Start game")
  end

  test "a seed in the lobby URL seeds the new game", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?seed=1,2,3")

    {:error, {:live_redirect, %{to: "/g/" <> id}}} =
      view |> element("button", "New game") |> render_click()

    assert {:ok, %{seed: {1, 2, 3}}} = GameServer.get(id)
  end

  test "lists open games with a Join button, live", %{conn: conn} do
    {:ok, id} = GameServer.start(3)
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#game-#{id}", "0 of 3 seated")
    assert has_element?(view, ~s(#game-#{id} a[href="/g/#{id}"]), "Join")

    {:ok, new_id} = GameServer.start(2)
    assert has_element?(view, "#game-#{new_id}")
  end

  test "the host's Options set house rules for the game", %{conn: conn} do
    {:ok, id} = GameServer.start(2)
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")

    view
    |> element("#options")
    |> render_change(%{"rules" => %{"explode_above" => "9", "rats" => "false"}})

    render_click(view, "players", %{"count" => "1"})
    view |> element("button", "Start game") |> render_click()

    assert has_element?(view, ~s(#fuse-meter[data-white="0"][data-limit="9"]), "0 / 9")
    assert has_element?(view, "[data-role=house-rules]", "explodes above 9 · no rats")
  end

  test "a default game shows no house rules", %{conn: conn} do
    {:ok, id} = GameServer.start(1)
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    refute has_element?(view, "[data-role=house-rules]")
  end

  test "parse_rules keeps the default for a missing or bad value" do
    rules =
      QuacksWeb.SetupComponents.parse_rules(%{"explode_above" => "12", "die" => "no_orange"})

    assert rules == %{Quacks.Game.default_rules() | die: :no_orange}

    assert QuacksWeb.SetupComponents.parse_rules(%{
             "starting_rubies" => "0",
             "fortune" => "false"
           }) ==
             %{Quacks.Game.default_rules() | starting_rubies: 0, fortune: false}
  end
end
