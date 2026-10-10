defmodule QuacksWeb.GalleryLiveTest do
  @moduledoc "The component gallery (dev only): the index and every variant's frame render."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuacksWeb.Gallery.Fixtures

  test "the index lists every component and frames each variant", %{conn: conn} do
    for c <- Fixtures.catalog() do
      {:ok, view, _html} = live(conn, "/dev/gallery?c=#{c.id}")
      assert has_element?(view, "[data-role=gallery-component][data-component='#{c.id}']")

      for v <- c.variants,
          do: assert(has_element?(view, "iframe[src='/dev/gallery/#{c.id}/#{v.id}']"))
    end
  end

  test "every frame renders without error", %{conn: conn} do
    for c <- Fixtures.catalog(), v <- c.variants do
      {:ok, view, _html} = live(conn, "/dev/gallery/#{c.id}/#{v.id}")

      assert has_element?(
               view,
               "#gallery-frame[data-component='#{c.id}'][data-variant='#{v.id}']"
             )
    end
  end

  test "an unknown variant goes back to the index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/dev/gallery"}}} =
             live(conn, "/dev/gallery/pot/nope")
  end
end
