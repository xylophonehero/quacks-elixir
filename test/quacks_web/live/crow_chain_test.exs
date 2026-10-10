defmodule QuacksWeb.CrowChainTest do
  @moduledoc """
  Round 42 (Nick: "blank spaces" in a crow skull chain): a crow skull placed from a
  crow skull offer starts a new offer. The new offer has new element ids, so the
  `.FromBag` hook mounts again and no chip keeps the old offer's fade-out.
  Scenario: `rule/crow-chain`.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}

  test "a crow skull placed from an offer shows its own offer under new ids", %{conn: conn} do
    conn = init_test_session(conn, player_token: "crow-chain")
    "/g/" <> id = conn |> get("/dev/scenarios/rule/crow-chain") |> redirected_to()
    {:ok, view, _html} = live(conn, "/g/#{id}")

    {:ok, %{game: g}} = GameServer.get(id)
    p = Game.player(g, 0)
    first = "#{g.round}-#{length(p.drawn)}"
    crow = Enum.find_index(p.pending, &match?({:blue, _}, &1))

    assert has_element?(view, "#bar-blue-#{first}")
    assert has_element?(view, "#crow-panel-#{first}")

    view |> element("#blue-chip-#{first}-#{crow}") |> render_click()

    {:ok, %{game: g}} = GameServer.get(id)
    p = Game.player(g, 0)
    assert p.phase == :blue_choice
    second = "#{g.round}-#{length(p.drawn)}"
    assert second != first

    refute has_element?(view, "#bar-blue-#{first}")
    refute has_element?(view, "#crow-panel-#{first}")

    for i <- 0..(length(p.pending) - 1) do
      assert has_element?(view, "#bar-blue-#{second} #blue-chip-#{second}-#{i}")
      assert has_element?(view, "#crow-panel-#{second} #crow-chip-#{second}-#{i}")
    end
  end
end
