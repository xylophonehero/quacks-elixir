defmodule QuacksWeb.Round39ShopTest do
  @moduledoc """
  Round 39 (shop): Ghost's breath V's chips in the context area (item 1) and
  every seat's scoring ring with the same motion as yours (item 2).
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.Rules.Chips
  alias QuacksWeb.{ActionCode, ShopComponents}

  @panel "#purple-buy-panel-1[data-role=purple-buy]"
  @bar "[data-role=bar-chip-actions]"

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  # Ghost's breath V open in the bar: two purple chips on the pot's late spaces.
  defp ghost_breath do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false}, :herb_witches)
    {:ok, view, _html} = live(browser("r39-#{System.unique_integer()}"), ~p"/g/#{id}")

    replace_game(id, fn g ->
      %{g | sets: Map.put(g.sets, :purple, 5)}
      |> H.put(
        phase: :explosion_choice,
        exploded?: true,
        drawn: [{{:purple, 1}, 40}, {{:purple, 1}, 30}],
        pot_index: 40
      )
      |> H.apply!({:explosion_choice, :buy})
    end)

    {:ok, %{game: game}} = GameServer.get(id)
    {:purple_buy, coins} = Enum.find(game.players[0].chip_choices, &match?({:purple_buy, _}, &1))
    {id, view, game, coins}
  end

  defp tick(view, chips),
    do:
      view
      |> element("#purple-buy-1")
      |> render_change(%{"chips" => Enum.map(chips, &ActionCode.encode/1)})

  describe "item 1: Ghost's breath V picks its chips in the context area" do
    test "a panel, not a sheet: every chip of the shop, the dear ones greyed" do
      {_id, view, game, coins} = ghost_breath()

      refute has_element?(view, "dialog [data-role=purple-buy]")
      assert has_element?(view, "[data-area=context] > #{@panel}.pick-panel")

      shop = List.flatten(ShopComponents.shop_rows(game.expansion, game.sets))
      assert length(shop) == length(view |> render() |> chips_in("#{@panel} label"))

      for chip <- shop, Chips.price(chip, game.sets) > coins do
        assert has_element?(
                 view,
                 "#{@panel} [data-role=purple-buy-off][data-chip='#{elem(chip, 0)} #{elem(chip, 1)}'] input:disabled"
               )
      end

      assert has_element?(view, "#{@panel} [data-role=purple-buy-tile][data-chip='orange 1']")
    end

    test "the purse and Take are in the bar; the panel has no footer of its own" do
      {id, view, game, coins} = ghost_breath()

      refute has_element?(view, "#{@panel} button[phx-click=action]")
      assert has_element?(view, "#{@bar} [data-role=purple-buy-total]", "#{coins}")
      assert has_element?(view, "#{@bar} [data-role=purple-buy-take]:disabled")
      refute has_element?(view, "[data-role=purple-buy-open]")

      tick(view, [{:green, 1}])
      left = coins - Chips.price({:green, 1}, game.sets)

      assert has_element?(
               view,
               "#{@bar} [data-role=purple-buy-total][aria-label='#{coins} coins, #{left} left after this']"
             )

      # The other greens are not with the ticked green.
      assert has_element?(
               view,
               "#{@panel} [data-role=purple-buy-off][data-chip='green 2'][title*='not with your other chip']"
             )

      view |> element("#{@bar} [data-role=purple-buy-take]", "Take 1") |> render_click()
      {:ok, %{game: game}} = GameServer.get(id)
      assert Enum.any?(game.log, &match?({0, {:chip, {:buy, [{:green, 1}]}}}, &1))
      refute has_element?(view, @panel)
    end

    test "on a phone the panel folds to its title (the chevron)" do
      {_id, view, _game, _coins} = ghost_breath()

      assert has_element?(
               view,
               "#{@panel} button.lg\\:hidden[data-role=purple-buy-fold][aria-controls=purple-buy-1]"
             )

      css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
      assert css =~ ".pick-panel.pick-folded .pick-tiles"
      assert css =~ "position-anchor: --pot-area"
    end
  end

  describe "item 2: every seat's scoring ring moves with yours" do
    test "the hook takes every ring, and moves them on any update, after your chip's flight" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      [_, hook] = String.split(js, "const PotMotion", parts: 2)
      [hook, _] = String.split(hook, "const csrfToken", parts: 2)

      assert hook =~ ~s{querySelectorAll("[data-role=next-space], [data-role=scoring-ring]")}
      refute hook =~ "[data-role=scoring-ring][data-seat="
      # your flight sets the wait; any update moves the changed marks
      assert hook =~ "this.wait = 460"
      assert hook =~ "if (!newRound && !reduced()) this.scoringMove(this.wait)"
    end

    test "the bots' rings are on your pot, one per seat, each with its seat" do
      {:ok, id} = GameServer.start(3, {1, 2, 3})
      token = "r39-rings-#{System.unique_integer()}"
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      for _ <- 2..3, do: {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()
      view |> element("button[data-slot=draw]") |> render_click()

      for seat <- 0..2 do
        assert has_element?(
                 view,
                 "#pot-0-lg [data-space] [data-role=scoring-ring][data-seat='#{seat}']"
               )
      end
    end
  end

  defp chips_in(html, selector),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.to_list()
end
