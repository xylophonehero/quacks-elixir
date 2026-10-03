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

  test "two browsers play one 2-player game and both see the evaluation" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)

    refute has_element?(alice, "[data-role=waiting-for-players]")
    assert has_element?(alice, "[data-role=turn]", "Everyone brews at the same time.")
    # each sees the other one small, still brewing
    assert has_element?(alice, ~s(article[data-seat="1"]), "waiting")
    assert has_element?(bob, ~s(article[data-seat="0"]), "waiting")

    alice |> element("button", "Draw a chip") |> render_click()
    bob |> element("button", "Draw a chip") |> render_click()
    # Alice's draw reached Bob's page through PubSub
    assert has_element?(bob, ~s(article[data-seat="0"] [data-role=pot-chip]))
    assert has_element?(bob, "li", ~r/^Seat 1: Drew white \d/)

    alice |> element("button", "Stop") |> render_click()
    assert has_element?(bob, ~s(article[data-seat="0"]), "done")
    bob |> element("button", "Stop") |> render_click()

    for view <- [alice, bob] do
      assert has_element?(view, "dd", "Shop")
      assert has_element?(view, "li", ~r/^Seat \d: Bonus die/)
    end

    # the shop goes seat by seat from the start seat (seat 0 in round 1)
    assert has_element?(alice, "[data-role=turn]", "Your turn: buy chips.")
    assert has_element?(alice, "button", "Buy nothing")
    assert has_element?(bob, "[data-role=turn]", "Seat 1's turn: buy chips.")
    refute has_element?(bob, "button", "Buy nothing")
    refute has_element?(bob, "button", "Undo")
    # only the buyer gets the shop dialog; the other one sees the turn line
    assert has_element?(alice, "dialog#decision-buy_chips")
    refute has_element?(bob, "dialog#decision-buy_chips")
    # both get the round results, with each seat's bonus die and totals
    for view <- [alice, bob], seat <- [0, 1] do
      assert has_element?(
               view,
               ~s(dialog#round-results [data-seat="#{seat}"] [data-role=result-total])
             )
    end

    assert has_element?(bob, ~s(button[popovertarget="sheet-players"]), "Players")
  end

  test "a nickname shows on the other player's page" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)

    alice |> element("input[aria-label='Your name']") |> render_blur(%{"value" => "Alice"})
    assert has_element?(bob, ~s(article[data-seat="0"] [data-role=player-name]), "Alice")
  end

  test "a browser without a seat watches: every pot, no buttons" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    _alice = open(browser("alice"), id)
    _bob = open(browser("bob"), id)
    eve = open(browser("eve"), id)

    assert has_element?(eve, "[data-role=spectator]")
    refute has_element?(eve, "[data-role=my-seat]")
    refute has_element?(eve, "button[phx-click=action]")
    assert has_element?(eve, ~s(article[data-seat="0"]))
    assert has_element?(eve, ~s(article[data-seat="1"]))
  end
end
