defmodule QuacksWeb.LobbyFlowTest do
  @moduledoc "The waiting room, the soft stop (Resume), simultaneous shopping and the supply option."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  # One browser: a fresh conn with its own player token.
  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  # A started 2-player game: alice (seat 0) and bob (seat 1).
  defp start_duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    alice |> element("button", "Start game") |> render_click()
    # Stop needs one chip in the pot; the first chip never explodes.
    for view <- [alice, bob], do: view |> element("button[data-slot=draw]") |> render_click()
    {id, alice, bob}
  end

  test "the waiting room shows every seat, the share link and who may start" do
    {:ok, id} = GameServer.start(3, {1, 2, 3})
    alice = open(browser("alice"), id)

    assert has_element?(alice, "[data-role=waiting-for-players]", "1 of 3 seated")
    assert has_element?(alice, ~s([data-role=seat-slot][data-seat="0"]), "Seat 1")
    assert has_element?(alice, ~s([data-role=seat-slot][data-seat="0"]), "you")
    assert has_element?(alice, ~s([data-role=seat-slot][data-seat="1"]), "empty")
    assert has_element?(alice, ~s([data-role=seat-slot][data-seat="2"]), "empty")
    assert has_element?(alice, ~s(input[data-role=share-link][readonly][value$="/g/#{id}"]))

    bob = open(browser("bob"), id)
    # bob's arrival reaches alice's page
    assert has_element?(alice, ~s([data-role=seat-slot][data-seat="1"]), "Seat 2")
    refute has_element?(bob, "button", "Start game")
    assert has_element?(bob, "[data-role=waiting-for-host]", "Waiting for Seat 1 to start")

    # a name set in the waiting room carries into the game
    bob |> element("input[aria-label='Your name']") |> render_blur(%{"value" => "Bob"})
    assert has_element?(alice, ~s([data-role=seat-slot][data-seat="1"]), "Bob")

    # one empty seat left: the game starts with the two seated players
    alice |> element("button", "Start game") |> render_click()
    assert {:ok, %{status: :playing, players: 2}} = GameServer.get(id)
    assert has_element?(alice, ~s(article[data-seat="1"] [data-role=player-name]), "Bob")
    assert has_element?(bob, "button[data-slot=draw]", "Draw a chip")
  end

  test "a closed page frees its seat; when the creator leaves, the next player may start" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)

    # the test process is linked to the pages; closing one must not stop the test
    Process.flag(:trap_exit, true)
    GenServer.stop(alice.pid, {:shutdown, :closed})

    assert has_element?(bob, ~s([data-role=seat-slot][data-seat="0"]), "empty")
    assert has_element?(bob, "[data-role=waiting-for-players]", "1 of 2 seated")
    bob |> element("button", "Start game") |> render_click()
    assert {:ok, %{status: :playing, players: 1, names: %{0 => "Seat 1"}}} = GameServer.get(id)
  end

  test "a stopped player sees Resume and who still brews" do
    {_id, alice, bob} = start_duo()

    alice |> element("button[data-slot=stop]", "Stop") |> render_click()
    assert has_element?(alice, "button[data-slot=stop]:not([disabled])", "Resume")
    assert has_element?(alice, "button[data-slot=draw][disabled]")
    assert has_element?(alice, "[data-role=turn]", "Waiting for 1 player: Seat 2.")
    assert has_element?(bob, ~s(article[data-seat="0"] [data-role=player-state]), "stopped")
    assert has_element?(bob, "[data-role=turn]", "Everyone brews at the same time.")

    # Resume puts alice back to brewing
    alice |> element("button[data-slot=stop]", "Resume") |> render_click()
    assert has_element?(alice, "button[data-slot=stop]", "Stop")
    assert has_element?(bob, ~s(article[data-seat="0"] [data-role=player-state]), "brewing")
  end

  test "both players shop at once and see each other's shop state" do
    {_id, alice, bob} = start_duo()
    alice |> element("button[data-slot=stop]") |> render_click()
    bob |> element("button[data-slot=stop]") |> render_click()

    # both shop dialogs are open at the same time, with the round results on top
    for view <- [alice, bob] do
      assert has_element?(view, "dialog#decision-shop")
      assert has_element?(view, "dialog#round-results")
    end

    assert has_element?(alice, ~s(article[data-seat="1"] [data-role=player-state]), "shopping")

    # one step: after buying nothing bob is still in the shop
    bob |> element("button", "Buy nothing") |> render_click()
    assert has_element?(alice, ~s(article[data-seat="1"] [data-role=player-state]), "shopping")

    assert has_element?(alice, "dialog#decision-shop")

    bob |> element("dialog#decision-shop button", "End round") |> render_click()
    assert has_element?(alice, ~s(article[data-seat="1"] [data-role=player-state]), "ready")
    assert has_element?(bob, "[data-role=turn]", "Waiting for 1 player: Seat 1.")
  end

  test "the lobby's chip supply option" do
    conn = browser("carol")
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#rules-supply-infinite[checked]")

    view |> element("#options") |> render_change(%{"rules" => %{"supply" => "limited"}})

    {:ok, game_view, _html} =
      view |> element("button", "New solo game") |> render_click() |> follow_redirect(conn)

    assert has_element?(game_view, "[data-role=house-rules]", "limited chip supply")
  end
end
