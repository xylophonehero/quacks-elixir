defmodule QuacksWeb.Plugs.CodexArtTest do
  # Changes app env, so not async.
  use QuacksWeb.ConnCase, async: false

  alias QuacksWeb.Plugs.CodexArt

  @tag :tmp_dir
  test "serves the art from CODEX_ART_DIR when it is set", %{conn: conn, tmp_dir: dir} do
    File.write!(Path.join(dir, "zz-test.webp"), "art")
    Application.put_env(:quacks, :codex_art_dir, dir)
    on_exit(fn -> Application.delete_env(:quacks, :codex_art_dir) end)

    conn = get(conn, "/images/codex/zz-test.webp")
    assert conn.status == 200
    assert conn.resp_body == "art"
  end

  test "does nothing when no dir is set" do
    conn = Plug.Test.conn(:get, "/images/codex/zz-test.webp")
    assert CodexArt.call(conn, []) == conn
  end
end
