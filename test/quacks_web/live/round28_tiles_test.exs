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

      # The bots buy once the last human is done: the next round shows the last shop.
      next = %{shop | phase: :brewing, round: 4, log: [{:round_end, 3} | shop.log]}
      assert %{items: [{:bought, {:green, 1}}], key: "3-shop-1-0"} = TileReveal.news(next, 0, nil)
      assert TileReveal.news(%{next | log: [{:round_end, 4} | next.log]}, 0, nil) == nil
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

  describe "the rat track" do
    defp track(vps) do
      game = Game.new(seed: {1, 2, 3}, players: length(vps))

      game =
        vps
        |> Enum.with_index()
        |> Enum.reduce(game, fn {vp, s}, g -> put_in(g.players[s].vp, vp) end)

      render_component(&QuacksWeb.GameComponents.rat_track/1, game: game, names: %{})
      |> LazyHTML.from_fragment()
    end

    defp vps(html, selector) do
      html |> LazyHTML.query(selector) |> Enum.map(&String.trim(LazyHTML.text(&1)))
    end

    test "shows every seat's VP by its dot, the leader's too" do
      html = track([20, 14, 3, 9])
      assert vps(html, "[data-role=leader-vp]") == ["20"]
      assert Enum.sort(vps(html, "[data-role=track-vp]")) == ["14", "3", "9"]
    end

    test "seats in one step: one number per VP, alternating above and below" do
      html = track([2, 2, 1, 0])
      labels = vps(html, "[data-role=leader-vp], [data-role=track-vp]")
      assert Enum.sort(labels) == ["0", "1", "2"]
      assert html |> LazyHTML.query("[data-below]") |> Enum.count() == 1
    end
  end

  describe "the tile" do
    defp tile(game, opts \\ []) do
      render_component(
        &QuacksWeb.GameComponents.player_chip/1,
        [game: game, seat: 1, name: "Wilhelmina"] ++ opts
      )
      |> LazyHTML.from_fragment()
    end

    defp has?(html, selector), do: Enum.count(LazyHTML.query(html, selector)) > 0

    test "no name text: the initial in the disc, the name as title and for screen readers" do
      html = tile(Game.new(seed: {1, 2, 3}, players: 2), bot: true)
      assert html |> LazyHTML.query("[data-role=seat-disc]") |> LazyHTML.text() =~ "W"
      assert has?(html, ~s([data-role=player-chip][title=Wilhelmina]))
      assert has?(html, "[data-role=player-name].sr-only")
      refute has?(html, "[data-role=player-name-text]")
      # VP, rubies, droplet, flask, pot space; the numbers large.
      for role <- ~w(player-vp player-rubies player-droplet player-flask player-space),
          do: assert(has?(html, "[data-role=#{role}]"), role)

      assert has?(html, "[data-role=player-space].text-xl")
      assert has?(html, "[data-role=player-vp].text-xl")
    end

    test "black chips in the pot only with black book I (either black rule)" do
      assert has?(tile(Game.new(seed: {1, 2, 3}, players: 2)), "[data-role=player-black]")

      standings = Game.new(seed: {1, 2, 3}, players: 2, rules: %{black_rule: :standings})
      assert has?(tile(standings), "[data-role=player-black]")

      for set <- [2, 3] do
        game =
          Game.new(seed: {1, 2, 3}, players: 2, expansions: [:herb_witches], sets: %{black: set})

        refute has?(tile(game), "[data-role=player-black]")
      end
    end

    test "news swaps the bottom line; a new key gives the line a new id" do
      game = Game.new(seed: {1, 2, 3}, players: 2)
      html = tile(game, news: %{key: "1-2", items: [{:vp, 3}]})
      assert has?(html, "#tile-line-1-1-2[data-news] [data-role=tile-news] [data-gain=vp]")
      refute has?(tile(game), "[data-role=tile-line][data-news]")
    end
  end
end
