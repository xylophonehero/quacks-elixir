defmodule QuacksWeb.Plugs.Gallery do
  @moduledoc """
  The gate of the gallery and the scenarios (`/dev/gallery`, `/dev/scenarios`).
  The routes are in every build; this plug answers 404 unless
  `Application.get_env(:quacks, :gallery)` is true: on in dev and test
  (`config/dev.exs`, `config/test.exs`) and on staging (`APP_ENV=staging` in
  `config/runtime.exs`), off in prod. Staging and prod are the same `MIX_ENV=prod`
  build, so only a runtime flag can tell them apart.

  It is also the `on_mount` of the gallery's `live_session`, so a live navigation
  cannot reach a gallery LiveView past the plug.
  """
  import Plug.Conn

  @behaviour Plug

  @doc "True when the gallery is on (`:gallery` config)."
  @spec enabled?() :: boolean
  def enabled?, do: Application.get_env(:quacks, :gallery, false) == true

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if enabled?(), do: conn, else: conn |> send_resp(404, "Not Found") |> halt()
  end

  @doc false
  def on_mount(:default, _params, _session, socket) do
    if enabled?(),
      do: {:cont, socket},
      else: {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
  end
end
