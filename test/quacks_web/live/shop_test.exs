defmodule QuacksWeb.ShopTest do
  @moduledoc """
  The shop: the sticky footer, prices and locks, the tiles from 64rem, the chips you own, a buy that ends the shop, round 9 without a shop, Ghost's breath V's chips, every seat's scoring ring, another seat's buy, Flea Market, the black book and the status line.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.Game
  alias Quacks.Game.Round
  alias Quacks.GameHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.Player
  alias Quacks.Rules.Chips
  alias QuacksWeb.ActionCode
  alias QuacksWeb.PanelComponents
  alias QuacksWeb.ShopComponents

  @panel "#purple-buy-panel-1[data-role=purple-buy]"
  @bar "[data-role=bar-chip-actions]"

  # Ghost's breath V open in the bar: two purple chips on the pot's late spaces.
  defp ghost_breath do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false}, :herb_witches)
    {:ok, view, _html} = live(browser("r39-#{System.unique_integer()}"), ~p"/g/#{id}")

    replace_game(id, fn g ->
      %{g | sets: Map.put(g.sets, :purple, 5)}
      |> H.put(
        phase: :explosion_choice,
        exploded?: true,
        drawn: [{{:purple, 1}, 40}, {{:purple, 1}, 30}],
        pot_index: 40
      )
      |> H.apply!({:explosion_choice, :buy})
    end)

    {:ok, %{game: game}} = GameServer.get(id)
    {:purple_buy, coins} = Enum.find(game.players[0].chip_choices, &match?({:purple_buy, _}, &1))
    {id, view, game, coins}
  end

  defp tick(view, chips),
    do:
      view
      |> element("#purple-buy-1")
      |> render_change(%{"chips" => Enum.map(chips, &ActionCode.encode/1)})

  describe "Ghost's breath V picks its chips in the context area" do
    test "a panel, not a sheet: every chip of the shop, the dear ones greyed" do
      {_id, view, game, coins} = ghost_breath()

      refute has_element?(view, "dialog [data-role=purple-buy]")
      assert has_element?(view, "[data-area=context] > #{@panel}.pick-panel")

      shop = List.flatten(ShopComponents.shop_rows(game.expansions, game.sets))
      assert length(shop) == length(view |> render() |> chips_in("#{@panel} label"))

      for chip <- shop, Chips.price(chip, game.sets) > coins do
        assert has_element?(
                 view,
                 "#{@panel} [data-role=purple-buy-off][data-chip='#{elem(chip, 0)} #{elem(chip, 1)}'] input:disabled"
               )
      end

      assert has_element?(view, "#{@panel} [data-role=purple-buy-tile][data-chip='orange 1']")
    end

    test "the purse and Take are in the bar; the panel has no footer of its own" do
      {id, view, game, coins} = ghost_breath()

      refute has_element?(view, "#{@panel} button[phx-click=action]")
      assert has_element?(view, "#{@bar} [data-role=purple-buy-total]", "#{coins}")
      assert has_element?(view, "#{@bar} [data-role=purple-buy-take]:disabled")
      refute has_element?(view, "[data-role=purple-buy-open]")

      tick(view, [{:green, 1}])
      left = coins - Chips.price({:green, 1}, game.sets)

      assert has_element?(
               view,
               "#{@bar} [data-role=purple-buy-total][aria-label='#{coins} coins, #{left} left after this']"
             )

      # The other greens are not with the ticked green.
      assert has_element?(
               view,
               "#{@panel} [data-role=purple-buy-off][data-chip='green 2'][title*='not with your other chip']"
             )

      view |> element("#{@bar} [data-role=purple-buy-take]", "Take 1") |> render_click()
      {:ok, %{game: game}} = GameServer.get(id)
      assert Enum.any?(game.log, &match?({0, {:chip, {:buy, [{:green, 1}]}}}, &1))
      refute has_element?(view, @panel)
    end

    test "on a phone the panel folds to its title (the chevron)" do
      {_id, view, _game, _coins} = ghost_breath()

      assert has_element?(
               view,
               "#{@panel} button.lg\\:hidden[data-role=purple-buy-fold][aria-controls=purple-buy-1]"
             )

      css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
      assert css =~ ".pick-panel.pick-folded .pick-tiles"
      assert css =~ "position-anchor: --pot-area"
    end
  end

  describe "every seat's scoring ring moves with yours" do
    test "the hook takes every ring, and moves them on any update, after your chip's flight" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      [_, hook] = String.split(js, "const PotMotion", parts: 2)
      [hook, _] = String.split(hook, "const csrfToken", parts: 2)

      assert hook =~ ~s{querySelectorAll("[data-role=next-space], [data-role=scoring-ring]")}
      refute hook =~ "[data-role=scoring-ring][data-seat="
      # your flight sets the wait; any update moves the changed marks
      assert hook =~ "this.wait = 460"
      assert hook =~ "if (!newRound && !reduced()) this.scoringMove(this.wait)"
    end

    test "the bots' rings are on your pot, one per seat, each with its seat" do
      {:ok, id} = GameServer.start(3, {1, 2, 3})
      token = "r39-rings-#{System.unique_integer()}"
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      for _ <- 2..3, do: {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()
      view |> element("button[data-slot=draw]") |> render_click()

      for seat <- 0..2 do
        assert has_element?(
                 view,
                 "#pot-0-lg [data-space] [data-role=scoring-ring][data-seat='#{seat}']"
               )
      end
    end
  end

  defp chips_in(html, selector),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.to_list()

  # Two seats in the shop, both with coins to spend.
  defp duo_in_shop do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    {:ok, _} = GameServer.begin(id, "alice")

    for view <- [alice, bob] do
      view |> element("button[data-slot=draw]") |> render_click()
      view |> element("button", "Stop") |> render_click()
    end

    GameHelpers.replace_game(id, fn g ->
      Enum.reduce([0, 1], g, &GameHelpers.put(&2, &1, coins: 30))
    end)

    {:ok, %{game: game}} = GameServer.get(id)
    {id, alice, bob, game}
  end

  defp buy_of(game, seat) do
    game
    |> Game.legal_actions(seat)
    |> Enum.find(&match?({:buy, [_]}, &1))
  end

  test "a buy of another seat keeps this seat's shop selection" do
    {id, alice, bob, game} = duo_in_shop()
    assert has_element?(alice, "dialog#decision-shop")

    {:buy, [chip]} = buy_of(game, 0)
    alice |> element("#shop") |> render_change(%{"chips" => [QuacksWeb.ActionCode.encode(chip)]})

    assert has_element?(
             alice,
             "#shop input[checked][value='#{QuacksWeb.ActionCode.encode(chip)}']"
           )

    {:buy, [bob_chip]} = buy_of(game, 1)

    bob
    |> element("#shop")
    |> render_change(%{"chips" => [QuacksWeb.ActionCode.encode(bob_chip)]})

    bob |> element("[data-role=shop-buy]") |> render_click()
    assert {:ok, %{game: after_buy}} = GameServer.get(id)
    assert length(after_buy.log) > length(game.log)

    # alice's page got bob's buy, and her tick is still there
    _ = render(alice)

    assert has_element?(
             alice,
             "#shop input[checked][value='#{QuacksWeb.ActionCode.encode(chip)}']"
           )

    refute has_element?(alice, "[data-role=shop-buy][disabled]")
  end

  # Solo, round 2, Flea Market turned up with this bag.
  defp flea_market(bag) do
    {:ok, id} = GameServer.start(1, {1, 2, 3})
    {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")

    GameHelpers.replace_game(id, fn g ->
      g
      |> GameHelpers.put(0, bag: bag, drawn: [], pending: [])
      |> GameHelpers.put(fortune_deck: [:p13], round: 2)
      |> Round.start_round()
    end)

    skip_results(view)

    view
  end

  test "Flea Market: the drawn chips are a picker; a chip that cannot go up says why" do
    view = flea_market([{:green, 1}, {:white, 1}, {:orange, 1}, {:red, 1}])
    # Round 31: the trades are bar buttons; the rows over the pot say why a chip stays.
    assert has_element?(view, "[data-role=bar-card] [data-choice=upgrade]")

    assert has_element?(
             view,
             "[id^=card-stage] [data-role=reveal-chip][title='white stays']"
           )

    refute has_element?(view, "#sheet-fortune-reveals [data-role=flea-result]")
  end

  test "Flea Market with nothing to trade up: all 4 chips, why, and the green 1" do
    view = flea_market(List.duplicate({:white, 1}, 4))
    refute has_element?(view, "[data-role=chip-pick]")

    assert has_element?(
             view,
             "#sheet-fortune-reveals [data-role=reveal-chip][title='white stays']"
           )

    assert has_element?(view, "#sheet-fortune-reveals [data-me] [data-gain=chip]")
    assert has_element?(view, "#sheet-fortune-reveals [data-role=flea-result]", "green 1")
  end

  # Play seat 0 of a solo game to the shop.
  defp to_shop(id) do
    Enum.find_value(1..60, fn _ ->
      {:ok, %{game: game}} = GameServer.get(id)
      actions = Game.legal_actions(game, 0)

      if game.phase == :shopping do
        # coins to buy with: a seat that can buy nothing skips the shop
        Quacks.GameHelpers.replace_game(id, &Quacks.GameHelpers.put(&1, 0, coins: 30))
      else
        action =
          Enum.find([:stop, :chip_done, {:explosion_choice, :buy}], hd(actions), &(&1 in actions))

        {:ok, _} = GameServer.apply(id, 0, action)
        nil
      end
    end)
  end

  test "the black book is offered without the expansion and reaches the game" do
    # Round 26: the books are picked in the spell book.
    {:ok, view, _html} = live(browser("host"), ~p"/?step=book&colour=black")

    refute has_element?(view, "#expansion[checked]")
    assert has_element?(view, "input[name='sets[black]'][value='2']")
    assert has_element?(view, "input[name='sets[black]'][value='3']")
    refute has_element?(view, "input[name='sets[black]'][value='5']")

    view |> element("#books") |> render_change(%{"sets" => %{"black" => "3"}})
    render_click(view, "players", %{"count" => "1"})

    {:error, {:live_redirect, %{to: "/g/" <> id}}} =
      view |> element("#new-game") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    refute Game.expansion?(game, :herb_witches)
    assert game.sets.black == 3
  end

  # Round 31: no dialog: the card hovers over the pot, its choices are the bar.
  test "a card with a choice: the card over the pot, the choices in the bar" do
    # seed 86,86,86 with 2 players deals a purple card with a choice for both seats
    {:ok, id} = GameServer.start(2, {86, 86, 86})
    alice = open(browser("alice"), id)
    _bob = open(browser("bob"), id)
    alice |> element("button", "Start game") |> render_click()

    refute has_element?(alice, "#decision-fortune_choice")
    refute has_element?(alice, "dialog#card-round-1")
    assert has_element?(alice, "#pot-card-1 [data-role=fortune-card]")
    assert has_element?(alice, "footer #bar-card-1 button", "No thanks")
    refute has_element?(alice, "footer #card-continue")

    alice |> element("#bar-card-1 button", "No thanks") |> render_click()
    # answered: the bar goes, and the card counts as seen (no reveal afterwards).
    # Round 35: the card stays, grown, with what everyone took, until Continue.
    refute has_element?(alice, "#bar-card-1")

    assert has_element?(
             alice,
             "#card-stage-1 [data-role=card-reveal-row][data-seat='0']",
             "passed"
           )

    alice |> element("#card-continue") |> render_click()
    refute has_element?(alice, "#pot-card-1")
    refute has_element?(alice, "[data-role=reveal]")
  end

  test "the card band: blue is for this round, purple says nothing more" do
    blue = render_component(&PanelComponents.fortune_card/1, id: :b1)
    purple = render_component(&PanelComponents.fortune_card/1, id: :p1)

    assert blue =~ "Fortune teller · this round"
    assert purple =~ "Fortune teller"
    refute purple =~ "Fortune teller ·"

    assert render_component(&PanelComponents.fortune_card/1, id: :p1, choice: true) =~
             "resolve now"
  end

  test "shop tiles: a tapped chip is outlined with a check, the others dim" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("solo"), id)
    to_shop(id)
    render(view)

    chip = {:orange, 1}
    render_change(view, "select", %{"chips" => [QuacksWeb.ActionCode.encode(chip)]})

    checked = ~s(#shop input[value="#{QuacksWeb.ActionCode.encode(chip)}"][checked])
    assert has_element?(view, checked)
    assert has_element?(view, "#shop label.has-checked\\:ring-\\[3px\\] input[checked]")
    # yellow is not for sale in round 1: its tile is hatched, locked and disabled
    assert has_element?(view, "#shop label.shop-locked [data-role=tile-lock]")
    assert has_element?(view, "#shop label.shop-locked input:disabled")
  end

  test "a chip offer has an info button with the books of the colours offered" do
    game = Game.new(seed: {1, 2, 3}, sets: %{red: 2})
    offer = [[{:white, 1}, {:red, 2}], [{:place, {:blue, 1}}, :return_all, {:rubies, 2}]]

    html =
      render_component(&QuacksWeb.ShopComponents.offer_books/1,
        id: "books-x",
        game: game,
        offer: offer
      )

    assert html =~ ~s(popovertarget="books-x")
    assert html =~ ~s(data-book="red-2")
    assert html =~ ~s(data-book="blue-1")
    refute html =~ ~s(data-book="white)

    assert render_component(&QuacksWeb.ShopComponents.offer_books/1,
             id: "y",
             game: game,
             offer: [:stop]
           ) == ""
  end

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.
  defp to_shop_2(id) do
    Enum.find_value(1..60, fn _ ->
      game = game(id)
      actions = Game.legal_actions(game, 0)

      if game.phase == :shopping do
        GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, coins: 30))
      else
        action =
          Enum.find([:stop, :chip_done, {:explosion_choice, :buy}], hd(actions), &(&1 in actions))

        {:ok, _} = GameServer.apply(id, 0, action)
        nil
      end
    end)
  end

  defp shop_view do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("shopper"), id)
    to_shop_2(id)
    render(view)
    view
  end

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  describe "the shop sheet" do
    test "a sticky footer holds the purse, Done and the buy with its count and price" do
      view = shop_view()
      footer = "#decision-shop [data-role=shop-footer].sticky"

      assert has_element?(view, "#{footer} [data-role=shop-total] .book-coin")

      assert has_element?(
               view,
               ~s(#{footer} [data-role=shop-total][aria-label="30 coins, 30 left after this buy"])
             )

      # Round 35: no Skip; Buy waits for a chip.
      refute has_element?(view, "#{footer} [data-role=shop-done]")
      assert has_element?(view, "#{footer} [data-role=shop-buy]:disabled")

      render_change(view, "select", %{"chips" => [ActionCode.encode({:orange, 1})]})

      assert has_element?(
               view,
               "#{footer} button[data-role=shop-buy]:not(:disabled)",
               "Buy 1 · 3 coins"
             )

      chips = Enum.map([{:orange, 1}, {:blue, 1}], &ActionCode.encode/1)
      render_change(view, "select", %{"chips" => chips})
      assert has_element?(view, "#{footer} button[data-role=shop-buy]", "Buy 2 · 8 coins")

      assert has_element?(
               view,
               ~s(#{footer} [data-role=shop-total][aria-label="30 coins, 22 left after this buy"])
             )
    end

    test "prices show a coin glyph; colours not for sale yet carry a lock" do
      view = shop_view()
      html = render(view)

      assert has_element?(view, "#shop [data-role=price] .book-coin")
      refute render(view) =~ ~r/\d+c\s*</
      # round 1: yellow (from round 2) and purple (from round 3) are locked
      assert count(html, "#shop label.shop-locked") ==
               length(Enum.filter(Chips.shop(), &(elem(&1, 0) in [:yellow, :purple])))

      assert count(html, "#shop label.shop-locked [data-role=tile-lock]") ==
               count(html, "#shop label.shop-locked")

      refute has_element?(view, "#shop label.shop-locked input:not(:disabled)")
    end
  end

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.

  defp shop_view_2 do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("shopper-#{id}"), ~p"/g/#{id}")
    to_shop_2(id)
    render(view)
    view
  end

  describe "the shop rows" do
    test "no Ingredient books line; each row has a label with the ingredient and its book" do
      view = shop_view_2()
      html = render(view)

      refute has_element?(view, "#decision-shop [data-role=books]")
      refute html |> query("#decision-shop") |> LazyHTML.text() =~ "Ingredient books:"

      assert count(html, "#shop [data-role=shop-row-label]") ==
               count(html, "#shop [data-role=shop-row]")

      assert has_element?(view, "#shop [data-role=shop-row-label]", "Garden spider")
      assert has_element?(view, "#shop [data-role=shop-row-label]", "book I")
    end
  end

  defp solo_2 do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {id, open(browser(token("solo")), id)}
  end

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    alice = open(browser(token("alice")), id)
    bob = open(browser(token("bob")), id)
    alice |> element("button", "Start game") |> render_click()
    {id, alice, bob}
  end

  test "from 64rem a shop tile is chip, value and price; the price never shrinks" do
    {id, view} = solo_2()
    replace_game(id, &H.put(&1, 0, phase: :shop, coins: 30))

    assert has_element?(
             view,
             "#shop label [data-role=tile-name].sr-only.sm\\:not-sr-only.lg\\:sr-only"
           )

    refute has_element?(view, "#shop [data-role=tile-name].xl\\:sr-only")
    assert has_element?(view, "#shop label.min-w-0 [data-role=price].shrink-0")
  end

  describe "round 9 has no shop" do
    test "the pill, the line and the back button speak of the final scoring" do
      {id, alice, _bob} = duo()

      replace_game(id, fn g ->
        g |> H.put(0, round: 9, phase: :shop, coins: 0, rubies: 3) |> H.put(1, rubies: 0)
      end)

      html = render(alice)
      refute html =~ "Everyone shops"
      # Round 47: while the results play the pill names the step on show; the
      # seat's phase is the final scoring.
      assert has_element?(alice, "[data-role=phase-pill]", "Scoring space")
      {:ok, %{game: game}} = Quacks.GameServer.get(id)

      assert render_component(&QuacksWeb.BarComponents.round_phase/1, game: game, seat: 0) =~
               "Final scoring"

      render_hook(alice, "seen", %{"kind" => "results", "round" => 9})
      refute has_element?(alice, "[data-role=turn]")
      # Round 31: no rubies step in round 9 (they turn into VP by themselves).
      refute has_element?(alice, "[data-role=decision-button]")
      refute has_element?(alice, "#bar-rubies")
    end

    test "brewing names the VP, not coins; the explosion's coins say they become VP" do
      {id, view} = solo_2()
      replace_game(id, &H.put(&1, 0, round: 9))
      skip_results(view)
      refute has_element?(view, "[data-role=next-reward]", "coin")
      assert has_element?(view, "[data-role=next-reward]", "VP")

      replace_game(id, &H.put(&1, 0, phase: :explosion_choice, exploded?: true))
      assert has_element?(view, "[data-role=bar-explosion] button", "VP at the end")
      refute has_element?(view, "[data-role=bar-explosion] button", "Shop")
    end
  end

  describe "the shop status line" do
    setup do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      alice = open(browser(token("alice")), id)
      bob = open(browser(token("bob")), id)
      alice |> element("button", "Start game") |> render_click()

      # Alice exploded and took the VP: she keeps her rubies to spend, but no buy.
      replace_game(id, fn g ->
        g
        |> H.put(0, explosion_choice: :vp, coins: 0, rubies: 3)
        |> H.put(1, coins: 20)
        |> Round.to_shop()
      end)

      %{alice: alice, bob: bob}
    end

    test "a seat with no buy waits for the others", %{alice: alice, bob: bob} do
      refute has_element?(alice, "[data-role=turn]")
      refute has_element?(bob, "[data-role=turn]")
    end
  end

  # A player detail sheet renders its body once its chip in the players row is tapped.

  # Seed 10,11,12 draws white 2, 3, 1: stop there for a shop with 7 coins.
  defp to_shop_3(view) do
    for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
    view |> element("button", "Stop") |> render_click()
    skip_results(view)
    view
  end

  # The rest of `to_shop_3/1` after one draw, then "Done" (round over).

  defp buy_orange(view) do
    view
    |> element("#shop")
    |> render_change(%{"chips" => [ActionCode.encode({:orange, 1})]})

    view |> element("button[data-role=shop-buy]") |> render_click()
    view
  end

  test "the shop shows every chip you own, as counts" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = browser("solo") |> open(id) |> to_shop_3()

    {:ok, %{game: game}} = GameServer.get(id)
    me = game.players[0]
    # the pot, the bag and any chip the round gave (the bonus die)
    owned = length(Player.pot_chips(me) ++ me.bag)
    assert owned >= 9
    assert has_element?(view, "#decision-shop [data-role=shop-bag]", "Your chips: #{owned}")
    assert has_element?(view, "#decision-shop [data-role=shop-bag] [aria-label='white 1']")
    assert has_element?(view, "#decision-shop [data-role=shop-bag] [data-role=chip-count]", "×4")
  end

  test "a buy ends the shop when no ruby can be spent; otherwise the rubies step opens" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = browser("solo") |> open(id) |> to_shop_3() |> buy_orange()
    assert has_element?(view, "li", "— Round 1 over —")

    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{starting_rubies: 3})
    view = browser("rich") |> open(id) |> to_shop_3()
    # the round results were closed (their close sends "seen")
    render_hook(view, "seen", %{"kind" => "results", "round" => 1})
    view = buy_orange(view)

    refute has_element?(view, "#decision-shop")
    # Round 29: the rubies step is in the bar.
    refute has_element?(view, "dialog#decision-rubies")
    assert has_element?(view, "#bar-rubies button[data-ruby=droplet]", "Droplet +1")
    refute has_element?(view, "li", "— Round 1 over —")

    view |> element("#bar-rubies [data-role=rubies-skip]", "Skip") |> render_click()
    assert has_element?(view, "li", "— Round 1 over —")
  end

  # A 2-player game without fortune cards, started by alice.
  defp duo_3(seed \\ {1, 2, 3}, rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, seed, %{}, rules)
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    alice |> element("button", "Start game") |> render_click()
    {id, alice, bob}
  end

  test "the shop: Done, no Buy nothing, no rubies; round 9 turns rubies into VP by itself" do
    {id, alice, _bob} = duo_3()
    replace_game(id, &H.put(&1, 0, phase: :shop, rubies: 3, coins: 30))

    assert has_element?(alice, "dialog#decision-shop #shop")
    assert has_element?(alice, "dialog#decision-shop [data-role=shop-bag]")
    # Round 35: no Skip in the shop; Buy waits for a chip.
    assert has_element?(alice, "dialog#decision-shop [data-role=shop-buy]:disabled", "Buy")
    refute has_element?(alice, "dialog#decision-shop [data-role=shop-done]")
    refute has_element?(alice, "button", "Buy nothing")
    refute has_element?(alice, "dialog#decision-shop [data-role=shop-rubies]")

    replace_game(id, &(&1 |> H.put(round: 9) |> H.put(0, rubies: 3)))
    refute has_element?(alice, "dialog#decision-shop")
    assert has_element?(alice, "#tile-stage")
    # Round 31: no rubies step in round 9: the rubies turn into VP by themselves
    # once the evaluation was seen.
    refute has_element?(alice, "#bar-rubies")
    {:ok, %{game: before}} = GameServer.get(id)
    vp = before.players[0].vp
    render_hook(alice, "reveal_close", %{})
    {:ok, %{game: game}} = GameServer.get(id)
    assert %{rubies: 1, vp: new_vp} = game.players[0]
    # 30 coins: 6 VP; 3 rubies: 1 VP, 1 ruby kept.
    assert new_vp == vp + 7
  end
end
