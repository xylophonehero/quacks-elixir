defmodule QuacksWeb.Round39DeskTest do
  @moduledoc """
  Round 39 (desk): on desktop the evaluation plays in the context column (the
  results stage over the bar, no overlay over the pot); the books and the herb
  witches are folded blocks in the left column; no second list of a card's
  results and no results panel in the context column.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp herb_solo do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
    {:ok, view, _html} = live(browser("r39-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  # A solo game in the shop phase of round 1: the results wait to play.
  defp solo_results do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("r39-solo-#{System.unique_integer()}"), ~p"/g/#{id}")

    replace_game(id, fn g ->
      g = put_in(g.players[0].drawn, [{{:green, 1}, 12}, {{:purple, 1}, 11}])
      g = %{g | log: [{0, {:purple, 1, :vp}}, {0, {:green_rubies, 1}}, {:round_end, 0}]}
      H.put(g, 0, phase: :shop, coins: 10)
    end)

    {id, view}
  end

  # A desktop browser's settings (no phone flag since round 39).
  defp desktop(view),
    do: render_hook(view, "reveal_settings", %{"mode" => "step", "speed" => "normal"})

  describe "item 2: the evaluation in the context column" do
    test "a desktop browser plays the steps in the results stage over the bar, no overlay" do
      {_id, view} = solo_results()
      desktop(view)

      refute has_element?(view, "[data-role=reveal]")
      refute has_element?(view, "dialog[id^=reveal-]")
      assert has_element?(view, "footer[data-area=bar] #results-stage")
      assert has_element?(view, "footer[data-area=bar] #tile-stage [data-role=tile-skip]")
      assert has_element?(view, "footer[data-area=bar] #tile-stage [data-role=tile-next]")

      # Next steps through to the shop panel in the context column.
      Enum.find(1..10, fn _ ->
        view |> element("[data-role=tile-next]") |> render_click()
        not has_element?(view, "#tile-stage")
      end)

      refute has_element?(view, "#results-stage")
      assert has_element?(view, "[data-role=side-column] dialog#decision-shop[data-side=panel]")
    end

    test "the menu has no Results choice any more" do
      {_id, view} = solo_results()
      refute has_element?(view, "#reveal-settings [name=show]")
      refute has_element?(view, "#reveal-settings [name=phone]")
      refute has_element?(view, "#reveal-settings", "Overlay")
    end
  end

  describe "item 3: no results panel next to the stage" do
    test "the context column has no evaluation list while the steps play" do
      {_id, view} = solo_results()
      desktop(view)

      assert has_element?(view, "#results-stage")
      refute has_element?(view, "[data-role=results-panel]")
      refute has_element?(view, "[data-role=result-row]")
    end
  end

  describe "item 2: the left column" do
    test "the books and the witches are folded blocks, closed by default" do
      {_id, view} = herb_solo()

      assert has_element?(view, "#left-column.hidden.xl\\:flex[data-area=books]")
      assert has_element?(view, "#left-column > details#books-column:not([open])")
      assert has_element?(view, "#left-column > details#witches-column:not([open])")

      assert has_element?(
               view,
               "#witches-column > summary[data-role=fold-title]",
               "Herb witches"
             )

      # The page keeps a fold open across patches.
      assert has_element?(view, ~s(#witches-column[phx-mounted*="ignore_attrs"]))
      assert has_element?(view, ~s(#books-column[phx-mounted*="ignore_attrs"]))

      for witch <- ~w(s2 c4 g4),
          do: assert(has_element?(view, "#witches-column [data-witch=#{witch}]"))
    end

    test "a witch is called from the left column; the title counts the calls" do
      {_id, view} = herb_solo()

      assert has_element?(view, "#witches-column [data-role=witches-callable]", "1 to call")

      view |> element("#witches-column [data-witch=s2] button", "Call") |> render_click()

      assert has_element?(
               view,
               "#bar-pick-witch_offer [data-role=info-row]",
               "The silver witch drew:"
             )

      refute has_element?(view, "#witches-column [data-role=witches-callable]")
    end

    test "from 80rem the context column's witches sheet hides (app.css)" do
      {_id, view} = herb_solo()
      assert has_element?(view, "[data-role=side-column] > #sheet-witches.sheet-left-xl")

      css = File.read!("assets/css/app.css")
      assert css =~ ~s([data-role="side-column"] > .sheet-inline-lg.sheet-left-xl)
    end

    test "no herb witches: no witches fold" do
      {_id, view} = solo_results()
      assert has_element?(view, "#left-column > #books-column")
      refute has_element?(view, "#witches-column")
    end
  end

  describe "item 1: one list of a card's results" do
    test "Take a Chance has no old list of rolls in the context column" do
      {id, view} = herb_solo()

      replace_game(id, fn g ->
        %{g | fortune_card: :p12, log: [{0, {:fortune, :p12, {:vp, 2}}} | g.log]}
      end)

      refute has_element?(view, "[data-role=chance-panel]")
      css = File.read!("assets/css/app.css")
      refute css =~ ".chance-row"
      refute css =~ ".results-panel"
    end
  end
end
