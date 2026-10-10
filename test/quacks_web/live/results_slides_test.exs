defmodule QuacksWeb.ResultsSlidesTest do
  @moduledoc """
  The results slides and the round summary: one slide per scoring step, the results table, the standings and the Fortune Teller card's outcome.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Quacks.Game
  alias Quacks.GameHelpers, as: H
  alias QuacksWeb.{PanelComponents, TileComponents}
  alias QuacksWeb.{Reveal, RevealComponents}

  # Newest first. Seat 0: die, green, purple, the scoring space and a card; seat 1:
  # its scoring VP.
  @log [
    {1, {:pot_vp, 2, 10}},
    {0, {:pot_vp, 3, 13}},
    {0, {:pot_ruby, 13}},
    {0, {:purple, 2, :vp1_ruby}},
    {0, {:green_rubies, 1}},
    {0, {:bonus_die, {:vp, 2}}},
    {0, {:fortune, :b1, {:vp, 1}}},
    {:round_end, 0}
  ]

  defp results_game(opts \\ []) do
    game = Game.new([seed: {1, 2, 3}, players: 2] ++ opts)

    game =
      put_in(game.players[0].drawn, [{{:green, 1}, 12}, {{:purple, 1}, 11}, {{:purple, 1}, 3}])

    game = put_in(game.players[1].drawn, [{{:black, 1}, 8}, {{:white, 2}, 2}])
    game = put_in(game.players[0].pot_index, 12)
    %{game | log: @log, phase: :shopping}
  end

  defp render_slide(slides, kind, settled) do
    index = Enum.find_index(slides, &(&1.kind == kind))

    render_component(&RevealComponents.reveal_overlay/1,
      reveal: %{key: {:results, 1}, slides: slides, index: index, settled: settled},
      names: %{0 => "Ann", 1 => "Bo"},
      seat: 0
    )
    |> LazyHTML.from_fragment()
  end

  describe "the standings" do
    # Before the round seat 1 led (6 to 5); seat 0's round (7 VP) puts it first.
    defp standings_game do
      game = results_game()
      game = put_in(game.players[0].vp, 12)
      put_in(game.players[1].vp, 8)
    end

    test "every seat in seat order, with its rank and totals before and after" do
      slides = Reveal.slides(standings_game(), 0)
      assert %{kind: :standings, rows: [row0, row1]} = List.last(slides)

      assert %{seat: 0, from_rank: 1, rank: 0, from_vp: 5, vp: 12} = row0
      assert %{seat: 1, from_rank: 0, rank: 1, from_vp: 6, vp: 8} = row1
    end

    test "the first render has the old ranks and VP, the settled one the new" do
      slides = Reveal.slides(standings_game(), 0)
      before = render_slide(slides, :standings, false)
      after_tick = render_slide(slides, :standings, true)

      rank = fn doc, seat ->
        doc
        |> LazyHTML.query(~s([data-role=standings-row][data-seat="#{seat}"]))
        |> LazyHTML.attribute("style")
      end

      assert rank.(before, 0) == ["--rank: 1"]
      assert rank.(after_tick, 0) == ["--rank: 0"]

      assert before
             |> LazyHTML.query(~s(#standings-row-0 .stat-tick))
             |> LazyHTML.attribute("data-value")
             |> hd() == "5"

      assert after_tick
             |> LazyHTML.query(~s(#standings-row-0 .stat-tick))
             |> LazyHTML.attribute("data-value")
             |> hd() == "12"

      # no running strip on this slide: the rows say it
      assert before |> LazyHTML.query("[data-role=reveal-strip]") |> Enum.count() == 0
    end
  end

  describe "QuacksWeb.StaticCheck" do
    defmodule Endpoint do
      def config(:cache_static_manifest_latest),
        do: %{"assets/css/app.css" => "assets/css/app-new.css"}
    end

    defp socket(static) do
      %Phoenix.LiveView.Socket{
        endpoint: Endpoint,
        transport_pid: self(),
        private: %{connect_params: %{"_track_static" => [static]}, live_temp: %{}}
      }
    end

    test "a tab with the old stylesheet is told to reload" do
      {:cont, socket} =
        QuacksWeb.StaticCheck.on_mount(
          :default,
          %{},
          %{},
          socket("http://x/assets/css/app-old.css")
        )

      assert [["quacks:reload", %{}]] = socket.private.live_temp[:push_events]
    end

    test "a tab with the current one is not" do
      {:cont, socket} =
        QuacksWeb.StaticCheck.on_mount(
          :default,
          %{},
          %{},
          socket("http://x/assets/css/app-new.css")
        )

      refute socket.private.live_temp[:push_events]
    end
  end

  # Newest first. Seat 0: two dice (the base die and G6), black, the space with a
  # ruby; seat 1: black and its scoring VP.
  @log [
    {1, {:pot_vp, 2, 10}},
    {0, {:pot_vp, 3, 13}},
    {0, {:pot_ruby, 13}},
    {1, {:black, :droplet}},
    {0, {:black, :droplet}},
    {0, {:effect, {:green, 6}, {:bonus_die, :ruby}}},
    {0, {:bonus_die, {:vp, 2}}},
    {:round_end, 0}
  ]

  defp game do
    game = Game.new(seed: {1, 2, 3}, players: 2)
    game = put_in(game.players[0].drawn, [{{:green, 1}, 12}, {{:black, 1}, 9}])
    game = put_in(game.players[1].drawn, [{{:black, 1}, 8}, {{:black, 1}, 4}])
    game = put_in(game.players[0].pot_index, 12)
    %{game | log: @log, phase: :shopping}
  end

  defp render_slide_2(kind) do
    slides = Reveal.slides(game(), 0)
    index = Enum.find_index(slides, &(&1.kind == kind))

    render_component(&RevealComponents.reveal_overlay/1,
      reveal: %{key: {:results, 1}, slides: slides, index: index},
      names: %{0 => "Ann", 1 => "Bo"},
      seat: 0
    )
    |> LazyHTML.from_fragment()
  end

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  test "the steps: die, black, the space, then the standings (round 28: no table)" do
    assert game() |> Reveal.slides(0) |> Enum.map(& &1.kind) ==
             [:die, :book, :space, :standings]
  end

  test "the die slide: a row per seat, two dice side by side for seat 0" do
    doc = render_slide_2(:die)
    assert count(doc, "[data-role=reveal-step-row]") == 2
    assert count(doc, ~s([data-role=reveal-step-row][data-seat="0"] [data-role=die])) == 2
    assert count(doc, ~s([data-role=reveal-step-row][data-seat="1"][data-scored=false])) == 1
  end

  test "the black slide: both seats, their chips and the neighbour compared" do
    doc = render_slide_2(:book)
    assert count(doc, ~s([data-seat="1"] [data-role=reveal-chips] [data-chip-icon=black])) == 2
    assert count(doc, ~s([data-seat="0"] [data-role=reveal-compare] [data-seat="1"])) == 1
    assert count(doc, ~s([data-seat="0"] [data-reward=droplet])) == 1
  end

  test "the space slide: coins, VP, and the ruby on the row that landed on one" do
    doc = render_slide_2(:space)
    assert count(doc, ~s([data-seat="0"] [data-role=reveal-ruby-landing])) == 1
    assert count(doc, ~s([data-seat="1"] [data-role=reveal-ruby-landing])) == 0
    assert count(doc, "[data-role=reveal-coins] [data-icon=coin]") == 2
  end

  test "the overlay is full screen on phones" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
    assert css =~ ~r/@media \(width < 40rem\) \{\s+\.sheet\.reveal-sheet \{\s+inset: 0;/
  end

  defp count_2(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  # Both seats' result lines, as their player sheets show them.
  defp results(game),
    do:
      Enum.map_join(game.seats, fn seat ->
        render_component(&TileComponents.result_lines/1, game: game, seat: seat)
      end)

  test "the summary shows the Take a Chance die per seat, not the rats (round start)" do
    game =
      Game.new(seed: {1, 2, 3}, players: 2, fortune: false)
      |> H.put(0, vp: 3)
      |> H.put(1, vp: 12)

    game = %{
      game
      | round: 2,
        log: [
          {0, {:fortune, :p8, {:drew, [{:white, 1}, {:white, 2}]}}},
          {1, {:fortune, :p12, :droplet}},
          {0, {:fortune, :p12, {:vp, 2}}} | game.log
        ]
    }

    html = results(game)
    assert html =~ "Take a Chance: rolled the die: 2 VP"
    assert html =~ "Take a Chance: rolled the die: droplet +1"
    assert html =~ "Less is More: drew white 1, white 2 (sum 3)"
    refute html =~ "Rats next round"
    assert count_2(html, "[data-role=result-rats]") == 0
    assert count_2(html, "[data-role=result-buying-power]") == 0
  end

  test "round 9: final buying power from the coins and rubies, or the log" do
    game =
      Game.new(seed: {1, 2, 3}, players: 2, fortune: false)
      |> H.put(0, coins: 17, rubies: 5)
      |> H.put(1, coins: 1, rubies: 0)

    game = %{game | round: 9, log: [{1, {:final_conversion, 12, 2, 3, 1}} | game.log]}

    html = results(game)
    assert html =~ "Final buying power: 17 coins → 3 VP, 5 rubies → 2 VP"
    assert html =~ "Final buying power: 12 coins → 2 VP, 3 rubies → 1 VP"
    assert count_2(html, "[data-role=result-rats]") == 0
  end

  test "solo has no rats" do
    html =
      render_component(&TileComponents.result_lines/1, game: Game.new(seed: {1, 2, 3}), seat: 0)

    assert count_2(html, "[data-role=result-rats]") == 0
  end

  test "a tiered book shows its tiers as a table on the tile and in the book list" do
    html = render_component(&PanelComponents.book_tile/1, colour: :purple, set: 2)
    assert count_2(html, "[data-role=book-tiers] tr") == 3
    assert html =~ "green 1 · blue 2 · 3 VP · droplet +1"

    html = render_component(&PanelComponents.book_list/1, books: [purple: 2, green: 1])
    assert count_2(html, "[data-book=purple-2] [data-role=book-tiers]") == 1
    assert count_2(html, "[data-book=green-1] [data-role=book-tiers]") == 0
  end
end
