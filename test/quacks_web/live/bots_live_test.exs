defmodule QuacksWeb.BotsLiveTest do
  @moduledoc """
  Bots: the spell book seats them; the waiting panel fills the open seats ("Fill
  with bots"). In the game a bot wears a
  "bot" badge.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.AI.Names
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  test "the waiting panel: Fill with bots seats named bots and starts" do
    # Round 26: the bots are picked in the spell book; the waiting panel only fills.
    {:ok, id} = GameServer.create(%{players: 3}, "a", {1, 2, 3})
    host = open(browser("a"), id)

    refute has_element?(host, "[data-role='add-bot']")
    refute has_element?(host, "button", "Start game")
    assert has_element?(host, "[data-role='waiting-for-players']", "1 of 3 seated")

    host |> element("[data-role=fill-bots]") |> render_click()
    {:ok, %{names: names, status: :playing}} = GameServer.get(id)
    assert names[1] in Names.all() and names[2] in Names.all() and names[1] != names[2]
    assert has_element?(host, "[data-role='player-chip'][data-seat='1'] [data-role='bot-badge']")
    refute has_element?(host, "[data-role='player-chip'][data-seat='0'] [data-role='bot-badge']")
  end

  test "a joiner sees bot rows read-only and no add control" do
    {:ok, id} = GameServer.start(4, {1, 2, 3})
    {:ok, 0} = GameServer.claim_seat(id, "a")
    {:ok, 1} = GameServer.add_bot(id, "a")
    {:ok, %{names: %{1 => name}}} = GameServer.get(id)
    guest = open(browser("b"), id)

    assert has_element?(guest, "[data-seat='1']", name)
    assert has_element?(guest, "[data-seat='1'] [data-role='bot-badge']")
    refute has_element?(guest, "[data-role='remove-bot']")
    refute has_element?(guest, "[data-role='add-bot']")
    # the guest took the next free seat, after the bot
    assert has_element?(guest, "[data-seat='2'] #seat-name")
  end
end
