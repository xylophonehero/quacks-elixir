defmodule QuacksWeb.MultiplayerLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  # One browser: a fresh conn with its own player token.
  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  # Seat alice and bob and start the game, as alice (the creator) would.
  defp start_duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    {id, alice, bob}
  end

  test "the waiting page: only the creator starts the game" do
    {id, alice, bob} = start_duo()
    assert has_element?(alice, "[data-role=waiting-for-players]", "2 of 2 seated")
    assert has_element?(bob, ~s(li[data-seat="0"]), "Seat 1")
    refute has_element?(bob, "button", "Start game")

    alice |> element("button", "Start game") |> render_click()
    assert {:ok, %{status: :playing}} = GameServer.get(id)
    assert has_element?(bob, "button", "Draw a chip")
  end

  test "a page closed before the start frees its seat" do
    {:ok, id} = GameServer.start(3, {1, 2, 3})
    _alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    assert {:ok, %{names: %{1 => "Seat 2"}}} = GameServer.get(id)

    # the test process is linked to the page; closing it must not stop the test
    Process.flag(:trap_exit, true)
    GenServer.stop(bob.pid, {:shutdown, :closed})
    assert {:ok, %{names: names}} = GameServer.get(id)
    assert names == %{0 => "Seat 1"}
  end

  test "two browsers play one 2-player game and both see the evaluation" do
    {id, alice, bob} = start_duo()
    {:ok, _} = GameServer.begin(id, "alice")

    refute has_element?(alice, "[data-role=waiting-for-players]")
    assert has_element?(alice, "[data-role=turn]", "Everyone brews at the same time.")
    # each sees the other one small, still brewing
    assert has_element?(alice, ~s(article[data-seat="1"] [data-role=player-state]), "brewing")
    assert has_element?(bob, ~s(article[data-seat="0"] [data-role=player-state]), "brewing")

    alice |> element("button", "Draw a chip") |> render_click()
    bob |> element("button", "Draw a chip") |> render_click()
    # Alice's draw reached Bob's page through PubSub
    assert has_element?(bob, ~s(article[data-seat="0"] [data-role=pot-chip]))
    assert has_element?(bob, "li", ~r/^Seat 1: Drew white \d/)

    # a soft stop: alice may resume while bob still brews
    alice |> element("button", "Stop") |> render_click()
    assert has_element?(alice, "button[data-slot=stop]", "Resume")
    alice |> element("button[data-slot=stop]", "Resume") |> render_click()
    alice |> element("button", "Stop") |> render_click()
    bob |> element("button", "Stop") |> render_click()

    for view <- [alice, bob] do
      assert has_element?(view, "dd", "Shop")
      assert has_element?(view, "li", ~r/^Seat \d: Bonus die/)
      # everyone shops at once, each in their own shop dialog
      assert has_element?(view, "[data-role=turn]", "Everyone shops at the same time.")
      assert has_element?(view, "dialog#decision-buy")
      assert has_element?(view, "button", "Buy nothing")
    end

    refute has_element?(bob, "button", "Undo")
    # shopping is simultaneous: both players get their own shop dialog
    assert has_element?(alice, "dialog#decision-buy")
    assert has_element?(bob, "dialog#decision-buy")
    # both get the round results, with each seat's bonus die and totals
    for view <- [alice, bob], seat <- [0, 1] do
      assert has_element?(
               view,
               ~s(dialog#round-results [data-seat="#{seat}"] [data-role=result-total])
             )
    end

    assert has_element?(bob, ~s(button[popovertarget="sheet-players"]), "Players")

    # bob is done shopping first; alice still buys
    bob |> element("button", "Buy nothing") |> render_click()
    assert has_element?(bob, "dialog#decision-rubies button", "End round")
    assert has_element?(alice, "dialog#decision-buy")
  end

  test "a nickname shows on the other player's page" do
    {id, alice, bob} = start_duo()
    {:ok, _} = GameServer.begin(id, "alice")

    alice |> element("input[aria-label='Your name']") |> render_blur(%{"value" => "Alice"})
    assert has_element?(bob, ~s(article[data-seat="0"] [data-role=player-name]), "Alice")
  end

  test "a browser without a seat watches: every pot, no buttons" do
    {id, _alice, _bob} = start_duo()
    eve = open(browser("eve"), id)
    assert has_element?(eve, "[data-role=spectator]")
    {:ok, _} = GameServer.begin(id, "alice")

    assert has_element?(eve, "[data-role=spectator]")
    refute has_element?(eve, "[data-role=my-seat]")
    refute has_element?(eve, "button[phx-click=action]")
    assert has_element?(eve, ~s(article[data-seat="0"]))
    assert has_element?(eve, ~s(article[data-seat="1"]))
  end
end
