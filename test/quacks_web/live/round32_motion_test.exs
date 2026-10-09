defmodule QuacksWeb.Round32MotionTest do
  @moduledoc """
  Round 32 (handoff quacks-round-32-motion), the page side: the Mandrake white chip
  hovers over the bag with an undo button (item 1), and the droplet move marker for
  `PotMotion` (item 2).
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

  describe "item 1: the Mandrake chip over the bag" do
    test "the white chip and the undo button show over the bag, with no text" do
      {id, alice, bob} = duo()
      refute has_element?(alice, "[data-role=mandrake-undo]")

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}])
      end)

      alice |> element("button[data-slot=draw]") |> render_click()

      assert has_element?(alice, "[data-role=bag-button] ~ [data-role=mandrake-undo] #keep-white")
      assert has_element?(alice, "[data-role=mandrake-undo] .mandrake-bob [aria-label='white 1']")
      refute render(alice) =~ "went back in your bag.</span>"
      refute has_element?(alice, ".game-tray [data-role=mandrake-undo]")
      refute has_element?(bob, "[data-role=mandrake-undo]")

      alice |> element("#keep-white") |> render_click()
      refute has_element?(alice, "[data-role=mandrake-undo]")
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.pot_chips(game, 0) == [{:yellow, 1}, {:white, 1}]
    end

    test "no undo button without the Mandrake answer" do
      {id, alice, _bob} = duo()

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:green, 1}])
      end)

      alice |> element("button[data-slot=draw]") |> render_click()
      refute has_element?(alice, "#keep-white")
    end
  end

  describe "item 2: the droplet move marker" do
    test "rubies paid for the droplet mark it for PotMotion's hop" do
      {id, alice, _bob} = duo()
      replace_game(id, &H.put(&1, 0, phase: :rubies, rubies: 4))
      render_click(alice, "seen", %{"kind" => "results", "round" => 1})
      refute has_element?(alice, "#droplet-0-lg[data-hop]")

      alice |> element("#bar-rubies button[data-ruby=droplet]") |> render_click()
      assert has_element?(alice, "#droplet-0-lg[data-hop=rubies][data-index='1']")
    end

    test "the last ruby spend on the droplet still ends the round, with the marker" do
      {id, alice, _bob} = duo()
      replace_game(id, &H.put(&1, 0, phase: :rubies, rubies: 2))
      render_click(alice, "seen", %{"kind" => "results", "round" => 1})

      alice |> element("#bar-rubies button[data-ruby=droplet]") |> render_click()
      {:ok, %{game: game}} = GameServer.get(id)
      assert game.players[0].droplet == 1
      assert {0, :end_round} in game.log
    end

    test "the flask brew sits in a clip group, so the hook can raise it" do
      {id, alice, _bob} = duo()
      replace_game(id, &H.put(&1, 0, flask: true))
      assert has_element?(alice, "[data-role=flask] g[clip-path] > [data-role=flask-brew]")
    end
  end
end
