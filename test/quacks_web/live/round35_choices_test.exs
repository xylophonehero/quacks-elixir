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

  describe "item 2: the toadstools beside the pot" do
    test "stack in a column" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, aside: [{:red, 1}, {:red, 2}]))

      assert has_element?(view, "[data-role=beside-pot].flex-col [data-role=aside-chip]")
      refute has_element?(view, "[data-role=beside-pot].-space-x-1\\.5")
    end
  end

  describe "item 3: the shop's book text scrolls into view" do
    test "the info button asks the sheet to show the opened text" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, phase: :shop, coins: 10))

      assert has_element?(
               view,
               "#decision-shop [data-role=book-info][phx-click*='quacks:reveal'][phx-click*='#shop-book-0']"
             )
    end
  end

  describe "item 4: the shop always buys" do
    test "no Skip: Buy is the one button, disabled until a chip is ticked" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, phase: :shop, coins: 10))

      refute has_element?(view, "#decision-shop [data-role=shop-done]")
      refute has_element?(view, "#decision-shop button", "Skip")
      assert has_element?(view, "#decision-shop [data-role=shop-buy]:disabled")
    end

    test "too few coins for any chip: only then Nothing to buy" do
      # The page skips the buy step when nothing is affordable (unless a copper
      # witch acts there), so the shop itself is checked here.
      {id, _view} = solo(%{})
      game = replace_game(id, &H.put(&1, phase: :shop, coins: 2))
      html = render_component(&QuacksWeb.GameLive.shop/1, game: game, seat: 0, selected: [])
      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query("[data-role=shop-done]") |> LazyHTML.text() =~ "Nothing to buy"
      assert doc |> LazyHTML.query("[data-role=shop-buy]") |> Enum.empty?()
    end
  end
end
