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

    refute has_element?(alice, "[data-role=turn]")

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
    refute has_element?(alice, "[data-role=turn]")
    assert has_element?(bob, "#card-round-1 button", "No thanks")
    assert state(alice, 1) =~ "choosing"
  end

  test "the shop: Done, no Buy nothing, no rubies; round 9 trades 2 rubies for 1 VP" do
    {id, alice, _bob} = duo()
    replace_game(id, &H.put(&1, 0, phase: :shop, rubies: 3, coins: 30))

    assert has_element?(alice, "dialog#decision-shop #shop")
    assert has_element?(alice, "dialog#decision-shop [data-role=shop-bag]")
    assert has_element?(alice, "dialog#decision-shop [data-role=shop-done]", "Done")
    refute has_element?(alice, "button", "Buy nothing")
    refute has_element?(alice, "dialog#decision-shop [data-role=shop-rubies]")

    replace_game(id, &(&1 |> H.put(round: 9) |> H.put(0, rubies: 3)))
    refute has_element?(alice, "dialog#decision-shop")
    assert has_element?(alice, "dialog#reveal-results-9")
    assert has_element?(alice, "dialog#decision-rubies")
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
      alice
      |> tap(&(&1 |> element("#reveal-skip") |> render_click()))
      |> element("#reveal-final-9 button", "Play again")
      |> render_click()

    assert {"/g/" <> ^new_id, _flash} = assert_redirect(bob)
    assert {:ok, %{status: :waiting, names: %{0 => _, 1 => _}}} = GameServer.get(new_id)
  end
end
