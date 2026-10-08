defmodule QuacksWeb.Round28TilesTest do
  @moduledoc """
  Round 28 (tiles): on a phone the evaluation plays on the tiles; a tile's bottom
  line swaps to the step's news; no name text on the tiles; black chips only with
  black book I; every seat's VP on the rat track.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.TileReveal

  defp browser(token), do: init_test_session(build_conn(), player_token: token)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp to_shop(id) do
    Enum.find_value(1..120, fn _ ->
      {:ok, %{game: game}} = GameServer.get(id)

      if game.phase == :shopping do
        true
      else
        seat = Enum.find(game.seats, &(Game.legal_actions(game, &1) -- [:resume] != []))
        actions = Game.legal_actions(game, seat) -- [:resume]
        pick = [:stop, :chip_done, {:explosion_choice, :vp}, :draw]
        {:ok, _} = GameServer.apply(id, seat, Enum.find(pick, hd(actions), &(&1 in actions)))
        nil
      end
    end)
  end

  defp duo_results do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    alice = open(browser("alice-#{id}"), id)
    _bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {:ok, _} = GameServer.apply(id, 0, :draw)
    {:ok, _} = GameServer.apply(id, 1, :draw)
    {:ok, _} = GameServer.apply(id, 1, :draw)
    to_shop(id)
    {id, alice}
  end

  defp settings(view, extra) do
    render_hook(
      view,
      "reveal_settings",
      Map.merge(%{"mode" => "step", "speed" => "normal"}, extra)
    )
  end

  describe "phones" do
    test "play the results on the tiles, whatever the Results choice says" do
      {_id, view} = duo_results()
      settings(view, %{"show" => "overlay", "phone" => true})

      refute has_element?(view, "[data-role=reveal]")
      assert has_element?(view, "#tile-stage[data-kind]")
      # The choice hides on a phone; the form says it is a phone.
      refute has_element?(view, "#reveal-settings [data-role=reveal-show]")
      assert has_element?(view, "#reveal-settings [data-role=reveal-show-phone]")
      assert has_element?(view, ~s(#reveal-settings input[name=phone][value=true]))
    end

    test "a larger screen keeps the overlay by default" do
      {_id, view} = duo_results()
      settings(view, %{"show" => "overlay", "phone" => false})

      assert has_element?(view, "[data-role=reveal]")
      refute has_element?(view, "#tile-stage")
      assert has_element?(view, "#reveal-show-overlay[checked]")
    end

    test "a form change without the Results choice keeps the choice" do
      {_id, view} = duo_results()
      settings(view, %{"show" => "tiles", "phone" => false})
      settings(view, %{"phone" => "false"})
      assert has_element?(view, "#reveal-show-tiles[checked]")
    end
  end

  describe "the news on the tile's bottom line" do
    test "a step's news swaps into the bottom line, inside the tile" do
      {_id, view} = duo_results()
      settings(view, %{"show" => "tiles", "phone" => true})

      news =
        Enum.find_value(1..10, fn _ ->
          if has_element?(view, "[data-role=tile-line][data-news] [data-role=tile-news]"),
            do: true,
            else: view |> element("[data-role=tile-next]") |> render_click() && nil
        end)

      assert news
      # The news and the totals share the line; nothing hangs outside the tile.
      assert has_element?(
               view,
               "[data-role=tile-line][data-news] [data-role=player-stats].tile-totals"
             )

      refute has_element?(view, "[data-role=tile-gain]")
    end

    test "news/3: die faces on the die step, badges on a book step, the shop's buys" do
      game = %Game{round: 3, phase: :brewing, seats: [0, 1], log: []}
      die = %{kind: :die, rows: [%{seat: 0, rolls: [%{face: :ruby}]}, %{seat: 1, rolls: []}]}

      book = %{
        kind: :book,
        book: :black,
        rows: [%{seat: 0, scored: true, vp: 0, rubies: 1, droplet: 1}]
      }

      reveal = %{tiles: true, slides: [die, book], index: 0}
      assert %{items: [{:die, :ruby}], key: "3-0"} = TileReveal.news(game, 0, reveal)
      assert TileReveal.news(game, 1, reveal) == nil

      assert %{items: [{:book, :black}, {:rubies, 1}, {:droplet, 1}], key: "3-1"} =
               TileReveal.news(game, 0, %{reveal | index: 1})

      shop = %{game | phase: :shopping, log: [{0, {:bought, [{:green, 1}]}}]}
      assert %{items: [{:bought, {:green, 1}}]} = TileReveal.news(shop, 0, nil)
    end

    test "droplets/3: the droplet before the steps still to come" do
      game = Game.new(seed: {1, 2, 3}, players: 2)
      game = put_in(game.players[0].droplet, 3)
      book = %{kind: :book, book: :black, rows: [%{seat: 0, scored: true, droplet: 1}]}
      die = %{kind: :die, rows: [%{seat: 0, rolls: [%{face: :droplet}]}]}

      assert TileReveal.droplets(game, [die, book], -1)[0] == 1
      assert TileReveal.droplets(game, [die, book], 0)[0] == 2
      assert TileReveal.droplets(game, [die, book], 1)[0] == 3
    end
  end
end
