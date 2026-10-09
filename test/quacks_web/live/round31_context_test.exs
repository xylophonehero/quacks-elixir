defmodule QuacksWeb.Round31ContextTest do
  @moduledoc """
  Round 31 (context): the rubies step shows only when a ruby buys something, and
  never in round 9; a card without a choice says what it did in a toast.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameServer
  alias Quacks.GameHelpers, as: H

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp duo(rules \\ %{}) do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, Map.merge(%{fortune: false}, rules))
    {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
    {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
    alice |> element("button", "Start game") |> render_click()
    {id, alice}
  end

  # Seat 0 at its rubies step (the buy done) in `round`, after the evaluation.
  defp rubies_step(id, alice, round, fields) do
    replace_game(id, &(&1 |> H.put(round: round) |> H.put(0, [phase: :rubies] ++ fields)))
    render_hook(alice, "seen", %{"kind" => "results", "round" => round})
  end

  test "rounds 1 to 8: the rubies step shows with enough rubies" do
    {id, alice} = duo()
    rubies_step(id, alice, 4, rubies: 2, flask: false)
    assert has_element?(alice, "#bar-rubies button[data-ruby=droplet]:not([disabled])")
    assert has_element?(alice, "#bar-rubies button[data-ruby=flask]:not([disabled])")
  end

  test "rounds 1 to 8: too few rubies, no step: the seat's round ends by itself" do
    {id, alice} = duo()
    rubies_step(id, alice, 4, rubies: 1)
    refute has_element?(alice, "#bar-rubies")
    {:ok, %{game: game}} = GameServer.get(id)
    assert game.players[0].phase == :ready
  end

  test "the reverse pot side offers the test tube in the step" do
    {id, alice} = duo(%{pot_side: :back})
    rubies_step(id, alice, 4, rubies: 2)
    assert has_element?(alice, "#bar-rubies button[data-ruby=tube]:not([disabled])")
  end

  test "round 9: no rubies step; the rubies turn into VP at the seat's end" do
    {id, alice} = duo()
    rubies_step(id, alice, 9, rubies: 4, coins: 0)
    refute has_element?(alice, "#bar-rubies")
    {:ok, %{game: game}} = GameServer.get(id)
    assert %{rubies: 0, phase: :ready} = game.players[0]
  end
end
