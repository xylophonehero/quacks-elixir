defmodule QuacksWeb.Round36UiTest do
  @moduledoc """
  Round 36 (ui): chip choices as chips, Ghost's breath V in a sheet, pot chips as
  targets, the short second tile row centred, the peeked chip over the bag and the
  scoring space's pulse when the chip lands.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameServer

  doctest QuacksWeb.GameComponents, import: true, only: [loop_start: 3]

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(sets \\ %{}) do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, sets, %{fortune: false})
    {:ok, view, _html} = live(browser("r36-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  # A table of `players` seats: this browser and bots, started.
  defp table(players) do
    {:ok, id} = GameServer.start(players, {1, 2, 3})
    token = "r36-#{System.unique_integer()}"
    {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
    for _ <- 2..players, do: {:ok, _seat} = GameServer.add_bot(id, token)
    view |> element("button", "Start game") |> render_click()
    {id, view}
  end

  describe "item 4: the short second tile row is centred" do
    test "5 seats: 6 half columns, row 2 starts half a column in" do
      {_id, view} = table(5)

      assert has_element?(view, "#players-row[style*='repeat(6,']")

      assert has_element?(
               view,
               "[data-role=player-chip][data-seat='0'][style*='grid-column: 1 / span 2']"
             )

      assert has_element?(
               view,
               "[data-role=player-chip][data-seat='3'][style*='grid-column: 4 / span 2']"
             )

      assert has_element?(
               view,
               "[data-role=player-chip][data-seat='4'][style*='grid-column: 2 / span 2']"
             )
    end

    test "6 seats: row 2 fills the row" do
      {_id, view} = table(6)

      assert has_element?(
               view,
               "[data-role=player-chip][data-seat='5'][style*='grid-column: 1 / span 2']"
             )
    end
  end
end
