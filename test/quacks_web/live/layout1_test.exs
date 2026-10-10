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
  alias QuacksWeb.{BarComponents, PotComponents, TileComponents}

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp card(game, seat, opts \\ []) do
    render_component(
      &TileComponents.player_chip/1,
      [game: game, seat: seat, name: Keyword.get(opts, :name, "Lavinia")] ++ opts
    )
  end

  describe "name card" do
    test "colour disc with the initial, name, BOT badge, VP, rubies, flask" do
      game = Game.new(seed: {1, 2, 3}, players: 2) |> H.put(1, vp: 27, rubies: 2)
      html = card(game, 1, bot: true)

      assert text(html, ~s([data-role=seat-disc].bg-player-1)) == "L"
      assert text(html, "[data-role=player-name]") =~ "Lavinia"
      # Round 28: the name is screen-reader text, the bot an icon on the disc.
      assert text(html, "[data-role=player-name].sr-only") =~ "bot"
      assert count(html, "[data-role=bot-badge].hero-cpu-chip-micro") == 1
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

      # Round 27: a brewing tile shows no badge (design B).
      assert count(card(game, 1), "[data-role=player-state]") == 0

      for {fields, state} <- [
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

    test "more than 4 players: two rows of tiles (round 27), no sideways scroll" do
      {:ok, id} = GameServer.start(6, {1, 2, 3})
      token = "six-#{id}"
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      for _ <- 1..5, do: {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()

      html = render(view)

      assert count(html, ~s(#players-row[data-columns="3"] [data-role=player-chip])) == 6
      assert count(html, "#players-row.overflow-x-auto") == 0
    end
  end

  describe "update chips" do
    test "the reveal overlay's end marks the round as seen; a card tap then opens its lines" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser("tap-#{id}"), ~p"/g/#{id}")
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 10))

      refute has_element?(view, "dialog#round-results")
      refute has_element?(view, ~s([data-role=player-chip][phx-click*="seen"]))

      render_hook(view, "reveal_close", %{})
      assert {:ok, %{seen: %{0 => %{results: 1}}}} = GameServer.get(id)
      assert has_element?(view, "#players-row.replay-done")

      view |> element(~s([data-role=player-chip][data-seat="0"])) |> render_click()
      assert has_element?(view, "#sheet-player-0 [data-role=round-results]")
    end

    test "round 14: no timer ends the replay in app.js; the server opens what waited" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      refute js =~ "[data-replay-last]"
      refute js =~ "onReplayEnd"
      assert js =~ ~s{window.addEventListener("phx:quacks:open"}
    end
  end

  describe "contextual side panel and phone sheets" do
    test "the fortune teller tops the right column; decisions are side panels under it" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      {:ok, view, _html} = live(browser("side-#{id}"), ~p"/g/#{id}")
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 10))

      column = "[data-role=side-column]"
      assert has_element?(view, "#{column} > #fortune-panel-1[data-role=fortune-panel].lg\\:flex")
      assert has_element?(view, "#{column} > dialog#decision-shop[data-side=panel]")
      # no choice on the card: no card dialog (round 14: the reveal overlay shows it)
      refute has_element?(view, "dialog#card-round-1")
      # round 22: the card sits in the pot's top left corner on every layout
      assert has_element?(view, "[data-role=pot-area] #corner-card[data-role=fortune-tile]")
    end

    # Round 31: no card dialog, also from 64rem: the choice is in the bar.
    test "a fortune choice is in the bar when it arrives, no panel" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      {:ok, view, _html} = live(browser("choice-#{id}"), ~p"/g/#{id}")

      replace_game(id, fn g ->
        g |> H.put(fortune_card: :p1, phase: :fortune_choice) |> Map.put(:phase, :fortune_choice)
      end)

      refute has_element?(view, "dialog#card-round-1")
      assert has_element?(view, "#bar-card-1[data-role=bar-card]")
      refute has_element?(view, "[data-role=decision-button]")
    end

    test "while a decision waits, one button takes the place of Stop and Draw on phones" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser("back-#{id}"), ~p"/g/#{id}")
      assert has_element?(view, "[data-role=action-bar]:not(.max-lg\\:hidden)")

      # Round 33: the crow skull is a bar choice: it takes the bar, no sheet.
      # Round 40: from 64rem it is in the context column; Stop and Draw stay.
      replace_game(id, &H.put(&1, 0, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))
      refute has_element?(view, "[data-role=action-bar]:not(.max-lg\\:hidden)")
      assert has_element?(view, "footer [data-role=bar-blue]")

      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 10))
      assert has_element?(view, "[data-role=decision-button]", "Back to shop")
      # round 14: the reveal overlay ends the replay, not this button
      refute has_element?(view, "[data-role=decision-button][phx-click*=seen]")
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

    # Round 13 (issue #1): a patch that removes `#results-N` before the open shop
    # moves the shop <dialog> (morphdom insertBefore). The move takes it out of the
    # top layer but keeps `open`, so the action bar took the taps on its lower part.
    # A LiveView test cannot see the top layer: check that app.js opens such a
    # dialog as a modal again after each patch.
    test "app.js opens a moved modal dialog as a modal again after a patch" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ "onPatchEnd: () => remodal()"
      assert js =~ ~s{document.querySelectorAll("dialog[open]")}
      assert js =~ ~s{d.matches(":modal")}
      assert js =~ "moving.add(d); d.close(); d.showModal()"
    end
  end

  describe "the board's chip order" do
    alias Quacks.Rules.{Books, Chips}

    test "one list: orange, blue, red, yellow, green, black, purple, locoweed" do
      assert Chips.order() -- [:white] ==
               [:orange, :blue, :red, :yellow, :green, :black, :purple, :locoweed]

      rows = BarComponents.shop_rows(nil, %{locoweed: 1})
      assert Enum.map(rows, &elem(hd(&1), 0)) == Chips.order() -- [:white]

      assert Enum.map(Books.in_play(nil, %{locoweed: 1}), &elem(&1, 0)) ==
               Chips.order() -- [:white]

      assert QuacksWeb.SetupComponents.book_colours() == Chips.order() -- [:white]
    end

    test "bag counts follow it too" do
      bag = [{:purple, 1}, {:white, 2}, {:black, 1}, {:green, 1}, {:white, 1}, {:orange, 1}]
      html = render_component(&PotComponents.chip_counts/1, chips: bag)

      assert html |> query("[aria-label]") |> LazyHTML.attribute("aria-label") ==
               ["white 1", "white 2", "orange 1", "green 1", "black 1", "purple 1"]
    end
  end
end
