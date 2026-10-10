defmodule QuacksWeb.ScenarioController do
  @moduledoc """
  The scenarios' routes (`QuacksWeb.Plugs.Gallery`: dev, test and staging).

  `GET /dev/scenarios`: the scenarios are in the gallery now
  (`QuacksWeb.Gallery.Stories`), one group per kind; this goes there.

  `GET /dev/scenarios/:kind/*id`: play the scenario (`Quacks.Scenarios.build/2`),
  start it as a debug table (`Quacks.GameServer.start_from_bundle/2`, the
  `/debug/replay` path) with this browser on seat 0, and go to the game page at its
  first step. `step=N` (1-based) starts at that step instead; `players=N` plays it
  with that many seats (the gallery's "Open as a live game").
  """
  use QuacksWeb, :controller

  alias Quacks.{GameServer, Scenarios}

  def index(conn, _params) do
    [first | _] = Scenarios.all()

    redirect(conn,
      to: "/dev/gallery/scenario-#{first.kind}/#{QuacksWeb.Gallery.Stories.scenario_id(first)}"
    )
  end

  def show(conn, %{"kind" => kind, "id" => parts} = params) do
    with %{} = entry <- Scenarios.get(kind, Enum.join(parts, "/")),
         {:ok, script} <- Scenarios.build(entry, players(params["players"])),
         bundle = Scenarios.bundle(entry, script),
         step = Enum.at(script.steps, step_index(params["step"], script.steps), hd(script.steps)),
         {:ok, id} <-
           GameServer.start_from_bundle(bundle,
             at: step.at,
             seat: 0,
             token: get_session(conn, "player_token")
           ) do
      redirect(conn, to: ~p"/g/#{id}")
    else
      nil -> send_resp(conn, 404, "No such scenario")
      {:error, reason} -> send_resp(conn, 422, "The scenario did not build: #{inspect(reason)}")
    end
  end

  defp players(nil), do: []

  defp players(n) do
    case Integer.parse(n) do
      {i, ""} when i in 2..5 -> [players: i]
      _bad -> []
    end
  end

  defp step_index(nil, _steps), do: 0

  defp step_index(n, steps) do
    case Integer.parse(n) do
      {i, ""} when i >= 1 -> min(i, length(steps)) - 1
      _bad -> 0
    end
  end
end
