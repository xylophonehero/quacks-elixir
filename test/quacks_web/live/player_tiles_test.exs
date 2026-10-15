defmodule QuacksWeb.PlayerTilesTest do
  @moduledoc """
  The players row and the player sheets: the seat loop of tiles, a tile's states (exploded, stopped, round leader), the name card anatomy, the update chips, the side panel and phone sheets, the board's chip order, the pieces on the board, the round's rat tails, the patient and essence pieces.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.Game
  alias Quacks.GameHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.Rules.Alchemists
  alias Quacks.Rules.PotTrack
  alias QuacksWeb.AlchemistsComponents
  alias QuacksWeb.PanelComponents
  alias QuacksWeb.PotComponents
  alias QuacksWeb.ShopComponents
  alias QuacksWeb.TileComponents

  doctest QuacksWeb.TileComponents, import: true, only: [ledger_columns: 2]

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

  describe "the ledger" do
    test "one column up to 4 seats on a phone, two from 5; more on wider screens" do
      assert for(n <- 1..8, do: TileComponents.ledger_columns(n, :phone)) ==
               [1, 1, 1, 1, 2, 2, 2, 2]

      assert for(n <- 1..8, do: TileComponents.ledger_columns(n, :md)) ==
               [1, 1, 2, 2, 2, 2, 2, 2]

      assert for(n <- 1..8, do: TileComponents.ledger_columns(n, :xl)) ==
               [1, 1, 2, 2, 3, 3, 3, 3]
    end

    test "the page lists the 8 rows in seat order, column by column" do
      {:ok, id} = GameServer.start(8, {1, 2, 3}, %{}, %{fortune: false})
      token = "eight-#{id}"

      {:ok, view, _html} =
        live(init_test_session(build_conn(), player_token: token), ~p"/g/#{id}")

      for _ <- 1..7, do: {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()

      html = render(view)
      assert count(html, ~s(#players-row[data-columns="2"] [data-role=player-chip])) == 8

      seats =
        html
        |> query("#players-row [data-role=player-chip]")
        |> Enum.flat_map(&LazyHTML.attribute(&1, "data-seat"))

      assert seats == Enum.map(0..7, &to_string/1)
      [style] = html |> query("#players-row") |> LazyHTML.attribute("style")
      assert style =~ "--rows: repeat(4, auto)"
      assert style =~ "--rows-xl: repeat(3, auto)"
      refute html =~ "overflow-x-auto snap-x"
    end
  end

  describe "the row" do
    test "while brewing: the white sum; else the pot space (its coins); the VP" do
      g = game(3) |> pot(1, 20, 2) |> H.put(1, vp: 14, rubies: 3)
      html = tile(g, 1)

      assert text(html, "[data-role=player-vp]") =~ "14"
      assert count(html, "[data-role=tile-white]") == 1
      assert count(html, "[data-role=player-space]") == 0
      assert count(html, "[data-role=seat-stripe].bg-player-1") == 1
      # Round 48: rubies, droplet, flask and the black count are in the sheet.
      assert count(html, "[data-role=player-rubies]") == 0

      html = tile(%{g | phase: :shopping}, 1)
      assert text(html, "[data-role=player-space]") =~ to_string(PotTrack.at(21).coins)
      assert count(html, ~s([data-role=player-space][data-index="21"])) == 1
    end

    test "your row is gold, with YOU" do
      g = game(2)
      html = tile(g, 0, you: true)
      assert count(html, "[data-role=player-chip][data-you].bg-gold\\/30") == 1
      assert text(html, "[data-role=player-chip]") =~ "you"
      assert count(tile(g, 1), "[data-role=player-chip].bg-gold\\/30") == 0
    end

    test "exploded: red stripes and the burst" do
      g = game(3) |> pot(2, 12) |> H.put(2, exploded?: true)
      html = tile(g, 2)

      assert count(html, "[data-role=player-chip][data-boom].tile-boom") == 1
      assert count(html, ~s([data-role=player-state][data-state=exploded] svg)) == 1
    end

    test "stopped: faded with a check; brewing: no mark" do
      g = game(3) |> pot(1, 9)
      assert count(tile(g, 1), "[data-role=player-state]") == 0
      assert count(tile(g, 1), ".opacity-55") == 0

      html = tile(H.put(g, 1, phase: :stopped), 1)
      assert count(html, "[data-role=player-chip][data-stopped].opacity-55") == 1
      assert count(html, ~s([data-role=player-state][data-state=stopped] path[d^="M3 8.5"])) == 1
    end

    test "the round leader wears the crown" do
      g = game(3)
      html = tile(g, 1, lead: true)

      assert count(html, "[data-role=player-chip][data-lead] [data-role=crown] svg") == 1
      assert count(tile(g, 1), "[data-role=crown]") == 0
    end

    test "the start player has the flag" do
      g = game(3)
      assert count(tile(g, 0), "[data-role=tile-start]") == 1
      assert count(tile(g, 1), "[data-role=tile-start]") == 0
    end

    test "the last draws are :sm chips with the icon, newest first" do
      g = game(2) |> H.put(1, drawn: [{{:green, 1}, 3}, {{:orange, 1}, 2}, {{:white, 1}, 1}])
      html = tile(g, 1, news: QuacksWeb.TileReveal.news(g, 1, nil))

      assert count(html, ~s([data-gain=drew] .chip-token)) == 3
      assert count(html, ~s([data-gain=drew][data-age="0"] [data-chip-icon=green])) == 1
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
    test "the name, the bot mark, the VP; the name is also screen-reader text" do
      game = Game.new(seed: {1, 2, 3}, players: 2) |> H.put(1, vp: 27, rubies: 2)
      html = card(game, 1, bot: true)

      assert text(html, "[data-role=tile-name]") =~ "Lavinia"
      assert text(html, "[data-role=player-name].sr-only") =~ "bot"
      assert count(html, "[data-role=bot-badge].hero-cpu-chip-micro") == 1
      assert text(html, "[data-role=player-vp]") =~ "27"
    end

    test "the status is a graphic; its word is for screen readers only" do
      game = Game.new(seed: {1, 2, 3}, players: 2)

      # A brewing row shows no mark.
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

    test "the patient's face is on the row" do
      game = Game.new(seed: {1, 2, 3}, players: 2) |> H.put(1, patient: :ear_worm)
      assert count(card(game, 1), "[data-role=player-patient] [data-icon=ear_worm]") == 1
    end

    test "the sheet has the pieces: rubies, droplet, flask, rat tails, pennies" do
      game =
        Game.new(seed: {1, 2, 3}, players: 2, expansion: :herb_witches, rules: %{rats: true})
        |> H.put(1, rubies: 2, rat_stone: 3)

      game = put_in(game.players[1].pennies, %{silver: true, copper: false, gold: true})

      html =
        render_component(&TileComponents.player_card/1,
          game: game,
          seat: 1,
          name: "Lavinia",
          bot: true
        )

      text = text(html, "[data-role=player-card] dl")
      assert text =~ "Rubies"
      assert text =~ "Droplet"
      assert text =~ "Flask"
      assert text =~ "Rat tails"
      assert text =~ "Pennies"
      assert text(html, "[data-role=peek-state]") =~ "Has not drawn yet"
      assert count(html, "[data-role=bot-badge]") == 1
    end

    test "more than 4 players: two columns, no sideways scroll" do
      {:ok, id} = GameServer.start(6, {1, 2, 3})
      token = "six-#{id}"
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      for _ <- 1..5, do: {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()

      html = render(view)

      assert count(html, ~s(#players-row[data-columns="2"] [data-role=player-chip])) == 6
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

    test "no timer ends the replay in app.js; the server opens what waited" do
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

  # Round 48: the pieces moved from the row to the player sheet (the tap view).
  describe "the pieces in the player sheet" do
    defp sheet(game),
      do: render_component(&TileComponents.player_card/1, game: game, seat: 1, name: "Bob")

    defp fact(html, label) do
      html
      |> query("[data-role=player-card] dl > div")
      |> Enum.find_value(fn d -> if LazyHTML.text(d) =~ label, do: LazyHTML.text(d) end)
    end

    test "shows rubies and the flask; no rats, essence or tube while off" do
      game = Game.new(seed: {1, 2, 3}, players: 2, rules: %{rats: false})
      game = put_in(game.players[1].rubies, 3)
      game = put_in(game.players[1].flask, false)
      html = sheet(game)

      assert fact(html, "Rubies") =~ "3"
      assert fact(html, "Flask") =~ "empty"
      refute fact(html, "Rat tails")
      refute fact(html, "Essence")
      refute fact(html, "Test tube")
    end

    test "shows rat tails, essence and the test tube when those are in play" do
      game =
        Game.new(seed: {1, 2, 3}, players: 2, expansions: [:alchemists], rules: %{rats: true})

      game = put_in(game.rules.pot_side, :back)
      game = put_in(game.players[1].rat_stone, 4)
      game = put_in(game.players[1].essence, 2)
      game = put_in(game.players[1].tube, 5)
      html = sheet(game)

      assert fact(html, "Rat tails") =~ "4"
      assert fact(html, "Essence") =~ "2"
      assert fact(html, "Test tube") =~ "5"
      assert fact(html, "Flask") =~ "full"
    end
  end

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice-#{id}"), id)
    bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {id, alice, bob}
  end

  # The game process stops, as after a crash or the idle timeout.

  test "a player sheet renders its body only while it is open" do
    {_id, alice, _bob} = duo()
    sheet = "#sheet-player-1[data-on-hide]"
    assert has_element?(alice, sheet)
    refute has_element?(alice, "#{sheet} [data-role=player-card]")

    alice |> element(~s([data-role=player-chip][data-seat="1"])) |> render_click()
    assert has_element?(alice, "#{sheet} [data-role=player-card]")
    refute has_element?(alice, "#sheet-player-0 [data-role=player-card]")

    render_click(alice, "close_player", %{"seat" => 1})
    refute has_element?(alice, "[data-role=player-card]")
  end

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.

  describe "patients and essence" do
    test "the slot grid draws glasses with glyphs; the reached glass is ringed" do
      html = render_component(&AlchemistsComponents.slot_grid/1, id: :carrot_nose, reached: 7)

      assert count(html, "li[data-space]") == 10
      assert count(html, ~s(li[data-space="1"] [data-glyph=rat])) == 1
      assert count(html, ~s(li[data-space="7"][data-reached] [data-glyph=vp])) == 1
      # the words stay for screen readers
      assert html |> query(~s(li[data-space="7"] .sr-only)) |> LazyHTML.text() =~ "1 VP"
    end

    test "the patient card shows the patient's picture large" do
      html = render_component(&AlchemistsComponents.patient_card/1, id: :ear_worm)
      assert count(html, "[data-role=patient-card] svg.size-12[data-icon=ear_worm]") == 1
      assert html =~ Alchemists.get(:ear_worm).name
    end

    test "the essence strip is a rack of vials" do
      game = Game.new(seed: {1, 2, 3}, expansions: [:alchemists])
      game = GameHelpers.put(game, 0, patient: :carrot_nose, essence: 3)
      html = render_component(&AlchemistsComponents.flask_strip/1, game: game, seat: 0)

      assert count(html, "[data-role=flask-strip] [data-role=essence-rack] li") == 11
      assert count(html, "[data-role=essence-rack] [data-role=essence-marker]") == 1
    end
  end

  defp duo_2(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, rules)
    alice = open(browser("alice-#{id}"), id)
    bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {id, alice, bob}
  end

  describe "player sheets" do
    test "another player's sheet shows the test tubes and the essence strip" do
      {:ok, id} =
        GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false, pot_side: :back}, nil)

      alice = open(browser("alice-#{id}"), id)
      _bob = open(browser("bob-#{id}"), id)
      {:ok, _} = GameServer.begin(id, "alice-#{id}")
      replace_game(id, &H.put(&1, 1, tube: 3, patient: :ear_worm, essence: 4))

      alice |> element(~s([data-role=player-chip][data-seat="1"])) |> render_click()
      card = "#sheet-player-1 [data-role=player-card]"
      assert has_element?(alice, ~s(#{card} svg[data-role=test-tubes][data-tube="3"]))
      assert has_element?(alice, ~s(#{card} [data-role=flask-strip][data-essence="4"]))
    end

    test "a tap on a second player while a sheet is open shows that player's sheet" do
      {_id, alice, _bob} = duo_2()
      alice |> element(~s([data-role=player-chip][data-seat="0"])) |> render_click()
      assert has_element?(alice, "#sheet-player-0 [data-role=player-card]")

      # the second chip's open arrives first, the first sheet's light-dismiss after
      alice |> element(~s([data-role=player-chip][data-seat="1"])) |> render_click()
      render_click(alice, "close_player", %{"seat" => 0})
      assert has_element?(alice, "#sheet-player-1 [data-role=player-card]")

      render_click(alice, "close_player", %{"seat" => 1})
      refute has_element?(alice, "[data-role=player-card]")
    end
  end

  describe "the rat tails at the start of the round" do
    test "a line under the players row names this round's rat tails; the results do not" do
      {id, alice, _bob} = duo_2()
      replace_game(id, &(&1 |> H.put(0, rat_stone: 2) |> H.put(1, rat_stone: 0)))
      # Round 11: the rat tails show on the name cards only, no line.
      refute has_element?(alice, "[data-role=round-rats]")

      replace_game(id, &H.put(&1, 0, phase: :buy, vp: 0))
      refute has_element?(alice, "[data-role=round-rats]")
      refute has_element?(alice, "[data-role=result-rats]")
      refute render(alice) =~ "Rats next round"
    end
  end

  # A player detail sheet renders its body once its chip in the players row is tapped.
  defp open_player(view, seat),
    do: view |> element(~s([data-role=player-chip][data-seat="#{seat}"])) |> render_click()

  # Seed 10,11,12 draws white 2, 3, 1: stop there for a shop with 7 coins.

  defp duo_3 do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    {:ok, _} = GameServer.begin(id, "alice")
    {id, alice, bob}
  end

  # The rest of `to_shop_2/1` after one draw, then "Done" (round over).

  test "the players row: one chip per seat, yours marked; a tap opens the detail sheet" do
    {_id, alice, _bob} = duo_3()

    # an outlined pill (seat-colour ring, parchment fill), not a gold button look-alike
    assert has_element?(alice, "[data-role=you-are] .ring-player-0.bg-parchment", "Player 1")
    refute has_element?(alice, "[data-role=you-are] .bg-player-0")
    assert has_element?(alice, "[data-role=my-seat].border-player-0")

    html = render(alice)
    assert count(html, "[data-role=players-row] [data-role=player-chip]") == 2

    assert has_element?(
             alice,
             ~s([data-role=player-chip][data-seat="0"][data-you].bg-gold\\/30),
             "you"
           )

    refute has_element?(alice, ~s([data-role=player-chip][data-seat="1"][data-you]))

    # Round 27: a brewing tile has no state badge (design B).
    assert has_element?(
             alice,
             ~s([data-role=player-chip][data-seat="1"][popovertarget="sheet-player-1"])
           )

    refute has_element?(
             alice,
             ~s([data-role=player-chip][data-seat="1"] [data-role=player-state])
           )

    sheet = ~s(#sheet-player-1[popover] article[data-seat="1"])
    # the sheet's body renders only while it is open
    refute has_element?(alice, sheet)
    open_player(alice, 1)
    assert has_element?(alice, "#{sheet} svg[aria-label='Pot track']")
    assert has_element?(alice, "#{sheet} [data-role=player-bag]", "In the bag: 9")
    assert has_element?(alice, "#{sheet} [data-role=player-bag] [aria-label='white 1']")
    assert has_element?(alice, "#{sheet} dt", "Rubies")
    assert has_element?(alice, "#{sheet} dt", "Flask")
  end
end
