defmodule QuacksWeb.Plugs.PlayerToken do
  @moduledoc """
  Gives every browser a random `player_token`, kept in the (signed cookie) session.
  There are no accounts: the token is how a `Quacks.GameServer` knows which seat a
  browser sits in. LiveViews read it from their `session` argument in `mount/3`.
  """
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if get_session(conn, "player_token") do
      conn
    else
      put_session(conn, "player_token", Base.url_encode64(:crypto.strong_rand_bytes(16)))
    end
  end
end
