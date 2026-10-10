defmodule QuacksWeb.VisualDetailsTest do
  @moduledoc """
  Small visual rules of the game page: button variants, the seat colour edge, the menu and witches buttons, the flask glow, focus on open, dialog glitches and phone sizes.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.{Game, GameHelpers, GameServer}
  alias Quacks.{Game, GameServer}
  alias Quacks.{Game, GameServer}
  alias QuacksWeb.{AlchemistsComponents, PanelComponents}
  alias QuacksWeb.{AlchemistsComponents, PanelComponents}
  alias QuacksWeb.CoreComponents
  alias QuacksWeb.PanelComponents
  alias QuacksWeb.PanelComponents

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  # Draw until the explosion choice opens (the starting bag holds 14 white points).

  test "button variants: primary gold, secondary parchment, ghost text, default for the table" do
    render = fn variant ->
      render_component(&CoreComponents.button/1,
        variant: variant,
        inner_block: [%{inner_block: fn _, _ -> "Go" end}]
      )
    end

    assert render.(:primary) =~ "bg-gold"
    assert render.(:secondary) =~ "bg-parchment-light"
    assert render.(:secondary) =~ "ring-ink/25"
    refute render.(:ghost) =~ "bg-gold"
    assert render.(:ghost) =~ "hover:underline"
    assert render.(nil) =~ "ring-parchment/45"

    for variant <- [nil, :primary, :secondary, :ghost] do
      html = render.(variant)
      assert html =~ "active:scale-[.98]"
      assert html =~ "focus-visible:outline-droplet"
      assert html =~ "disabled:saturate-[.3]"
    end
  end

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.
  defp to_shop(id) do
    Enum.find_value(1..60, fn _ ->
      game = game(id)
      actions = Game.legal_actions(game, 0)

      if game.phase == :shopping do
        GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, coins: 30))
      else
        action =
          Enum.find([:stop, :chip_done, {:explosion_choice, :buy}], hd(actions), &(&1 in actions))

        {:ok, _} = GameServer.apply(id, 0, action)
        nil
      end
    end)
  end

  defp shop_view do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("shopper-#{id}"), ~p"/g/#{id}")
    to_shop(id)
    render(view)
    view
  end

  describe "focus on open" do
    test "every dialog has exactly one autofocus target" do
      view = shop_view()
      html = render(view)
      dialogs = html |> query("dialog") |> LazyHTML.attribute("id")
      assert "decision-shop" in dialogs

      for id <- dialogs do
        assert count(html, "dialog##{id} [autofocus]") == 1, "#{id} has not one autofocus"
      end
    end

    test "the shop opens on its focus target (Buy is disabled)" do
      view = shop_view()
      assert has_element?(view, "#decision-shop [data-role=focus-start][autofocus]")
      refute has_element?(view, "#decision-shop button[autofocus]")
    end

    test "with a witch call but no ruby options, Done is primary and takes the focus" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
      {:ok, view, _html} = live(browser("rubies-#{id}"), ~p"/g/#{id}")
      to_shop(id)
      GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, rubies: 0))
      {:ok, _} = GameServer.apply(id, 0, {:buy, []})
      render(view)

      assert has_element?(view, "#decision-rubies button[data-role=rubies-done][autofocus]")
      refute has_element?(view, "#decision-rubies [data-role=focus-start]")
    end
  end

  describe "the bar, the seat edge and the corner buttons" do
    test "the bar has no Stop/Draw while everyone shops; the side column is marked" do
      {:ok, id} = GameServer.start(1, {10, 11, 12})
      view = open(browser("bar-#{System.unique_integer()}"), id)
      assert has_element?(view, "[data-role=action-bar]")
      assert has_element?(view, "aside[data-role=side-column]")
      for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
      view |> element("button", "Stop") |> render_click()
      refute has_element?(view, "[data-role=action-bar]")
    end

    test "the seat colour edge runs over both columns on large screens" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      alice = open(browser("edge-a"), id)
      _bob = open(browser("edge-b"), id)
      {:ok, _} = GameServer.begin(id, "edge-a")
      # Round 11: one grid for the page, so one edge spans every column.
      assert has_element?(alice, "#game[data-role=my-seat].border-t-4.border-player-0")
    end

    test "the menu's sheet buttons are parchment like their neighbours" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      view = open(browser("menu-#{System.unique_integer()}"), id)

      assert has_element?(
               view,
               "#sheet-menu button[popovertarget=sheet-books].bg-parchment-light"
             )

      refute has_element?(view, "#sheet-menu button[popovertarget=sheet-books].bg-iron-dark")
    end

    test "the witches button is a small tile in the pot's corner" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{}, :herb_witches)
      view = open(browser("witch-#{System.unique_integer()}"), id)
      # round 22: below the card, in the corner stack
      assert has_element?(
               view,
               "[data-role=pot-corner].top-0.left-0 [data-role=witches-button].flex-col",
               "Witches"
             )
    end

    # Round 11: no hint line (it moved the pot); the flask's SVG <title> says it.
    test "a usable flask glows, with no hint line" do
      {:ok, id} = GameServer.start(1, {10, 11, 12})
      view = open(browser("flask-#{System.unique_integer()}"), id)
      view |> element("button[data-slot=draw]") |> render_click()
      refute has_element?(view, "[data-role=flask-hint]")
      assert has_element?(view, "[data-role=pot-area] [data-role=flask] title")
    end
  end

  # Take a seat from a page that closes at once (a browser that lost its cookie
  # afterwards): the seat stays, but no page holds it.

  describe "dialogs, locks and seals" do
    test "the decision button hides while a dialog is open" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      view = open(browser(token("g1")), id)
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 30))
      skip_results(view)

      assert has_element?(
               view,
               "[data-role=decision-button][class*='[body:has(dialog[open])_&]:invisible']"
             )
    end

    test "a locked shop tile has the lock, and its price is struck through" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      view = open(browser(token("g2")), id)
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 30))

      assert has_element?(view, "#shop label.shop-locked [data-role=tile-lock]")
      assert has_element?(view, "#shop label.shop-locked [data-role=price]")

      css = File.read!("assets/css/app.css")
      assert css =~ ~s(.shop-locked > [data-role="price"] {\n  text-decoration: line-through;)
    end

    test "a glass VP bonus is the laurel seal, not a coin" do
      html = render_component(&AlchemistsComponents.slot_grid/1, id: :carrot_nose, reached: 7)

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s(li[data-space="7"] [data-glyph=vp] use[href="#icon-vp"]))
             |> Enum.count() == 1
    end
  end

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    alice = open(browser(token("alice")), id)
    bob = open(browser(token("bob")), id)
    alice |> element("button", "Start game") |> render_click()
    {id, alice, bob}
  end

  describe "phone sizes, pills and badges" do
    test "the phone pot sits in the middle of its box (equal bands)" do
      css = File.read!("assets/css/app.css")
      assert css =~ "margin-top: calc((100cqh - 100cqmin) / 2);"
    end

    test "the card tile left the header for the pot's top left corner" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      view = open(browser(token("g6")), id)

      refute has_element?(view, "header [data-role=fortune-tile]")
      assert has_element?(view, "[data-role=pot-area] [data-role=pot-corner] #corner-card")
    end

    test "the YOU pill does not shrink; the phase pill may" do
      {_id, alice, _bob} = duo()
      assert has_element?(alice, "[data-role=you-are].shrink-0")
      refute has_element?(alice, "[data-role=you-are].min-w-0")
      assert has_element?(alice, "header dd.truncate")
    end

    test "the state badge sits beside the initial; a bot is an icon on phones" do
      {:ok, id} = GameServer.start(3, {1, 2, 3}, %{}, %{fortune: false})
      alice = token("alice")
      view = open(browser(alice), id)
      # Round 36: a second human still brews, so the bot has not brewed yet.
      {:ok, 1} = GameServer.claim_seat(id, "bob")
      {:ok, _} = GameServer.add_bot(id, alice)
      view |> element("button", "Start game") |> render_click()

      # Round 27: on the tile's top right corner, once the seat stops.
      {:ok, _} = GameServer.apply(id, 0, :draw)
      {:ok, _} = GameServer.apply(id, 0, :stop)
      assert has_element?(view, "[data-role=player-chip] [data-role=player-state].-right-1\\.5")

      # Round 28: the bot is a small icon on the seat disc, "bot" is in the name.
      assert has_element?(
               view,
               "[data-role=player-chip] [data-role=bot-badge].hero-cpu-chip-micro"
             )

      assert has_element?(view, "[data-role=player-chip] [data-role=player-name].sr-only", "bot")
    end

    # Round 11: the legend went; the name cards carry the colours.
    test "no ring legend under the pot" do
      {_id, alice, _bob} = duo()
      refute has_element?(alice, "[data-role=ring-legend]")
    end
  end

  test "the card tile is small on phones" do
    html = render_component(&PanelComponents.fortune_tile/1, id: :b3)
    assert html =~ "w-12"
    assert html =~ "lg:w-20"
  end
end
