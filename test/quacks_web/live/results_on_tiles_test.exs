defmodule QuacksWeb.ResultsOnTilesTest do
  @moduledoc """
  The round results played on the player tiles: one update per step, the news on a tile's bottom line, the brewing news, black and white on the tiles and the type scale.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import QuacksWeb.LiveHelpers, except: [text: 2]
  alias Quacks.Game
  alias Quacks.Game.Potions
  alias Quacks.GameServer
  alias QuacksWeb.Reveal
  alias QuacksWeb.TileReveal

  # Two seats brew to the shop: each stops (or answers what it must).
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

  # Round 39: no Results setting; once the browser's settings come, every screen
  # plays the steps on the tiles (an old saved "overlay" changes nothing).
  test "the browser's settings play the steps on the tiles, never in the overlay" do
    {_id, view} = duo_results()
    refute has_element?(view, "#reveal-settings [name=show]")

    render_hook(view, "reveal_settings", %{
      "mode" => "step",
      "speed" => "normal",
      "show" => "overlay"
    })

    refute has_element?(view, "[data-role=reveal]")
    assert has_element?(view, "#tile-stage[data-kind]")
    # The tiles show the running totals while the steps play.
    assert has_element?(view, "[data-role=player-chip] [data-role=player-vp] .tile-count")

    # Next steps through; the last step ends the reveal, the tiles keep the die.
    Enum.find(1..10, fn _ ->
      view |> element("[data-role=tile-next]") |> render_click()
      not has_element?(view, "#tile-stage")
    end)

    refute has_element?(view, "#tile-stage")
    assert has_element?(view, "[data-role=player-chip] [data-role=tile-die] [data-role=die-face]")
  end

  test "Skip ends the steps on the tiles" do
    {_id, view} = duo_results()

    render_hook(view, "reveal_settings", %{
      "mode" => "auto",
      "speed" => "normal",
      "show" => "tiles"
    })

    assert has_element?(view, "#tile-stage")
    refute has_element?(view, "[data-role=tile-next]")
    view |> element("[data-role=tile-skip]") |> render_click()
    refute has_element?(view, "#tile-stage")
  end

  test "badges: a book's ingredient and its rewards; the space's VP and ruby" do
    book = %{
      kind: :book,
      book: :black,
      rows: [
        %{seat: 0, scored: true, vp: 0, rubies: 1, droplet: 1},
        %{seat: 1, scored: false, vp: 0, rubies: 0, droplet: 0}
      ]
    }

    assert TileReveal.badges(book, 0) == [{:book, :black}, {:rubies, 1}, {:droplet, 1}]
    assert TileReveal.badges(book, 1) == []

    space = %{kind: :space, rows: [%{seat: 0, coins: 9, vp: 2, rubies: 1}]}
    assert TileReveal.badges(space, 0) == [{:vp, 2}, {:rubies, 1}]
    assert TileReveal.label(book) == "Black book"

    # Round 37: the standings ("Round scored") moved to the recap after the shop.
    assert TileReveal.slides([%{kind: :die}, %{kind: :results}, %{kind: :standings}]) == [
             %{kind: :die}
           ]
  end

  defp settings(view, extra) do
    render_hook(
      view,
      "reveal_settings",
      Map.merge(%{"mode" => "step", "speed" => "normal"}, extra)
    )
  end

  # Round 39: phones and larger screens alike play the results on the tiles.
  describe "every screen" do
    test "plays the results on the tiles; the menu has no Results choice" do
      for extra <- [%{"show" => "overlay", "phone" => true}, %{"phone" => false}] do
        {_id, view} = duo_results()
        settings(view, extra)

        refute has_element?(view, "[data-role=reveal]")
        assert has_element?(view, "#tile-stage[data-kind]")
        refute has_element?(view, "#reveal-settings [data-role=reveal-show]")
        refute has_element?(view, "#reveal-settings [name=phone]")
      end
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

      # Round 31: `index` names the step Next scores; the news is the scored one's.
      reveal = %{tiles: true, slides: [die, book], index: 0}
      assert TileReveal.news(game, 0, reveal) == nil
      reveal = %{reveal | index: 1}
      assert %{items: [{:die, :ruby}], key: "3-1"} = TileReveal.news(game, 0, reveal)
      assert TileReveal.news(game, 1, reveal) == nil

      assert %{items: [{:book, :black}, {:rubies, 1}, {:droplet, 1}], key: "3-2"} =
               TileReveal.news(game, 0, %{reveal | index: 2})

      shop = %{game | phase: :shopping, log: [{0, {:bought, [{:green, 1}]}}]}
      assert %{items: [{:bought, {:green, 1}}]} = TileReveal.news(shop, 0, nil)

      # The bots buy once the last human is done: the next round shows the last shop.
      next = %{shop | phase: :brewing, round: 4, log: [{:round_end, 3} | shop.log]}

      assert %{items: [{:bought, {:green, 1}}], key: "3-shop-1-0-0"} =
               TileReveal.news(next, 0, nil)

      assert TileReveal.news(%{next | log: [{:round_end, 4} | next.log]}, 0, nil) == nil
    end

    test "Flea Market: the chip traded and the chip got, once chosen and the card is gone" do
      game = Game.new(seed: {1, 2, 3}, players: 2)

      log = [
        {0, {:fortune, :p13, {:upgrade, {:green, 1}}}},
        {0, {:fortune, :p13, {:drew, [{:white, 1}, {:orange, 1}, {:white, 2}, {:green, 1}]}}}
      ]

      game = %{game | fortune_card: :p13, log: log ++ game.log, phase: :potions}
      game = put_in(game.players[0].phase, :potions)

      assert %{items: [{:card, :p13, {:green, 1}, {:green, 2}}]} = TileReveal.news(game, 0, nil)
      assert TileReveal.news(game, 0, %{key: {:card, 1}}) == nil

      html =
        render_component(&QuacksWeb.TileComponents.player_chip/1,
          game: game,
          seat: 0,
          name: "Ann",
          news: TileReveal.news(game, 0, nil)
        )

      assert html =~ ~s(data-gain="card")
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

      render_component(&QuacksWeb.TrackComponents.rat_track/1, game: game, names: %{})
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
        &QuacksWeb.TileComponents.player_chip/1,
        [game: game, seat: 1, name: "Wilhelmina"] ++ opts
      )
      |> LazyHTML.from_fragment()
    end

    defp has?(html, selector), do: not Enum.empty?(LazyHTML.query(html, selector))

    test "no name text: the initial in the disc, the name as title and for screen readers" do
      html = tile(Game.new(seed: {1, 2, 3}, players: 2), bot: true)
      assert html |> LazyHTML.query("[data-role=seat-disc]") |> LazyHTML.text() =~ "W"
      assert has?(html, ~s([data-role=player-chip][title=Wilhelmina]))
      assert has?(html, "[data-role=player-name].sr-only")
      refute has?(html, "[data-role=player-name-text]")
      # VP, rubies, droplet, flask, pot space; the numbers large.
      for role <- ~w(player-vp player-rubies player-droplet player-flask player-space),
          do: assert(has?(html, "[data-role=#{role}]"), role)

      assert has?(html, "[data-role=player-space].text-num")
      assert has?(html, "[data-role=player-vp].text-num")
    end

    # Round 31: out of the brewing (while brewing `tile-black` has the count).
    test "black chips in the pot only with black book I (either black rule)" do
      shop = &%{&1 | phase: :shopping}
      assert has?(tile(shop.(Game.new(seed: {1, 2, 3}, players: 2))), "[data-role=player-black]")

      standings = Game.new(seed: {1, 2, 3}, players: 2, rules: %{black_rule: :standings})
      assert has?(tile(shop.(standings)), "[data-role=player-black]")

      for set <- [2, 3] do
        game =
          Game.new(seed: {1, 2, 3}, players: 2, expansions: [:herb_witches], sets: %{black: set})

        refute has?(tile(shop.(game)), "[data-role=player-black]")
      end
    end

    test "news swaps the bottom line; a new key gives the line a new id" do
      game = Game.new(seed: {1, 2, 3}, players: 2)
      html = tile(game, news: %{key: "1-2", items: [{:vp, 3}]})
      assert has?(html, "#tile-line-1-1-2[data-news] [data-role=tile-news] [data-gain=vp]")
      refute has?(tile(game), "[data-role=tile-line][data-news]")
    end
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
        render_component(&QuacksWeb.TileComponents.player_chip/1,
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

    # Round 31 (Nick): the pot's SVG numbers went back to their round 28 sizes
    # (space 17, VP 12, chip badge 16 units), so only the classes keep the floor.
    test "no class below the floor in the pot" do
      g = brewing_game()
      html = render_component(&QuacksWeb.PotComponents.pot/1, game: g, seat: 1)
      assert [] = Enum.filter(classes(html), &below_floor?/1)
    end
  end

  # Two seats brew far enough that the scoring space pays VP, then the tiles play.
  defp duo_on_tiles do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
    {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    for _ <- 1..4, seat <- [0, 1], do: GameServer.apply(id, seat, :draw)
    to_shop(id)

    render_hook(alice, "reveal_settings", %{
      "mode" => "step",
      "speed" => "normal",
      "show" => "tiles"
    })

    {:ok, %{game: game}} = GameServer.get(id)
    {game, alice}
  end

  defp step_label(view),
    do:
      view
      |> element("[data-role=tile-step]")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> String.trim()

  defp next_until(view, label) do
    Enum.find(1..10, fn _ ->
      step_label(view) == label or
        (view |> element("[data-role=tile-next]") |> render_click() && step_label(view) == label)
    end)
  end

  # Round 35 (item 4): the scoring space is one step again (coins, VP and ruby).
  test "the scoring space is one step with its coins, VP and ruby" do
    space = %{
      kind: :space,
      rows: [
        %{seat: 0, coins: 6, vp: 1, rubies: 1, exploded: false, choice: nil},
        %{seat: 1, coins: 4, vp: 0, rubies: 0, exploded: false, choice: nil}
      ],
      gains: %{0 => {1, 1}, 1 => {0, 0}}
    }

    assert [step] = TileReveal.slides([space])
    assert step.gains == %{0 => {1, 1}, 1 => {0, 0}}
    assert TileReveal.badges(step, 0) == [{:vp, 1}, {:rubies, 1}]
    assert TileReveal.badges(step, 1) == []
    assert TileReveal.label(step) == "Scoring space"
  end

  # Round 35: the step the bar names is the step on show (it is scored).
  test "a tile shows the VP before the space step until Next shows it" do
    {game, view} = duo_on_tiles()
    slides = game |> Reveal.slides(0) |> TileReveal.slides()
    index = Enum.find_index(slides, &(&1.kind == :space))
    assert index && index > 0, "a step before the space step"

    {seat, {gain, _}} =
      Enum.find(slides |> Enum.at(index) |> Map.get(:gains), fn {_s, {v, _}} -> v > 0 end)

    {before, _} = TileReveal.totals(game, slides, index - 1)[seat]

    # The step before the space step is on show: the space is not scored yet.
    next_until(view, slides |> Enum.at(index - 1) |> TileReveal.label())
    assert has_element?(view, "#tile-vp-#{seat}-#{before}")
    refute has_element?(view, "#tile-vp-#{seat}-#{before + gain}")

    # Next shows (and scores) it.
    view |> element("[data-role=tile-next]") |> render_click()
    assert step_label(view) == "Scoring space"
    assert has_element?(view, "#tile-vp-#{seat}-#{before + gain}")
  end

  test "the pot's droplet and the ruby counter follow the steps" do
    {game, view} = duo_on_tiles()
    slides = game |> Reveal.slides(0) |> TileReveal.slides()
    # Nothing is scored before the first Next.
    droplets = TileReveal.droplets(game, slides, -1)
    {_vp, rubies} = TileReveal.totals(game, slides, -1)[0]

    assert has_element?(view, ".pot-lg [data-role=droplet][data-index='#{droplets[0]}']")
    assert view |> element("#stat-rubies .sr-only") |> render() =~ ">#{rubies}<"
  end

  describe "black and white on the tiles" do
    defp tile_2(game, seat \\ 1) do
      render_component(&QuacksWeb.TileComponents.player_chip/1,
        game: game,
        seat: seat,
        name: "Wilhelmina"
      )
      |> LazyHTML.from_fragment()
    end

    defp text(html, selector),
      do: html |> LazyHTML.query(selector) |> LazyHTML.text() |> String.replace(~r/\s+/, " ")

    defp brewing(players) do
      game = Game.new(seed: {1, 2, 3}, players: players)
      %{game | phase: :potions}
    end

    test "while brewing a tile shows the black count and the white sum against the limit" do
      game = brewing(8)
      white = Game.white_sum(game, 1)
      limit = Potions.explode_above(game, 1)
      html = tile_2(game)

      assert text(html, "[data-role=tile-white]") =~ "#{white}/#{limit}"
      assert text(html, "[data-role=tile-black]") =~ "0"
      # The black count moves out of the stats line while it is on the right end.
      assert Enum.empty?(LazyHTML.query(html, "[data-role=player-black]"))
    end

    test "out of the brewing the stats line keeps its black count, no white sum" do
      game = %{brewing(2) | phase: :shopping}
      html = tile_2(game)
      assert Enum.empty?(LazyHTML.query(html, "[data-role=tile-brew]"))
      refute Enum.empty?(LazyHTML.query(html, "[data-role=player-black]"))
    end

    test "the white sum turns amber one point before the limit and red at it" do
      game = brewing(2)
      limit = Potions.explode_above(game, 1)

      level = fn white ->
        drawn = [{{:white, white}, 1}]
        g = update_in(game.players[1], &%{&1 | drawn: drawn})

        g
        |> tile_2()
        |> LazyHTML.query("[data-role=tile-white]")
        |> LazyHTML.attribute("data-level")
      end

      assert level.(limit - 2) == ["safe"]
      assert level.(limit - 1) == ["warn"]
      assert level.(limit) == ["danger"]
    end

    test "with 8 players a tile keeps 2 draws beside the counts" do
      game = brewing(8)
      chips = for v <- [1, 2, 1], do: {{:orange, v}, 1}
      game = update_in(game.players[0], &%{&1 | drawn: chips})
      assert %{items: items} = TileReveal.news(game, 0, nil)
      assert length(items) == 2
    end
  end

  describe "the bar names the step with its picture" do
    defp stage(slides, index, mode \\ :step) do
      render_component(&QuacksWeb.TileRevealComponents.tile_stage/1,
        reveal: %{slides: slides, index: index},
        mode: mode,
        close_label: "To the shop"
      )
      |> LazyHTML.from_fragment()
    end

    defp q(html, sel), do: LazyHTML.query(html, sel)

    test "a book step shows its chip; the die and the space parts their pieces" do
      book = %{kind: :book, book: :purple, rows: []}
      die = %{kind: :die, rows: []}
      vp = %{kind: :space, rows: []}
      slides = [die, book, vp]

      html = stage(slides, 2)

      assert q(html, "[data-role=tile-step-icon] [data-book=purple] [data-chip-icon=purple]")
             |> Enum.count() == 1

      # Round 35: the name shows; "Step 2 of 3" stays small.
      assert q(html, "[data-role=tile-step]") |> LazyHTML.text() =~ "Purple book"
      assert LazyHTML.text(html) =~ "Step 2 of 3"

      assert q(
               stage(slides, 1),
               "[data-role=tile-step-icon] [data-icon=die], [data-role=tile-step-icon] svg"
             )
             |> Enum.count() >= 1

      assert q(stage(slides, 1), "[data-book]") |> Enum.count() == 0
    end

    test "once every step is scored the button closes, also in Auto" do
      slides = [%{kind: :die, rows: []}]
      html = stage(slides, 1, :auto)
      assert q(html, "[data-role=tile-next]") |> LazyHTML.text() =~ "To the shop"
      assert q(html, "[data-role=tile-skip]") |> Enum.count() == 0
    end
  end

  describe "a draw slides the tile's chips" do
    defp drawn(game, n) do
      chips = for v <- 1..n, do: {{:orange, v}, v}
      update_in(game.players[1], &%{&1 | drawn: Enum.reverse(chips)})
    end

    defp line(game) do
      html =
        render_component(&QuacksWeb.TileComponents.player_chip/1,
          game: game,
          seat: 1,
          name: "W",
          news: TileReveal.news(game, 1, nil)
        )
        |> LazyHTML.from_fragment()

      {html |> LazyHTML.query("[data-role=tile-line]") |> LazyHTML.attribute("id"),
       html |> LazyHTML.query(".tile-draw") |> LazyHTML.attribute("id"),
       html |> LazyHTML.query(".tile-draw") |> LazyHTML.attribute("data-age")}
    end

    test "the line keeps its id; the chips get new ids, the newest first" do
      game = %{Game.new(seed: {1, 2, 3}, players: 2) | phase: :potions}
      {line2, chips2, ages2} = line(drawn(game, 2))
      {line3, chips3, ages3} = line(drawn(game, 3))

      assert line2 == line3
      assert ages2 == ["0", "1"]
      assert ages3 == ["0", "1", "2"]
      assert MapSet.disjoint?(MapSet.new(chips2), MapSet.new(chips3))
    end
  end
end
