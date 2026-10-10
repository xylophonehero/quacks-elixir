defmodule QuacksWeb.QaFixesTest do
  @moduledoc """
  The QA pass of 2026-10-04 (`docs/research/qa-2026-10-04.md`): reloads keep the
  closed card and results closed (B2, B3), the rename survives a colour tap (B4),
  the host passes on (B5), white picks warn (B6), the rubies wait for the results
  (B7), and the visual and text fixes.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers, as: H
  alias QuacksWeb.{BarComponents, GameText, PanelComponents}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp auto_open?(view, dialog),
    do: has_element?(view, "dialog#{dialog}[phx-mounted*='quacks:modal']")

  describe "B2/B3: a reload keeps what the seat closed" do
    test "the round's card opens once; after it closed, a reload leaves it closed" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      token = "card-#{System.unique_integer()}"
      view = open(browser(token), id)

      # round 24: the card hovers over the pot until a tap
      assert has_element?(view, "#pot-card-1 [data-role=card-caption]")

      view |> element("#card-tap") |> render_click()
      assert {:ok, %{seen: %{0 => %{card: 1}}}} = GameServer.get(id)

      reloaded = open(browser(token), id)
      refute has_element?(reloaded, "#pot-card-1")
      refute has_element?(reloaded, "#card-tap")
    end

    test "the replay plays once; after that, a reload opens the shop" do
      {:ok, id} = GameServer.start(1, {10, 11, 12})
      token = "results-#{System.unique_integer()}"
      view = open(browser(token), id)
      for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
      view |> element("button", "Stop") |> render_click()

      assert has_element?(view, "dialog#reveal-results-1")
      refute has_element?(view, "#players-row.replay-done")
      refute auto_open?(view, "#decision-shop")

      render_hook(view, "seen", %{"kind" => "results", "round" => 1})

      reloaded = open(browser(token), id)
      refute has_element?(reloaded, "dialog#reveal-results-1")
      assert has_element?(reloaded, "#players-row.replay-done")
      refute has_element?(reloaded, "[data-role=replay-timer]")
      assert auto_open?(reloaded, "#decision-shop")
    end

    test "a stale or foreign 'seen' does nothing" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      view = open(browser("stale-#{System.unique_integer()}"), id)
      render_hook(view, "seen", %{"kind" => "bogus", "round" => 1})
      render_hook(view, "seen", %{"kind" => "card", "round" => "1"})
      assert {:ok, %{seen: seen}} = GameServer.get(id)
      assert seen == %{}
    end
  end

  test "B7: the rubies step waits for the round results to close" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("rubies-#{System.unique_integer()}"), id)

    replace_game(
      id,
      &H.put(&1, 0, phase: :shop, exploded?: true, explosion_choice: :vp, rubies: 2)
    )

    assert has_element?(view, "dialog#reveal-results-1")
    # Round 29: the rubies wait in the bar, under the results.
    assert has_element?(view, "#bar-rubies")
    refute has_element?(view, "dialog#decision-rubies")
  end

  describe "B4/B5: the configure screen" do
    test "the name goes on blur and with a colour tap, so a fast tap keeps both" do
      {:ok, id} = GameServer.start(2)
      alice = open(browser("alice-#{System.unique_integer()}"), id)

      assert has_element?(alice, "#seat-name[phx-debounce=blur][phx-hook=NameMemory]")

      swatch = ~s([data-role=colour-picker] button[data-colour="5"])
      assert has_element?(alice, "#{swatch}[phx-click*='#rename-form']")

      alice |> form("#rename-form", name: "Zed") |> render_submit()
      alice |> element(swatch) |> render_click()

      {:ok, table} = GameServer.get(id)
      assert table.names[0] == "Zed" and table.colours[0] == 5
    end

    test "when the host leaves, the next seat is host with full controls" do
      {:ok, id} = GameServer.start(3)
      host = open(browser("alice-#{System.unique_integer()}"), id)
      bob = open(browser("bob-#{System.unique_integer()}"), id)

      # Round 26: the waiting panel; only the host may fill the seats.
      refute has_element?(bob, "[data-role=fill-bots]")
      assert has_element?(bob, "[data-role=waiting-for-host]")

      # the host's page closes (its seat is freed in `terminate/2`)
      ref = Process.monitor(host.pid)
      GenServer.stop(host.pid)
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}

      assert render(bob) =~ "You are now the host."
      assert has_element?(bob, "[data-role=fill-bots]")
      assert has_element?(bob, ~s([data-seat="1"]), "host")
      refute has_element?(bob, "[data-role=waiting-for-host]")
    end
  end

  describe "B6: a white pick that takes the pot over the limit" do
    defp picks_html(game, actions, pool) do
      render_component(&BarComponents.chip_picks/1,
        actions: actions,
        pool: pool,
        game: game,
        me: game.players[0]
      )
    end

    test "the crow skull warns 'explodes!' on that chip only" do
      game =
        Game.new(seed: {1, 2, 3}, fortune: false)
        |> H.put(drawn: [{{:white, 3}, 3}, {{:white, 2}, 5}])

      html =
        picks_html(game, [{:place, {:white, 3}}, {:place, {:white, 1}}], [
          {:white, 3},
          {:white, 1}
        ])

      doc = LazyHTML.from_fragment(html)
      assert [warning] = Enum.to_list(LazyHTML.query(doc, "[data-role=explode-warning]"))
      assert LazyHTML.text(warning) =~ "explodes!"
      assert html =~ ~s(data-over="explodes")
      assert html =~ "Crow skull: place white 3: explodes the pot"
      # the safe chip says what a tap does
      assert LazyHTML.text(LazyHTML.query(doc, "[data-role=pick-verb]")) =~ "Place"
    end

    test "Safety Procedure says the chip goes over the limit but cannot explode" do
      game =
        Game.new(seed: {1, 2, 3}, fortune: false)
        |> H.put(fortune_card: :b7, drawn: [{{:white, 3}, 3}, {{:white, 2}, 5}])

      html =
        picks_html(game, [{:fortune, {:place, {:white, 3}}}, {:fortune, :return_all}], [
          {:white, 3}
        ])

      assert html =~ "over 7, safe"
      assert html =~ ~s(data-over="safe")
      refute html =~ "explodes!"
    end
  end

  describe "visual fixes" do
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

  describe "text" do
    test "the game-over breakdown names witches, cards and pennies" do
      log = [
        {0, {:witch, :g1, {:vp, 4}}},
        {0, {:fortune, :p6, {:vp, 4}}},
        {0, {:pennies, 2}},
        {0, {:pot_vp, 3, 12}}
      ]

      assert GameText.vp_breakdown(log, 0, 14) ==
               [brewing: 3, witches: 4, cards: 4, pennies: 2, other: 1]

      assert GameText.vp_part_name(:pennies) == "Unused pennies"
      assert GameText.vp_part_hint(:other) =~ "no other part"
    end

    test "Second Chances logs the chips it put back; Stop and Stopped are one line" do
      log = [
        {0, {:fortune, :b3, {:drew, [{:white, 1}, {:green, 1}]}}},
        {1, :stopped},
        {1, :stop},
        {0, :stop}
      ]

      html =
        render_component(&PanelComponents.action_log/1, log: log, names: %{0 => "A", 1 => "B"})

      assert html =~ "Second Chances: put back white 1, green 1"
      assert length(String.split(html, "B: Stopped<")) == 2
      assert html =~ "A: Stopped<"
    end
  end
end
