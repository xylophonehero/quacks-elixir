defmodule QuacksWeb.GameLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias Quacks.Rules.Chips
  alias QuacksWeb.{GameComponents, GameLive}

  @pot_chip "[data-role=pot-chip]"

  # Every test browser gets its own player token, as the PlayerToken plug would.
  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "solo-#{System.unique_integer()}")}
  end

  # A solo game in a GameServer, opened in the browser (which takes seat 0).
  defp live_game(conn, seed) do
    {:ok, id} = GameServer.start(1, seed)
    live(conn, ~p"/g/#{id}")
  end

  defp mount(conn), do: live_game(conn, {1, 2, 3})

  defp pot_chips(view), do: view |> render() |> count(@pot_chip)

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  # The first legal action is the first enabled action button on the page.
  defp first_action(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[phx-value-action]:not([disabled])")
    |> LazyHTML.attribute("phx-value-action")
    |> List.first()
  end

  # One step: the first legal action, or (an empty rubies step waits for it) close
  # the round results as the browser does.
  defp step(view, html) do
    case first_action(html) do
      nil ->
        round =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("[data-role=round-counter]")
          |> LazyHTML.text()
          |> String.trim()
          |> Integer.parse()
          |> elem(0)

        render_hook(view, "seen", %{"kind" => "results", "round" => round})

      action ->
        render_click(view, "action", %{"action" => action})
    end
  end

  test "mounts round 1 with a Draw button and the seed", %{conn: conn} do
    {:ok, view, html} = mount(conn)
    assert html =~ "1 / 9"
    assert html =~ "Seed"
    assert html =~ "1,2,3"
    assert has_element?(view, "button", "Draw a chip")
    assert pot_chips(view) == 0
  end

  test "Draw places a chip in the pot and Undo takes it back", %{conn: conn} do
    {:ok, view, _html} = mount(conn)

    view |> element("button", "Draw a chip") |> render_click()
    assert pot_chips(view) == 1
    assert has_element?(view, "li", ~r/Drew white \d → space \d/)
    refute has_element?(view, "li", "Draw a chip")

    view |> element("button", "Undo") |> render_click()
    assert pot_chips(view) == 0
  end

  test "a malformed action payload shows a flash and does not crash", %{conn: conn} do
    {:ok, view, _html} = mount(conn)

    html = render_click(view, "action", %{"action" => "not-base64!!"})
    assert html =~ "That move could not be read."
    assert Process.alive?(view.pid)
  end

  test "a well-formed but illegal action shows a flash", %{conn: conn} do
    {:ok, view, _html} = mount(conn)

    html = render_click(view, "action", %{"action" => GameLive.encode(:stop)})
    assert html =~ "Stop is not allowed right now."
    assert pot_chips(view) == 0
  end

  test "decode rejects payloads that would create functions or atoms" do
    assert {:error, :bad_action} = GameLive.decode("@@@")
    fun = :erlang.term_to_binary(fn -> :boom end) |> Base.url_encode64(padding: false)
    assert {:error, :bad_action} = GameLive.decode(fun)
    assert {:ok, {:buy, [{:green, 2}]}} = GameLive.decode(GameLive.encode({:buy, [{:green, 2}]}))
  end

  test "clicking the first legal action until the end reaches game over", %{conn: conn} do
    {:ok, view, html} = mount(conn)

    html =
      Enum.reduce_while(1..500, html, fn _, html ->
        if html =~ "Game over",
          do: {:halt, html},
          else: {:cont, step(view, html)}
      end)

    assert html =~ "Game over"
    assert html =~ "victory points"

    assert has_element?(view, "#game-over [data-role=buying-power]", "Final coins and rubies")

    assert has_element?(view, "#game-over [data-role=return-to-lobby]", "Return to lobby")
    refute has_element?(view, "[data-role=action-bar]")
    refute has_element?(view, "button[data-slot=draw]")
    refute has_element?(view, "button[data-slot=stop]")

    {:ok, view, _html} =
      view
      |> element("#game-over button", "Play again")
      |> render_click()
      |> follow_redirect(conn)

    # The new game has a random seed; a purple fortune card may open with a choice.
    assert has_element?(view, "button[phx-click=action]")
  end

  # A shop with 7 coins: seed 10,11,12 draws white 2, 3, 1 (index 6, scoring space 7).
  defp mount_shop(conn) do
    {:ok, view, _html} = live_game(conn, {10, 11, 12})
    for _ <- 1..3, do: view |> element("button", "Draw a chip") |> render_click()
    view |> element("button", "Stop") |> render_click()
    assert has_element?(view, "dd", "Shop")
    assert has_element?(view, "[data-role=coins]", "7 coins to spend")
    view
  end

  defp select(view, chips),
    do: render_change(view, "select", %{"chips" => Enum.map(chips, &GameLive.encode/1)})

  defp checkbox(chip), do: ~s(#shop input[value="#{GameLive.encode(chip)}"])

  defp bag_size(view) do
    [_, n] = Regex.run(~r/Bag \((\d+) chips\)/, render(view))
    String.to_integer(n)
  end

  test "the pot draws each chip on its recorded space", %{conn: _conn} do
    game = Game.new(seed: {1, 2, 3})
    game = put_in(game.players[0].drawn, [{{:red, 2}, 4}, {{:orange, 1}, 1}])
    html = render_component(&GameComponents.pot/1, game: game)
    assert count(html, ~s([data-space="4"] #{@pot_chip}[aria-label="red 2"])) == 1
    assert count(html, ~s([data-space="1"] #{@pot_chip}[aria-label="orange 1"])) == 1
    assert count(html, ~s([data-space="3"] #{@pot_chip})) == 0
    assert count(html, @pot_chip) == 2
  end

  test "the pot shows the rat stone at droplet + rat stone, only when there is one" do
    game = Game.new(seed: {1, 2, 3}, players: 2)
    html = render_component(&GameComponents.pot/1, game: game, seat: 1)
    assert count(html, "[data-role=rat-stone]") == 0

    game = put_in(game.players[1].droplet, 2)
    game = put_in(game.players[1].rat_stone, 3)

    for size <- [:lg, :sm] do
      html = render_component(&GameComponents.pot/1, game: game, seat: 1, size: size)
      assert count(html, ~s([data-role=rat-stone][data-index="5"])) == 1
      assert count(html, "[data-role=rat-stone]") == 1
    end
  end

  test "the game page fills the screen: full layout, sheets for bag and log", %{conn: conn} do
    {:ok, view, html} = mount(conn)
    assert has_element?(view, "main[data-layout=full]")
    refute html =~ "py-20"
    refute html =~ "max-w-2xl"
    assert has_element?(view, ~s([data-role=pot-area] button[popovertarget="sheet-bag"]), "9")
    assert has_element?(view, ~s(#sheet-menu button[popovertarget="sheet-log"]), "Log")
    assert has_element?(view, "#sheet-log[popover]")
    # solo: one name card, for the update chips of the round
    assert has_element?(view, "[data-role=players-row] [data-role=player-chip]")
  end

  test "the shop dialog is in the page only while shopping", %{conn: conn} do
    {:ok, view, _html} = live_game(conn, {10, 11, 12})
    refute has_element?(view, "dialog#decision-shop")

    view = mount_shop(conn)
    assert has_element?(view, "dialog#decision-shop #shop")
    assert has_element?(view, "dialog#decision-shop[phx-mounted]")

    # 1 ruby: nothing to spend, so the buy ends the round at once
    view |> element("[data-role=shop-done]") |> render_click()
    refute has_element?(view, "dialog#decision-shop")
    assert has_element?(view, "li", "— Round 1 over —")
  end

  test "an unknown game id sends the browser to the lobby", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/g/nosuch")
  end

  test "the crow skull strip shows duplicate offers, each chip a button" do
    game = Game.new(seed: {1, 2, 3})
    game = put_in(game.players[0].phase, :blue_choice)
    game = put_in(game.players[0].pending, [{:white, 1}, {:white, 1}])
    assert Game.legal_actions(game) == [{:place, {:white, 1}}, :return_all]

    html =
      render_component(&GameLive.chip_picks/1,
        actions: Game.legal_actions(game),
        pool: game.players[0].pending,
        game: game,
        me: game.players[0]
      )

    place = GameLive.encode({:place, {:white, 1}})

    assert count(
             html,
             ~s(button[phx-value-action="#{place}"] [data-role="offer-chip"][aria-label="white 1"])
           ) == 2
  end

  test "shop: tick two chips, buy them, the bag grows", %{conn: conn} do
    view = mount_shop(conn)
    [_, before] = Regex.run(~r/Your chips: (\d+)/, render(view))
    before = String.to_integer(before)
    assert has_element?(view, "button[data-role=shop-buy]:disabled", "Buy")
    assert has_element?(view, checkbox({:orange, 1}) <> ":not(:disabled)")
    assert has_element?(view, checkbox({:yellow, 1}) <> ":disabled")
    assert has_element?(view, checkbox({:green, 2}) <> ":disabled")

    select(view, [{:orange, 1}])
    assert has_element?(view, checkbox({:orange, 1}) <> ":checked")

    assert has_element?(
             view,
             ~s([data-role=shop-total][aria-label="7 coins, 4 left after this buy"])
           )

    assert has_element?(view, "button[data-role=shop-buy]", "Buy 1 · 3 coins")
    assert has_element?(view, checkbox({:green, 1}) <> ":not(:disabled)")

    select(view, [{:orange, 1}, {:green, 1}])

    assert has_element?(
             view,
             ~s([data-role=shop-total][aria-label="7 coins, 0 left after this buy"])
           )

    assert has_element?(view, "button[data-role=shop-buy]:not(:disabled)", "Buy 2 · 7 coins")
    # with two ticked, every other box is disabled
    assert count(render(view), "#shop input:disabled") == length(Chips.shop()) - 2

    view |> element("button[data-role=shop-buy]") |> render_click()
    assert has_element?(view, "li", "Bought green 1 + orange 1")
    # the round ended (nothing left to do): every chip is back in the bag
    assert bag_size(view) == before + 2
  end

  test "shop: one row per colour in step B order, chips as tiles", %{conn: conn} do
    html = conn |> mount_shop() |> render() |> LazyHTML.from_fragment()

    first_per_row =
      html
      |> LazyHTML.query("[data-role=shop-row] li:first-child [aria-label]")
      |> LazyHTML.attribute("aria-label")

    assert first_per_row ==
             ["orange 1", "blue 1", "red 1", "yellow 1", "black 1", "green 1", "purple 1"]

    green_row = html |> LazyHTML.query("[data-role=shop-row]") |> Enum.at(5)

    assert LazyHTML.attribute(LazyHTML.query(green_row, "[aria-label]"), "aria-label") ==
             ["green 1", "green 2", "green 4"]

    assert html |> LazyHTML.query("[data-role=shop-row] [aria-label]") |> Enum.count() ==
             length(Chips.shop())

    assert GameLive.shop_rows() |> List.flatten() |> Enum.sort() == Chips.shop()
    # no visible checkboxes: each box is hidden inside its tile, with a check glyph
    assert html |> LazyHTML.query("#shop input[type=checkbox]:not(.sr-only)") |> Enum.empty?()

    assert html |> LazyHTML.query("#shop label [data-role=tile-check]") |> Enum.count() ==
             length(Chips.shop())
  end

  test "the log narrates the scoring space and the round end", %{conn: conn} do
    # seed 10,11,12 stops on scoring space 7: 7 coins, 1 VP, no ruby
    view = mount_shop(conn)
    assert has_element?(view, "li", "Scoring space 7: +1 VP")
    refute render(view) =~ "Round 1 over"

    view |> element("[data-role=shop-done]") |> render_click()
    assert has_element?(view, "li", "— Round 1 over —")
    refute has_element?(view, "li", "End round")
  end

  test "shop: a selection the engine rejects cannot be bought", %{conn: conn} do
    view = mount_shop(conn)
    # a crafted change event with two greens (same colour) and an unaffordable total
    select(view, [{:green, 1}, {:green, 2}])
    assert has_element?(view, "button[data-role=shop-buy]:disabled", "Buy 2 · 12 coins")

    assert has_element?(
             view,
             ~s([data-role=shop-total][aria-label="7 coins, -5 left after this buy"])
           )

    view |> element("[data-role=shop-done]") |> render_click()
    assert has_element?(view, "li", "— Round 1 over —")
  end

  test "every engine action in the choice phases has a human label" do
    for action <- [:return_white, :keep, {:place, {:white, 1}}, :return_all] do
      refute GameComponents.label(action) =~ ~r/^[:{]/
    end
  end

  test "every scoring event has a human label" do
    assert GameComponents.label({:green_rubies, 2}) == "Garden spider: +2 rubies"
    assert GameComponents.label({:green_rubies, 1}) == "Garden spider: +1 ruby"

    assert GameComponents.label({:purple, 2, :vp1_ruby}) ==
             "Ghost's breath (tier 2): +1 VP, +1 ruby"

    assert GameComponents.label({:black, :droplet}) == "Hawkmoth: droplet +1"
    assert GameComponents.label({:black, :droplet_ruby}) == "Hawkmoth: droplet +1, +1 ruby"
    assert GameComponents.label({:rats, 3}) == "Rats: 3 tails"
    assert GameComponents.label({:pot_ruby, 24}) == "Scoring space 24: +1 ruby"
    assert GameComponents.label({:pot_vp, 8, 24}) == "Scoring space 24: +8 VP"
    assert GameComponents.label({:round_end, 4}) == "— Round 4 over —"

    assert GameComponents.label({:final_conversion, 17, 3, 5, 2}) ==
             "Final: 17 coins → 3 VP, 5 rubies → 2 VP"

    for event <- [{:purple, 1, :vp1}, {:purple, 3, :vp2_droplet}] do
      refute GameComponents.label(event) =~ ~r/^[:{]/
    end
  end
end
