defmodule QuacksWeb.Layout1Test do
  @moduledoc """
  Layout 1: the name card anatomy, the update chips that replace the round results
  dialog, the contextual side panel and closable phone sheets, the board's chip
  order and the shop's inline book info.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers, as: H
  alias QuacksWeb.GameComponents

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp card(game, seat, opts \\ []) do
    render_component(
      &GameComponents.player_chip/1,
      [game: game, seat: seat, name: Keyword.get(opts, :name, "Lavinia")] ++ opts
    )
  end

  describe "name card" do
    test "colour disc with the initial, name, BOT badge, VP, rubies, flask" do
      game = Game.new(seed: {1, 2, 3}, players: 2) |> H.put(1, vp: 27, rubies: 2)
      html = card(game, 1, bot: true)

      assert text(html, ~s([data-role=seat-disc].bg-player-1)) == "L"
      assert text(html, "[data-role=player-name]") =~ "Lavinia"
      assert text(html, "[data-role=player-name] [data-role=bot-badge]") == "bot"
      assert text(html, "[data-role=player-vp]") =~ "27"
      assert text(html, "[data-role=player-rubies]") =~ "2"
      assert count(html, ~s([data-role=player-flask][data-flask=full])) == 1
    end

    test "rat tails are one rat icon and a number" do
      game = Game.new(seed: {1, 2, 3}, players: 2) |> H.put(1, rat_stone: 3)
      html = card(game, 1)

      assert count(html, "[data-role=player-rats] [data-icon=rat]") == 1
      assert text(html, "[data-role=player-rats]") =~ "3"
    end

    test "the status is a graphic; its word is for screen readers only" do
      game = Game.new(seed: {1, 2, 3}, players: 2)

      for {fields, state} <- [
            {[], "brewing"},
            {[phase: :stopped], "stopped"},
            {[exploded?: true], "exploded"}
          ] do
        html = card(H.put(game, 1, fields), 1)
        badge = ~s([data-role=player-state][data-state=#{state}])
        assert count(html, "#{badge} svg") == 1
        assert text(html, "#{badge} .sr-only") == state
        assert text(html, badge) == state
      end
    end

    test "while everyone shops there is no state; a tick once a seat is ready" do
      game = %{Game.new(seed: {1, 2, 3}, players: 2) | phase: :shopping}
      game = game |> H.put(0, phase: :shop) |> H.put(1, phase: :shop)
      assert count(card(game, 1), "[data-role=player-state]") == 0

      game = H.put(game, 1, phase: :ready)
      assert count(card(game, 1), "[data-role=player-state][data-state=ready]") == 1
    end

    test "the expansion slot: witch pennies (spent ones dim) or the patient" do
      game = Game.new(seed: {1, 2, 3}, players: 2, expansion: :herb_witches)
      game = put_in(game.players[1].pennies, %{silver: true, copper: false, gold: true})
      html = card(game, 1)
      assert count(html, "[data-role=player-pennies] [data-icon=penny]") == 3
      assert count(html, "[data-role=player-pennies] .opacity-30") == 1

      game = Game.new(seed: {1, 2, 3}, players: 2) |> H.put(1, patient: :ear_worm)
      assert count(card(game, 1), "[data-role=player-patient] [data-icon=ear_worm]") == 1
    end

    test "more than 4 players: the row scrolls sideways instead of shrinking" do
      {:ok, id} = GameServer.start(6, {1, 2, 3})
      token = "six-#{id}"
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      for _ <- 1..5, do: {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()

      html = render(view)

      assert count(html, "#players-row.overflow-x-auto.grid-flow-col [data-role=player-chip]") ==
               6
    end
  end

  describe "update chips" do
    test "a tap on a card during the replay marks the round as seen and opens its lines" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser("tap-#{id}"), ~p"/g/#{id}")
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 10))

      refute has_element?(view, "dialog#round-results")
      assert has_element?(view, ~s([data-role=player-chip][phx-click*="seen"]))

      view |> element(~s([data-role=player-chip][data-seat="0"])) |> render_click()
      assert {:ok, %{seen: %{0 => %{results: 1}}}} = GameServer.get(id)
      assert has_element?(view, "#players-row.replay-done")
      assert has_element?(view, "#sheet-player-0 [data-role=round-results]")
      refute has_element?(view, ~s([data-role=player-chip][phx-click*="seen"]))
    end

    test "app.js ends the replay when the last chip lands" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ ~s(addEventListener("animationend")
      assert js =~ "[data-replay-last]"
      assert js =~ "onReplayEnd"
    end
  end

  describe "contextual side panel and phone sheets" do
    test "the fortune teller tops the right column; decisions are side panels under it" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      {:ok, view, _html} = live(browser("side-#{id}"), ~p"/g/#{id}")
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 10))

      column = "[data-role=side-column]"
      assert has_element?(view, "#{column} > #fortune-panel-1[data-role=fortune-panel].xl\\:flex")
      assert has_element?(view, "#{column} > dialog#decision-shop[data-side=panel]")
      # no choice on the card: from 64rem its dialog does not open (the panel shows it)
      assert has_element?(view, "#{column} > dialog#card-round-1[data-side=hidden]")
      assert has_element?(view, "[data-role=fortune-tile].lg\\:hidden")
    end

    test "a fortune choice opens the card's dialog as a panel when it arrives" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      {:ok, view, _html} = live(browser("choice-#{id}"), ~p"/g/#{id}")

      replace_game(id, fn g ->
        g |> H.put(fortune_card: :p1, phase: :fortune_choice) |> Map.put(:phase, :fortune_choice)
      end)

      assert has_element?(view, "dialog#card-round-1[data-side=panel]")
      assert has_element?(view, "#card-choice-1[phx-mounted*='quacks:modal']")
      assert has_element?(view, "[data-role=decision-button]", "Back to choice")
    end

    test "while a decision waits, one button takes the place of Stop and Draw on phones" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser("back-#{id}"), ~p"/g/#{id}")
      assert has_element?(view, "[data-role=action-bar]:not(.max-lg\\:hidden)")

      replace_game(id, &H.put(&1, 0, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))
      assert has_element?(view, "[data-role=action-bar].max-lg\\:hidden")

      assert has_element?(
               view,
               "[data-role=decision-button][phx-click*='decision-blue_choice']",
               "Back to choice"
             )

      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 10))
      assert has_element?(view, "[data-role=decision-button]", "Back to shop")
      # during the replay it also ends the replay
      assert has_element?(view, "[data-role=decision-button][phx-click*=seen]")
    end

    test "dialog_sheet: side panel mode and the app.js that opens it" do
      html =
        render_component(&QuacksWeb.CoreComponents.dialog_sheet/1,
          id: "d",
          label: "D",
          side: :panel,
          inner_block: [%{inner_block: fn _, _ -> "x" end}]
        )

      assert count(html, "dialog#d[data-side=panel]") == 1

      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ ~s{matchMedia("(min-width: 64rem)")}
      assert js =~ "d.show()"
      assert js =~ ~s(side === "hidden")
      # a tap on the dimmed backdrop closes a modal sheet
      assert js =~ ~s{d.matches(":modal")}

      css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
      assert css =~ ~s{.sheet[data-side="panel"][open]:not(:modal)}
      assert css =~ "@keyframes fortune-sweep"
    end
  end

  describe "the board's chip order" do
    alias Quacks.Rules.{Books, Chips}
    alias QuacksWeb.GameLive

    test "one list: orange, blue, red, yellow, green, black, purple, locoweed" do
      assert Chips.order() -- [:white] ==
               [:orange, :blue, :red, :yellow, :green, :black, :purple, :locoweed]

      rows = GameLive.shop_rows(nil, %{locoweed: 1})
      assert Enum.map(rows, &elem(hd(&1), 0)) == Chips.order() -- [:white]

      assert Enum.map(Books.in_play(nil, %{locoweed: 1}), &elem(&1, 0)) ==
               Chips.order() -- [:white]

      assert QuacksWeb.SetupComponents.book_colours() == Chips.order() -- [:white]
    end

    test "bag counts follow it too" do
      bag = [{:purple, 1}, {:white, 2}, {:black, 1}, {:green, 1}, {:white, 1}, {:orange, 1}]
      html = render_component(&GameComponents.chip_counts/1, chips: bag)

      assert html |> query("[aria-label]") |> LazyHTML.attribute("aria-label") ==
               ["white 1", "white 2", "orange 1", "green 1", "black 1", "purple 1"]
    end
  end
end
