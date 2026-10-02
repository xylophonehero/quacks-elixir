defmodule QuacksWeb.HomeLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "GET / renders Quacks", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Quacks"
  end
end
