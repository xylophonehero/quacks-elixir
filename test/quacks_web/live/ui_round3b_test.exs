defmodule QuacksWeb.UiRound3bTest do
  @moduledoc """
  The configure screen, the round 9 "Stir!" step, concurrent choices, the one-step
  shop, the overflow bowl in every game and "Play again".
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H

  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  # A 2-player game without fortune cards, started by alice.
  defp duo(seed \\ {1, 2, 3}, rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, seed, %{}, rules)
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    alice |> element("button", "Start game") |> render_click()
    {id, alice, bob}
  end

  defp state(view, seat),
    do:
      view
      |> element(~s([data-role=player-chip][data-seat="#{seat}"] [data-role=player-state]))
      |> render()

  test "the host configures the game; a joiner sees the settings read-only, live" do
    {:ok, id} = GameServer.start(2)
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)

    # two are seated, so the count cannot go below 2; only the host may change it
    assert has_element?(alice, "button[aria-label='Fewer players'][disabled]")
    assert has_element?(bob, "button[aria-label='More players'][disabled]")
    assert has_element?(bob, "#books fieldset[disabled]")
    assert has_element?(bob, "[data-role=read-only]", "Player 1 sets the game up.")

    alice |> element("button[aria-label='More players']") |> render_click()
    assert has_element?(bob, "[data-role=count]", "3")
    assert has_element?(bob, ~s([data-role=seat-slot][data-seat="2"]), "empty")

    alice |> form("#books", sets: %{green: "2"}) |> render_change()
    assert has_element?(bob, "#books [data-book=green-2]")
    # a joiner sees the tiles but no pickers
    refute has_element?(bob, "#books button[popovertarget]")
    refute has_element?(bob, "#book-picker-green")

    alice |> element("#options") |> render_change(%{"rules" => %{"rats" => "false"}})
    assert has_element?(bob, "#rules-rats:not([checked])")

    # a crafted event from the joiner changes nothing
    render_click(bob, "players", %{"count" => "4"})
    assert {:ok, %{max_players: 3, sets: %{green: 2}, rules: %{rats: false}}} = GameServer.get(id)
  end

  test "solo: count 1, then Start begins the game at once" do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("solo"), id)
    view |> element("button[aria-label='Fewer players']") |> render_click()
    assert has_element?(view, "[data-role=count]", "1")
    refute has_element?(view, "[data-role=share-link]")

    view |> element("button", "Start game") |> render_click()
    assert has_element?(view, "button[data-slot=draw]:not([disabled])", "Draw a chip")
    assert {:ok, %{status: :playing, players: 1}} = GameServer.get(id)
  end

  test "round 9: a Stir! banner; a pick locks Draw and Stop; no Resume" do
    {id, alice, bob} = duo()

    replace_game(id, fn g ->
      g
      |> H.put(round: 9)
      |> H.put(0, bag: [{:orange, 1}, {:orange, 1}])
      |> H.put(1, drawn: [{{:orange, 1}, 2}], pot_index: 2, bag: [{:white, 1}, {:orange, 1}])
    end)

    for view <- [alice, bob] do
      assert has_element?(view, "[data-role=stir]", "Stir! Everyone draws together.")
    end

    assert state(alice, 0) =~ "deciding"
    alice |> element("button", "Draw a chip") |> render_click()

    assert has_element?(alice, "button[data-slot=draw][disabled]")
    assert has_element?(alice, "button[data-slot=stop][disabled]")

    assert has_element?(
             alice,
             "[data-role=turn]",
             "You chose draw. Waiting for 1 player: Player 2."
           )

    assert state(bob, 0) =~ "chosen"
    assert state(bob, 1) =~ "deciding"

    # bob stops: the step resolves, alice draws again; bob's stop is final
    bob |> element("button", "Stop") |> render_click()
    assert has_element?(alice, "button[data-slot=draw]:not([disabled])")
    refute has_element?(bob, "button", "Resume")
    assert has_element?(bob, "button[data-slot=stop][disabled]", "Stop")
  end

  test "a card choice opens for every seat at once; who answered sees who still decides" do
    # seed 30,30,30 with 2 players deals a card with a choice for both seats
    {_id, alice, bob} = duo({30, 30, 30}, %{})

    for view <- [alice, bob] do
      assert has_element?(view, "dialog#card-round-1[phx-mounted] [data-role=card-modal]")
    end

    alice |> element("#card-round-1 button", "No thanks") |> render_click()
    refute has_element?(alice, "#card-round-1 button", "No thanks")
    assert has_element?(alice, "[data-role=turn]", "Waiting for 1 player: Player 2.")
    assert has_element?(bob, "#card-round-1 button", "No thanks")
    assert state(alice, 1) =~ "choosing"
  end

  test "the shop: Done, no Buy nothing, no rubies; round 9 trades 2 rubies for 1 VP" do
    {id, alice, _bob} = duo()
    replace_game(id, &H.put(&1, 0, phase: :shop, rubies: 3))

    assert has_element?(alice, "dialog#decision-shop #shop")
    assert has_element?(alice, "dialog#decision-shop [data-role=shop-bag]")
    assert has_element?(alice, "dialog#decision-shop [data-role=shop-done]", "Done")
    refute has_element?(alice, "button", "Buy nothing")
    refute has_element?(alice, "dialog#decision-shop [data-role=shop-rubies]")

    replace_game(id, &(&1 |> H.put(round: 9) |> H.put(0, rubies: 3)))
    refute has_element?(alice, "dialog#decision-shop")
    assert has_element?(alice, "dialog#round-results[data-then-open=decision-rubies]")
    alice |> element("dialog#decision-rubies button", "2 rubies → 1 VP") |> render_click()
    assert has_element?(alice, "li", "Spent 2 rubies: +1 VP")
  end

  test "the overflow bowl shows under the pot in a base game once it has chips" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("bowl"), id)
    refute has_element?(view, "[data-role=bowl]")

    replace_game(id, &H.put(&1, 0, bowl: [{:white, 1}]))
    assert has_element?(view, "[data-role=bowl] [data-role=bowl-chip]")
  end

  test "Play again takes both players to the next game" do
    {id, alice, bob} = duo()
    replace_game(id, &H.put(&1, phase: :over))

    {:error, {:live_redirect, %{to: "/g/" <> new_id}}} =
      alice |> element("#game-over button", "Play again") |> render_click()

    assert {"/g/" <> ^new_id, _flash} = assert_redirect(bob)
    assert {:ok, %{status: :waiting, names: %{0 => _, 1 => _}}} = GameServer.get(new_id)
  end
end
