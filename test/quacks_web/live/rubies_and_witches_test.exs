defmodule QuacksWeb.RubiesAndWitchesTest do
  @moduledoc """
  The rubies step, the toasts of a card without a choice, the gold witch Cheap rubies, the test tube in round 9, the reveal overlay and settings, the herb witch pickers, the witches sheet and the menu.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers, except: [open: 2]
  import QuacksWeb.RevealHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

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

  describe "no full-height sheets" do
    test "a decision opens over the pot, not as a bottom sheet" do
      {id, alice} = duo()
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 10))
      assert has_element?(alice, "dialog#decision-shop[data-pot=true][data-side=panel]")
    end

    test "the shop opens over the pot; its purse and buttons sit in the bar" do
      {id, alice} = duo()
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 15))
      assert has_element?(alice, "dialog#decision-shop[data-pot=true] [data-role=shop-footer]")
      css = File.read!("assets/css/app.css")
      assert css =~ ~s(.sheet[data-pot][open] [data-role="shop-footer"] {\n    position: fixed;)
    end

    test "the player sheets cover the pot, not the screen" do
      {_id, alice} = duo()
      assert has_element?(alice, "#sheet-player-0.sheet-pot[popover]")
      assert has_element?(alice, "#sheet-player-1.sheet-pot[popover]")
    end

    test "the CSS anchors the overlay to the pot column; app.js opens it non-modal" do
      css = File.read!("assets/css/app.css")
      assert css =~ ~s([data-area="pot"] {\n  anchor-name: --pot-area;)
      assert css =~ "position-anchor: --pot-area;"
      js = File.read!("assets/js/app.js")
      assert js =~ "side || d.dataset.pot ? d.show() : d.showModal()"
    end
  end

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

    skip_results(view)

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
    skip_results(view)

    assert has_element?(view, "#bar-rubies button[data-ruby=vp]", "1 VP")
    refute has_element?(view, "#bar-rubies button[data-ruby=flask]")

    view |> element("#bar-rubies button[data-ruby=tube]") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    assert %{rubies: 1, tube: 4, vp: 2} = game.players[0]
  end

  defp herb_solo do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
    {:ok, view, _html} = live(browser("r14-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  # A solo game in the shop phase of round 1: the results overlay shows.
  defp solo_results(fortune? \\ false) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: fortune?})
    token = "r14-solo-#{System.unique_integer()}"
    {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")

    replace_game(id, fn g ->
      g = put_in(g.players[0].drawn, [{{:green, 1}, 12}, {{:purple, 1}, 11}])
      g = %{g | log: [{0, {:purple, 1, :vp}}, {0, {:green_rubies, 1}}, {:round_end, 0}]}
      H.put(g, 0, phase: :shop, coins: 10)
    end)

    {id, view, token}
  end

  defp reveal(view), do: :sys.get_state(view.pid).socket.assigns.reveal

  describe "the reveal overlay" do
    test "the round's card: one slide; closing marks it seen" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      {:ok, view, _html} = live(browser("r14-card-#{System.unique_integer()}"), ~p"/g/#{id}")

      # Round 24: the card waits for a tap over the pot, with no sheet.
      assert has_element?(view, "#pot-card-1 [data-role=card-caption]")
      refute has_element?(view, "#reveal-card-1")

      view |> element("#card-tap") |> render_click()
      assert {:ok, %{seen: %{0 => %{card: 1}}}} = GameServer.get(id)
    end

    test "the end of the game (round 31): the score chart over the pot, no overlay" do
      {id, view, _token} = solo_results()
      render_hook(view, "reveal_close", %{})

      replace_game(id, fn g ->
        %{
          g
          | phase: :over,
            round: 9,
            log: [{:round_end, 9}, {0, {:final_conversion, 7, 1, 2, 1}} | g.log]
        }
      end)

      refute has_element?(view, "[data-role=reveal]")
      assert has_element?(view, "[data-role=pot-area] #final-board [data-role=final-score]")
      assert has_element?(view, "[data-role=game-over-actions] [data-role=play-again]")
      assert has_element?(view, "[data-role=game-over-actions] [data-role=return-to-lobby]")
      refute has_element?(view, "[data-role=action-bar]")
    end
  end

  describe "the reveal settings" do
    test "the menu has Step/Auto and the speeds; the browser's values come back" do
      {_id, view, _token} = solo_results()
      assert has_element?(view, "#sheet-menu #reveal-settings[phx-hook=RevealSettings]")
      assert has_element?(view, "#reveal-mode-step[checked]")
      assert has_element?(view, "#reveal-speed-normal[checked]")

      render_hook(view, "reveal_settings", %{
        "mode" => "auto",
        "speed" => "slower",
        "reduced" => false
      })

      assert has_element?(view, "#reveal-mode-auto[checked]")
      assert has_element?(view, "#reveal-speed-slower[checked]")
      # Round 39: the results play on the tiles; Auto runs the step's timer.
      assert is_reference(reveal(view).tick)
      refute has_element?(view, "[data-role=tile-next]")

      view |> form("#reveal-settings", mode: "step", speed: "slow") |> render_change()
      assert has_element?(view, "#reveal-mode-step[checked]")
      assert has_element?(view, "#reveal-speed-slow[checked]")
      assert has_element?(view, "[data-role=tile-next]")
      assert reveal(view).tick == nil
    end

    test "Auto: the server's timer advances the steps; a stale tick does nothing" do
      {_id, view, _token} = solo_results()
      render_hook(view, "reveal_settings", %{"mode" => "auto", "speed" => "normal"})
      %{tick: tick, index: 1, tiles: true} = reveal(view)
      assert is_reference(tick)

      send(view.pid, {:reveal_tick, make_ref()})
      assert has_element?(view, ~s(#tile-stage[data-index="1"]))

      send(view.pid, {:reveal_tick, tick})
      assert has_element?(view, ~s(#tile-stage[data-index="2"]))

      # A stale tick after the step moved on does nothing.
      send(view.pid, {:reveal_tick, tick})
      assert has_element?(view, ~s(#tile-stage[data-index="2"]))
    end

    test "reduced motion: Step only, no timer" do
      {_id, view, _token} = solo_results()

      render_hook(view, "reveal_settings", %{
        "mode" => "auto",
        "speed" => "slow",
        "reduced" => true
      })

      assert has_element?(view, "#reveal-mode-step[checked]")
      assert has_element?(view, "#reveal-mode-auto[disabled]")
      assert reveal(view).tick == nil
    end

    test "app.js keeps them in this browser and sets --beat-ms on <html>" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ ~s{localStorage.setItem("quacks:reveal"}
      assert js =~ ~s{style.setProperty("--beat-ms"}

      assert js =~
               ~S|this.pushEvent("reveal_settings", {mode, speed, risk: loadRisk(), reduced: reduced(), tips: loadTips()})|
    end
  end

  describe "the herb witch pickers" do
    test "show with the expansion; a pick goes into the game and the browser's memory" do
      # Round 26: the witches are picked in the spell book (its witch pages).
      {:ok, host, _html} =
        live(browser("r14-host-#{System.unique_integer()}"), ~p"/?seed=1,2,3&step=books")

      refute has_element?(host, "[data-role=witch-pickers]")

      host |> element("#books") |> render_change(%{"expansion" => "true", "sets" => %{}})
      assert has_element?(host, "[data-role=witch-tile][data-colour=copper]", "Random")

      tiles =
        host
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("[data-role=witch-tile]")
        |> LazyHTML.attribute("data-colour")

      assert tiles == ~w(copper silver gold)
      assert has_element?(host, "#page-witch-silver [data-witch=s3]", "Two whites back")

      host
      |> element("#books")
      |> render_change(%{
        "expansion" => "true",
        "sets" => %{},
        "witches" => %{"copper" => "c3", "silver" => "", "gold" => ""}
      })

      assert has_element?(host, "[data-role=witch-tile][data-witch=c3]", "One free copy")
      assert_push_event(host, "save_config", %{expansion: true, witches: %{copper: "c3"}})

      render_click(host, "players", %{"count" => "1"})

      {:error, {:live_redirect, %{to: "/g/" <> id}}} =
        host |> element("#new-game") |> render_click()

      {:ok, %{game: game}} = GameServer.get(id)
      assert game.witches.copper == :c3
    end

    test "parse_witches: an unknown id or a missing colour is Random" do
      assert QuacksWeb.SetupComponents.parse_witches(%{"copper" => "c3", "gold" => "g9"}) ==
               %{copper: :c3, silver: nil, gold: nil}

      assert QuacksWeb.SetupComponents.parse_witches(nil) == %{
               copper: nil,
               silver: nil,
               gold: nil
             }
    end

    test "a fresh spell book takes the saved picks back" do
      {:ok, host, _html} = live(browser("r14-fresh-#{System.unique_integer()}"), ~p"/?step=books")

      render_hook(host, "load_config", %{
        "players" => 2,
        "expansion" => true,
        "witches" => %{"gold" => "g2", "copper" => "nope"}
      })

      assert has_element?(host, "[data-role=witch-tile][data-witch=g2]", "Count the bag")
      assert has_element?(host, "[data-role=witch-tile][data-colour=copper]", "Random")
    end

    test "a debug table from a bundle keeps the picks" do
      session =
        Quacks.Session.new({1, 2, 3}, 1, expansions: [:herb_witches], witches: %{silver: :s4})

      bundle = Quacks.Session.bundle(session)
      {:ok, id} = GameServer.start_from_bundle(bundle)

      assert {:ok, %{game: %{witches: %{silver: :s4}}, witches: %{silver: :s4}}} =
               GameServer.get(id)
    end
  end

  describe "the witches sheet" do
    test "has a title row and shows copper, silver, gold" do
      {_id, view} = herb_solo()
      assert has_element?(view, "#sheet-witches > [data-role=witches-title]", "Herb witches")

      html = render(view)

      ids =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#sheet-witches [data-role=witch-card]")
        |> LazyHTML.attribute("data-witch")

      assert Enum.map(ids, &String.first/1) == ["c", "s", "g"]
    end
  end

  describe "the menu" do
    test "round 29: has no App line; the seed stays" do
      {_id, view} = herb_solo()
      refute has_element?(view, "#app-status")
      refute render(view) =~ "install prompt"
      assert has_element?(view, "#sheet-menu a[href^='/?seed=']")

      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      refute js =~ "AppStatus"
    end
  end

  describe "name cards" do
    test "show no name text (round 28): the initial, the name for screen readers" do
      {_id, view} = herb_solo()
      assert has_element?(view, "[data-role=player-chip] > [data-role=player-name].sr-only")
      refute has_element?(view, "[data-role=player-name-text]")
      refute render(view) =~ "wrap-anywhere"
    end
  end
end
