defmodule QuacksWeb.Plugs.GalleryTest do
  @moduledoc """
  The gallery and the scenarios are in every build and gated at runtime: with the
  `:gallery` flag off (prod) every `/dev/gallery` and `/dev/scenarios` path is a
  404; with it on (dev, test, staging) they answer.
  """
  # Changes the app env: not async.
  use QuacksWeb.ConnCase, async: false

  alias QuacksWeb.Plugs.Gallery

  @paths [
    "/dev/gallery",
    "/dev/gallery/tiles/tiles?players=8",
    "/dev/gallery/frame/screens/brewing",
    "/dev/scenarios",
    "/dev/scenarios/card/p12"
  ]

  setup do
    on_exit(fn -> Application.put_env(:quacks, :gallery, true) end)
  end

  test "with the flag off every gallery and scenario path is a 404", %{conn: conn} do
    Application.put_env(:quacks, :gallery, false)

    for path <- @paths do
      assert conn |> get(path) |> response(404), path
    end
  end

  test "with the flag on the gallery and the scenarios answer", %{conn: conn} do
    Application.put_env(:quacks, :gallery, true)

    assert conn |> get("/dev/gallery") |> html_response(200)
    assert conn |> get("/dev/gallery/frame/screens/brewing") |> html_response(200)
    assert "/dev/gallery/scenario-card/" <> _ = conn |> get("/dev/scenarios") |> redirected_to()
    assert "/g/" <> _ = conn |> get("/dev/scenarios/card/p12") |> redirected_to()
  end

  test "a live mount with the flag off goes to the lobby" do
    Application.put_env(:quacks, :gallery, false)

    assert {:halt, %{redirected: {:redirect, %{to: "/"}}}} =
             Gallery.on_mount(:default, %{}, %{}, %Phoenix.LiveView.Socket{})
  end
end
