defmodule QuacksWeb.BotsLiveTest do
  @moduledoc """
  Bots on the configure screen: the host adds a named bot to an empty seat row with
  one tap, removes it with ×; joiners see bot rows read-only. In the game a bot wears a
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

  test "the host adds a bot to an empty seat, removes it, and starts with one" do
    {:ok, id} = GameServer.start(3, {1, 2, 3})
    host = open(browser("a"), id)

    refute has_element?(host, "[data-seat='0'] [data-role='add-bot']")

    host |> element("[data-seat='2'] [data-role='add-bot']") |> render_click()
    {:ok, %{names: %{2 => name}}} = GameServer.get(id)
    assert name in Names.all()
    assert has_element?(host, "[data-seat='2']", name)
    assert has_element?(host, "[data-seat='2'] [data-role='bot-badge']")
    refute has_element?(host, "[data-seat='2'] [data-role='add-bot']")
    assert has_element?(host, "[data-role='waiting-for-players']", "2 of 3 seated")
    refute has_element?(host, "[aria-label='Fewer players'][disabled]")

    host |> element("[data-seat='1'] [data-role='add-bot']") |> render_click()
    {:ok, %{names: %{1 => second}}} = GameServer.get(id)
    assert second in Names.all() and second != name
    assert has_element?(host, "[data-seat='1']", second)
    assert has_element?(host, "[data-role='waiting-for-players']", "3 of 3 seated")
    assert has_element?(host, "[aria-label='Fewer players'][disabled]")

    host |> element("[data-seat='2'] [data-role='remove-bot']") |> render_click()
    refute has_element?(host, "[data-seat='2'] [data-role='bot-badge']")
    assert has_element?(host, "[data-role='waiting-for-players']", "2 of 3 seated")

    host |> element("button", "Start game") |> render_click()
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
