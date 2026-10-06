defmodule QuacksWeb.Round14Test do
  @moduledoc """
  Round 14 playtest fixes: the witches sheet has a title row and the order copper,
  silver, gold; the menu's "App" line; name cards on one line.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

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
    test "Next steps through the slides; the last one opens the shop" do
      {id, view, _token} = solo_results()
      assert has_element?(view, "dialog#reveal-results-1[phx-mounted*='quacks:modal']")
      assert has_element?(view, "#reveal-slide-0[data-kind=book]")
      assert has_element?(view, "[data-role=reveal-count]", "1 / 5")
      assert has_element?(view, "#reveal-slide-0 [data-role=reveal-chips]")

      view |> element("#reveal-next") |> render_click()
      assert has_element?(view, "#reveal-slide-1[data-kind=book]")
      # a tap on the slide is Next too; round 20: the scoring space has its slide
      view |> element("#reveal-stage") |> render_click()
      assert has_element?(view, "#reveal-slide-2[data-kind=space]")
      view |> element("#reveal-next") |> render_click()
      # round 16: one results slide, and the running results on every slide
      assert has_element?(view, "#reveal-slide-3[data-kind=results]", "Round 1 results")
      assert has_element?(view, "[data-role=reveal-strip] [data-seat='0']")
      assert has_element?(view, "#reveal-slide-3 [data-role=reveal-result][data-seat='0']")
      # round 18: then the standings
      view |> element("#reveal-next") |> render_click()
      assert has_element?(view, "#reveal-slide-4[data-kind=standings]")
      refute has_element?(view, "#reveal-skip")
      assert has_element?(view, "#reveal-next", "To the shop")

      view |> element("#reveal-next") |> render_click()
      refute has_element?(view, "[data-role=reveal]")
      assert_push_event(view, "quacks:open", %{to: "#decision-shop"})
      assert {:ok, %{seen: %{0 => %{results: 1}}}} = GameServer.get(id)
    end

    test "Skip jumps to the last slide; Esc (the dialog's close) ends it" do
      {_id, view, _token} = solo_results()
      view |> element("#reveal-skip") |> render_click()
      assert has_element?(view, "#reveal-slide-4[data-kind=standings]")

      assert has_element?(view, "dialog#reveal-results-1[data-on-close*=reveal_close]")
      render_hook(view, "reveal_close", %{})
      refute has_element?(view, "[data-role=reveal]")
    end

    test "a reload mid-reveal starts at the first slide; after the end it stays closed" do
      {id, view, token} = solo_results()
      view |> element("#reveal-next") |> render_click()
      {:ok, again, _html} = live(browser(token), ~p"/g/#{id}")
      assert has_element?(again, "#reveal-slide-0")

      again |> element("#reveal-skip") |> render_click()
      again |> element("#reveal-next") |> render_click()
      {:ok, third, _html} = live(browser(token), ~p"/g/#{id}")
      refute has_element?(third, "[data-role=reveal]")
    end

    test "the round's card: one slide; closing marks it seen" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      {:ok, view, _html} = live(browser("r14-card-#{System.unique_integer()}"), ~p"/g/#{id}")

      assert has_element?(
               view,
               "#reveal-card-1 #reveal-slide-0[data-kind=card] [data-role=reveal-card-name]"
             )

      view |> element("#reveal-next") |> render_click()
      assert {:ok, %{seen: %{0 => %{card: 1}}}} = GameServer.get(id)
    end

    test "the end of the game: the final scoring and the podium, then the game-over sheet" do
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

      assert has_element?(view, "dialog#reveal-final-9 #reveal-slide-0[data-kind=final]")
      assert has_element?(view, "dialog#game-over")
      refute has_element?(view, "dialog#game-over[phx-mounted*='quacks:modal']")

      view |> element("#reveal-next") |> render_click()
      assert has_element?(view, "#reveal-slide-1[data-kind=podium]", "You win!")
      assert has_element?(view, "#reveal-next", "See the results")
      view |> element("#reveal-next") |> render_click()
      assert_push_event(view, "quacks:open", %{to: "#game-over"})
    end

    test "Enter and Space are Next; a focused button keeps its own key" do
      {_id, view, _token} = solo_results()
      view |> element("#game") |> render_keydown(%{"key" => "Enter"})
      assert has_element?(view, "#reveal-slide-1")
      view |> element("#game") |> render_keydown(%{"key" => " "})
      assert has_element?(view, "#reveal-slide-2")
      view |> element("#game") |> render_keydown(%{"key" => "Enter", "control" => true})
      assert has_element?(view, "#reveal-slide-2")
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
      # Auto: the slide's timer bar runs for its time at that speed
      assert has_element?(view, ~s([data-role=reveal-timer][style*="--slide-ms: 8500ms"]))

      view |> form("#reveal-settings", mode: "step", speed: "slow") |> render_change()
      assert has_element?(view, "#reveal-mode-step[checked]")
      assert has_element?(view, "#reveal-speed-slow[checked]")
      refute has_element?(view, "[data-role=reveal-timer]")
      assert reveal(view).tick == nil
    end

    test "Auto: the server's timer advances the slides; a stale tick does nothing" do
      {_id, view, _token} = solo_results()
      render_hook(view, "reveal_settings", %{"mode" => "auto", "speed" => "normal"})
      %{tick: tick, index: 0} = reveal(view)
      assert is_reference(tick)

      send(view.pid, {:reveal_tick, make_ref()})
      assert has_element?(view, "#reveal-slide-0")

      send(view.pid, {:reveal_tick, tick})
      assert has_element?(view, "#reveal-slide-1")

      # Next still works, and drops the old timer
      %{tick: tick} = reveal(view)
      view |> element("#reveal-next") |> render_click()
      send(view.pid, {:reveal_tick, tick})
      assert has_element?(view, "#reveal-slide-2")
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
      assert js =~ ~S|this.pushEvent("reveal_settings", {mode, speed, reduced: reduced()})|
    end
  end

  describe "the herb witch pickers" do
    test "show with the expansion; a pick goes into the game and the browser's memory" do
      {:ok, id} = GameServer.start(2)
      {:ok, host, _html} = live(browser("r14-host-#{System.unique_integer()}"), ~p"/g/#{id}")
      refute has_element?(host, "[data-role=witch-pickers]")

      host |> form("#books", expansion: "true") |> render_change()
      assert has_element?(host, "[data-role=witch-tile][data-colour=copper]", "Random")

      tiles =
        host
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("[data-role=witch-tile]")
        |> LazyHTML.attribute("data-colour")

      assert tiles == ~w(copper silver gold)
      assert has_element?(host, "#witch-picker-silver [data-witch=s3]", "Two whites back")

      host
      |> form("#books", expansion: "true", witches: %{copper: "c3", silver: "", gold: ""})
      |> render_change()

      assert {:ok, %{witches: %{copper: :c3, silver: nil, gold: nil}}} = GameServer.get(id)
      assert has_element?(host, "[data-role=witch-tile][data-witch=c3]", "One free copy")

      assert_push_event(host, "save_config", %{
        expansion: true,
        witches: %{copper: "c3", silver: "", gold: ""}
      })

      host |> element("button", "Start game") |> render_click()
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

    test "a fresh screen takes the saved picks back" do
      {:ok, id} = GameServer.start(2)
      {:ok, host, _html} = live(browser("r14-fresh-#{System.unique_integer()}"), ~p"/g/#{id}")

      render_hook(host, "load_config", %{
        "players" => 2,
        "expansion" => true,
        "witches" => %{"gold" => "g2", "copper" => "nope"}
      })

      assert {:ok, %{witches: %{gold: :g2, copper: nil}}} = GameServer.get(id)
      assert has_element?(host, "[data-role=witch-tile][data-witch=g2]", "Count the bag")
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
    test "has the App line that app.js fills" do
      {_id, view} = herb_solo()
      assert has_element?(view, "#sheet-menu #app-status[phx-hook=AppStatus]", "App:")

      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ "navigator.serviceWorker?.getRegistration()"
      assert js =~ "install prompt: ${prompt}"
    end
  end

  describe "name cards" do
    test "keep the name on one line, cut with an ellipsis" do
      {_id, view} = herb_solo()
      assert has_element?(view, "[data-role=player-name] > [data-role=player-name-text].truncate")
      refute render(view) =~ "wrap-anywhere"
    end
  end
end
