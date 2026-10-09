defmodule QuacksWeb.Round30BarTest do
  @moduledoc """
  Round 30 (bar + pot): Continue in the contextual button area while the round's
  card waits over the pot, a reward row that keeps the ruby's slot, fixed number
  widths, and one red explosion icon in the bar and on the tiles.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, rules)
    {:ok, view, _html} = live(browser("r30-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  defp new_card(card) do
    {id, view} = solo()

    replace_game(id, fn g ->
      %{g | fortune_card: card, log: [{:fortune_drawn, card} | g.log]}
    end)

    {id, view}
  end

  describe "Continue while the card hovers" do
    test "one Continue takes the place of Stop and Draw; it dismisses the card" do
      {_id, view} = new_card(:b1)

      assert has_element?(view, "button#card-continue[phx-click=card_tap]", "Continue")
      assert has_element?(view, "[data-role=action-bar].hidden")

      view |> element("#card-continue") |> render_click()
      refute has_element?(view, "#pot-card-1")
      refute has_element?(view, "#card-continue")
      refute has_element?(view, "[data-role=action-bar].hidden")
      assert has_element?(view, "[data-role=action-bar] [data-slot=draw]")
    end

    test "the grown corner card shows Continue too; Continue shrinks it" do
      {_id, view} = new_card(:b1)
      view |> element("#card-continue") |> render_click()

      view |> element("#corner-card") |> render_click()
      assert has_element?(view, "#card-continue")
      assert has_element?(view, "[data-role=action-bar].hidden")

      view |> element("#card-continue") |> render_click()
      refute has_element?(view, "#card-continue")
      refute has_element?(view, "[data-role=action-bar].hidden")
    end

    test "Enter does the same" do
      {_id, view} = new_card(:b1)
      render_hook(view, "hotkey", %{"key" => "Enter", "typing" => false})
      refute has_element?(view, "#card-continue")
      refute has_element?(view, "[data-role=action-bar].hidden")
    end
  end
end
