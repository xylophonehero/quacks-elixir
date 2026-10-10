defmodule QuacksWeb.GalleryFitTest do
  @moduledoc """
  Things the component gallery showed that did not fit at 360 px: each test opens
  the gallery frame (or scenario) where it showed and checks the fix.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.Game
  alias QuacksWeb.Gallery.Fixtures

  defp frame(conn, path) do
    {:ok, view, _html} = live(conn, "/dev/gallery/frame/" <> path)
    view
  end

  defp doc(view, selector), do: view |> element(selector) |> render() |> LazyHTML.from_fragment()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&String.trim(LazyHTML.text(&1)))

  describe "score track labels" do
    test "seats 1 VP apart put their numbers on both sides of the line", %{conn: conn} do
      view = frame(conn, "track/8p")
      above = "#rat-track [data-role=track-vp]:not([data-below])"
      below = "#rat-track [data-role=track-vp][data-below]"
      assert has_element?(view, above <> "[data-vp='41']")
      assert has_element?(view, below <> "[data-vp='40']")
    end

    test "rat numbers do not run together or repeat a seat's VP", %{conn: conn} do
      # 28 / 24 / 19: rats 26, 24, 22, 20 in a row; only every other one has room,
      # and 24 is a seat's VP.
      rats = conn |> frame("track/8p") |> doc("#rat-track") |> texts("[data-role=track-rat]")
      assert Enum.reject(rats, &(&1 == "")) == ~w(26 22)

      rats =
        conn |> frame("track/big-gaps") |> doc("#rat-track") |> texts("[data-role=track-rat]")

      refute "30" in rats
    end
  end

  describe "player tiles" do
    test "the state badge sits above the VP, and narrow tiles take smaller numbers",
         %{conn: conn} do
      view = frame(conn, "tiles/exploded")

      assert has_element?(
               view,
               "[data-role=player-chip][data-boom] [data-role=player-state].-top-2\\.5"
             )

      assert has_element?(view, "[data-role=player-chip].\\@container\\/tile")

      assert has_element?(
               view,
               "[data-role=player-vp].\\@max-\\[5\\.75rem\\]\\/tile\\:text-label"
             )
    end
  end

  describe "results panel" do
    test "the step bar keeps room for the step name on a phone", %{conn: conn} do
      view = frame(conn, "results/5p-purple")
      assert has_element?(view, "#tile-stage [data-role=tile-next].w-1\\/3")
      assert has_element?(view, "#tile-stage [data-role=tile-skip].px-3")
    end

    test "a long name takes two lines", %{conn: conn} do
      view = frame(conn, "results/8p-space")
      assert has_element?(view, "#results-stage [data-role=stage-name].line-clamp-2")

      assert has_element?(
               view,
               "#results-stage [data-role=stage-name][title='Wilhelmina Pottersfield-Brown']"
             )
    end

    test "a 1 VP or 1 ruby gain shows its digit", %{conn: conn} do
      gains =
        conn
        |> frame("results/chance")
        |> doc("#gallery-card-stage")
        |> texts("[data-gain=vp] > span[aria-hidden], [data-gain=rubies] > span[aria-hidden]")

      # Two seats roll the 1 VP face.
      assert "+1" in gains
      for gain <- gains, do: assert(gain =~ ~r/^[+−]\d+$/)
    end
  end

  test "the spoon's scoring ring stays inside the brew", %{conn: conn} do
    view = frame(conn, "pot/last-space")
    assert has_element?(view, "[data-space='53'] [data-role=scoring-ring][r='22']")
    # Elsewhere the ring keeps its size.
    {:ok, fx} = Fixtures.fixture("pot", "mid-brew")
    i = Game.scoring_index(fx.game, 0)
    view = frame(conn, "pot/mid-brew")
    assert has_element?(view, "[data-space='#{i}'] [data-role=scoring-ring][r='26']")
  end

  test "rows of valued :sm chips leave room for the badge", %{conn: conn} do
    view = frame(conn, "chip/all")
    refute has_element?(view, "[data-size=sm] span.gap-1")
    assert has_element?(view, "[data-size=sm] span.gap-1\\.5")
  end

  test "an open sheet over the pot folds the results stage (app.css)" do
    css = File.read!("assets/css/app.css")

    assert css =~
             ~r/:root:has\(\.sheet\[data-pot\]\[open\][^{]*\.results-stage\s+\[data-role="stage-rows"\]\s*\{\s*display: none/
  end
end
