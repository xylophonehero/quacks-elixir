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

  describe "item 6: the scoring space pulses when the chip lands" do
    test "the draw's flight hides the gold space and the ring, then pops them" do
      js = File.read!("assets/js/app.js")

      assert js =~ "if (s0 !== 1) this.scoringPulse(460)"
      assert js =~ ~s([data-role=next-space], [data-role=scoring-ring][data-seat=)
      assert js =~ "delay: after"
      # Reduced motion: `fly` returns before the flight, so no pulse.
      assert js =~ "lift = 70) {\n    if (reduced()) return"
    end

    test "the pot marks its scoring space and this seat's ring" do
      {_id, view} = solo()
      view |> element("[data-role=action-bar] button", "Draw") |> render_click()

      assert has_element?(view, "#pot-0-lg [data-role=next-space]")
      assert has_element?(view, "#pot-0-lg [data-role=scoring-ring][data-seat='0']")
    end
  end
end
