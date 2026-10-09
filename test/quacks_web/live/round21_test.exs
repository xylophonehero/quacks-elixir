defmodule QuacksWeb.Round21Test do
  @moduledoc """
  Round 21: the expansions are a list on phones, the Games page fills a phone's
  screen (the list scrolls, New game stays at the foot), and a Full screen toggle
  sits in the game menu and on the lobby's Games page.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "r21-#{System.unique_integer()}")}
  end

  test "the expansions are a list of rows (round 29: on New game)", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?step=players")

    # A row: icon, title and line, Customise, the switch on the right.
    assert has_element?(view, "#page-players [data-role=expansion-cards].grid")
    assert has_element?(view, "#page-players #row-expansion[data-role=expansion-row]")

    ids =
      view
      |> element("#page-players [data-role=expansion-cards]")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("input[type=checkbox]")
      |> LazyHTML.attribute("id")

    assert ids == ~w(expansion alchemists rules-pot_side)
    assert has_element?(view, "#page-players #to-rules.page-link")
    assert has_element?(view, "#page-players #to-books.page-link")
  end

  test "the Games page is one screen on a phone: the list scrolls, New game at the foot",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # `.lobby-screen[data-step=home]` (app.css) holds the hero and the book.
    assert has_element?(view, ".lobby-screen[data-step=home] [data-role=lobby-hero]")
    assert has_element?(view, ".lobby-screen[data-step=home] #spell-book #page-home")
    assert has_element?(view, "#page-home ul#games.games-list")
    assert has_element?(view, "#page-home #games-scroll + .page-foot #new-game-flow")

    # Another page: the screen's data-step follows the URL.
    {:ok, view, _html} = live(conn, ~p"/?step=players")
    assert has_element?(view, ".lobby-screen[data-step=players]")
  end

  test "Full screen: an icon on the Games page, a button in the game menu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # app.js handles `data-role=fullscreen`; app.css shows the toggle only with
    # `html[data-fullscreen]` and swaps the icon on `:fullscreen`.
    assert has_element?(
             view,
             "#page-home .book-heading button#fullscreen-lobby.fullscreen-toggle[data-role=fullscreen]"
           )

    assert has_element?(view, "#fullscreen-lobby .when-windowed.hero-arrows-pointing-out")
    assert has_element?(view, "#fullscreen-lobby .when-fullscreen.hero-arrows-pointing-in")
    assert has_element?(view, "#fullscreen-lobby .sr-only", "Full screen")

    {:ok, id} = Quacks.GameServer.start(1, {1, 2, 3})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")

    assert has_element?(
             view,
             "#sheet-menu button#fullscreen-menu.fullscreen-toggle[data-role=fullscreen][type=button]",
             "Full screen"
           )

    assert has_element?(view, "#fullscreen-menu .when-fullscreen", "Exit full screen")
  end
end
