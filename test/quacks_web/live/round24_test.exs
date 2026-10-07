defmodule QuacksWeb.Round24Test do
  @moduledoc """
  Round 24: a new card hovers over the pot with no sheet until a tap, a card's
  result or choice opens on that tap, the corner card grows back into the big card,
  the leader's VP on the rat track, the chip actions with every rung, and the
  install hint.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(rules \\ %{}) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, rules)
    {:ok, view, _html} = live(browser("r24-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  # A game with no cards, then a card turns up with `log` entries since it came.
  defp new_card(card, entries) do
    {id, view} = solo(%{fortune: false})

    replace_game(id, fn g ->
      %{g | fortune_card: card, log: entries ++ [{:fortune_drawn, card} | g.log]}
    end)

    {id, view}
  end

  describe "a plain card: no sheet, a tap dismisses it" do
    test "the card hovers with a caption; a tap shrinks it into the corner" do
      {id, view} = new_card(:b1, [])

      assert has_element?(view, "[data-role=pot-area] #pot-card-1.pot-card-reveal")
      assert has_element?(view, "#pot-card-1 [data-role=card-caption]", "Tap to continue")
      assert has_element?(view, "button#card-tap[phx-click=card_tap]")
      refute has_element?(view, "dialog#reveal-card-1")

      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "#pot-card-1")
      refute has_element?(view, "#card-tap")
      assert has_element?(view, "#corner-card")
      assert {:ok, %{seen: %{0 => %{card: 1}}}} = GameServer.get(id)
    end

    test "Enter dismisses it too" do
      {_id, view} = new_card(:b1, [])
      render_hook(view, "hotkey", %{"key" => "Enter", "typing" => false})
      refute has_element?(view, "#pot-card-1")
    end

    test "the caption fades after 2 s; it hides in the card transition" do
      css = File.read!("assets/css/app.css")
      assert css =~ "animation: card-caption-out 400ms ease-out 2s forwards;"
      assert css =~ "html:active-view-transition-type(card) .card-caption"
    end
  end

  describe "a card with a result or a choice" do
    test "the tap opens the result sheet; Continue shrinks the card" do
      {_id, view} = new_card(:p2, [{0, {:fortune, :p2, :droplet}}])

      refute has_element?(view, "dialog#reveal-card-1")
      view |> element("#card-tap") |> render_click()

      assert has_element?(view, "dialog#reveal-card-1.reveal-card-sheet")
      assert has_element?(view, "#reveal-card-1 [data-role=card-outcome]", "Droplet +1")
      assert has_element?(view, "#pot-card-1")
      refute has_element?(view, "#card-tap")

      view |> element("#reveal-next") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "#pot-card-1")
    end

    test "the tap opens the choice; the card stays over the pot until the choice" do
      {id, view} = solo(%{fortune: false})

      replace_game(id, fn g ->
        g |> H.put(fortune_card: :p1, phase: :fortune_choice) |> Map.put(:phase, :fortune_choice)
      end)

      assert has_element?(view, "dialog#card-round-1")
      refute has_element?(view, "dialog#card-round-1[phx-mounted*='quacks:modal']")
      assert has_element?(view, "#pot-card-1 [data-role=card-caption]")

      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:open", %{to: "#card-round-1"})
      assert has_element?(view, "#pot-card-1")
      refute has_element?(view, "#pot-card-1 [data-role=card-caption]")
      assert {:ok, %{seen: %{0 => %{card: 1}}}} = GameServer.get(id)
    end

    test "a card that draws chips keeps its dialog after the tap, the card in it" do
      {id, view} = solo(%{fortune: false})

      replace_game(id, fn g ->
        g
        |> H.put(fortune_card: :p13, phase: :fortune_choice, pending: [{:green, 1}])
        |> Map.put(:phase, :fortune_choice)
      end)

      assert has_element?(view, "#pot-card-1")
      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:open", %{to: "#card-round-1"})
      refute has_element?(view, "#pot-card-1")
      assert has_element?(view, "#card-round-1 [data-role=fortune-card]")
    end
  end

  describe "the corner card grows back" do
    test "a tap on the corner card grows it; a tap shrinks it again" do
      {_id, view} = new_card(:b1, [])
      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})

      view |> element("#corner-card") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      assert has_element?(view, "#pot-card-1.pot-card-reveal [data-role=card-caption]")
      refute has_element?(view, "#reveal-card-1")

      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "#pot-card-1")
    end

    test "the card's text stays in the menu" do
      {_id, view} = new_card(:b1, [])
      refute has_element?(view, "#corner-card[popovertarget]")

      assert has_element?(
               view,
               "#sheet-menu [data-role=menu-fortune][popovertarget=sheet-fortune]"
             )

      assert has_element?(view, "#sheet-fortune [data-role=fortune-card]")
    end
  end
end
