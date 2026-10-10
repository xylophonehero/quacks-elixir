defmodule QuacksWeb.GalleryLiveTest do
  @moduledoc """
  The gallery: a viewer with one frame for the picked story, the viewport width and
  the story's args in the URL, controls and presets that change the args, every
  story's frame renders (default args and each preset), and the scenarios' steps
  render as full screens.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.Scenarios
  alias QuacksWeb.Gallery.Stories

  test "the sidebar lists every story and the viewer has one frame", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery")

    for g <- Stories.catalog(), s <- g.stories do
      assert has_element?(
               view,
               "[data-role=gallery-variant-link][data-variant='#{g.id}/#{s.id}']"
             )
    end

    assert view
           |> render()
           |> LazyHTML.from_document()
           |> LazyHTML.query("iframe")
           |> Enum.count() == 1
  end

  test "a story has its own URL and the width and the args are kept in it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery/tiles/tiles?players=8&w=1280")

    assert has_element?(
             view,
             "iframe[data-role=gallery-frame][src='/dev/gallery/frame/tiles/tiles?players=8']"
           )

    assert has_element?(view, "#gallery-stage[data-width='1280']")
    assert has_element?(view, "#arg-players option[selected][value='8']")

    view |> element("[data-role=gallery-width][data-width='360']") |> render_click()
    assert_patch(view, "/dev/gallery/tiles/tiles?players=8&w=360")

    view |> element("[data-role=gallery-width][data-width=full]") |> render_click()
    assert has_element?(view, "#gallery-stage[data-width='0']")
  end

  test "the controls and the presets change the args in the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery/tiles/tiles?w=392")

    view
    |> form("#gallery-args", args: %{players: "2", state: "shop", bots: "true"})
    |> render_change()

    assert_patch(view, "/dev/gallery/tiles/tiles?bots=true&players=2&state=shop&w=392")

    view |> element("[data-role=gallery-preset][data-preset='8p-long']") |> render_click()

    assert_patch(
      view,
      "/dev/gallery/tiles/tiles?bots=true&long_names=true&players=8&state=shop&w=392"
    )

    view |> element("[data-role=gallery-reset]") |> render_click()
    assert_patch(view, "/dev/gallery/tiles/tiles?w=392")
  end

  test "an arg out of range is clamped and a bad value is the default", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery/tiles/tiles?players=99&state=nope")
    assert has_element?(view, "iframe[src='/dev/gallery/frame/tiles/tiles?players=8']")
  end

  test "an old variant URL goes to the story with that variant's args", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/dev/gallery/bar/crow?chips=5&w=392"}}} =
             live(conn, "/dev/gallery/bar/crow-5")

    assert {:error,
            {:live_redirect,
             %{to: "/dev/gallery/results/step-die?long_names=true&players=8&w=392"}}} =
             live(conn, "/dev/gallery/results/8p-die")
  end

  test "prev / next and the arrow keys step through the stories", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery/bar/crow?w=392")

    view |> element("[data-role=gallery-next]") |> render_click()
    assert_patch(view, "/dev/gallery/bar/draw-stop?w=392")

    render_keydown(view, "key", %{"key" => "ArrowLeft"})
    assert_patch(view, "/dev/gallery/bar/crow?w=392")

    # Not while a control has the focus.
    render_keydown(view, "key", %{"key" => "ArrowLeft", "typing" => true})
    refute_patched(view)
  end

  test "every story renders with its default args and with each preset", %{conn: conn} do
    for g <- Stories.catalog(), not String.starts_with?(g.id, "scenario-"), s <- g.stories do
      for {_id, _title, args} <- [{"default", "", %{}} | s.presets] do
        query = Stories.query(s, Stories.args(s, stringify(args)))
        path = "/dev/gallery/frame/#{g.id}/#{s.id}?" <> URI.encode_query(query)
        {:ok, view, _html} = live(conn, path)

        assert has_element?(
                 view,
                 "#gallery-frame[data-component='#{g.id}'][data-variant='#{s.id}']"
               ),
               path

        refute has_element?(view, "[data-role=gallery-error]"), path
      end
    end
  end

  test "a screen is the whole game page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery/frame/screens/evaluation?step=space&players=8")
    assert has_element?(view, "#gallery-frame[data-view=screen] #game [data-area=pot]")

    assert has_element?(view, "#players-row [data-role=player-chip]") or
             has_element?(view, "#players-row")

    assert has_element?(view, "[data-area=bar]")
  end

  test "every scenario step renders as a full screen", %{conn: conn} do
    for e <- Scenarios.all() do
      {:ok, script} = Scenarios.build(e)
      id = Stories.scenario_id(e)

      for i <- 1..length(script.steps) do
        path = "/dev/gallery/frame/scenario-#{e.kind}/#{id}?step=#{i}"
        {:ok, view, _html} = live(conn, path)
        assert has_element?(view, "#gallery-frame[data-view=screen] #game"), path
      end
    end
  end

  test "a scenario's story has its steps as a control and a link to the live game", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery/scenario-card/p12?step=2")
    {:ok, script} = Scenarios.build(Scenarios.get("card", "p12"))

    assert view |> element("#arg-step") |> render() =~ "#{length(script.steps)} · "
    assert has_element?(view, "[data-role=gallery-live][href='/dev/scenarios/card/p12?step=2']")
  end

  test "an unknown story goes back to the index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/dev/gallery"}}} =
             live(conn, "/dev/gallery/frame/pot/nope")

    assert {:error, {:live_redirect, %{to: "/dev/gallery"}}} = live(conn, "/dev/gallery/pot/nope")
  end

  defp stringify(args), do: Map.new(args, fn {k, v} -> {k, to_string(v)} end)
end
