defmodule QuacksWeb.R10EngineTest do
  @moduledoc """
  Round 10 (handoff quacks-r10-engine), the page side: the free droplet move says it
  is free and why (item 1), the shop's two steps (item 1), the overflow bowl option
  (item 3), the Mandrake "Keep the white chip instead" button (item 5), the player
  sheets (item 6) and the round-start rat tails (item 7).
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers, as: H

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp duo(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, rules)
    alice = open(browser("alice-#{id}"), id)
    bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {id, alice, bob}
  end

  describe "item 1: rubies last, the free droplet move" do
    test "the droplet choice says the move is free and where it came from" do
      {id, alice, _bob} = duo(%{fortune: false, pot_side: :back})

      replace_game(id, fn g ->
        g
        |> H.put(0, phase: :buy, coins: 10, rubies: 4, droplet_moves: 1)
        |> Map.update!(:log, &[{0, {:black, :droplet}}, {0, {:bonus_die, :droplet}} | &1])
      end)

      render_click(alice, "seen", %{"kind" => "results", "round" => 1})
      assert has_element?(alice, "#decision-droplet_choice", "A free move (no rubies)")
      assert has_element?(alice, "[data-role=droplet-sources] li", "Hawkmoth: droplet +1")
      assert has_element?(alice, "[data-role=droplet-sources] li", "Bonus die")

      # the droplet first, then the buy, then the rubies
      render_click(alice, "action", %{"action" => QuacksWeb.GameLive.encode({:droplet, :tube})})
      assert has_element?(alice, "dialog#decision-shop")
      refute has_element?(alice, "dialog#decision-rubies")

      render_click(alice, "action", %{"action" => QuacksWeb.GameLive.encode({:buy, []})})
      assert has_element?(alice, "#decision-rubies button", "Spend 2 rubies: test tube")
    end
  end

  describe "item 3: the overflow bowl option" do
    test "the Herb Witches toggle leaves the overflow rule alone" do
      {:ok, id} = GameServer.start(2)
      host = open(browser("host-#{id}"), id)
      refute render(host) =~ "Witch cards, overflow bowl"

      host |> element("#options") |> render_change(%{"rules" => %{"overflow" => "false"}})
      host |> element("#books") |> render_change(%{"sets" => %{}, "expansion" => "true"})
      assert {:ok, %{rules: %{overflow: false}, expansion: :herb_witches}} = GameServer.get(id)

      host |> element("#books") |> render_change(%{"sets" => %{}, "expansion" => "false"})
      host |> element("#options") |> render_change(%{"rules" => %{"overflow" => "true"}})
      assert {:ok, %{rules: %{overflow: true}, expansion: nil}} = GameServer.get(id)
      assert has_element?(host, "#options-section #rules-overflow")
    end
  end

  describe "item 5: Mandrake" do
    test "the server put the white chip back; the button keeps it, once" do
      {id, alice, bob} = duo()

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}])
      end)

      alice |> element("button", "Draw a chip") |> render_click()
      refute has_element?(alice, "#decision-yellow_choice")
      assert has_element?(alice, "[data-role=mandrake-undo]", "went back in your bag")
      refute has_element?(bob, "#keep-white")

      alice |> element("#keep-white") |> render_click()
      refute has_element?(alice, "#keep-white")
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.pot_chips(game, 0) == [{:yellow, 1}, {:white, 1}]
    end

    test "the button goes once another seat acts" do
      {id, alice, bob} = duo()

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}])
      end)

      alice |> element("button", "Draw a chip") |> render_click()
      assert has_element?(alice, "#keep-white")
      bob |> element("button", "Draw a chip") |> render_click()
      refute has_element?(alice, "#keep-white")
      assert GameServer.keep_white(id, 0) == {:error, :too_late}
    end
  end

  describe "item 6: player sheets" do
    test "another player's sheet shows the test tubes and the essence strip" do
      {:ok, id} =
        GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false, pot_side: :back}, nil)

      alice = open(browser("alice-#{id}"), id)
      _bob = open(browser("bob-#{id}"), id)
      {:ok, _} = GameServer.begin(id, "alice-#{id}")
      replace_game(id, &H.put(&1, 1, tube: 3, patient: :ear_worm, essence: 4))

      alice |> element(~s([data-role=player-chip][data-seat="1"])) |> render_click()
      card = "#sheet-player-1 [data-role=player-card]"
      assert has_element?(alice, ~s(#{card} svg[data-role=test-tubes][data-tube="3"]))
      assert has_element?(alice, ~s(#{card} [data-role=flask-strip][data-essence="4"]))
    end

    test "a tap on a second player while a sheet is open shows that player's sheet" do
      {_id, alice, _bob} = duo()
      alice |> element(~s([data-role=player-chip][data-seat="0"])) |> render_click()
      assert has_element?(alice, "#sheet-player-0 [data-role=player-card]")

      # the second chip's open arrives first, the first sheet's light-dismiss after
      alice |> element(~s([data-role=player-chip][data-seat="1"])) |> render_click()
      render_click(alice, "close_player", %{"seat" => 0})
      assert has_element?(alice, "#sheet-player-1 [data-role=player-card]")

      render_click(alice, "close_player", %{"seat" => 1})
      refute has_element?(alice, "[data-role=player-card]")
    end
  end

  describe "item 7: the rat tails at the start of the round" do
    test "a line under the players row names this round's rat tails; the results do not" do
      {id, alice, _bob} = duo()
      replace_game(id, &(&1 |> H.put(0, rat_stone: 2) |> H.put(1, rat_stone: 0)))
      assert has_element?(alice, "[data-role=round-rats]", "Rats this round: Player 1 (2 tails)")

      replace_game(id, &H.put(&1, 0, phase: :buy, vp: 0))
      refute has_element?(alice, "[data-role=round-rats]")
      refute has_element?(alice, "[data-role=result-rats]")
      refute render(alice) =~ "Rats next round"
    end
  end
end
