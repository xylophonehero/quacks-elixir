defmodule QuacksWeb.BooksLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "books-#{System.unique_integer()}")}
  end

  # Play seat 0 until the shop opens: stop as soon as possible, skip every choice.
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

  # Round 26: the books are picked in the spell book only (no configure screen).
  defp book(conn) do
    {:ok, view, _html} = live(conn, ~p"/?seed=1,2,3&step=books")
    view
  end

  defp pick(view, params), do: view |> element("#books") |> render_change(params)

  # Solo Start from the spell book: the game begins at once.
  defp start_solo(view) do
    render_click(view, "players", %{"count" => "1"})

    {:error, {:live_redirect, %{to: "/g/" <> id}}} =
      view |> element("#new-game") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  test "the spell book shows one book tile per colour", %{conn: conn} do
    view = book(conn)

    for colour <- ~w(green blue red yellow purple orange black locoweed) do
      assert has_element?(view, "#books [data-role=book-tile][data-colour=#{colour}]")
      assert has_element?(view, "#books #book-link-#{colour}")
    end

    green = "#books [data-role=book-tile][data-colour=green]"
    assert has_element?(view, green, "Garden spider")
    # the tiles are compact: the rule text is on the colour page
    refute has_element?(view, green, "1 ruby for each green chip")

    assert has_element?(
             view,
             "#page-book-green [data-set='1']",
             "1 ruby for each green chip that is your last or next-to-last chip."
           )

    assert has_element?(view, "#{green} .book-seal", "I")
    assert has_element?(view, "#books [data-book=locoweed-off] .book-seal", "Off")
  end

  test "a colour page lists its books; a card changes the book", %{conn: conn} do
    view = book(conn)
    page = "#page-book-green"
    assert has_element?(view, "#{page} [data-role=book-card]", "Book I")
    # Books I–VI with or without the expansion
    assert has_element?(view, "#{page} [data-role=book-card]", "Book IV")
    assert has_element?(view, "#{page} [data-role=book-card][data-set='6']", "Book VI")
    assert has_element?(view, "#{page} input[name='sets[green]'][value='1'][checked]")

    pick(view, %{"sets" => %{"green" => "3"}})
    green = "#books [data-role=book-tile][data-colour=green]"
    assert has_element?(view, "#{page} [data-set='3']", "exactly 7")
    assert has_element?(view, "#{green} .book-seal", "III")
    assert has_element?(view, "#{page} input[value='3'][checked]")

    black = "#page-book-black [data-role=book-card]"
    assert has_element?(view, "#{black}[data-set='2']", "Book II")
    assert has_element?(view, "#{black}[data-set='3']", "Book III")
    refute has_element?(view, "#{black}[data-set='5']")
    assert has_element?(view, "#page-book-orange [data-role=book-card][data-set='2']", "6")
    assert %{green: 3} = start_solo(view).sets
  end

  test "the host picks orange 2 and locoweed in a base game", %{conn: conn} do
    view = book(conn)
    not_in_play = "#page-book-locoweed [data-role=book-card][data-set=off]"
    assert has_element?(view, not_in_play, "Not in play")
    assert has_element?(view, "#{not_in_play} input[value=''][checked]")
    assert has_element?(view, "#books [data-book=locoweed-off]")
    assert has_element?(view, not_in_play, "No locoweed chips")

    pick(view, %{"sets" => %{"orange" => "2", "locoweed" => "1"}})
    assert has_element?(view, "#books [data-book=locoweed-1]")
    assert has_element?(view, "#page-book-locoweed [data-set='1']", "rat stone")

    pick(view, %{"sets" => %{"orange" => "2", "locoweed" => ""}})
    assert has_element?(view, "#books [data-book=locoweed-off]")
    pick(view, %{"sets" => %{"orange" => "2", "locoweed" => "1"}})

    game = start_solo(view)
    assert game.expansion == nil
    assert %{orange: 2, locoweed: 1} = game.sets
  end

  test "the locoweed page lists Off and books I–VI; III is greyed out", %{conn: conn} do
    view = book(conn)
    card = "#page-book-locoweed [data-role=book-card]"

    for set <- ~w(off 1 2 3 4 5 6), do: assert(has_element?(view, "#{card}[data-set='#{set}']"))
    refute has_element?(view, "#{card}[data-set='7']")
    assert has_element?(view, "#{card}[data-set='1']", "rat stone")
    assert has_element?(view, "#{card}[data-set='3'][aria-disabled]", "needs The Alchemists")
    assert has_element?(view, "#{card}[data-set='3'] input[disabled]")
    refute has_element?(view, "#{card}[data-set='4'][aria-disabled]")
    assert has_element?(view, "#{card}[data-set='4']", "Book IV")
    assert has_element?(view, "#{card}[data-set='4']", "each colour in your pot")
    assert has_element?(view, "#{card}[data-set='5']", "return 1 coloured chip")
    assert has_element?(view, "#{card}[data-set='6']", "white chips in your pot")
    assert has_element?(view, "#{card}[data-set='4']", "16")

    pick(view, %{"sets" => %{"locoweed" => "6"}})
    assert has_element?(view, "#books [data-book=locoweed-6] .book-seal", "VI")

    # a crafted III falls back to no locoweed
    pick(view, %{"sets" => %{"locoweed" => "3"}})
    assert has_element?(view, "#books [data-book=locoweed-off]")
    refute Map.has_key?(start_solo(view).sets, :locoweed)
  end

  test "locoweed 5: the pot's coloured chips are taps that return one", %{conn: conn} do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{locoweed: 5}, %{fortune: false})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")

    Quacks.GameHelpers.replace_game(
      id,
      &Quacks.GameHelpers.force_draws(&1, [{:green, 1}, {:locoweed, 1}])
    )

    assert has_element?(view, "[data-role=chip-picks]", "Locoweed: return one to your bag")

    assert has_element?(
             view,
             "[data-role=chip-pick][aria-label='Locoweed: return green 1 to the bag']"
           )

    view |> element("[data-role=chip-pick][aria-label*='green 1']") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    assert [{{:locoweed, 1}, 2}] = game.players[0].drawn
  end

  test "the expansion toggle changes no book", %{conn: conn} do
    view = book(conn)
    books = %{"green" => "5", "orange" => "2", "locoweed" => "4", "black" => "3"}
    pick(view, %{"sets" => books})
    assert has_element?(view, "#books [data-book=locoweed-4]")

    pick(view, %{"expansion" => "true", "sets" => books})
    assert has_element?(view, "input[name='sets[orange]'][value='2'][checked]")
    assert has_element?(view, "input[name='sets[locoweed]'][value='4'][checked]")

    game = start_solo(view)
    assert game.expansion == :herb_witches
    assert %{green: 5, orange: 2, locoweed: 4, black: 3} = game.sets

    # with no books picked the toggle keeps orange 1 and no locoweed
    view = book(conn)
    pick(view, %{"expansion" => "true", "sets" => %{}})
    assert has_element?(view, "input[name='sets[orange]'][value='1'][checked]")
    assert has_element?(view, "input[name='sets[locoweed]'][value=''][checked]")
    sets = start_solo(view).sets
    refute Map.has_key?(sets, :orange) or Map.has_key?(sets, :locoweed)
  end

  test "the shop has an inline book info per row; the menu lists the chosen books", %{conn: conn} do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{orange: 2, locoweed: 2}, %{fortune: false})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    to_shop(id)
    html = render(view)

    rows = html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-role=shop-row]")
    # orange (1, 6), blue, red, yellow, green, black, purple, locoweed
    assert Enum.count(rows) == 8

    for {_row, i} <- Enum.with_index(rows) do
      # the book opens in place under its row, not in another sheet
      assert has_element?(
               view,
               "[data-role=shop-row-label] button[aria-controls=shop-book-#{i}][aria-expanded=false][phx-click*=toggle]"
             )

      assert has_element?(
               view,
               "#shop-book-#{i}.hidden[data-role=shop-book] [data-role=book-text]"
             )

      refute has_element?(view, "#shop-book-#{i}[popover]")
    end

    assert has_element?(view, "#shop-book-0 [data-book=orange-2]")
    assert has_element?(view, "#shop-book-5", "Hawkmoth")
    assert has_element?(view, "#shop-book-7 [data-book=locoweed-2]", "Acts as the last coloured")
    # black 1 has tiers; a solo game shows only the solo row
    assert has_element?(view, "#shop-book-5 [data-role=book-tiers]", "1+ black")
    refute has_element?(view, "#shop-book-5 [data-role=book-tiers]", "same count")
    assert has_element?(view, "#shop label", ~r/orange 6\s+22c/)

    assert has_element?(view, "#sheet-menu button[popovertarget=sheet-books]", "Books")
    assert has_element?(view, "header button[data-role=open-books][popovertarget=sheet-books]")

    assert has_element?(
             view,
             "#sheet-books [data-role=book-tile][data-book=green-1]",
             "Garden spider"
           )

    # orange has no rule text, only its prices (the 6-chip at 22)
    assert has_element?(view, "#sheet-books [data-book=orange-2]", "22")
    refute has_element?(view, "#sheet-books [data-book=orange-2] p", "fill the pot")
    assert has_element?(view, "#sheet-books [data-book=locoweed-2]")

    assert has_element?(
             view,
             "#sheet-books [data-book=black-1] [data-role=book-tiers]",
             "1+ black"
           )
  end
end
