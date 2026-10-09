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

  defp solo(rules) do
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
      assert css =~ "card-caption-in 300ms ease-out 800ms both,"
      assert css =~ "card-caption-out 400ms ease-out 2800ms forwards;"
      assert css =~ "html:active-view-transition-type(card) .card-caption"
    end
  end

  describe "a card with a result or a choice" do
    # Round 31: no result sheet; the card shrinks and a toast says what it did.
    test "the tap shrinks the card; a toast says what it did" do
      {_id, view} = new_card(:p2, [{0, {:fortune, :p2, :droplet}}])

      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "dialog#reveal-card-1")
      refute has_element?(view, "#pot-card-1")
      assert has_element?(view, "#card-toast-1", "Drop It: Droplet +1")
    end

    # Round 31: the choice is in the bar at once, the card over the pot.
    test "the choice is in the bar; the card stays over the pot until the choice" do
      {id, view} = solo(%{fortune: false})

      replace_game(id, fn g ->
        g |> H.put(fortune_card: :p1, phase: :fortune_choice) |> Map.put(:phase, :fortune_choice)
      end)

      refute has_element?(view, "dialog#card-round-1")
      refute has_element?(view, "#card-tap")
      assert has_element?(view, "#pot-card-1")
      # Round 35: the ruby with its 3 in the chip row.
      assert has_element?(view, "#bar-card-1 [data-choice=rubies]", "3")

      view |> element("#bar-card-1 [data-choice=rubies]") |> render_click()
      # Round 35: the card stays, grown, with what everyone took; Continue shrinks it.
      assert has_element?(view, "#card-stage-1[data-role=card-stage]")
      view |> element("#card-continue") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "#pot-card-1")
      assert {:ok, %{seen: %{0 => %{card: 1}}}} = GameServer.get(id)
    end

    test "a card that draws chips: the card stays over the pot, the trade in the bar" do
      {id, view} = solo(%{fortune: false})

      replace_game(id, fn g ->
        g
        |> H.put(fortune_card: :p13, phase: :fortune_choice, pending: [{:green, 1}])
        |> Map.put(:phase, :fortune_choice)
      end)

      assert has_element?(view, "#pot-card-1")
      refute has_element?(view, "#card-tap")
      assert has_element?(view, "#bar-card-1 [data-choice=upgrade]")
      assert has_element?(view, "#bar-card-1 [data-choice=skip]")
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

  describe "the rat track" do
    test "the leader's VP shows once above the leader's dot" do
      {:ok, id} = GameServer.start(3, {1, 2, 3}, %{}, %{fortune: false})
      token = "r24-rats-#{System.unique_integer()}"
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      {:ok, _} = GameServer.add_bot(id, token)
      {:ok, _} = GameServer.add_bot(id, token)
      {:ok, _} = GameServer.begin(id, token)

      replace_game(id, fn g ->
        [2, 30, 11]
        |> Enum.with_index()
        |> Enum.reduce(g, fn {vp, s}, g -> H.put(g, s, vp: vp) end)
      end)

      leader = "#rat-track [data-role=leader-vp]"
      assert has_element?(view, leader, "30")
      html = view |> element("#rat-track") |> render()

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-role=leader-vp]")
             |> Enum.count() == 1

      # The leader's step is the first: its x is half a step.
      assert has_element?(view, ~s(#{leader}[style*="0.0385"]))
      # The other dots keep their tooltips.
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='0'][title]")
    end
  end

  describe "chip actions: every rung" do
    # Step B with `pot` in the pot (the explosion's buy path runs the evaluation).
    defp chip_actions(sets, pot, fields \\ []) do
      {id, view} = solo(%{fortune: false})

      replace_game(id, fn g ->
        %{g | sets: Map.merge(g.sets, sets)}
        |> H.put([phase: :explosion_choice, exploded?: true, drawn: pot, pot_index: 10] ++ fields)
        |> H.apply!({:explosion_choice, :buy})
      end)

      view
    end

    # Round 33: the chip actions are a step in the bar (info row + buttons), no sheet.
    test "Ghost's breath II: trade 1 and 2 are buttons, trade 3 is greyed with a reason" do
      view = chip_actions(%{purple: 2}, [{{:purple, 1}, 10}, {{:purple, 1}, 8}])
      bar = "[data-role=bar-chip-actions]"
      refute has_element?(view, "dialog#decision-chip_choice")

      assert has_element?(view, "#{bar} button[data-role=chip-action]:not([disabled])", "Trade 1")
      assert has_element?(view, "#{bar} button[data-role=chip-action]:not([disabled])", "Trade 2")

      off = "#{bar} button[data-role=ladder-rung-off][disabled]"
      assert has_element?(view, off, "Trade 3")
      assert has_element?(view, off, "needs 3 purple")
      assert has_element?(view, "#{off}[aria-label*='needs 3 purple, you have 2']")

      assert has_element?(view, "#{bar} button[data-role=chip-action]", "Done")

      view |> element("#{bar} button[data-role=chip-action]", "Trade 2") |> render_click()
      refute has_element?(view, bar)
    end

    test "Garden spider IV: a rung over the rubies is greyed" do
      view =
        chip_actions(%{green: 4}, [{{:green, 1}, 10}, {{:green, 1}, 8}], rubies: 1)

      bar = "[data-role=bar-chip-actions]"
      assert has_element?(view, "#{bar} button[data-role=chip-action]:not([disabled])", "Pay 1")
      assert has_element?(view, "#{bar} button[data-role=ladder-rung-off]", "needs 2 rubies")
    end

    test "Ghost's breath IV: the tiers the pot does not reach are greyed" do
      view =
        chip_actions(%{purple: 4}, [{{:purple, 1}, 10}, {{:green, 1}, 8}])

      bar = "[data-role=bar-chip-actions]"
      # Round 36: the swaps are taps on the pot chip.
      assert has_element?(view, "#pot-0-lg [data-role=pot-chip][data-target]")
      off = "#{bar} button[data-role=ladder-rung-off]"
      assert has_element?(view, "#{off}[aria-label*='a 2-chip → a 4-chip']")
      assert has_element?(view, off, "needs 3 purple")
    end
  end

  describe "the install hint" do
    test "the lobby has the browser-menu hint, hidden until app.js shows it" do
      conn = browser("r24-install-#{System.unique_integer()}")
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(
               view,
               "#install-app .pwa-menu-hint[data-role=install-menu-hint]",
               "Install from your browser menu: ⋮ → Install app"
             )

      assert has_element?(view, "#install-app .pwa-install[data-role=install]")
      assert has_element?(view, "#install-app .pwa-ios-hint[data-role=install-hint]")
    end

    test "app.js shows it 3 s after load without a prompt; CSS keys it on data-install" do
      js = File.read!("assets/js/app.js")
      assert js =~ ~s{installState("menu")}
      assert js =~ "}, 3000)"
      assert js =~ "!installFired && !standalone"

      css = File.read!("assets/css/app.css")
      assert css =~ ~s{html[data-install="menu"] .pwa-menu-hint {\n  display: block;}
    end
  end
end
