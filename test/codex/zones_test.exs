defmodule Codex.ZonesTest do
  @moduledoc "Zones.locate/2 gives the same answer as a scan of every placement."
  use ExUnit.Case, async: true

  alias Codex.{Game, Zones}
  alias Codex.Bot.Plan

  test "locate/2 agrees with placements/1 for every card, on games and views" do
    {:ok, g} = Game.new(%{bot: true}, {8, 1, 2})

    Enum.reduce(1..160, g, fn i, g ->
      if rem(i, 20) == 0, do: check(g)

      case g.phase do
        :over ->
          g

        _ ->
          {a, _} = Plan.choose(Game.bot_view(g, g.active), nil)
          {:ok, g} = Game.apply(g, g.active, a)
          %{g | history: []}
      end
    end)
  end

  defp check(g) do
    view = Game.bot_view(g, 0)

    for state <- [g, view], id <- [999_999 | Map.keys(g.cards)] do
      slow = Enum.find_value(Zones.placements(state), fn {i, at} -> i == id && at end)
      assert Zones.locate(state, id) == slow
    end
  end
end
