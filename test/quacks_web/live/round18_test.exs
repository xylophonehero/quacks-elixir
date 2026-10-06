defmodule QuacksWeb.Round18Test do
  @moduledoc """
  Round 18: the results slide is one compact table (a real `<table>`, the other
  lines in a closed "Details"), a Standings slide glides the rows from the old
  order to the new one, the droplet choice waits for the end of the reveal, and a
  tab that outlived a deploy reloads (`QuacksWeb.StaticCheck`).
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.Game
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
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

  defp render_slide(slides, kind, settled \\ true) do
    index = Enum.find_index(slides, &(&1.kind == kind))

    render_component(&RevealComponents.reveal_overlay/1,
      reveal: %{key: {:results, 1}, slides: slides, index: index, settled: settled},
      names: %{0 => "Ann", 1 => "Bo"},
      seat: 0
    )
    |> LazyHTML.from_fragment()
  end

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&String.trim(LazyHTML.text(&1)))

  describe "the results table" do
    test "a real table: rank, player, coins, VP, ruby, die, chips (round 20: no space)" do
      doc = results_game() |> Reveal.slides(0) |> render_slide(:results)

      assert doc |> LazyHTML.query("table[data-role=reveal-results] thead th") |> Enum.count() ==
               7

      # round 20: the coins column's header is the coin icon
      assert doc |> LazyHTML.query(~s(thead th[title=Coins] [data-icon=coin])) |> Enum.count() ==
               1

      rows = LazyHTML.query(doc, "tbody tr[data-role=reveal-result]")
      assert Enum.map(rows, &LazyHTML.attribute(&1, "data-seat")) == [["0"], ["1"]]

      # seat 0 rolled the die (a 2 VP face); seat 1 did not
      assert doc
             |> LazyHTML.query(~s(tr[data-seat="0"] [data-role=die-face][data-face=vp2]))
             |> Enum.count() == 1

      assert texts(doc, ~s(tr[data-seat="1"] [data-role=reveal-die-cell])) == ["–"]

      # the chips: green, black, purple counts
      assert doc |> LazyHTML.query(~s(tr[data-seat="0"] [data-role=reveal-pot])) |> Enum.count() ==
               1
    end

    test "the card line waits in a closed Details" do
      doc = results_game() |> Reveal.slides(0) |> render_slide(:results)

      assert [details] =
               doc |> LazyHTML.query("details[data-role=reveal-details]") |> Enum.to_list()

      assert LazyHTML.attribute(details, "open") == [nil] or
               LazyHTML.attribute(details, "open") == []

      assert texts(doc, "details [data-role=reveal-extra]") == [
               QuacksWeb.GameComponents.label({:fortune, :b1, {:vp, 1}})
             ]

      # no text line in the table itself
      assert doc |> LazyHTML.query("table [data-role=reveal-extra]") |> Enum.count() == 0
    end

    test "the locoweed column comes with The Alchemists" do
      plain = results_game() |> Reveal.slides(0) |> Enum.find(&(&1.kind == :results))
      assert plain.rows |> hd() |> Map.fetch!(:pot) |> Keyword.keys() == [:green, :black, :purple]

      alchemists =
        [expansions: [:alchemists]]
        |> results_game()
        |> Reveal.slides(0)
        |> Enum.find(&(&1.kind == :results))

      assert alchemists.rows |> hd() |> Map.fetch!(:pot) |> Keyword.keys() ==
               [:green, :black, :purple, :locoweed]
    end
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

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  # A solo reverse-side game in the shop of round 1 with its reveal unseen.
  defp solo_shop(fields) do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false, pot_side: :back})
    {:ok, view, _html} = live(browser("r18-#{System.unique_integer()}"), ~p"/g/#{id}")

    replace_game(id, fn g ->
      g = put_in(g.players[0].drawn, [{{:green, 1}, 12}])
      g = %{g | log: [{0, {:green_rubies, 1}}, {:round_end, 0}]}
      H.put(g, 0, [phase: :shop, coins: 10] ++ fields)
    end)

    {id, view}
  end

  describe "in the LiveView" do
    test "the standings slide settles on the server's tick" do
      {_id, view} = solo_shop([])
      view |> element("#reveal-skip") |> render_click()
      assert has_element?(view, "[data-role=reveal-standings][data-settled=false]")

      %{settle: ref} = :sys.get_state(view.pid).socket.assigns.reveal
      assert is_reference(ref)
      send(view.pid, {:reveal_settle, ref})
      assert has_element?(view, "[data-role=reveal-standings][data-settled=true]")
    end

    test "the droplet choice waits under the reveal and opens after it" do
      {_id, view} = solo_shop(droplet_moves: 1)

      assert has_element?(view, "#reveal-slide-0")
      assert has_element?(view, "dialog#decision-droplet_choice")
      refute has_element?(view, "dialog#decision-droplet_choice[phx-mounted*='quacks:modal']")

      view |> element("#reveal-skip") |> render_click()
      assert has_element?(view, "[data-role=reveal-slide][data-kind=standings]")
      assert has_element?(view, "#reveal-next", "Move the droplet")
      view |> element("#reveal-next") |> render_click()

      refute has_element?(view, "[data-role=reveal]")
      assert_push_event(view, "quacks:open", %{to: "#decision-droplet_choice"})
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
end
