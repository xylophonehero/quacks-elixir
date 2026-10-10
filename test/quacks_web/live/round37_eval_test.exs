defmodule QuacksWeb.Round37EvalTest do
  @moduledoc """
  Round 37 (eval): the results panels share one row grid (aligned columns),
  "Round scored" moves to a recap after the shop (with the shop's results first),
  Take a Chance shows every roll, Flea Market waits for Continue, and the final
  scores stand in columns.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers
  alias QuacksWeb.{Reveal, TileReveal}

  defp browser(token), do: init_test_session(build_conn(), player_token: token)

  defp to_phase(id, phases) do
    Enum.find_value(1..200, fn _ ->
      {:ok, %{game: game}} = GameServer.get(id)

      if game.phase in phases do
        game
      else
        seat = Enum.find(game.seats, &(Game.legal_actions(game, &1) -- [:resume] != []))
        actions = Game.legal_actions(game, seat) -- [:resume]
        pick = [:stop, :chip_done, {:explosion_choice, :vp}, :draw, {:buy, []}, :end_round]
        {:ok, _} = GameServer.apply(id, seat, Enum.find(pick, hd(actions), &(&1 in actions)))
        nil
      end
    end)
  end

  defp tiles(view) do
    render_hook(view, "reveal_settings", %{
      "mode" => "step",
      "speed" => "normal",
      "show" => "tiles"
    })
  end

  defp next(view), do: view |> element("[data-role=tile-next]") |> render_click()

  # Two seats play round 1 to its end (the shop done), so round 2 begins.
  defp round_two do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
    {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
    tiles(alice)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    for _ <- 1..4, seat <- [0, 1], do: GameServer.apply(id, seat, :draw)
    to_phase(id, [:shopping])
    # Alice closes the round's results (on the tiles) and shops.
    if has_element?(alice, "[data-role=tile-skip]"),
      do: alice |> element("[data-role=tile-skip]") |> render_click()

    for seat <- [0, 1] do
      {:ok, _} = GameServer.apply(id, seat, {:buy, [{:orange, 1}]})
      {:ok, %{game: g}} = GameServer.get(id)
      if :end_round in Game.legal_actions(g, seat), do: GameServer.apply(id, seat, :end_round)
    end

    {:ok, %{game: game}} = GameServer.get(id)
    assert game.round == 2
    {id, game, alice}
  end

  describe "items 1-3: one row grid for every panel" do
    test "columns: one per kind of result, in a fixed order" do
      rows = [
        %{seat: 0, why: [], got: [vp: 2, coins: 6], none: false, lead: false},
        %{seat: 1, why: [], got: [rubies: 1], none: false, lead: false},
        %{seat: 2, why: [], got: [:choosing], none: false, lead: false}
      ]

      assert TileReveal.columns(rows) == [:coins, :vp, :rubies]
    end

    test "the scoring space: every row has a cell in each column" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
      {:ok, _} = GameServer.begin(id, "alice-#{id}")
      for _ <- 1..4, seat <- [0, 1], do: GameServer.apply(id, seat, :draw)
      game = to_phase(id, [:shopping])
      tiles(view)
      slides = game |> Reveal.slides(0) |> TileReveal.slides()
      for _ <- 2..length(slides)//1, do: next(view)

      assert has_element?(view, "#results-stage[data-kind=space] ol.stage-grid")
      space = List.last(slides)
      cols = game |> TileReveal.stage_rows(space) |> TileReveal.columns()

      for s <- game.seats, col <- cols do
        assert has_element?(
                 view,
                 "#results-stage [data-role=stage-row][data-seat='#{s}'] [data-role=stage-got][data-col=#{col}]"
               )
      end
    end

    test "Round scored rows know how many places they moved (FLIP)" do
      slide = %{
        kind: :standings,
        rows: [
          %{seat: 0, from_rank: 0, rank: 1, from_vp: 5, vp: 6},
          %{seat: 1, from_rank: 1, rank: 0, from_vp: 4, vp: 9}
        ]
      }

      assert [%{seat: 1, shift: 1, lead: true}, %{seat: 0, shift: -1}] =
               TileReveal.stage_rows(%{seats: [0, 1]}, slide)
    end
  end

  describe "item 4: the recap after the shop" do
    test "recap_slides: the shop, then Round scored of the last round" do
      {_id, game, _view} = round_two()

      assert [%{kind: :shop, round: 1} = shop, %{kind: :standings, round: 1} = standings] =
               Reveal.recap_slides(game)

      assert Enum.all?(shop.rows, &({:orange, 1} in &1.chips))

      for row <- standings.rows,
          do: assert(row.vp == Game.player(game, row.seat).vp)
    end

    test "no recap in round 1, in the shop or at the game's end" do
      game = Game.new(seed: {1, 2, 3}, players: 1, fortune: false)
      assert Reveal.recap_slides(game) == []
      assert Reveal.recap_slides(%{game | round: 3, phase: :shopping}) == []
      assert Reveal.recap_slides(%{game | round: 9, phase: :over}) == []
    end

    test "a shop where nobody bought anything has no step" do
      game = Game.new(seed: {1, 2, 3}, players: 2, fortune: false)
      assert [%{kind: :standings}] = Reveal.recap_slides(%{game | round: 2})
    end

    test "the round begins with the shop step, then Round scored, then the round" do
      {id, _game, view} = round_two()

      assert has_element?(view, "#results-stage[data-kind=shop]")
      assert has_element?(view, "[data-role=tile-step]", "Shop")
      assert has_element?(view, "#results-stage [data-role=stage-row] [data-cell=chips]")

      next(view)
      assert has_element?(view, "#results-stage[data-kind=standings]")
      assert has_element?(view, "#results-stage [data-cell=total]")
      assert has_element?(view, "[data-role=tile-next]", "Next round")

      next(view)
      refute has_element?(view, "#results-stage")
      assert {:ok, %{seen: %{0 => %{recap: 1}}}} = GameServer.get(id)

      # Seen: a reload does not show it again.
      {:ok, again, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
      tiles(again)
      refute has_element?(again, "#results-stage")
    end
  end

  describe "item 5: Take a Chance shows every roll" do
    test "card_reveals: a row per seat with its face and what it gave" do
      game = Game.new(seed: {1, 2, 3}, players: 2, fortune: false)

      game = %{
        game
        | fortune_card: :p12,
          log: [{1, {:fortune, :p12, :ruby}}, {0, {:fortune, :p12, {:vp, 2}}} | game.log]
      }

      assert %{0 => %{die: {:vp, 2}, gains: [{:vp, 2}]}, 1 => %{die: :ruby, gains: [rubies: 1]}} =
               Reveal.card_reveals(game)
    end

    test "after the card, the panel shows each seat's die" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
      {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
      {:ok, _} = GameServer.begin(id, "alice-#{id}")

      GameHelpers.replace_game(id, fn g ->
        %{
          g
          | fortune_card: :p12,
            log: [{1, {:fortune, :p12, :droplet}}, {0, {:fortune, :p12, {:vp, 1}}} | g.log]
        }
      end)

      render_click(view, "card_tap", %{})
      _ = render(view)

      assert has_element?(view, "[data-role=card-stage][data-card=p12] [data-role=reveal-die]")

      for s <- [0, 1],
          do: assert(has_element?(view, "[data-role=card-reveal-row][data-seat='#{s}']"))
    end
  end

  describe "item 10: Flea Market waits after the choice" do
    test "after the trade the card stays with everyone's rows and Continue" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")

      GameHelpers.replace_game(id, fn g ->
        g
        |> GameHelpers.put(0, bag: [{:green, 1}, {:white, 1}, {:orange, 1}, {:red, 1}])
        |> GameHelpers.put(0, drawn: [], pending: [])
        |> GameHelpers.put(fortune_deck: [:p13], round: 2)
        |> Game.start_round()
      end)

      {:ok, %{game: game}} = GameServer.get(id)
      trade = Enum.find(Game.legal_actions(game, 0), &match?({:fortune, {:upgrade, _}}, &1))
      render_click(view, "action", %{"action" => QuacksWeb.GameLive.encode(trade)})
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.player(game, 0).phase == :potions

      assert has_element?(view, "[data-role=card-stage][data-card=p13]")
      assert has_element?(view, "[data-role=card-reveal-row][data-seat='0']")
    end
  end

  describe "item 3: the final scores in columns" do
    test "each part has its column and rows that moved say so" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
      {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
      {:ok, _} = GameServer.begin(id, "alice-#{id}")

      GameHelpers.replace_game(id, fn g ->
        g
        |> GameHelpers.put(0, vp: 30)
        |> GameHelpers.put(1, vp: 31)
        |> Map.put(:phase, :over)
        |> Map.put(:round, 9)
        |> Map.put(:log, [
          {1, {:final_conversion, 10, 2, 2, 1}},
          {0, {:final_conversion, 0, 0, 0, 0}} | g.log
        ])
      end)

      _ = render(view)
      # Seat 1: 28 + 3 = 31 passes seat 0's 30 (round 9 order: 30, 28): it moves up one place.
      assert has_element?(view, "[data-role=final-score][data-seat='1'][data-shift='1']")
      assert has_element?(view, "[data-role=final-score][data-seat='0'][data-shift='-1']")
      assert has_element?(view, "[data-role=final-score] [data-col=coins]")
      assert has_element?(view, "[data-role=final-score] [data-col=rubies]")
    end
  end
end
