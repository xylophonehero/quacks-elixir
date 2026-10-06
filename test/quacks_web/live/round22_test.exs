defmodule QuacksWeb.Round22Test do
  @moduledoc """
  Round 22: the pot's corners (the kept Toadstool chips top right, the fortune card
  top left), the new card over the pot, the rat track in equal steps, the final
  scoring in one overlay flow, and the Toadstool rows.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, rules)
    {:ok, view, _html} = live(browser("r22-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  defp red_choice(id, pending) do
    replace_game(id, fn g ->
      %{g | sets: Map.put(g.sets, :red, 2)} |> H.put(0, phase: :red_choice, pending: pending)
    end)
  end

  describe "the Toadstool rows" do
    test "one row per chip, three buttons each, one line of help" do
      {id, view} = solo()
      red_choice(id, [{:red, 1}, {:red, 2}])

      rows = "dialog#decision-red_choice [data-role=red-rows]"
      assert has_element?(view, "#{rows} #red-row-0 [data-role=red-chip][aria-label='red 1']")
      assert has_element?(view, "#{rows} #red-row-1 [data-role=red-chip][aria-label='red 2']")

      for i <- 0..1, kind <- ~w(place keep return) do
        assert has_element?(view, "#{rows} #red-row-#{i} button[data-role=red-#{kind}]")
      end

      # Place is the primary button; the three share the row equally.
      assert has_element?(view, "#{rows} #red-row-0 .grid-cols-3 button[data-role=red-place]")

      assert has_element?(
               view,
               "#{rows} #red-row-0 button[data-role=red-keep][class~='min-h-12']"
             )

      refute has_element?(view, "#{rows} [data-role=chip-pick]")
    end

    test "Keep puts the chip beside the pot" do
      {id, view} = solo()
      red_choice(id, [{:red, 2}])

      view |> element("#red-row-0 button[data-role=red-keep]") |> render_click()

      assert has_element?(
               view,
               "[data-role=pot-area] [data-role=beside-pot] [data-role=aside-chip]"
             )
    end
  end

  describe "the corner card" do
    test "the round's card sits in the pot's top left corner with its icon and name" do
      {id, view} = solo(%{})
      {:ok, %{game: game}} = GameServer.get(id)
      card = Quacks.Rules.Fortune.card(game.fortune_card)

      tile = "[data-role=pot-area] > [data-role=pot-corner] > #corner-card"
      assert has_element?(view, ~s(#{tile}[popovertarget="sheet-fortune"]), card.name)
      assert has_element?(view, "#{tile} [data-role=card-motif], #{tile} svg")
      refute has_element?(view, "header [data-role=fortune-tile]")
    end
  end
end
