defmodule QuacksWeb.PwaController do
  @moduledoc """
  The web app manifest, built per flavour so staging and dev install next to prod
  with their own name and icon colour (`:flavour` in `config/runtime.exs`).
  """
  use QuacksWeb, :controller

  @names %{prod: "Quacks", staging: "Quacks Staging", dev: "Quacks Dev"}

  @doc "`:prod`, `:staging` or `:dev`."
  def flavour, do: Application.get_env(:quacks, :flavour, :prod)

  @doc "The app name for this flavour."
  def name, do: Map.fetch!(@names, flavour())

  @doc "Path of a PWA icon for this flavour: `/images/pwa[/staging|/dev]/<file>`."
  def icon(file) do
    case flavour() do
      :prod -> "/images/pwa/" <> file
      other -> "/images/pwa/#{other}/" <> file
    end
  end

  def manifest(conn, _params) do
    conn
    |> put_resp_content_type("application/manifest+json")
    |> send_resp(
      200,
      Jason.encode!(%{
        name: name(),
        short_name: name(),
        description: "Brew, push your luck, don't explode.",
        id: "/",
        start_url: "/",
        scope: "/",
        display: "standalone",
        orientation: "portrait",
        background_color: "#3e2a16",
        theme_color: "#3e2a16",
        icons: [
          %{src: icon("icon-192.png"), sizes: "192x192", type: "image/png", purpose: "any"},
          %{src: icon("icon-512.png"), sizes: "512x512", type: "image/png", purpose: "any"},
          %{
            src: icon("icon-maskable-512.png"),
            sizes: "512x512",
            type: "image/png",
            purpose: "maskable"
          }
        ]
      })
    )
  end
end
