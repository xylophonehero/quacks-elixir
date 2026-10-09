defmodule QuacksWeb.UiRound4Test do
  @moduledoc """
  Round 4 playtest fixes: the black book in every game, the remembered
  configuration, one dialog for the new card and its choice, the shop tiles and
  the round results before the shop.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.GameComponents

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
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

  test "a card with a choice is one dialog: the card, its offer and the buttons" do
    # seed 30,30,30 with 2 players deals a purple card with a choice for both seats
    {:ok, id} = GameServer.start(2, {30, 30, 30})
    alice = open(browser("alice"), id)
    _bob = open(browser("bob"), id)
    alice |> element("button", "Start game") |> render_click()

    refute has_element?(alice, "#decision-fortune_choice")
    assert has_element?(alice, "dialog#card-round-1 [data-role=fortune-card]")

    assert has_element?(
             alice,
             "#card-round-1 [data-role=fortune-card]",
             "Fortune teller · resolve now"
           )

    assert has_element?(alice, "#card-round-1 section[aria-label=Actions] button", "No thanks")
    refute has_element?(alice, "#card-round-1 form[method=dialog] button", "OK")
    # Round 30: while the card hovers, the footer has Continue (it opens the
    # card's dialog) in place of the button that reopens the dialog
    assert has_element?(alice, "footer #card-continue")
    refute has_element?(alice, "footer button[phx-click*='card-round-1']")
    alice |> element("#card-continue") |> render_click()
    assert has_element?(alice, "footer button[phx-click*='card-round-1']")

    alice |> element("#card-round-1 button", "No thanks") |> render_click()
    # answered: the dialog goes, and the card counts as seen (round 14: no
    # reveal overlay for it afterwards)
    refute has_element?(alice, "#card-round-1")
    refute has_element?(alice, "[data-role=reveal]")
  end

  test "the card band: blue is for this round, purple says nothing more" do
    blue = render_component(&GameComponents.fortune_card/1, id: :b1)
    purple = render_component(&GameComponents.fortune_card/1, id: :p1)

    assert blue =~ "Fortune teller · this round"
    assert purple =~ "Fortune teller"
    refute purple =~ "Fortune teller ·"

    assert render_component(&GameComponents.fortune_card/1, id: :p1, choice: true) =~
             "resolve now"
  end

  test "the reveal overlay comes first; the shop opens when it closes" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("solo"), id)
    to_shop(id)
    render(view)

    # the overlay shows and hands over to the shop, which waits
    assert has_element?(view, "dialog#reveal-results-1")
    assert has_element?(view, "#reveal-next")
    assert has_element?(view, "dialog#decision-shop #shop")
    refute has_element?(view, "dialog#decision-shop[phx-mounted*='quacks:modal']")
    # the footer still opens the shop at any time
    assert has_element?(view, "footer [data-role=decision-button]")

    # a reload while the overlay shows starts it again at the first slide
    view |> element("#reveal-next") |> render_click()
    view = open(browser("solo"), id)
    assert has_element?(view, "dialog#reveal-results-1 #reveal-slide-0")
    refute has_element?(view, "dialog#decision-shop[phx-mounted*='quacks:modal']")

    # the last slide's button opens the shop
    view |> element("#reveal-skip") |> render_click()
    assert has_element?(view, "#reveal-next", "To the shop")
    view |> element("#reveal-next") |> render_click()
    refute has_element?(view, "[data-role=reveal]")
    assert_push_event(view, "quacks:open", %{to: "#decision-shop"})
  end

  test "shop tiles: a tapped chip is outlined with a check, the others dim" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("solo"), id)
    to_shop(id)
    render(view)

    chip = {:orange, 1}
    render_change(view, "select", %{"chips" => [QuacksWeb.GameLive.encode(chip)]})

    checked = ~s(#shop input[value="#{QuacksWeb.GameLive.encode(chip)}"][checked])
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
      render_component(&QuacksWeb.GameLive.offer_books/1, id: "books-x", game: game, offer: offer)

    assert html =~ ~s(popovertarget="books-x")
    assert html =~ ~s(data-book="red-2")
    assert html =~ ~s(data-book="blue-1")
    refute html =~ ~s(data-book="white)

    assert render_component(&QuacksWeb.GameLive.offer_books/1,
             id: "y",
             game: game,
             offer: [:stop]
           ) == ""
  end
end
