defmodule QuacksWeb.Plugs.FramingTest do
  @moduledoc """
  Issue #71: WebinarGeek shows the game in an iframe. Browser pages name who may
  embed them (`frame-ancestors`) and leave out the SAMEORIGIN `x-frame-options`.
  """
  use QuacksWeb.ConnCase, async: true

  test "the lobby may be framed by the allowed sites only", %{conn: conn} do
    conn = get(conn, "/")

    assert get_resp_header(conn, "x-frame-options") == []

    assert get_resp_header(conn, "content-security-policy") == [
             "frame-ancestors 'self' https://*.webinargeek.com http://localhost:3333"
           ]
  end
end
