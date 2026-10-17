defmodule QuacksWeb.Plugs.CodexArt do
  @moduledoc """
  Serves the Codex card art at `/images/codex` from `CODEX_ART_DIR` when it is set
  (the Fly volume on staging). The art is Sirlin Games' and is not in git, so a
  release has none of it in `priv/static`. With no dir set, this plug does nothing
  and `Plug.Static` serves `priv/static/images/codex` (dev, after `mix codex.cards`).
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["images", "codex" | _]} = conn, _opts) do
    case dir() do
      nil -> conn
      dir -> Plug.Static.call(conn, Plug.Static.init(at: "/images/codex", from: dir))
    end
  end

  def call(conn, _opts), do: conn

  @doc "The folder that holds the art: `CODEX_ART_DIR`, else nil."
  def dir, do: Application.get_env(:quacks, :codex_art_dir)
end
