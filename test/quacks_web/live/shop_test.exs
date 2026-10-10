defmodule QuacksWeb.ShopTest do
  @moduledoc """
  The shop: Ghost's breath V's chips in the context area, every seat's scoring ring, another seat's buy, Flea Market, the black book and the shop tiles.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.Rules.Chips
  alias Quacks.{Game, GameHelpers, GameServer}
  alias Quacks.{Game, GameServer}
  alias QuacksWeb.PanelComponents
  alias QuacksWeb.{ActionCode, ShopComponents}

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

      shop = List.flatten(ShopComponents.shop_rows(game.expansion, game.sets))
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
      |> Game.start_round()
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
    assert game.expansion == nil
    assert game.sets.black == 3
  end

  # Round 31: no dialog: the card hovers over the pot, its choices are the bar.
  test "a card with a choice: the card over the pot, the choices in the bar" do
    # seed 30,30,30 with 2 players deals a purple card with a choice for both seats
    {:ok, id} = GameServer.start(2, {30, 30, 30})
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
end
