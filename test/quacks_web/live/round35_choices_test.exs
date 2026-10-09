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

  describe "item 5: Choices, Choices as a chip row" do
    test "the black chip, the 2-chips and a ruby with 3, in the bottom row only" do
      {id, view} = solo(%{})

      replace_game(id, fn g ->
        %{g | phase: :fortune_choice, fortune_card: :p1} |> H.put(0, phase: :fortune_choice)
      end)

      row = "footer section[data-role=bar-card][data-card=p1]"
      assert has_element?(view, "#{row} button[data-choice=take] [aria-label='black 1']")
      assert has_element?(view, "#{row} button[data-choice=take] [aria-label='red 2']")
      assert has_element?(view, "#{row} button [data-role=ruby-count]", "3")
      refute has_element?(view, "#{row} [data-role=info-row]")
      refute has_element?(view, "#{row} [data-role=choice-grid]")

      view |> element("#{row} button[data-choice=rubies]") |> render_click()
      refute has_element?(view, row)
      {:ok, %{game: game}} = GameServer.get(id)
      assert game.players[0].rubies == 4
    end
  end

  describe "item 6: what everyone took after an everyone-card" do
    defp p1(g),
      do:
        %{g | phase: :fortune_choice, fortune_card: :p1}
        |> Map.update!(
          :players,
          &Map.new(&1, fn {s, p} -> {s, %{p | phase: :fortune_choice}} end)
        )

    test "solo: after the choice the card grows with the row; Continue shrinks it" do
      {id, view} = solo(%{})
      replace_game(id, &p1/1)
      refute has_element?(view, "[data-role=pot-card] [data-role=card-reveals]")

      view |> element("[data-card=p1] button[data-choice=rubies]") |> render_click()

      row =
        "[data-role=pot-card] [data-role=card-reveals][data-card=p1] [data-role=card-reveal-row]"

      assert has_element?(view, "#{row}[data-me=true] [data-role=seat-disc]")
      assert has_element?(view, "#{row} [data-gain=rubies]", "+3")
      assert has_element?(view, "#card-continue")

      view |> element("#card-continue") |> render_click()
      refute has_element?(view, "[data-role=pot-card] [data-role=card-reveals]")
    end

    test "two players: the one who chose sees the other still choosing, then the take" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, alice, _} = live(browser("r35-alice-#{id}"), ~p"/g/#{id}")
      {:ok, bob, _} = live(browser("r35-bob-#{id}"), ~p"/g/#{id}")
      alice |> element("button", "Start game") |> render_click()
      replace_game(id, &p1/1)

      alice |> element("[data-card=p1] button[data-choice=rubies]") |> render_click()
      rows = "[data-role=pot-card] [data-role=card-reveal-row]"
      assert has_element?(alice, "#{rows}[data-seat='1']", "choosing")

      bob |> element("[data-card=p1] button[aria-label*='black 1']") |> render_click()
      assert has_element?(alice, "#{rows}[data-seat='1'] [data-gain=chip] [aria-label='black 1']")
      assert has_element?(bob, "#{rows}[data-seat='0'] [data-gain=rubies]", "+3")
    end
  end
end
