defmodule QuacksWeb.ExplosionWitchTest do
  @moduledoc """
  Round 42 (Nick): the silver witch "No explosion penalty" (S4) is in the explosion's
  choice bar, next to VP and coins. Calling her applies her effect and removes the
  choice. Scenario: `witch/silver/s4` (step "call").
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}

  test "an exploded seat with the silver witch S4 calls her from the explosion bar",
       %{conn: conn} do
    conn = init_test_session(conn, player_token: "explosion-witch")
    "/g/" <> id = conn |> get("/dev/scenarios/witch/silver/s4") |> redirected_to()
    {:ok, view, _html} = live(conn, "/g/#{id}")

    assert has_element?(view, "[data-role=bar-explosion] [data-choice=vp]")
    assert has_element?(view, "[data-role=bar-explosion] [data-choice=buy]")
    view |> element("[data-role=bar-explosion] [data-role=explosion-witch]") |> render_click()

    {:ok, %{game: g}} = GameServer.get(id)
    assert Game.player(g, 0).explosion_choice == :witch
    assert Enum.any?(g.log, &match?({0, {:witch, :s4, :no_penalty}}, &1))
    refute has_element?(view, "[data-role=bar-explosion]")
  end
end
