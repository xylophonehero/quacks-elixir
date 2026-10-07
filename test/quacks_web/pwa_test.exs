defmodule QuacksWeb.PwaTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the manifest is served as application/manifest+json with the install keys", %{conn: conn} do
    conn = get(conn, "/manifest.webmanifest")

    assert response(conn, 200)
    assert [type] = get_resp_header(conn, "content-type")
    assert type =~ "application/manifest+json"

    manifest = Jason.decode!(conn.resp_body)
    assert manifest["name"] == "Quacks"
    assert manifest["short_name"] == "Quacks"
    assert manifest["start_url"] == "/"
    assert manifest["scope"] == "/"
    assert manifest["display"] == "standalone"
    assert manifest["theme_color"] == manifest["background_color"]

    sizes = for icon <- manifest["icons"], do: {icon["sizes"], icon["purpose"]}
    assert {"192x192", "any"} in sizes
    assert {"512x512", "any"} in sizes
    assert {"512x512", "maskable"} in sizes

    for icon <- manifest["icons"] do
      assert File.exists?(Path.join(:code.priv_dir(:quacks), "static" <> icon["src"]))
    end
  end

  test "the root layout links the manifest, the theme colour and the touch icon", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    doc = LazyHTML.from_document(html)

    assert [_] =
             LazyHTML.query(doc, ~s(link[rel="manifest"][href="/manifest.webmanifest"]))
             |> Enum.to_list()

    assert [_] =
             LazyHTML.query(doc, ~s(meta[name="theme-color"][content="#3e2a16"]))
             |> Enum.to_list()

    assert [_] = LazyHTML.query(doc, ~s(meta[name="mobile-web-app-capable"])) |> Enum.to_list()
    assert [_] = LazyHTML.query(doc, ~s(link[rel="apple-touch-icon"])) |> Enum.to_list()

    assert [_] =
             LazyHTML.query(doc, ~s(meta[name="viewport"][content*="viewport-fit=cover"]))
             |> Enum.to_list()
  end

  test "the manifest href in the root layout is the undigested path and answers 200",
       %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    [href] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s(link[rel="manifest"]))
      |> LazyHTML.attribute("href")

    # A digested name (manifest-<hash>.webmanifest?vsn=d) is not in Plug.Static's
    # `only:` list, so it would answer 404 in prod.
    assert href == "/manifest.webmanifest"
    assert Path.basename(href) in QuacksWeb.static_paths()

    conn = get(build_conn(), href)
    assert response(conn, 200)
    assert [type] = get_resp_header(conn, "content-type")
    assert type =~ "application/manifest+json"
  end

  test "the lobby has the install button and the iOS hint, both hidden until app.js shows them",
       %{conn: conn} do
    conn = init_test_session(conn, player_token: "pwa-#{System.unique_integer()}")
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#install-app .pwa-install[data-role=install]")
    assert has_element?(view, "#install-app .pwa-ios-hint[data-role=install-hint]")
  end
end
