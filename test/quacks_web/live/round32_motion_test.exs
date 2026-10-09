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
end
