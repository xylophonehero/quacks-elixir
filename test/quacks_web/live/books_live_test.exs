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
        game
      else
        action =
          Enum.find([:stop, :chip_done, {:explosion_choice, :buy}], hd(actions), &(&1 in actions))

        {:ok, _} = GameServer.apply(id, 0, action)
        nil
      end
    end)
  end

  test "the lobby shows the chosen book's text and updates it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    green = "[data-colour=green] [data-role=chosen-book]"
    assert has_element?(view, green, "Garden spider")
    assert has_element?(view, green, "1 ruby for each green chip")

    view |> form("#books", sets: %{green: "3"}) |> render_change()
    assert has_element?(view, green, "exactly 7")
    refute has_element?(view, green, "1 ruby for each green chip")
  end

  test "the lobby picks orange 2 and locoweed in a base game", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "select[name='sets[locoweed]'] option[value='']", "Not used")
    refute has_element?(view, "[data-colour=locoweed] [data-role=chosen-book]")

    view |> form("#books", sets: %{orange: "2", locoweed: "5"}) |> render_change()
    assert has_element?(view, "[data-colour=locoweed] [data-role=chosen-book]", "rat stone")

    {:error, {:live_redirect, %{to: "/g/" <> id}}} =
      view |> element("button", "New solo game") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    assert game.expansion == nil
    assert %{orange: 2, locoweed: 5} = game.sets
  end

  test "the expansion toggle defaults orange to 2 and locoweed to 5", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> form("#books", expansion: "true") |> render_change()
    assert has_element?(view, "select[name='sets[orange]'] option[value='2'][selected]")
    assert has_element?(view, "select[name='sets[locoweed]'] option[value='5'][selected]")
  end

  test "the shop has an info button per row; the menu lists the chosen books", %{conn: conn} do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{orange: 2, locoweed: 6}, %{fortune: false})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    to_shop(id)
    html = render(view)

    rows = html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-role=shop-row]")
    assert Enum.count(rows) == 6

    for {_row, i} <- Enum.with_index(rows) do
      assert has_element?(view, "[data-role=shop-row] button[popovertarget=shop-book-#{i}]")
      assert has_element?(view, "#shop-book-#{i} [data-role=book-text]")
    end

    assert has_element?(view, "#shop-book-0", "Hawkmoth")
    assert has_element?(view, "#shop-book-1 [data-book=locoweed-6]", "Copies")
    assert has_element?(view, "#shop label", ~r/orange 6\s+22c/)

    assert has_element?(view, "#sheet-menu button[popovertarget=sheet-books]", "Books")
    assert has_element?(view, "#sheet-books [data-book=green-1]", "Garden spider")
    assert has_element?(view, "#sheet-books [data-book=orange-2]", "orange 6-chip")
    assert has_element?(view, "#sheet-books [data-book=locoweed-6]")
  end
end
