defmodule QuacksWeb.Round27Test do
  @moduledoc """
  Round 27: the players row is a loop of tiles (design B): pot space, VP, rubies,
  black chips; exploded, stopped and round leader (crown) states; a fixed seat loop
  in two rows from 5 players.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers, as: H
  alias Quacks.Rules.PotTrack
  alias QuacksWeb.TileComponents

  doctest QuacksWeb.TileComponents, import: true, only: [seat_loop: 1]

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()

  defp tile(game, seat, opts \\ []) do
    render_component(
      &TileComponents.player_chip/1,
      [game: game, seat: seat, name: "Clara"] ++ opts
    )
  end

  # A pot that ends at `index`, with `blacks` black chips in it.
  defp pot(game, seat, index, blacks \\ 0) do
    drawn =
      for i <- 1..max(blacks, 1), do: {if(i <= blacks, do: {:black, 1}, else: {:orange, 1}), i}

    H.put(game, seat, drawn: drawn, pot_index: index)
  end

  defp game(n), do: Game.new(seed: {1, 2, 3}, players: n, rules: %{fortune: false})

  describe "the seat loop" do
    # The rows as seen on screen, left to right (nil: an empty cell).
    defp rows(n) do
      at =
        Map.new(TileComponents.seat_loop(Enum.to_list(0..(n - 1))), fn {s, r, c} ->
          {{r, c}, s + 1}
        end)

      cols = TileComponents.loop_columns(n)
      rows = at |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
      for row <- rows, do: for(col <- 1..cols, do: at[{row, col}])
    end

    test "2 to 4 seats: one row in seat order" do
      assert rows(2) == [[1, 2]]
      assert rows(3) == [[1, 2, 3]]
      assert rows(4) == [[1, 2, 3, 4]]
    end

    test "5 to 8 seats: two rows, the second backwards, so the tiles form a loop" do
      assert rows(5) == [[1, 2, 3], [nil, 5, 4]]
      assert rows(6) == [[1, 2, 3], [6, 5, 4]]
      assert rows(7) == [[1, 2, 3, 4], [nil, 7, 6, 5]]
      assert rows(8) == [[1, 2, 3, 4], [8, 7, 6, 5]]
    end

    test "neighbours touch: each seat sits beside or above the next" do
      for n <- 2..8 do
        at =
          Map.new(TileComponents.seat_loop(Enum.to_list(0..(n - 1))), fn {s, r, c} ->
            {s, {r, c}}
          end)

        for s <- 0..(n - 2) do
          {r1, c1} = at[s]
          {r2, c2} = at[s + 1]
          assert abs(r1 - r2) + abs(c1 - c2) == 1, "#{n} seats: #{s} and #{s + 1} do not touch"
        end

        # With an even count the loop closes: the last seat sits under the first.
        if n >= 6 and rem(n, 2) == 0, do: assert(at[n - 1] == {2, 1})
      end
    end

    test "the page places the 8 tiles in the loop and never scrolls sideways" do
      {:ok, id} = GameServer.start(8, {1, 2, 3}, %{}, %{fortune: false})
      token = "eight-#{id}"

      {:ok, view, _html} =
        live(init_test_session(build_conn(), player_token: token), ~p"/g/#{id}")

      for _ <- 1..7, do: {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()

      html = render(view)
      assert count(html, ~s(#players-row[data-columns="4"] [data-role=player-chip])) == 8

      placed =
        html
        |> query("#players-row [data-role=player-chip]")
        |> Enum.map(fn t ->
          [seat] = LazyHTML.attribute(t, "data-seat")
          [row] = LazyHTML.attribute(t, "data-row")
          [col] = LazyHTML.attribute(t, "data-col")
          {seat, row, col}
        end)

      assert {"0", "1", "1"} in placed
      assert {"3", "1", "4"} in placed
      assert {"4", "2", "4"} in placed
      assert {"7", "2", "1"} in placed
      refute html =~ "overflow-x-auto snap-x"
    end
  end

  describe "the tile" do
    test "pot space (its coins), VP, rubies and black chips in the pot" do
      g = game(3) |> pot(1, 20, 2) |> H.put(1, vp: 14, rubies: 3)
      html = tile(g, 1)

      assert text(html, "[data-role=player-space]") =~ to_string(PotTrack.at(21).coins)
      assert count(html, ~s([data-role=player-space][data-index="21"])) == 1
      assert text(html, "[data-role=player-vp]") =~ "14"
      assert text(html, "[data-role=player-rubies]") =~ "3"
      # Round 31: while brewing the black count sits on the line's right end.
      assert text(html, "[data-role=tile-black]") =~ "2"
      assert count(html, "[data-role=seat-disc].bg-player-1") == 1
    end

    test "your tile has the gold border" do
      g = game(2)
      assert count(tile(g, 0, you: true), "[data-role=player-chip][data-you].border-gold") == 1
      assert count(tile(g, 1), "[data-role=player-chip].border-gold") == 0
    end

    test "exploded: red stripes and the burst badge" do
      g = game(3) |> pot(2, 12) |> H.put(2, exploded?: true)
      html = tile(g, 2)

      assert count(html, "[data-role=player-chip][data-boom].tile-boom") == 1
      assert count(html, ~s([data-role=player-state][data-state=exploded] svg)) == 1
    end

    test "stopped: faded with a check badge; brewing: no badge" do
      g = game(3) |> pot(1, 9)
      assert count(tile(g, 1), "[data-role=player-state]") == 0
      assert count(tile(g, 1), ".opacity-55") == 0

      html = tile(H.put(g, 1, phase: :stopped), 1)
      assert count(html, "[data-role=player-chip][data-stopped].opacity-55") == 1
      assert count(html, ~s([data-role=player-state][data-state=stopped] path[d^="M3 8.5"])) == 1
    end

    test "the round leader wears the crown and the gold glow" do
      g = game(3)
      html = tile(g, 1, lead: true)

      assert count(html, "[data-role=player-chip][data-lead].tile-lead [data-role=crown] svg") ==
               1

      assert count(tile(g, 1), "[data-role=crown]") == 0
    end
  end

  describe "round_leaders/1" do
    test "the furthest pot that did not explode; ties share the crown" do
      g = game(4) |> pot(0, 10) |> pot(1, 14) |> pot(2, 18) |> pot(3, 14)
      g = H.put(g, 2, exploded?: true)
      assert TileComponents.round_leaders(g) == [1, 3]

      g = H.put(g, 2, explosion_choice: :witch)
      assert TileComponents.round_leaders(g) == [2]
    end

    test "nobody before a chip is drawn, and nobody solo" do
      assert TileComponents.round_leaders(game(4)) == []
      assert TileComponents.round_leaders(game(1) |> pot(0, 10)) == []
    end

    test "the page crowns the leader's tile" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      token = "crown-#{id}"

      {:ok, view, _html} =
        live(init_test_session(build_conn(), player_token: token), ~p"/g/#{id}")

      {:ok, _seat} = GameServer.add_bot(id, token)
      view |> element("button", "Start game") |> render_click()
      refute has_element?(view, "[data-role=crown]")

      H.replace_game(id, fn g -> g |> pot(0, 6) |> pot(1, 9) end)

      assert has_element?(
               view,
               ~s([data-role=player-chip][data-seat="1"][data-lead] [data-role=crown])
             )

      refute has_element?(view, ~s([data-role=player-chip][data-seat="0"] [data-role=crown]))
    end
  end
end
