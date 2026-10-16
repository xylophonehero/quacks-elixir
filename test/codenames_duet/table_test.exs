defmodule CodenamesDuet.TableTest do
  @moduledoc """
  `CodenamesDuet.Table` as a `Table.Server` adapter. The game is not in the
  lobby yet (no board), so the room test adds it to the games config for a moment:
  not async.
  """
  use ExUnit.Case, async: false

  alias CodenamesDuet.{Game, Table}
  alias Elixir.Table.Server, as: Room

  @key "codenames_duet_test"

  setup do
    old = Application.fetch_env!(:quacks, Elixir.Table)
    games = Map.put(old[:games], @key, %{name: "Duet", game: Table})
    Application.put_env(:quacks, Elixir.Table, Keyword.put(old, :games, games))
    on_exit(fn -> Application.put_env(:quacks, Elixir.Table, old) end)
  end

  test "the callbacks go to the engine; there are no bots" do
    {:ok, game} = Table.new(%{}, {1, 2, 3})
    assert Table.seats(game) == [0, 1]
    assert Table.status(game) == Game.status(game)
    assert Table.legal_actions(game, 0) == Game.legal_actions(game, 0)
    assert Table.view(game, 1) == Game.view(game, 1)
    assert {:ok, _} = Table.apply(game, 0, {:clue, "quokka", 1})
    assert Table.bot_levels() == []
  end

  @tag rule: "§1.1"
  test "a room for two people: no bot seat, each seat its own view" do
    host = "host-#{System.unique_integer()}"
    assert {:error, :invalid_level} = Room.create(@key, %{opts: %{}, bots: 1}, host)
    assert {:ok, code} = Room.create(@key, %{opts: %{}, bots: 0, name: "Nick"}, host)

    assert {:ok, %{seat: 0, view: host_view}} = Room.join(@key, code, host)
    assert {:ok, %{seat: 1, view: guest_view}} = Room.join(@key, code, "guest")
    refute host_view.view.key == guest_view.view.key
    assert host_view.status == {:playing, [0, 1]}
  end
end
