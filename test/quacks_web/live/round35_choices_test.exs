defmodule QuacksWeb.Round35ChoicesTest do
  @moduledoc """
  Round 35 (choices): the crow skull's chips in the bottom row, the toadstools
  beside the pot in a column, the shop always buys, Choices Choices as a chip
  row, and what everyone took after an everyone-card.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(rules) do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, Map.merge(%{fortune: false}, rules))
    {:ok, view, _html} = live(browser("r35-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  describe "item 1: the crow skull in the bottom row" do
    test "the drawn chips and Skip in one row, the white track stays" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))

      row = "footer section[data-role=bar-blue][phx-hook$='FromBag'][phx-remove]"
      assert has_element?(view, "#{row} button[data-pool-chip] .chip-token")
      assert has_element?(view, "#{row} [data-role=blue-skip]", "Skip")
      refute has_element?(view, "#{row} [data-role=info-row]")
      assert has_element?(view, "[data-role=fuse-row]")
      refute has_element?(view, "[data-role=action-bar]")
    end

    test "a tap places the chip; Skip returns them all" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))

      view |> element("[data-role=bar-blue] button[aria-label*='red 1']") |> render_click()
      refute has_element?(view, "[data-role=bar-blue]")
      assert has_element?(view, "[data-role=action-bar]")

      replace_game(id, &H.put(&1, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))
      view |> element("[data-role=blue-skip]") |> render_click()
      refute has_element?(view, "[data-role=bar-blue]")
    end
  end
end
