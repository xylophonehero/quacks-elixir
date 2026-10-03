defmodule QuacksWeb.PotReverseLiveTest do
  @moduledoc "The reverse pot side: the Options checkbox, the test-tube rack and the droplet choice."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H

  alias Quacks.GameServer
  alias QuacksWeb.SetupComponents

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp solo_back do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false, pot_side: :back})
    {id, browser("solo-#{System.unique_integer()}") |> open(id)}
  end

  test "the Options checkbox turns the reverse side on; the rack shows under the pot" do
    {:ok, id} = GameServer.start(2)
    view = browser("host") |> open(id)
    refute has_element?(view, "#rules-pot_side[checked]")

    view |> element("#options") |> render_change(%{"rules" => %{"pot_side" => "true"}})
    assert has_element?(view, "#rules-pot_side[checked]")
    assert {:ok, %{rules: %{pot_side: :back}}} = GameServer.get(id)

    render_click(view, "players", %{"count" => "1"})
    view |> element("button", "Start game") |> render_click()

    assert has_element?(view, "[data-role=house-rules]", "reverse pot side (test tubes)")
    assert has_element?(view, ~s(svg[data-role=test-tubes][data-tube="0"]))
    assert has_element?(view, "[data-role=test-tubes] [data-role=tube-droplet]")
  end

  test "a front-side game has no rack" do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false})
    refute has_element?(browser("front") |> open(id), "[data-role=test-tubes]")
  end

  test "the saved config ('back') and the checkbox ('true') both parse" do
    assert SetupComponents.parse_rules(%{"pot_side" => "back"}).pot_side == :back
    assert SetupComponents.parse_rules(%{"pot_side" => "true"}).pot_side == :back
    assert SetupComponents.parse_rules(%{"pot_side" => "false"}).pot_side == :front
    assert SetupComponents.parse_rules(%{"pot_side" => "nope"}).pot_side == :front
  end

  test "a waiting droplet move opens the choice dialog; the tube pays its glass" do
    {id, view} = solo_back()
    replace_game(id, &H.put(&1, droplet_moves: 1))

    assert has_element?(view, "dialog#decision-droplet_choice [data-role=droplet-choice]")
    assert has_element?(view, "#decision-droplet_choice button", "Pot droplet +1")

    view
    |> element("#decision-droplet_choice button", "Test tube (bonus: 1 ruby)")
    |> render_click()

    refute has_element?(view, "#decision-droplet_choice")
    assert has_element?(view, ~s(svg[data-role=test-tubes][data-tube="1"]))
    assert has_element?(view, ~s([data-role=glass][data-filled="true"]))
    assert {:ok, %{game: game}} = GameServer.get(id)
    assert %{tube: 1, rubies: 2} = game.players[0]
  end

  test "the rubies step offers the pot droplet and the next glass" do
    {id, view} = solo_back()
    replace_game(id, &H.put(&1, phase: :rubies, rubies: 2, tube: 2))

    assert has_element?(view, "#decision-rubies button", "Spend 2 rubies: pot droplet +1")

    view
    |> element("#decision-rubies button", "Spend 2 rubies: test tube (bonus: blue 1 chip)")
    |> render_click()

    assert has_element?(view, ~s(svg[data-role=test-tubes][data-tube="3"]))
  end
end
