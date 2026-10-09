defmodule QuacksWeb.Round31EvalTest do
  @moduledoc """
  Round 31 (item 6): the evaluation on the tiles applies one update per step.
  The scoring space plays as three steps (coins, VP, rubies), and a tile, the rat
  track, the pot and the ruby counter show the values before a step until Next.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.{Reveal, TileReveal}

  defp browser(token), do: init_test_session(build_conn(), player_token: token)

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

  test "the scoring space splits into coins, VP and rubies steps, one update each" do
    space = %{
      kind: :space,
      rows: [
        %{seat: 0, coins: 6, vp: 1, rubies: 1, exploded: false, choice: nil},
        %{seat: 1, coins: 4, vp: 0, rubies: 0, exploded: false, choice: nil}
      ],
      gains: %{0 => {1, 1}, 1 => {0, 0}}
    }

    assert [coins, vp, rubies] = TileReveal.slides([space])
    assert {coins.part, vp.part, rubies.part} == {:coins, :vp, :rubies}
    assert coins.gains == %{0 => {0, 0}, 1 => {0, 0}}
    assert vp.gains == %{0 => {1, 0}, 1 => {0, 0}}
    assert rubies.gains == %{0 => {0, 1}, 1 => {0, 0}}
    assert TileReveal.badges(coins, 0) == [{:coins, 6}]
    assert TileReveal.badges(vp, 0) == [{:vp, 1}]
    assert TileReveal.badges(vp, 1) == []
    assert TileReveal.badges(rubies, 0) == [{:rubies, 1}]

    assert Enum.map([coins, vp, rubies], &TileReveal.label/1) == [
             "Coins",
             "Victory points",
             "Rubies"
           ]

    # A part nobody gets has no step.
    none = put_in(space, [:rows, Access.all(), :rubies], 0)
    assert none |> List.wrap() |> TileReveal.slides() |> Enum.map(& &1.part) == [:coins, :vp]
  end

  test "a tile shows the VP before the VP step until Next, then the VP after it" do
    {game, view} = duo_on_tiles()
    slides = game |> Reveal.slides(0) |> TileReveal.slides()
    index = Enum.find_index(slides, &(&1[:part] == :vp))
    assert index && index > 0, "a step before the VP step"

    {seat, {gain, 0}} =
      Enum.find(slides |> Enum.at(index) |> Map.get(:gains), fn {_s, {v, _}} -> v > 0 end)

    {before, _} = TileReveal.totals(game, slides, index - 1)[seat]

    # The bar names the VP step: it is not scored yet.
    next_until(view, "Victory points")
    assert has_element?(view, "#tile-vp-#{seat}-#{before}")
    refute has_element?(view, "#tile-vp-#{seat}-#{before + gain}")
    # The pot plays the scored step's own update only: no VP tag yet.
    refute has_element?(view, "[data-role=vp-float]")
    refute has_element?(view, "#tile-stage [data-role=tile-step-icon] [data-book]")

    # Next scores it.
    view |> element("[data-role=tile-next]") |> render_click()
    refute step_label(view) == "Victory points"
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

  describe "item 8: black and white on the tiles" do
    defp tile(game, seat \\ 1) do
      render_component(&QuacksWeb.GameComponents.player_chip/1,
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
      limit = Quacks.Game.Potions.explode_above(game, 1)
      html = tile(game)

      assert text(html, "[data-role=tile-white]") =~ "#{white}/#{limit}"
      assert text(html, "[data-role=tile-black]") =~ "0"
      # The black count moves out of the stats line while it is on the right end.
      assert Enum.empty?(LazyHTML.query(html, "[data-role=player-black]"))
    end

    test "out of the brewing the stats line keeps its black count, no white sum" do
      game = %{brewing(2) | phase: :shopping}
      html = tile(game)
      assert Enum.empty?(LazyHTML.query(html, "[data-role=tile-brew]"))
      refute Enum.empty?(LazyHTML.query(html, "[data-role=player-black]"))
    end

    test "the white sum turns amber one point before the limit and red at it" do
      game = brewing(2)
      limit = Quacks.Game.Potions.explode_above(game, 1)

      level = fn white ->
        drawn = [{{:white, white}, 1}]
        g = update_in(game.players[1], &%{&1 | drawn: drawn})

        g
        |> tile()
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

  describe "item 4: the bar names the step with its picture" do
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
      vp = %{kind: :space, part: :vp, rows: []}
      slides = [die, book, vp]

      html = stage(slides, 1)

      assert q(html, "[data-role=tile-step-icon] [data-book=purple] [data-chip-icon=purple]")
             |> Enum.count() == 1

      # The name stays for screen readers; "Step 2 of 3" stays small.
      assert q(html, "[data-role=tile-step].sr-only") |> LazyHTML.text() =~ "Purple book"
      assert LazyHTML.text(html) =~ "Step 2 of 3"

      assert q(
               stage(slides, 0),
               "[data-role=tile-step-icon] [data-icon=die], [data-role=tile-step-icon] svg"
             )
             |> Enum.count() >= 1

      assert q(stage(slides, 0), "[data-book]") |> Enum.count() == 0
    end

    test "once every step is scored the button closes, also in Auto" do
      slides = [%{kind: :die, rows: []}]
      html = stage(slides, 1, :auto)
      assert q(html, "[data-role=tile-next]") |> LazyHTML.text() =~ "To the shop"
      assert q(html, "[data-role=tile-skip]") |> Enum.count() == 0
    end
  end
end
