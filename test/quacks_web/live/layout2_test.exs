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
  alias Quacks.Rules.Fortune

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

      view |> element("#replay-skip") |> render_click()
      refute has_element?(view, "#books-column .book-beat")
    end
  end

  describe "tablet tabs" do
    test "Decision and Books tabs; Books while nothing waits, Decision when a decision opens" do
      {id, view} = start("tabs", %{fortune: false})

      tabs = "[data-role=side-column] > [data-role=side-tabs].lg\\:grid.xl\\:hidden"
      assert has_element?(view, "#{tabs} [data-role=tab-decision]", "Decision")
      assert has_element?(view, "#{tabs} [data-role=tab-books]", "Books")
      assert has_element?(view, "#{tabs} input[data-tab=books][checked]")
      refute has_element?(view, "#{tabs} input[data-tab=decision][checked]")
      assert has_element?(view, "[data-role=side-column] > #books-tab.lg\\:flex.xl\\:hidden")

      replace_game(id, &H.put(&1, 0, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))
      assert has_element?(view, "#side-tab-decision-blue_choice[checked]")
      refute has_element?(view, "#side-tab-books-blue_choice[checked]")

      # the tabs are CSS only: app.css hides the other tab's content
      css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
      assert css =~ ~s{[data-role="side-column"]:has([data-tab="books"]:checked)}
      assert css =~ "@media (64rem <= width < 80rem)"
    end
  end

  describe "the fortune teller card in full" do
    test "the right column (desktop) and under the pot (tablet) show the whole text" do
      {id, view} = start("card")
      {:ok, %{game: game}} = GameServer.get(id)
      card = Fortune.card(game.fortune_card)
      round = game.round

      for {selector, class} <- [
            {"[data-role=side-column] > #fortune-panel-#{round}", "xl\\:flex"},
            {"[data-role=my-seat] #fortune-under-#{round}", "lg\\:flex.xl\\:hidden"}
          ] do
        assert has_element?(view, "#{selector}.#{class}", card.name)
        assert has_element?(view, "#{selector} p", card.text)
        assert has_element?(view, "#{selector} [aria-hidden] svg")
        refute has_element?(view, "#{selector} .truncate")
        refute has_element?(view, "#{selector} [class*=line-clamp]")
      end

      assert has_element?(view, "[data-role=fortune-tile].lg\\:hidden")
    end
  end
end
