defmodule QuacksWeb.Round7BooksTest do
  @moduledoc """
  Round 7: book tiers by player count (tile, picker, book list), tiers in the picker
  cards, orange books without text, and the pot-side checkbox beside the expansion.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuacksWeb.PanelComponents

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "round7-#{System.unique_integer()}")}
  end

  # Round 26: the books are picked in the spell book (its colour pages).
  defp configure(conn, players) do
    {:ok, view, _html} = live(conn, ~p"/?step=books")
    render_click(view, "players", %{"count" => to_string(players)})
    view
  end

  defp rows(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  test "the black tile shows only the rows for the table size" do
    for {players, shown, hidden} <- [
          {1, "1+ black", "same count"},
          {2, "same count", "more than both"},
          {3, "more than both", "1+ black"},
          {6, "more than 1 neighbour", "same count"}
        ] do
      html =
        render_component(&PanelComponents.book_tile/1, colour: :black, set: 1, players: players)

      assert html =~ shown
      refute html =~ hidden
    end

    html = render_component(&PanelComponents.book_list/1, books: [black: 1], players: 2)
    assert rows(html, "[data-role=book-tiers] tr") == 2
  end

  test "the spell book follows the player stepper", %{conn: conn} do
    view = configure(conn, 2)
    # The tiles are compact; the colour page's card has the tier table.
    black = "#page-book-black [data-set='1'] [data-role=book-tiers]"
    picker = black
    assert has_element?(view, black, "same count")
    assert has_element?(view, picker, "same count")

    render_click(view, "players", %{"count" => "3"})
    assert has_element?(view, black, "more than both")
    refute has_element?(view, black, "same count")
    refute has_element?(view, picker, "same count")

    render_click(view, "players", %{"count" => "1"})
    assert has_element?(view, black, "1+ black")
    refute has_element?(view, black, "more than both")
  end

  test "picker cards show the same tier tables as the tiles", %{conn: conn} do
    view = configure(conn, 2)

    for {colour, set, row} <- [
          {:purple, 1, "3+ purple"},
          {:purple, 2, "2 purple"},
          {:purple, 3, "space 10–19"},
          {:purple, 4, "a 1-chip → a 4-chip"},
          {:green, 2, "blue 1 or red 1"},
          {:red, 1, "1–2 orange"},
          {:yellow, 3, "3rd yellow"},
          {:yellow, 4, "4th+ yellow"}
        ] do
      assert has_element?(
               view,
               "#page-book-#{colour} [data-set='#{set}'] [data-role=book-tiers]",
               row
             )
    end

    refute has_element?(view, "#page-book-green [data-set='1'] [data-role=book-tiers]")
  end

  test "orange books carry no text: tile, picker card and book list", %{conn: conn} do
    for set <- [1, 2] do
      html = render_component(&PanelComponents.book_tile/1, colour: :orange, set: set)
      assert rows(html, "[data-role=book-tile] > p") == 0
      assert html =~ "Pumpkin"
    end

    html = render_component(&PanelComponents.book_tile/1, colour: :orange, set: 2)
    assert rows(html, "[data-role=chip]") == 2 or html =~ "22"

    html = render_component(&PanelComponents.book_list/1, books: [orange: 2])
    refute html =~ "No action"
    refute html =~ "·"

    view = configure(conn, 2)
    card = "#page-book-orange [data-set='2']"
    assert has_element?(view, card, "22")
    refute has_element?(view, "#{card} span.text-sm")
  end

  test "the pot-side checkbox sits beside the expansion and still sets the house rule",
       %{conn: conn} do
    view = configure(conn, 2)
    assert has_element?(view, "[data-role=expansion-cards] #expansion[form=books]")
    assert has_element?(view, ~s([data-role=expansion-cards] #rules-pot_side[form="options"]))
    refute has_element?(view, "#options #rules-pot_side")

    view |> element("#options") |> render_change(%{"rules" => %{"pot_side" => "true"}})
    assert has_element?(view, "#rules-pot_side[checked]")
  end
end
