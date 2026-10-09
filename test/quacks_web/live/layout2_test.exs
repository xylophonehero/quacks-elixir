defmodule QuacksWeb.Layout2Test do
  @moduledoc """
  Layout 2: the desktop books column (80rem), the tablet tabs "Decision" and
  "Books" (64–80rem), and the fortune teller card in full.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.Rules.{Books, Fortune}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp start(name, opts \\ %{}) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, opts)
    {:ok, view, _html} = live(browser("#{name}-#{id}"), ~p"/g/#{id}")
    {id, view}
  end

  defp attrs(view, selector, name) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute(name)
  end

  describe "desktop books column" do
    test "the books in play, left of the pot, in board order" do
      {_id, view} = start("books")

      assert has_element?(view, "[data-role=my-seat] > #books-column.xl\\:flex.hidden")

      assert attrs(view, "#books-column [data-role=book-line]", "data-colour") ==
               ~w(orange blue red yellow green black purple)

      assert has_element?(view, "#books-column [data-book=blue-1]", "Crow skull")
      assert has_element?(view, "#books-column [data-book=blue-1]", "On draw")
    end

    test "a tiered book shows only the rows for this table size" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      {:ok, view, _html} = live(browser("tiers-#{id}"), ~p"/g/#{id}")
      {:ok, _seat} = GameServer.add_bot(id, "tiers-#{id}")
      view |> element("button", "Start game") |> render_click()

      black = "#books-column [data-book=black-1] [data-role=book-tiers]"
      assert has_element?(view, black, "same count (1+)")
      refute has_element?(view, black, "neighbour")
    end

    test "during the replay a book lights up on the beat of its line" do
      {id, view} = start("beat", %{fortune: false})

      replace_game(id, fn g ->
        g = put_in(g.players[0].drawn, [{{:green, 1}, 12}, {{:purple, 1}, 11}])
        g = %{g | log: [{0, {:purple, 1, :vp}}, {0, {:green_rubies, 1}}, {:round_end, 0}]}
        H.put(g, 0, phase: :shop, coins: 10)
      end)

      assert has_element?(
               view,
               ~s(#books-column [data-colour=green].book-beat[style*="--beat: 0"])
             )

      assert has_element?(
               view,
               ~s(#books-column [data-colour=purple].book-beat[style*="--beat: 1"])
             )

      refute has_element?(view, "#books-column [data-colour=black].book-beat")

      render_hook(view, "reveal_close", %{})
      refute has_element?(view, "#books-column .book-beat")
    end
  end

  # Round 11 replaced the tablet tabs with a Books button and a drawer.
  describe "tablet books drawer" do
    test "a Books button with the count opens the books in a drawer; no tabs" do
      {id, view} = start("drawer", %{fortune: false})
      {:ok, %{game: game}} = GameServer.get(id)
      count = length(Books.in_play(game.expansion, game.sets))

      refute has_element?(view, "[data-role=side-tabs]")
      refute has_element?(view, "#books-tab")

      button = "header button[data-role=open-books][popovertarget=sheet-books].xl\\:hidden"
      assert has_element?(view, "#{button} [data-role=books-count]", "#{count}")
      assert has_element?(view, "#sheet-books.sheet-drawer[popover]")
      assert has_element?(view, "#sheet-books [data-role=books-in-play]")

      # A decision coming does not close the drawer: the dialog waits for it.
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 10))
      assert has_element?(view, "#sheet-books.sheet-drawer")
      assert has_element?(view, "dialog#decision-shop")

      css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
      assert css =~ "@media (width >= 48rem), (orientation: landscape) and (max-height: 30rem)"
      assert css =~ ".sheet.sheet-drawer:not(:popover-open, [open])"
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ ~s{#sheet-books:popover-open}
    end
  end

  describe "the fortune teller card in full" do
    test "the context column (from 64rem) shows the whole text; nothing under the pot" do
      {id, view} = start("card")
      {:ok, %{game: game}} = GameServer.get(id)
      card = Fortune.card(game.fortune_card)
      round = game.round

      refute has_element?(view, "#fortune-under-#{round}")

      for {selector, class} <- [
            {"[data-role=side-column] > #fortune-panel-#{round}", "lg\\:flex"}
          ] do
        assert has_element?(view, "#{selector}.#{class}", card.name)
        assert has_element?(view, "#{selector} p", card.text)
        assert has_element?(view, "#{selector} [aria-hidden] svg")
        refute has_element?(view, "#{selector} .truncate")
        refute has_element?(view, "#{selector} [class*=line-clamp]")
      end

      assert has_element?(view, "[data-role=pot-area] #corner-card[data-role=fortune-tile]")
    end
  end
end
