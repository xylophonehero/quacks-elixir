defmodule QuacksWeb.Round29TilesTest do
  @moduledoc """
  Round 29 (tiles + type): while the round brews, a tile's bottom line holds the
  seat's last draws (B2); an exploded tile shakes; numbers on the tiles and the
  pot use the type tokens, none below 13 px (B3).
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

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    alice = open(browser("alice-#{id}"), id)
    _bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {id, alice}
  end

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  # Draw for `seat` until it explodes (answering any choice on the way).
  defp explode(id, seat) do
    Enum.find_value(1..60, fn _ ->
      g = game(id)
      p = Game.player(g, seat)
      actions = Game.legal_actions(g, seat) -- [:resume]

      cond do
        p.exploded? -> true
        :draw in actions -> GameServer.apply(id, seat, :draw) && nil
        actions == [] -> true
        true -> GameServer.apply(id, seat, hd(actions -- [:stop, :use_flask])) && nil
      end
    end)
  end

  describe "brewing news (B2)" do
    test "a tile's bottom line holds the seat's last draws, newest first" do
      {id, view} = duo()
      for _ <- 1..4, do: {:ok, _} = GameServer.apply(id, 1, :draw)
      {:ok, _} = GameServer.apply(id, 0, :draw)

      g = game(id)
      [{{colour, value}, _space} | _] = Game.player(g, 1).drawn
      render(view)

      assert has_element?(
               view,
               ~s(#players-row [data-seat="1"] [data-role="tile-line"][data-hold])
             )

      newest = ~s(#players-row [data-seat="1"] [data-gain="drew"][data-age="0"])
      assert has_element?(view, newest <> ~s( [aria-label="#{colour} #{value}"]))
      assert has_element?(view, ~s(#players-row [data-seat="1"] [data-gain="drew"][data-age="3"]))
      refute has_element?(view, ~s(#players-row [data-seat="1"] [data-gain="drew"][data-age="4"]))
      assert has_element?(view, ~s(#players-row [data-seat="0"] [data-gain="drew"][data-age="0"]))
    end

    test "news/3 while brewing: the last draws, keyed by the draw count" do
      {id, _view} = duo()
      for _ <- 1..4, do: {:ok, _} = GameServer.apply(id, 1, :draw)
      g = game(id)

      assert %{key: key, items: items, hold: true} = TileReveal.news(g, 1, nil)
      assert key == "#{g.round}-draw-4"
      # Two columns: up to seven draws fit.
      assert Enum.map(items, &elem(&1, 2)) == [0, 1, 2, 3]

      expected = g |> Game.player(1) |> Map.get(:drawn) |> Enum.map(&elem(&1, 0))
      assert Enum.map(items, &elem(&1, 1)) == expected
    end

    # Round 31: two draws, the line's right end holds the black and white counts.
    test "news/3 with eight players (four columns): the last two draws" do
      g =
        Enum.reduce(1..4, Game.new(seed: {1, 2, 3}, players: 8), fn _, g ->
          {:ok, g} = Game.apply(g, 1, :draw)
          g
        end)

      assert %{items: items} = TileReveal.news(g, 1, nil)
      assert Enum.map(items, &elem(&1, 2)) == [0, 1]
    end

    test "an exploded tile gets the boom class (red stripes and the shake)" do
      {id, view} = duo()
      assert explode(id, 1)
      render(view)
      assert has_element?(view, ~s(#players-row .player-tile.tile-boom[data-seat="1"]))
    end
  end

  describe "type scale (B3)" do
    # A Tailwind size class below the 13 px floor: text-xs (12 px), text-[Npx]
    # with N < 13, or a rem size below 0.8125rem.
    defp below_floor?(class) do
      Regex.match?(~r/(^|[\s:])text-xs(\s|$)/, class) or
        Enum.any?(Regex.scan(~r/text-\[(\d+(?:\.\d+)?)px\]/, class), fn [_, n] ->
          String.to_float(n <> if(n =~ ".", do: "", else: ".0")) < 13
        end)
    end

    defp classes(html) do
      html |> LazyHTML.from_fragment() |> LazyHTML.query("[class]") |> LazyHTML.attribute("class")
    end

    defp brewing_game do
      {id, _view} = duo()
      for _ <- 1..3, do: {:ok, _} = GameServer.apply(id, 1, :draw)
      game(id)
    end

    test "the tokens are defined in app.css" do
      css = File.read!("assets/css/app.css")

      for {name, px} <- [tag: 13, label: 15, num: 18, big: 24],
          do: assert(css =~ "--text-#{name}: #{px}px;")
    end

    test "no class below the floor on a tile; its numbers use the tokens" do
      g = brewing_game()

      html =
        render_component(&QuacksWeb.GameComponents.player_chip/1,
          game: g,
          seat: 1,
          name: "Wilhelmina",
          news: TileReveal.news(g, 1, nil)
        )

      assert [] = Enum.filter(classes(html), &below_floor?/1)
      doc = LazyHTML.from_fragment(html)
      refute Enum.empty?(LazyHTML.query(doc, "[data-role=player-space].text-num"))
      refute Enum.empty?(LazyHTML.query(doc, "[data-role=player-stats].text-tag"))
      refute Enum.empty?(LazyHTML.query(doc, "[data-role=tile-news].text-tag"))
      refute Enum.empty?(LazyHTML.query(doc, "[data-gain=drew] .text-tag"))
    end

    test "no class below the floor in the pot; its SVG numbers are at least 13 px on a phone" do
      g = brewing_game()
      html = render_component(&QuacksWeb.GameComponents.pot/1, game: g, seat: 1)
      assert [] = Enum.filter(classes(html), &below_floor?/1)

      # The pot is at least 328 px wide on a phone: 13 px is 13 * 536 / 328 units.
      floor = 13 * 536 / 328 - 0.1

      sizes =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("text[font-size]")
        |> LazyHTML.attribute("font-size")
        |> Enum.map(&elem(Float.parse(&1), 0))

      assert sizes != []
      assert Enum.all?(sizes, &(&1 >= floor)), inspect(Enum.uniq(sizes))
    end
  end
end
