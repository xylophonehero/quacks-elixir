defmodule QuacksWeb.Round29BarTest do
  @moduledoc """
  Round 29 (bar): the bottom bar carries every action. Draw, the waiting state, the
  explosion and ruby choices, the evaluation steps and the shop's Skip.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias QuacksWeb.GameLive

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("solo-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  describe "item 1: Draw" do
    test "the button says Draw, next to Stop" do
      {_id, view} = solo()
      assert has_element?(view, "[data-role=action-bar] button[data-slot=draw]", "Draw")
      refute has_element?(view, "button[data-slot=draw]", "a chip")
      assert has_element?(view, "[data-role=action-bar] button[data-slot=stop]", "Stop")
    end
  end

  describe "item 3: waiting" do
    test "after Stop the phase pill says Waiting; Draw stays, greyed, with no names" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, alice, _} = live(browser("alice"), ~p"/g/#{id}")
      {:ok, _bob, _} = live(browser("bob"), ~p"/g/#{id}")
      {:ok, _} = GameServer.begin(id, "alice")

      alice |> element("button[data-slot=draw]") |> render_click()
      alice |> element("button[data-slot=stop]") |> render_click()

      assert has_element?(alice, "header dd", "Waiting")
      assert has_element?(alice, "button[data-slot=draw][disabled]", "Draw")
      refute has_element?(alice, "button[data-slot=draw]", "bob")
    end
  end

  describe "item 7: the shop's Skip" do
    test "nothing ticked: Skip is the one button; ticked: Buy and a small Skip" do
      {id, view} = solo()
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 20))

      assert has_element?(view, "[data-role=shop-done].flex-1", "Skip")
      refute has_element?(view, "[data-role=shop-buy]")

      view
      |> element("#shop")
      |> render_change(%{"chips" => [GameLive.encode({:orange, 1})]})

      assert has_element?(view, "[data-role=shop-buy]:not(:disabled)", "Buy 1")
      assert has_element?(view, "[data-role=shop-done].flex-none", "Skip")
    end
  end

  describe "item 2: reward and risk beside the white meter" do
    test "icons for coins, VP, ruby and the risk; the menu's Risk picks Percent, Chips or Off" do
      {id, view} = solo()

      # 6 white in the pot, limit 7: the 3-white of two chips explodes.
      replace_game(id, fn g ->
        H.put(g, 0,
          drawn: [{{:white, 3}, 3}, {{:white, 3}, 1}],
          bag: [{:white, 3}, {:orange, 1}],
          starters: []
        )
      end)

      row = "[data-role=fuse-row] > [data-role=reward-line]"
      assert has_element?(view, "#{row} [data-role=reward-coins] use[href='#icon-coin']")
      assert has_element?(view, "#{row} [data-role=reward-vp] use[href='#icon-vp']")
      assert has_element?(view, "#{row} [data-role=explode-chance] use[href='#icon-explosion']")

      # Default: Percent.
      assert has_element?(view, "input#reveal-risk-percent[checked]")
      assert has_element?(view, "[data-role=explode-chance]", "50%")

      view |> element("#reveal-settings") |> render_change(%{"risk" => "chips"})
      assert has_element?(view, "[data-role=explode-chance]", "1/2")
      refute has_element?(view, "[data-role=explode-chance]", "%")

      view |> element("#reveal-settings") |> render_change(%{"risk" => "off"})
      refute has_element?(view, "[data-role=explode-chance]")
      assert has_element?(view, "[data-role=reward-vp]")
    end

    test "app.js keeps the risk in this browser" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ ~s{localStorage.setItem("quacks:risk"}
    end
  end

  describe "item 4: the explosion's beat and choice in the bar" do
    test "BOOM over the pot, then Take VP / Take coins where Stop and Draw were; no sheet" do
      {id, view} = solo()
      replace_game(id, &H.put(&1, 0, phase: :explosion_choice, exploded?: true))

      assert has_element?(view, "[data-role=pot-area] #boom-1.boom[phx-hook=Boom]", "BOOM")
      refute has_element?(view, "dialog#decision-explosion_choice")
      refute has_element?(view, "[data-role=decision-button]")
      refute has_element?(view, "[data-role=action-bar]")

      bar = "[data-role=bar-explosion].bar-choice-late"
      assert has_element?(view, "#{bar} button[data-choice=vp] use[href='#icon-vp']")
      assert has_element?(view, "#{bar} button[data-choice=buy] use[href='#icon-coin']")
      assert has_element?(view, "#{bar} button[data-choice=vp]", "Score now, no coins")
      assert has_element?(view, "#{bar} button[data-choice=buy]", "Shop, no VP")

      view |> element("#{bar} button[data-choice=vp]") |> render_click()
      refute has_element?(view, "[data-role=bar-explosion]")

      assert GameServer.get(id)
             |> elem(1)
             |> Map.fetch!(:game)
             |> then(& &1.players[0].explosion_choice) == :vp
    end

    test "app.js buzzes only in the Boom hook, guarded" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert length(String.split(js, "navigator.vibrate(")) == 2
      assert js =~ ~s{typeof navigator.vibrate === "function"}
      assert js =~ "navigator.vibrate([40, 30, 90])"
    end
  end

  describe "item 5: the ruby choice in the bar" do
    test "Skip, test tube, flask, pot in one row; each paying button says 2 and the ruby" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false, pot_side: :back})
      {:ok, view, _} = live(browser("r29-rubies"), ~p"/g/#{id}")
      replace_game(id, &H.put(&1, 0, phase: :rubies, coins: 0, rubies: 2, flask: true))

      refute has_element?(view, "dialog#decision-rubies")
      bar = "#bar-rubies.flex"
      assert has_element?(view, "#{bar} > button:nth-child(1)[data-role=rubies-skip]", "Skip")

      assert has_element?(
               view,
               "#{bar} > button:nth-child(2)[data-ruby=tube] use[href='#icon-tube']"
             )

      assert has_element?(
               view,
               "#{bar} > button:nth-child(3)[data-ruby=flask] use[href='#icon-flask']"
             )

      assert has_element?(
               view,
               "#{bar} > button:nth-child(4)[data-ruby=droplet] use[href='#icon-pot']"
             )

      for use <- ~w(tube flask droplet) do
        assert has_element?(view, "#{bar} button[data-ruby=#{use}] use[href='#icon-ruby']")
        assert has_element?(view, "#{bar} button[data-ruby=#{use}]", "2")
      end

      # The flask is full: disabled, and it says why.
      assert has_element?(view, "#{bar} button[data-ruby=flask][disabled]", "Flask full")
      refute has_element?(view, "#{bar} button[data-ruby=droplet][disabled]")

      # Same height as Stop / Draw: the pot does not move.
      assert has_element?(view, "#bar-rubies[class*='*:min-h-12']")

      view |> element("#{bar} button[data-ruby=droplet]") |> render_click()
      refute has_element?(view, "#bar-rubies")
    end

    test "the gold witch's price (G4: 1 ruby) shows on the buttons" do
      {id, view} = solo()
      replace_game(id, &H.put(&1, 0, phase: :rubies, coins: 0, rubies: 1, ruby_price: 1))
      assert has_element?(view, "#bar-rubies button[data-ruby=droplet]:not([disabled])", "1")
      refute has_element?(view, "#bar-rubies button[data-ruby=tube]")
    end
  end
end
