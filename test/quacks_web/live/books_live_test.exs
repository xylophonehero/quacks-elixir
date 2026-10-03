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

  # The configure screen of a new waiting game, as its host.
  defp configure(conn) do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    {id, view}
  end

  test "the configure screen shows one book tile per colour", %{conn: conn} do
    {_id, view} = configure(conn)

    for colour <- ~w(green blue red yellow purple orange black locoweed) do
      assert has_element?(view, "#books [data-role=book-tile][data-colour=#{colour}]")
      assert has_element?(view, "#books button[popovertarget=book-picker-#{colour}]")
    end

    green = "#books [data-role=book-tile][data-colour=green]"
    assert has_element?(view, green, "Garden spider")

    assert has_element?(
             view,
             green,
             "1 ruby for each green chip that is your last or next-to-last chip."
           )

    assert has_element?(view, "#{green} .book-seal", "I")
    assert has_element?(view, "#books [data-book=locoweed-off] .book-seal", "Off")
  end

  test "a picker lists the books of a colour; a card changes the book", %{conn: conn} do
    {id, view} = configure(conn)
    picker = "#book-picker-green[popover]"
    assert has_element?(view, picker, "Garden spider")
    assert has_element?(view, "#{picker} [data-role=book-card]", "Book I")
    assert has_element?(view, "#{picker} [data-role=book-card]", "Book IV")
    refute has_element?(view, "#{picker} [data-role=book-card]", "Book V")
    assert has_element?(view, "#{picker} input[name='sets[green]'][value='1'][checked]")

    assert has_element?(
             view,
             "#{picker} input[value='3'][phx-click*='quacks:close']"
           )

    view |> form("#books", sets: %{green: "3"}) |> render_change()
    green = "#books [data-role=book-tile][data-colour=green]"
    assert has_element?(view, green, "exactly 7")
    assert has_element?(view, "#{green} .book-seal", "III")
    assert has_element?(view, "#{picker} input[value='3'][checked]")
    {:ok, %{sets: %{green: 3}}} = GameServer.get(id)

    assert has_element?(view, "#book-picker-black [data-role=book-card][data-set='5']")
    assert has_element?(view, "#book-picker-black [data-role=book-card][data-set='6']")
    refute has_element?(view, "#book-picker-black [data-role=book-card][data-set='2']")
    assert has_element?(view, "#book-picker-orange [data-role=book-card][data-set='2']", "6")
  end

  test "the host picks orange 2 and locoweed in a base game", %{conn: conn} do
    {id, view} = configure(conn)
    not_in_play = "#book-picker-locoweed [data-role=book-card][data-set=off]"
    assert has_element?(view, not_in_play, "Not in play")
    assert has_element?(view, "#{not_in_play} input[value=''][checked]")
    assert has_element?(view, "#books [data-book=locoweed-off]", "No locoweed chips")

    view |> form("#books", sets: %{orange: "2", locoweed: "5"}) |> render_change()
    assert has_element?(view, "#books [data-book=locoweed-5]", "rat stone")

    view |> form("#books", sets: %{locoweed: ""}) |> render_change()
    assert has_element?(view, "#books [data-book=locoweed-off]")
    view |> form("#books", sets: %{locoweed: "5"}) |> render_change()

    view |> element("button", "Start game") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    assert game.expansion == nil
    assert %{orange: 2, locoweed: 5} = game.sets
  end

  test "the locoweed picker lists Off, 5, 6 and The Alchemists' books 8, 9, 10", %{conn: conn} do
    {id, view} = configure(conn)
    card = "#book-picker-locoweed [data-role=book-card]"

    for set <- ~w(off 5 6 8 9 10), do: assert(has_element?(view, "#{card}[data-set='#{set}']"))
    refute has_element?(view, "#{card}[data-set='7']")
    assert has_element?(view, "#{card}[data-set='8']", "Book VIII")
    assert has_element?(view, "#{card}[data-set='8']", "each colour in your pot")
    assert has_element?(view, "#{card}[data-set='9']", "return 1 coloured chip")
    assert has_element?(view, "#{card}[data-set='10']", "white chips in your pot")
    assert has_element?(view, "#{card}[data-set='8']", "16")

    view |> form("#books", sets: %{locoweed: "10"}) |> render_change()
    assert has_element?(view, "#books [data-book=locoweed-10] .book-seal", "X")
    assert {:ok, %{sets: %{locoweed: 10}}} = GameServer.get(id)

    # a saved config with locoweed 9 comes back on a fresh screen
    {id, view} = configure(conn)
    render_hook(view, "load_config", %{"sets" => %{"locoweed" => "9"}, "expansion" => false})
    assert {:ok, %{sets: %{locoweed: 9}}} = GameServer.get(id)
  end

  test "locoweed 9: the pot's coloured chips are taps that return one", %{conn: conn} do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{locoweed: 9}, %{fortune: false})
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

  test "the expansion toggle defaults orange to 2 and locoweed to 5", %{conn: conn} do
    {_id, view} = configure(conn)
    view |> form("#books", expansion: "true") |> render_change()
    assert has_element?(view, "input[name='sets[orange]'][value='2'][checked]")
    assert has_element?(view, "input[name='sets[locoweed]'][value='5'][checked]")
    assert has_element?(view, "#book-picker-green [data-role=book-card][data-set='6']")
  end

  test "the shop has an info button per row; the menu lists the chosen books", %{conn: conn} do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{orange: 2, locoweed: 6}, %{fortune: false})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    to_shop(id)
    html = render(view)

    rows = html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-role=shop-row]")
    # orange (1, 6), blue, red, yellow, black, green, purple, locoweed
    assert Enum.count(rows) == 8

    for {_row, i} <- Enum.with_index(rows) do
      assert has_element?(view, "[data-role=shop-row] button[popovertarget=shop-book-#{i}]")
      assert has_element?(view, "#shop-book-#{i} [data-role=book-text]")
    end

    assert has_element?(view, "#shop-book-0 [data-book=orange-2]")
    assert has_element?(view, "#shop-book-4", "Hawkmoth")
    assert has_element?(view, "#shop-book-7 [data-book=locoweed-6]", "Acts as the last coloured")
    # black 1 has tiers; a solo game shows only the solo row
    assert has_element?(view, "#shop-book-4 [data-role=book-tiers]", "1+ black")
    refute has_element?(view, "#shop-book-4 [data-role=book-tiers]", "same count")
    assert has_element?(view, "#shop label", ~r/orange 6\s+22c/)

    assert has_element?(view, "#sheet-menu button[popovertarget=sheet-books]", "Books")

    assert has_element?(
             view,
             "#sheet-books [data-role=book-tile][data-book=green-1]",
             "Garden spider"
           )

    # orange has no rule text, only its prices (the 6-chip at 22)
    assert has_element?(view, "#sheet-books [data-book=orange-2]", "22")
    refute has_element?(view, "#sheet-books [data-book=orange-2] p", "fill the pot")
    assert has_element?(view, "#sheet-books [data-book=locoweed-6]")
  end
end
