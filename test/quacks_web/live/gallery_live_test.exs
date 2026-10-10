defmodule QuacksWeb.GalleryLiveTest do
  @moduledoc """
  The component gallery (dev only): a viewer with one frame for the picked
  variant, a viewport width in the URL, and every variant's frame renders.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuacksWeb.Gallery.Fixtures

  test "the sidebar lists every variant and the viewer has one frame", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery")

    for c <- Fixtures.catalog(), v <- c.variants do
      assert has_element?(
               view,
               "[data-role=gallery-variant-link][data-variant='#{c.id}/#{v.id}']"
             )
    end

    assert view
           |> render()
           |> LazyHTML.from_document()
           |> LazyHTML.query("iframe")
           |> Enum.count() ==
             1
  end

  test "a variant has its own URL and the width is kept in it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery/bar/crow-4?w=1280")

    assert has_element?(
             view,
             "iframe[data-role=gallery-frame][src='/dev/gallery/frame/bar/crow-4']"
           )

    assert has_element?(view, "#gallery-stage[data-width='1280']")
    assert has_element?(view, "[data-role=gallery-width][data-width='1280'][aria-current]")

    view |> element("[data-role=gallery-width][data-width='360']") |> render_click()
    assert_patch(view, "/dev/gallery/bar/crow-4?w=360")

    view |> element("[data-role=gallery-width][data-width=full]") |> render_click()
    assert has_element?(view, "#gallery-stage[data-width='0']")
  end

  test "prev / next and the arrow keys step through the variants", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/gallery/bar/crow-4?w=392")

    view |> element("[data-role=gallery-next]") |> render_click()
    assert_patch(view, "/dev/gallery/bar/crow-5?w=392")

    render_keydown(view, "key", %{"key" => "ArrowLeft"})
    assert_patch(view, "/dev/gallery/bar/crow-4?w=392")
  end

  test "every frame renders without error", %{conn: conn} do
    for c <- Fixtures.catalog(), v <- c.variants do
      {:ok, view, _html} = live(conn, "/dev/gallery/frame/#{c.id}/#{v.id}")

      assert has_element?(
               view,
               "#gallery-frame[data-component='#{c.id}'][data-variant='#{v.id}']"
             )
    end
  end

  test "an unknown variant goes back to the index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/dev/gallery"}}} =
             live(conn, "/dev/gallery/frame/pot/nope")

    assert {:error, {:live_redirect, %{to: "/dev/gallery"}}} = live(conn, "/dev/gallery/pot/nope")
  end
end
