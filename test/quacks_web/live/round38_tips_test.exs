defmodule QuacksWeb.Round38TipsTest do
  @moduledoc """
  Round 38: the first-time hints (tour design T2). A hint shows once its browser
  sent its seen hints; "Got it", a Draw or a tap on the lit area closes it, "No
  more tips" and the menu turn them off, "Show again" brings them back.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  defp browser(token), do: init_test_session(build_conn(), player_token: token)

  defp solo(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, rules)
    {:ok, view, _html} = live(browser("solo-#{id}"), ~p"/g/#{id}")
    view
  end

  # What the `RevealSettings` hook sends on mount, with this browser's tips.
  defp settings(view, tips) do
    render_hook(view, "reveal_settings", %{
      "mode" => "step",
      "speed" => "normal",
      "show" => "tiles",
      "tips" => tips
    })
  end

  defp fresh(view), do: settings(view, %{"v" => 1, "seen" => [], "off" => false})

  defp tip(view, key), do: has_element?(view, "[data-role=tip][data-tip=#{key}]")

  test "no hint before the browser sent its tips" do
    view = solo()
    refute has_element?(view, "[data-role=tip]")
    refute has_element?(view, "#game[data-tip]")
  end

  test "the first brew: a chain of 3 hints, each with its ring" do
    view = solo()
    fresh(view)

    assert tip(view, "brew")
    assert has_element?(view, "#game[data-tip=brew]")
    assert has_element?(view, "[data-role=tip-label]", "1 of 3")
    view |> element("[data-role=tip-done]", "Next tip") |> render_click()
    assert_push_event(view, "quacks:tips", %{v: 1, seen: ["brew"], off: false})

    assert tip(view, "bag")
    view |> element("[data-role=tip-done]", "Next tip") |> render_click()

    assert tip(view, "players")

    assert has_element?(
             view,
             "[data-role=tip-text]",
             "These are the players. Each tile shows their score and how their brew is going. Tap a tile for more."
           )

    view |> element("[data-role=tip-done]", "Got it") |> render_click()
    assert_push_event(view, "quacks:tips", %{seen: ["bag", "brew", "players"]})
    refute has_element?(view, "[data-role=tip]")
    refute has_element?(view, "#game[data-tip]")
  end

  test "a Draw closes the hint on show" do
    view = solo()
    fresh(view)
    view |> element("button[data-slot=draw]") |> render_click()
    assert_push_event(view, "quacks:tips", %{seen: ["brew"]})
    assert tip(view, "bag")
  end

  test "a tap on the bag closes the bag hint" do
    view = solo()
    settings(view, %{"v" => 1, "seen" => ["brew"], "off" => false})
    view |> element("[data-role=bag-button]") |> render_click()
    assert_push_event(view, "quacks:tips", %{seen: ["bag", "brew"]})
    assert tip(view, "players")
  end

  test "seen hints stay closed after a reload" do
    view = solo()
    settings(view, %{"v" => 1, "seen" => ["brew", "bag", "players"], "off" => false})
    refute has_element?(view, "[data-role=tip]")
  end

  test "No more tips turns every hint off; the menu turns them on again" do
    view = solo()
    fresh(view)
    view |> element("[data-role=tip-off]") |> render_click()
    assert_push_event(view, "quacks:tips", %{off: true})
    refute has_element?(view, "[data-role=tip]")
    assert has_element?(view, "#tips-off[checked]")

    view |> form("#tips-settings", %{"tips" => "on"}) |> render_change()
    assert_push_event(view, "quacks:tips", %{off: false})
    assert tip(view, "brew")
  end

  test "the menu's Off, then Show again clears the seen hints" do
    view = solo()
    settings(view, %{"v" => 1, "seen" => ["brew", "bag"], "off" => false})
    assert tip(view, "players")

    view |> form("#tips-settings", %{"tips" => "off"}) |> render_change()
    refute has_element?(view, "[data-role=tip]")

    view |> element("[data-role=tips-again]") |> render_click()
    assert_push_event(view, "quacks:tips", %{v: 1, seen: [], off: false})
    assert tip(view, "brew")
  end

  test "the first fortune card: the hint takes Continue's place, Got it goes on" do
    view = solo(%{})
    fresh(view)

    assert tip(view, "card")
    refute has_element?(view, "#card-continue")
    view |> element("[data-role=tip-done]", "Got it") |> render_click()

    refute has_element?(view, "[data-role=pot-card]")
    assert tip(view, "brew")
  end

  test "a spectator gets no hints" do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false})
    {:ok, _player, _html} = live(browser("solo-#{id}"), ~p"/g/#{id}")
    {:ok, watcher, _html} = live(browser("watch-#{id}"), ~p"/g/#{id}")
    fresh(watcher)
    refute has_element?(watcher, "[data-role=tip]")
  end

  test "the first scoring: the hint over the pot on step 1, Next closes it, then the shop's" do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
    {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
    settings(alice, %{"v" => 1, "seen" => ["brew", "bag", "players", "risk"], "off" => false})
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    for _ <- 1..2, seat <- [0, 1], do: GameServer.apply(id, seat, :draw)
    for seat <- [0, 1], do: GameServer.apply(id, seat, :stop)

    assert tip(alice, "scoring")
    assert has_element?(alice, "[data-role=pot-area] [data-role=tip]")
    assert has_element?(alice, "#game[data-tip=scoring] [data-role=results-stage]")

    alice |> element("[data-role=tile-next]") |> render_click()
    assert_push_event(alice, "quacks:tips", %{seen: seen})
    assert "scoring" in seen
    refute tip(alice, "scoring")

    # The other steps, to the shop.
    for _ <- 1..10, has_element?(alice, "[data-role=tile-next]") do
      alice |> element("[data-role=tile-next]") |> render_click()
    end

    assert tip(alice, "shop")
    assert has_element?(alice, "#game[data-tip=shop] [data-role=shop-footer]")
  end
end
