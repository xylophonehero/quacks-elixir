defmodule QuacksWeb.CopperUpgradeLiveTest do
  @moduledoc """
  Round 45 (Nick): the copper witch C1 "Upgrade" has her own step before the shop.
  The pot chips are in view: the chips she can upgrade glow, a tap upgrades one,
  Skip keeps the penny. Then the shop opens.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import QuacksWeb.RevealHelpers
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H

  alias Quacks.{Game, GameServer}

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "c1-#{System.unique_integer()}")}
  end

  # A solo game with the copper witch C1, at her step: `drawn` in the pot (newest first).
  defp at_upgrade(conn, drawn) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")

    replace_game(id, fn g ->
      %{g | witches: %{g.witches | copper: :c1}}
      |> H.put(0, phase: :upgrade, drawn: drawn, rubies: 0, coins: 10)
    end)

    {id, skip_results(view)}
  end

  defp game(id), do: elem(GameServer.get(id), 1).game

  test "the step shows the pot: the chips C1 can upgrade glow; no shop yet", %{conn: conn} do
    {_id, view} = at_upgrade(conn, [{{:orange, 1}, 6}, {{:green, 1}, 3}, {{:blue, 1}, 1}])

    assert has_element?(view, "[data-role=bar-upgrade] [data-role=tap-pot]")
    assert has_element?(view, "[data-role=upgrade-skip]", "keep the penny")
    refute has_element?(view, "#decision-shop")
    refute has_element?(view, "[data-role=pot-area] svg[data-bagged]")

    targets = "[data-role=pot-area] [data-role=pot-chip][data-target]"
    assert has_element?(view, targets <> "[aria-label='Copper witch: upgrade green 1']")
    assert has_element?(view, targets <> "[aria-label='Copper witch: upgrade blue 1']")
    refute has_element?(view, targets <> "[aria-label^='orange']")
  end

  test "a tap upgrades the chip: the pot shows the bigger chip, then the shop opens", %{
    conn: conn
  } do
    {id, view} = at_upgrade(conn, [{{:orange, 1}, 6}, {{:green, 1}, 3}, {{:blue, 1}, 1}])

    html =
      view
      |> element("[data-role=pot-chip][aria-label='Copper witch: upgrade green 1']")
      |> render_click()

    # The moment: the pot keeps its chips, the green 1 is a green 2.
    doc = LazyHTML.from_fragment(html)
    assert [_] = doc |> LazyHTML.query("[data-role=pot-chip][data-grow]") |> Enum.to_list()
    assert html =~ ~s(data-role="upgraded")

    # The same chip node is now a green 2 (`PotMotion` morphs it, with its sound).
    assert [chip] = doc |> LazyHTML.query("[data-grow]") |> LazyHTML.attribute("data-chip")
    assert chip == "green-2"

    g = game(id)
    assert {:green, 2} in g.players[0].bag and Game.phase(g, 0) == :shop
    refute g.players[0].pennies.copper

    # Then the shop (`upgrade_ms` is 0 in the tests).
    render(view)
    assert has_element?(view, "#decision-shop")
    refute has_element?(view, "[data-role=bar-upgrade]")
  end

  test "the last 2 chips: a tap on one of them asks, this chip or the last 2", %{conn: conn} do
    {id, view} = at_upgrade(conn, [{{:red, 1}, 6}, {{:green, 1}, 3}, {{:orange, 1}, 1}])

    view
    |> element("[data-role=pot-chip][aria-label='red 1: upgrade it, or the last 2 chips']")
    |> render_click()

    assert has_element?(view, "[data-role=pot-picked]", "red 1")
    assert has_element?(view, "[data-role=upgrade-option][data-choice=one]")
    assert has_element?(view, "[data-role=pot-pick-back]")

    view |> element("[data-role=upgrade-option][data-choice=last-two]") |> render_click()

    bag = game(id).players[0].bag
    assert {:red, 2} in bag and {:green, 2} in bag
  end

  test "Skip keeps the penny and opens the shop", %{conn: conn} do
    {id, view} = at_upgrade(conn, [{{:green, 1}, 3}, {{:orange, 1}, 1}])
    view |> element("[data-role=upgrade-skip]") |> render_click()

    g = game(id)
    assert Game.phase(g, 0) == :shop and g.players[0].pennies.copper
    assert has_element?(view, "#decision-shop")
  end
end
