defmodule QuacksWeb.DebugReplayController do
  @moduledoc """
  `GET /debug/replay`: load a bug report's game in the browser
  (`Quacks.GameServer.start_from_bundle/2`) and go to it.

  Params: `issue=123` (the bundle comes from that GitHub issue,
  `Quacks.BugReports.fetch_bundle/1`) or `bundle=<base64 JSON>`; `at=N` replays
  only the first N actions (default: all); `seat=S` takes that seat (default: the
  reporter's seat in the bundle). This browser gets the seat, the bots stay frozen.

  Open in `:dev` (`dev_routes`); elsewhere only with `token=` equal to the
  `DEBUG_TOKEN` env var, else 404.
  """
  use QuacksWeb, :controller

  alias Quacks.{BugReports, GameServer}

  def show(conn, params) do
    with :ok <- allowed(params),
         {:ok, bundle} <- bundle(params),
         {:ok, id} <-
           GameServer.start_from_bundle(bundle,
             at: int(params["at"]),
             seat: int(params["seat"]) || bundle["seat"],
             token: get_session(conn, "player_token")
           ) do
      redirect(conn, to: ~p"/g/#{id}")
    else
      {:error, :forbidden} -> send_resp(conn, 404, "Not Found")
      {:error, reason} -> send_resp(conn, 422, "Could not load the replay: #{inspect(reason)}")
    end
  end

  defp allowed(params) do
    token = Application.get_env(:quacks, :debug_token)

    cond do
      Application.get_env(:quacks, :dev_routes) ->
        :ok

      is_binary(token) and token != "" and is_binary(params["token"]) and
          Plug.Crypto.secure_compare(params["token"], token) ->
        :ok

      true ->
        {:error, :forbidden}
    end
  end

  defp bundle(%{"issue" => issue}) do
    case int(issue) do
      nil -> {:error, :bad_issue}
      number -> BugReports.fetch_bundle(number)
    end
  end

  defp bundle(%{"bundle" => encoded}) do
    with {:ok, json} <- decode64(encoded),
         {:ok, %{} = bundle} <- Jason.decode(json) do
      {:ok, bundle}
    else
      _bad -> {:error, :bad_bundle}
    end
  end

  defp bundle(_params), do: {:error, :no_bundle}

  defp decode64(encoded) do
    encoded = String.trim(encoded)

    with :error <- Base.url_decode64(encoded, padding: false),
         :error <- Base.url_decode64(encoded),
         do: Base.decode64(encoded)
  end

  defp int(nil), do: nil

  defp int(string) do
    case Integer.parse(to_string(string)) do
      {n, ""} when n >= 0 -> n
      _bad -> nil
    end
  end
end
