defmodule QuacksWeb.Round35EvalTest do
  @moduledoc """
  Round 35 (eval): the results stage (direction A) in the band above the bar's
  buttons: one row per player for the step on show, the reason and the result
  as icons; the bonus die rolls on its row; the last step is "Round scored".
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.{Reveal, TileReveal}

  defp browser(token), do: init_test_session(build_conn(), player_token: token)

  defp to_phase(id, phases) do
    Enum.find_value(1..160, fn _ ->
      {:ok, %{game: game}} = GameServer.get(id)

      if game.phase in phases do
        game
      else
        seat = Enum.find(game.seats, &(Game.legal_actions(game, &1) -- [:resume] != []))
        actions = Game.legal_actions(game, seat) -- [:resume]
        pick = [:stop, :chip_done, {:explosion_choice, :vp}, :draw]
        {:ok, _} = GameServer.apply(id, seat, Enum.find(pick, hd(actions), &(&1 in actions)))
        nil
      end
    end)
  end

  defp tiles(view, mode \\ "step") do
    render_hook(view, "reveal_settings", %{"mode" => mode, "speed" => "normal", "show" => "tiles"})
  end

  # Two seats brew, then the shop opens and the steps play on the tiles.
  defp duo(opts \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, opts)
    {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
    {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    for _ <- 1..4, seat <- [0, 1], do: GameServer.apply(id, seat, :draw)
    game = to_phase(id, [:shopping])
    tiles(alice)
    {id, game, alice}
  end

  defp next(view), do: view |> element("[data-role=tile-next]") |> render_click()

  describe "item 1: the results stage" do
    test "shows the first step at once, one row per player" do
      {_id, game, view} = duo()
      [first | _] = game |> Reveal.slides(0) |> TileReveal.slides()

      assert has_element?(view, "#results-stage[data-kind=#{first.kind}]")

      for s <- game.seats,
          do: assert(has_element?(view, "#results-stage [data-role=stage-row][data-seat='#{s}']"))

      assert view |> element("[data-role=tile-step]") |> render() =~ TileReveal.label(first)
    end

    test "the last step is Round scored: totals, the leader first with the lead" do
      {_id, game, view} = duo()
      slides = game |> Reveal.slides(0) |> TileReveal.slides()
      assert %{kind: :standings} = List.last(slides)

      for _ <- 2..length(slides)//1, do: next(view)

      assert has_element?(view, "#results-stage[data-kind=standings]")

      assert has_element?(
               view,
               "#results-stage [data-role=stage-row][data-lead] [data-cell=rank]"
             )

      assert has_element?(view, "#results-stage [data-cell=total]")
      leader = Enum.max_by(game.seats, &Game.player(game, &1).vp)

      assert has_element?(
               view,
               "#results-stage [data-role=stage-row][data-seat='#{leader}'][data-lead]"
             )
    end

    test "stage_rows: the space's coins, VP and ruby in one row; no result fades" do
      game = %{seats: [0, 1]}

      space = %{
        kind: :space,
        rows: [
          %{seat: 0, coins: 6, vp: 1, rubies: 1, exploded: false},
          %{seat: 1, coins: 0, vp: 0, rubies: 0, exploded: true}
        ]
      }

      assert [
               %{seat: 0, got: [coins: 6, vp: 1, rubies: 1], none: false},
               %{seat: 1, got: [], why: [{:text, "exploded"}], none: true}
             ] = TileReveal.stage_rows(game, space)
    end

    test "stage_rows: black book I says the black count and whom it beats" do
      game = %{seats: [0, 1, 2]}
      chips = fn n -> List.duplicate({:black, 1}, n) end

      book = %{
        kind: :book,
        book: :black,
        rows: [
          %{
            seat: 0,
            scored: true,
            chips: chips.(2),
            compare: [{1, 1}, {2, 0}],
            vp: 0,
            rubies: 1,
            droplet: 1
          },
          %{
            seat: 1,
            scored: true,
            chips: chips.(1),
            compare: [{2, 0}, {0, 2}],
            vp: 0,
            rubies: 0,
            droplet: 1
          },
          %{
            seat: 2,
            scored: false,
            chips: [],
            compare: [{0, 2}, {1, 1}],
            vp: 0,
            rubies: 0,
            droplet: 0
          }
        ]
      }

      [a, b, c] = TileReveal.stage_rows(game, book)
      assert a.why == [{:count, 2, :black}, {:beats, [1, 2], :both}]
      assert a.got == [rubies: 1, droplet: 1]
      assert b.why == [{:count, 1, :black}, {:beats, [2], :some}]
      assert c.why == [{:count, 0, :black}]
      assert c.none
    end

    test "stage_rows: Round scored shares a place on equal VP" do
      rows = [
        %{seat: 0, rank: 1, from_rank: 0, vp: 5, from_vp: 3},
        %{seat: 1, rank: 0, from_rank: 1, vp: 5, from_vp: 2},
        %{seat: 2, rank: 2, from_rank: 2, vp: 1, from_vp: 1}
      ]

      assert [
               %{seat: 1, why: [rank: 0], got: [gain: 3, total: 5], lead: true},
               %{seat: 0, why: [rank: 0], lead: true},
               %{seat: 2, why: [rank: 2], lead: false}
             ] = TileReveal.stage_rows(%{seats: [0, 1, 2]}, %{kind: :standings, rows: rows})
    end
  end

  describe "item 2: the bonus die rolls on its row" do
    test "each roller's row ends with its dice; the others fade" do
      game = %{seats: [0, 1, 2], players: %{}}

      die = %{
        kind: :die,
        rows: [
          %{seat: 0, rolls: [%{face: {:vp, 2}}]},
          %{seat: 1, rolls: [%{face: :ruby}, %{face: :droplet}]},
          %{seat: 2, rolls: []}
        ]
      }

      game =
        %Game{} |> Map.merge(game) |> Map.put(:players, Map.new(0..2, &{&1, %Quacks.Player{}}))

      [a, b, c] = TileReveal.stage_rows(game, die)
      assert a.got == [{:dice, [{:vp, 2}]}]
      assert b.got == [{:dice, [:ruby, :droplet]}]
      assert c.none

      html =
        render_component(&QuacksWeb.TileRevealComponents.results_stage/1,
          rows: [a, b, c],
          slide: die,
          index: 1,
          names: %{0 => "Ann", 1 => "Bo", 2 => "Cy"}
        )

      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query("[data-seat='1'] [data-cell=dice] .stage-die") |> Enum.count() ==
               2

      assert doc |> LazyHTML.query("[data-seat='2'][data-none]") |> Enum.count() == 1
    end

    test "Auto waits for the dice: the die step lasts longer per roll" do
      die = %{kind: :die, rows: [%{seat: 0, rolls: [%{face: :ruby}, %{face: :ruby}]}]}
      assert TileReveal.duration(:normal, die) > TileReveal.duration(:normal)

      assert TileReveal.duration(:normal, %{kind: :space, rows: []}) ==
               TileReveal.duration(:normal)
    end
  end

  describe "item 8: a chip as a result" do
    test "a chip with no value has its icon in the centre and no badge" do
      html = render_component(&QuacksWeb.GameComponents.chip/1, chip: {:green, nil}, size: :sm)
      doc = LazyHTML.from_fragment(html)
      assert doc |> LazyHTML.query("[data-role=chip-value]") |> Enum.count() == 0
      refute html =~ "-translate-x-"

      with_value =
        render_component(&QuacksWeb.GameComponents.chip/1, chip: {:green, 2}, size: :sm)

      assert with_value =~ "chip-value"
    end
  end
end
