defmodule QuacksWeb.PlayerTilesTest do
  @moduledoc """
  The players row: the seat loop of tiles, a tile's states (exploded, stopped, round leader), the name card anatomy, the update chips, the side panel and phone sheets, the board's chip order and the pieces on the board.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.Rules.PotTrack
  alias Quacks.{Game, GameServer}
  alias QuacksWeb.TileComponents
  alias QuacksWeb.{PanelComponents, PotComponents, TileComponents}
  alias QuacksWeb.{PotComponents, ShopComponents, TileComponents}

  doctest QuacksWeb.TileComponents, import: true, only: [seat_loop: 1]

  defp tile(game, seat, opts \\ []) do
    render_component(
      &TileComponents.player_chip/1,
      [game: game, seat: seat, name: "Clara"] ++ opts
    )
  end

  # A pot that ends at `index`, with `blacks` black chips in it.
  defp pot(game, seat, index, blacks \\ 0) do
    drawn =
      for i <- 1..max(blacks, 1), do: {if(i <= blacks, do: {:black, 1}, else: {:orange, 1}), i}

    H.put(game, seat, drawn: drawn, pot_index: index)
  end

  defp game(n), do: Game.new(seed: {1, 2, 3}, players: n, rules: %{fortune: false})

  describe "the seat loop" do
    # The rows as seen on screen, left to right (nil: an empty cell).
    defp rows(n) do
      at =
        Map.new(TileComponents.seat_loop(Enum.to_list(0..(n - 1))), fn {s, r, c} ->
          {{r, c}, s + 1}
        end)

      cols = TileComponents.loop_columns(n)
      rows = at |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
      for row <- rows, do: for(col <- 1..cols, do: at[{row, col}])
    end

    test "2 to 4 seats: one row in seat order" do
      assert rows(2) == [[1, 2]]
      assert rows(3) == [[1, 2, 3]]
      assert rows(4) == [[1, 2, 3, 4]]
    end

    test "5 to 8 seats: two rows, the second backwards, so the tiles form a loop" do
      assert rows(5) == [[1, 2, 3], [nil, 5, 4]]
      assert rows(6) == [[1, 2, 3], [6, 5, 4]]
      assert rows(7) == [[1, 2, 3, 4], [nil, 7, 6, 5]]
      assert rows(8) == [[1, 2, 3, 4], [8, 7, 6, 5]]
    end

    test "neighbours touch: each seat sits beside or above the next" do
      for n <- 2..8 do
        at =
          Map.new(TileComponents.seat_loop(Enum.to_list(0..(n - 1))), fn {s, r, c} ->
            {s, {r, c}}
          end)

        for s <- 0..(n - 2) do
          {r1, c1} = at[s]
          {r2, c2} = at[s + 1]
          assert abs(r1 - r2) + abs(c1 - c2) == 1, "#{n} seats: #{s} and #{s + 1} do not touch"
        end

        # With an even count the loop closes: the last seat sits under the first.
        if n >= 6 and rem(n, 2) == 0, do: assert(at[n - 1] == {2, 1})
      end
    end

    test "the page places the 8 tiles in the loop and never scrolls sideways" do
      {:ok, id} = GameServer.start(8, {1, 2, 3}, %{}, %{fortune: false})
      token = "eight-#{id}"

      {:ok, view, _html} =
        live(init_test_session(build_conn(), player_token: token), ~p"/g/#{id}")

      for _ <- 1..7, do: {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()

      html = render(view)
      assert count(html, ~s(#players-row[data-columns="4"] [data-role=player-chip])) == 8

      placed =
        html
        |> query("#players-row [data-role=player-chip]")
        |> Enum.map(fn t ->
          [seat] = LazyHTML.attribute(t, "data-seat")
          [row] = LazyHTML.attribute(t, "data-row")
          [col] = LazyHTML.attribute(t, "data-col")
          {seat, row, col}
        end)

      assert {"0", "1", "1"} in placed
      assert {"3", "1", "4"} in placed
      assert {"4", "2", "4"} in placed
      assert {"7", "2", "1"} in placed
      refute html =~ "overflow-x-auto snap-x"
    end
  end

  describe "the tile" do
    test "pot space (its coins), VP, rubies and black chips in the pot" do
      g = game(3) |> pot(1, 20, 2) |> H.put(1, vp: 14, rubies: 3)
      html = tile(g, 1)

      assert text(html, "[data-role=player-space]") =~ to_string(PotTrack.at(21).coins)
      assert count(html, ~s([data-role=player-space][data-index="21"])) == 1
      assert text(html, "[data-role=player-vp]") =~ "14"
      assert text(html, "[data-role=player-rubies]") =~ "3"
      # Round 31: while brewing the black count sits on the line's right end.
      assert text(html, "[data-role=tile-black]") =~ "2"
      assert count(html, "[data-role=seat-disc].bg-player-1") == 1
    end

    test "your tile has the gold border" do
      g = game(2)
      assert count(tile(g, 0, you: true), "[data-role=player-chip][data-you].border-gold") == 1
      assert count(tile(g, 1), "[data-role=player-chip].border-gold") == 0
    end

    test "exploded: red stripes and the burst badge" do
      g = game(3) |> pot(2, 12) |> H.put(2, exploded?: true)
      html = tile(g, 2)

      assert count(html, "[data-role=player-chip][data-boom].tile-boom") == 1
      assert count(html, ~s([data-role=player-state][data-state=exploded] svg)) == 1
    end

    test "stopped: faded with a check badge; brewing: no badge" do
      g = game(3) |> pot(1, 9)
      assert count(tile(g, 1), "[data-role=player-state]") == 0
      assert count(tile(g, 1), ".opacity-55") == 0

      html = tile(H.put(g, 1, phase: :stopped), 1)
      assert count(html, "[data-role=player-chip][data-stopped].opacity-55") == 1
      assert count(html, ~s([data-role=player-state][data-state=stopped] path[d^="M3 8.5"])) == 1
    end

    test "the round leader wears the crown and the gold glow" do
      g = game(3)
      html = tile(g, 1, lead: true)

      assert count(html, "[data-role=player-chip][data-lead].tile-lead [data-role=crown] svg") ==
               1

      assert count(tile(g, 1), "[data-role=crown]") == 0
    end
  end

  describe "round_leaders/1" do
    test "the furthest pot that did not explode; ties share the crown" do
      g = game(4) |> pot(0, 10) |> pot(1, 14) |> pot(2, 18) |> pot(3, 14)
      g = H.put(g, 2, exploded?: true)
      assert TileComponents.round_leaders(g) == [1, 3]

      g = H.put(g, 2, explosion_choice: :witch)
      assert TileComponents.round_leaders(g) == [2]
    end

    test "nobody before a chip is drawn, and nobody solo" do
      assert TileComponents.round_leaders(game(4)) == []
      assert TileComponents.round_leaders(game(1) |> pot(0, 10)) == []
    end

    test "the page crowns the leader's tile" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      token = "crown-#{id}"

      {:ok, view, _html} =
        live(init_test_session(build_conn(), player_token: token), ~p"/g/#{id}")

      {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()
      refute has_element?(view, "[data-role=crown]")

      H.replace_game(id, fn g -> g |> pot(0, 6) |> pot(1, 9) end)

      assert has_element?(
               view,
               ~s([data-role=player-chip][data-seat="1"][data-lead] [data-role=crown])
             )

      refute has_element?(view, ~s([data-role=player-chip][data-seat="0"] [data-role=crown]))
    end
  end

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
      skip_results(view)
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

      rows = ShopComponents.shop_rows(nil, %{locoweed: 1})
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

  defp attrs(html, selector, attr), do: html |> query(selector) |> LazyHTML.attribute(attr)

  describe "pot" do
    test "the droplet is a full piece on its space" do
      game = Game.new(seed: {1, 2, 3}, players: 2)
      game = put_in(game.players[0].droplet, 2)

      for size <- [:lg, :sm] do
        html = render_component(&PotComponents.pot/1, game: game, size: size)
        assert count(html, ~s(#droplet-0-#{size}[data-role=droplet][data-index="2"])) == 1
        assert count(html, ~s(#droplet-0-#{size} circle[r="19"])) == 1
      end
    end

    test "one rat piece per rat tail, on each space after the droplet" do
      game = Game.new(seed: {1, 2, 3}, players: 2)
      game = put_in(game.players[1].droplet, 2)
      game = put_in(game.players[1].rat_stone, 3)
      game = put_in(game.players[1].drawn, [{{:white, 1}, 6}])

      for size <- [:lg, :sm] do
        html = render_component(&PotComponents.pot/1, game: game, seat: 1, size: size)
        assert count(html, "[data-role=rat]") == 3
        assert attrs(html, "[data-role=rat]", "data-index") == ~w(3 4 5)
        # Round 35: a rat's id names its space.
        assert attrs(html, "[data-role=rat]", "id") == for(t <- 3..5, do: "rat-1-#{size}-#{t}")
        # The first chip lands after the last rat.
        assert attrs(html, "[data-role=pot-chip]", "data-index") == ["6"]
      end
    end

    test "no rat pieces without rat tails" do
      html = render_component(&PotComponents.pot/1, game: Game.new(seed: {1, 2, 3}))
      assert count(html, "[data-role=rat]") == 0
    end
  end

  test "the fortune card and its header tile are portrait cards" do
    html = render_component(&PanelComponents.fortune_card/1, id: :b3)
    assert count(html, "[data-role=fortune-card].card-portrait") == 1

    html = render_component(&PanelComponents.fortune_card/1, id: :b3, flip: true)
    assert count(html, "#card-flip-b3 [data-role=fortune-card].card-portrait") == 1

    html = render_component(&PanelComponents.fortune_tile/1, id: :b3)
    assert count(html, "[data-role=fortune-tile].card-portrait") == 1
    assert count(html, "[data-role=fortune-tile] [data-icon=bag]") == 1
  end

  test "the log is behind the menu, not in the desktop column" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    {:ok, view, _html} = live(init_test_session(build_conn(), player_token: "solo"), ~p"/g/#{id}")

    assert has_element?(view, "#sheet-log[popover]")
    refute has_element?(view, "[data-role=side-column] #sheet-log")
    refute has_element?(view, "#sheet-log.sheet-inline-lg")
    assert has_element?(view, ~s(#sheet-menu button[popovertarget="sheet-log"]), "Log")
    [class] = attrs(render(view), ~s(#sheet-menu button[popovertarget="sheet-log"]), "class")
    refute class =~ "lg:hidden"
  end

  describe "name card (2)" do
    test "shows rubies and the flask" do
      game = Game.new(seed: {1, 2, 3}, players: 2)
      game = put_in(game.players[1].rubies, 3)
      game = put_in(game.players[1].flask, false)
      html = render_component(&TileComponents.player_chip/1, game: game, seat: 1, name: "Bob")

      assert count(html, "[data-role=player-chip] [data-role=player-vp]") == 1
      assert html |> query("[data-role=player-rubies]") |> LazyHTML.text() =~ "3"
      assert count(html, ~s([data-role=player-flask][data-flask="empty"])) == 1
      assert count(html, "[data-role=player-rats]") == 0
      assert count(html, "[data-role=player-essence]") == 0
      assert count(html, "[data-role=player-tube]") == 0
    end

    test "shows rat tails, essence and the test tube when those are in play" do
      game = Game.new(seed: {1, 2, 3}, players: 2, expansions: [:alchemists])
      game = put_in(game.rules.pot_side, :back)
      game = put_in(game.players[1].rat_stone, 4)
      game = put_in(game.players[1].essence, 2)
      game = put_in(game.players[1].tube, 5)
      html = render_component(&TileComponents.player_chip/1, game: game, seat: 1, name: "Bob")

      assert html |> query("[data-role=player-rats]") |> LazyHTML.text() =~ "4"
      assert html |> query("[data-role=player-essence]") |> LazyHTML.text() =~ "2"
      assert html |> query("[data-role=player-tube]") |> LazyHTML.text() =~ "5"
      assert count(html, ~s([data-role=player-flask][data-flask="full"])) == 1
    end
  end
end
