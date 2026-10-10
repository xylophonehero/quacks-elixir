defmodule QuacksWeb.Round37EngineTest do
  @moduledoc """
  Round 37 (engine): the gold witch "Cheap rubies" (G4) in the rubies step (item 11)
  and the test tube in round 9 (item 12).
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp open(id) do
    conn = init_test_session(build_conn(), player_token: "solo-#{System.unique_integer()}")
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp solo(rules, expansion \\ nil) do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, Map.put(rules, :fortune, false), expansion)
    {id, open(id)}
  end

  test "G4: the rubies step offers the witch; then each use costs 1 ruby" do
    {id, view} = solo(%{}, :herb_witches)

    replace_game(id, fn g ->
      %{g | witches: %{g.witches | gold: :g4}}
      |> H.put(phase: :rubies, rubies: 1, flask: false)
    end)

    # 1 ruby: the uses wait for the witch, and say so
    assert has_element?(view, "#bar-rubies [data-role=rubies-witch]")
    assert has_element?(view, "#bar-rubies button[data-ruby=droplet][disabled]", "Witch: 1 ruby")

    view |> element("#bar-rubies [data-role=rubies-witch]") |> render_click()

    refute has_element?(view, "#bar-rubies [data-role=rubies-witch]")

    view
    |> element(~s(#bar-rubies button[data-ruby=droplet][aria-label="Spend 1 ruby: droplet +1"]))
    |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    # nothing left to spend: the round ended after the move
    assert %{rubies: 0, droplet: 1} = game.players[0]
    assert {0, {:witch, :g4, :ruby_price}} in game.log
    assert {0, {:rubies_spent, :droplet, 1}} in game.log
  end

  test "round 9 on the reverse side: a glass beside 2 rubies -> 1 VP" do
    {id, view} = solo(%{pot_side: :back})
    replace_game(id, &H.put(&1, round: 9, phase: :rubies, rubies: 3, tube: 3))

    assert has_element?(view, "#bar-rubies button[data-ruby=vp]", "1 VP")
    refute has_element?(view, "#bar-rubies button[data-ruby=flask]")

    view |> element("#bar-rubies button[data-ruby=tube]") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    assert %{rubies: 1, tube: 4, vp: 2} = game.players[0]
  end
end
