defmodule QuacksWeb.ResultsStageTest do
  @moduledoc """
  The round results in the results stage over the bar: one row per player per step, the bonus die, Auto, rubies at the end, each choice on its own book step, the recap after the shop and the evaluation in the desktop context column.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.Game
  alias Quacks.GameHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias QuacksWeb.Reveal
  alias QuacksWeb.TileReveal
  alias QuacksWeb.TileRevealComponents

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

  describe "the results stage" do
    test "shows the first step at once, one row per player" do
      {_id, game, view} = duo()
      [first | _] = game |> Reveal.slides(0) |> TileReveal.slides()

      assert has_element?(view, "#results-stage[data-kind=#{first.kind}]")

      for s <- game.seats,
          do: assert(has_element?(view, "#results-stage [data-role=stage-row][data-seat='#{s}']"))

      assert view |> element("[data-role=tile-step]") |> render() =~ TileReveal.label(first)
    end

    test "the last step is the scoring space; Round scored waits for the recap" do
      {_id, game, view} = duo()
      slides = game |> Reveal.slides(0) |> TileReveal.slides()
      refute Enum.any?(slides, &(&1.kind == :standings))
      assert %{kind: :space} = List.last(slides)

      for _ <- 2..length(slides)//1, do: next(view)

      assert has_element?(view, "#results-stage[data-kind=space]")
      refute has_element?(view, "#results-stage[data-kind=standings]")
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

    test "stage_rows: a book's chips show their values only where the book scores by them" do
      game = %{seats: [0]}

      row = %{
        seat: 0,
        scored: true,
        chips: [{:green, 1}, {:green, 4}],
        vp: 0,
        rubies: 1,
        droplet: 0
      }

      [r] = TileReveal.stage_rows(game, %{kind: :book, book: :green, set: 1, rows: [row]})
      assert r.why == [{:stack, :green, [green: nil, green: nil]}]

      for set <- [2, 3, 5] do
        [r] = TileReveal.stage_rows(game, %{kind: :book, book: :green, set: set, rows: [row]})
        assert r.why == [{:stack, :green, [green: 1, green: 4]}]
      end

      purple = %{row | chips: [{:purple, 1}, {:purple, 1}, {:purple, 1}]}
      [r] = TileReveal.stage_rows(game, %{kind: :book, book: :purple, set: 6, rows: [purple]})
      assert r.why == [{:stack, :purple, List.duplicate({:purple, nil}, 3)}]
    end

    test "a stack: the count, then the chips at :sm, overlapping; values only if given" do
      html =
        render_component(&TileRevealComponents.results_stage/1,
          rows: [
            %{
              seat: 0,
              why: [{:stack, :black, [black: nil, black: nil, black: nil]}],
              got: [],
              none: false,
              lead: false
            },
            %{
              seat: 1,
              why: [{:stack, :green, [green: 2, green: 4]}],
              got: [],
              none: false,
              lead: false
            },
            %{seat: 2, why: [{:stack, :black, []}], got: [], none: true, lead: false}
          ],
          slide: %{kind: :book, book: :black, rows: []},
          index: 1,
          names: %{}
        )

      doc = LazyHTML.from_fragment(html)

      count = fn seat ->
        doc |> LazyHTML.query("[data-seat='#{seat}'] [data-role=stack-count]") |> LazyHTML.text()
      end

      chips = fn seat ->
        doc
        |> LazyHTML.query("[data-seat='#{seat}'] [data-role=stack-chip] .chip-token")
        |> Enum.count()
      end

      values = fn seat ->
        doc |> LazyHTML.query("[data-seat='#{seat}'] [data-role=chip-value]") |> Enum.count()
      end

      assert {count.(0), chips.(0), values.(0)} == {"3", 3, 0}
      assert {count.(1), chips.(1), values.(1)} == {"2", 2, 2}
      # No chip: the count 0 and one chip of the colour.
      assert {count.(2), chips.(2)} == {"0", 1}
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
      # Round 44: a stack of the black chips, no values.
      assert a.why == [{:stack, :black, [black: nil, black: nil]}, {:beats, [1, 2], :both}]
      assert a.got == [rubies: 1, droplet: 1]
      assert b.why == [{:stack, :black, [black: nil]}, {:beats, [2], :some}]
      assert c.why == [{:stack, :black, []}]
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

  describe "the bonus die rolls on its row" do
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

  describe "Auto is the default" do
    # The setting lives in this browser (`RevealSettings` in app.js): with nothing
    # saved it sends Auto; Step stays in the settings.
    test "app.js sends Auto when nothing is saved" do
      js = File.read!("assets/js/app.js")
      assert js =~ ~S{saved.mode || "auto"}
      assert js =~ ~S{form.get("mode") || "auto"}
    end

    test "Auto plays the die step, then moves on by itself" do
      {_id, game, view} = duo()
      tiles(view, "auto")
      [first, second | _] = game |> Reveal.slides(0) |> TileReveal.slides()
      assert has_element?(view, "#results-stage[data-kind=#{first.kind}]")
      refute has_element?(view, "[data-role=tile-next]")

      tick_reveal(view)
      assert has_element?(view, "#results-stage[data-kind=#{second.kind}]")
    end
  end

  # Round 37: the rubies step follows the last step (the scoring space), since
  # "Round scored" moved to the recap after the shop.
  describe "rubies at the results' end" do
    defp to_last_step(view, slides) do
      for _ <- 2..length(slides)//1, do: next(view)
      view
    end

    test "Next on the last step asks for the rubies; Keep goes to the shop; no rubies step after the buy" do
      {id, game, view} = duo()
      GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, rubies: 4))
      slides = game |> Reveal.slides(0) |> TileReveal.slides()
      to_last_step(view, slides)
      assert has_element?(view, "#results-stage[data-kind=space]")

      next(view)
      assert has_element?(view, "#bar-rubies [data-role=rubies-keep]", "Skip")
      # Round 47 (audit #5): the bar's own title strip, as in the shop.
      assert has_element?(view, "#bar-rubies [data-role=info-title]", "Spend rubies")
      refute has_element?(view, "#results-stage")
      refute has_element?(view, "#tile-stage")

      # A spend keeps the step while a ruby still buys something.
      view |> element("#bar-rubies [data-ruby=droplet]") |> render_click()
      assert {:ok, %{game: game}} = GameServer.get(id)
      assert Game.player(game, 0).rubies == 2
      assert has_element?(view, "#bar-rubies")

      view |> element("[data-role=rubies-keep]") |> render_click()
      refute has_element?(view, "#results-stage")
      refute has_element?(view, "#bar-rubies")

      # After the buy, no second rubies step: the round ends for this seat.
      render_click(view, "action", %{"action" => QuacksWeb.ActionCode.encode({:buy, []})})
      refute has_element?(view, "#bar-rubies")
      {:ok, %{game: game}} = GameServer.get(id)
      assert game.round == 2 or Game.player(game, 0).phase == :ready
    end

    test "the last ruby spent ends the results by itself" do
      {id, game, view} = duo()
      GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, rubies: 2))
      slides = game |> Reveal.slides(0) |> TileReveal.slides()
      to_last_step(view, slides)
      next(view)

      view |> element("#bar-rubies [data-ruby=droplet]") |> render_click()
      refute has_element?(view, "#results-stage")
      refute has_element?(view, "#bar-rubies")
    end

    test "no ruby to spend: Next on the last step ends the results" do
      {id, game, view} = duo()
      GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, rubies: 1))
      slides = game |> Reveal.slides(0) |> TileReveal.slides()
      to_last_step(view, slides)
      next(view)
      refute has_element?(view, "#results-stage")
      refute has_element?(view, "#bar-rubies")
    end
  end

  describe "each choice on its own book step" do
    # Seat 0 ends on a green 2 and a purple 1 (G2 and P2: choices) with one black
    # chip more than seat 1 (the Hawkmoth: a free droplet move, reverse pot side).
    defp choices_game(settings_first \\ true) do
      sets = %{green: 2, purple: 2}
      {:ok, id} = GameServer.start(2, {1, 2, 3}, sets, %{fortune: false, pot_side: :back})
      {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
      {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
      {:ok, _} = GameServer.begin(id, "alice-#{id}")
      if settings_first, do: tiles(alice)

      GameHelpers.replace_game(id, fn g ->
        g
        |> GameHelpers.put(0,
          drawn: [{{:green, 2}, 12}, {{:purple, 1}, 11}, {{:black, 1}, 10}],
          pot_index: 12
        )
        |> GameHelpers.put(1, drawn: [{{:orange, 1}, 5}], pot_index: 5)
      end)

      {:ok, _} = GameServer.apply(id, 1, :stop)
      {:ok, game} = GameServer.apply(id, 0, :stop)
      render(alice)
      if !settings_first, do: tiles(alice, "auto")
      {id, game, alice}
    end

    # The step on show (the panel hides while a choice waits on it).
    defp shown(view) do
      %{kind: kind, book: book} = reveal_state(view)
      {kind, book}
    end

    defp act(view, action),
      do: render_click(view, "action", %{"action" => QuacksWeb.ActionCode.encode(action)})

    # Next until the step with this kind (and book) shows; a free droplet move on
    # the way goes to the pot.
    defp until_book(view, colour) do
      Enum.find(1..8, fn _ ->
        cond do
          shown(view) == {:book, colour} -> true
          has_element?(view, "#bar-droplet") -> act(view, {:droplet, :pot}) && false
          true -> next(view) && false
        end
      end)
    end

    test "the steps begin with the choices; the droplet, green and purple each on their step" do
      {id, game, view} = choices_game()
      assert game.phase == :chip_choice
      assert has_element?(view, "#results-stage")
      refute has_element?(view, "#results-stage[data-kind=space]")

      # The die first; the Hawkmoth's droplet move on the black step (the panel
      # hides, so the pot and the test tubes show).
      assert has_element?(view, "#results-stage[data-kind=die]")
      refute has_element?(view, "#bar-droplet")
      next(view)
      assert has_element?(view, "#bar-droplet")
      refute has_element?(view, "#results-stage")
      assert reveal_state(view).index == 2
      act(view, {:droplet, :pot})

      # Green: only the green book's chips; the purple trade waits for its step.
      until_book(view, :green)
      assert has_element?(view, "#bar-chip-actions-1")
      refute has_element?(view, "#results-stage")
      {:ok, %{game: game}} = GameServer.get(id)
      legal = Game.legal_actions(game, 0)
      greens = Enum.filter(legal, &(TileReveal.choice_colour(&1) == :green))
      assert greens != [] and Enum.any?(legal, &(TileReveal.choice_colour(&1) == :purple))
      refute render(view) =~ QuacksWeb.ActionCode.encode({:chip, {:purple_trade, 1}})

      # Done on green moves on to purple (the engine still waits for this seat).
      act(view, :chip_done)

      assert view |> element("#bar-chip-actions-1") |> render() =~
               QuacksWeb.ActionCode.encode({:chip, {:purple_trade, 1}})

      assert {:ok, %{game: %{phase: :chip_choice}}} = GameServer.get(id)

      # The purple choice ends the choices: the shop opens, the scoring space follows.
      act(view, {:chip, {:purple_trade, 1}})
      {:ok, %{game: game}} = GameServer.get(id)
      assert game.phase == :shopping
      next(view)
      assert has_element?(view, "#results-stage[data-kind=space]")
    end

    test "the settings coming after the choices began still start the steps" do
      {_id, _game, view} = choices_game(false)
      assert has_element?(view, "#results-stage[data-kind=die]")
    end

    test "Auto never closes the steps while this seat's choice waits on the last one" do
      {_id, _game, view} = choices_game(false)

      tick = fn -> tick_reveal(view) end

      # The die, then the black step's droplet move, then "Done" on green: purple is
      # the last step while the choices wait.
      tick.()
      act(view, {:droplet, :pot})
      tick.()
      assert shown(view) == {:book, :green}
      act(view, :chip_done)
      assert shown(view) == {:book, :purple}

      for _ <- 1..3 do
        tick.()
        render(view)
      end

      assert has_element?(view, "#bar-chip-actions-1")
      assert %{tiles: true} = reveal_state(view)
    end

    test "live/2: while choosing, a book with a choice has its step, no space yet" do
      {_id, game, _view} = choices_game()

      kinds =
        game |> TileReveal.live(Reveal.result_slides(game)) |> Enum.map(&{&1.kind, &1[:book]})

      assert {:book, :green} in kinds and {:book, :purple} in kinds
      refute Enum.any?(kinds, &(elem(&1, 0) in [:space, :standings]))
      assert TileReveal.choosing(game, :green) == [0]
    end

    test "a green II step that waits shows the choosing seat's greens with their values" do
      {_id, game, _view} = choices_game()
      slides = TileReveal.live(game, Reveal.result_slides(game))
      green = Enum.find(slides, &(&1[:book] == :green))

      [row | _] = TileReveal.stage_rows(game, green, TileReveal.choosing(game, :green))
      assert row.seat == 0
      assert row.why == [{:stack, :green, [green: 2]}]
      assert row.got == [:choosing]
    end
  end

  describe "a die face on a tile" do
    test "waits for its die: each face has its roll's place (app.css `.tile-news-die`)" do
      html =
        render_component(&TileRevealComponents.tile_news/1,
          items: [{:die, {:vp, 1}}, {:die, :droplet}]
        )

      doc = LazyHTML.from_fragment(html)
      dice = LazyHTML.query(doc, ".tile-news-die")
      assert Enum.count(dice) == 2
      assert html =~ "--roll: 0" and html =~ "--roll: 1"
    end
  end

  describe "a chip as a result" do
    test "a chip with no value has its icon in the centre and no badge" do
      html = render_component(&QuacksWeb.ChipComponents.chip/1, chip: {:green, nil}, size: :sm)
      doc = LazyHTML.from_fragment(html)
      assert doc |> LazyHTML.query("[data-role=chip-value]") |> Enum.count() == 0
      refute html =~ "-translate-x-"

      with_value =
        render_component(&QuacksWeb.ChipComponents.chip/1, chip: {:green, 2}, size: :sm)

      assert with_value =~ "chip-value"
    end
  end

  defp to_phase_2(id, phases) do
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

  defp tiles_2(view) do
    render_hook(view, "reveal_settings", %{
      "mode" => "step",
      "speed" => "normal",
      "show" => "tiles"
    })
  end

  # Two seats play round 1 to its end (the shop done), so round 2 begins.
  defp round_two do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
    {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
    tiles_2(alice)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    for _ <- 1..4, seat <- [0, 1], do: GameServer.apply(id, seat, :draw)
    to_phase_2(id, [:shopping])
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

  describe "one row grid for every panel" do
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
      game = to_phase_2(id, [:shopping])
      tiles_2(view)
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

  describe "the recap after the shop" do
    test "recap_slides: the shop, then Round scored of the last round" do
      {_id, game, _view} = round_two()

      assert [%{kind: :shop, round: 1} = shop, %{kind: :standings, round: 1} = standings] =
               Reveal.recap_slides(game)

      assert Enum.all?(shop.rows, &({:orange, 1} in &1.chips))

      for row <- standings.rows,
          do: assert(row.vp == Game.player(game, row.seat).vp)
    end

    test "the shop step shows droplet and flask refills (thpxis crash)" do
      slide = %{kind: :shop, rows: [%{seat: 0, chips: [], droplets: 1, flasks: 1}]}
      rows = TileReveal.stage_rows(%{seats: [0]}, slide, nil)

      html =
        render_component(&QuacksWeb.TileRevealComponents.results_stage/1,
          rows: rows,
          slide: slide,
          index: 0,
          names: %{0 => "Nick"}
        )

      assert html =~ ~s(data-cell="flask")
      assert html =~ ~s(data-cell="droplet")
    end

    test "the shop step: the chips bought at :sm, with icon and value" do
      slide = %{kind: :shop, rows: [%{seat: 0, chips: [{:blue, 2}, {:orange, 1}], droplets: 0}]}
      rows = TileReveal.stage_rows(%{seats: [0]}, slide, nil)

      html =
        render_component(&QuacksWeb.TileRevealComponents.results_stage/1,
          rows: rows,
          slide: slide,
          index: 0,
          names: %{0 => "Nick"}
        )

      doc = LazyHTML.from_fragment(html)
      chips = LazyHTML.query(doc, "[data-cell=chips] .chip-token")
      assert Enum.count(chips) == 2

      assert doc |> LazyHTML.query("[data-cell=chips] [data-role=chip-value]") |> Enum.count() ==
               2
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
      # Round 47 (audit #5): the last step says Next too.
      assert has_element?(view, "[data-role=tile-next]", "Next")

      next(view)
      refute has_element?(view, "#results-stage")
      assert {:ok, %{seen: %{0 => %{recap: 1}}}} = GameServer.get(id)

      # Seen: a reload does not show it again.
      {:ok, again, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
      tiles_2(again)
      refute has_element?(again, "#results-stage")
    end
  end

  describe "Take a Chance shows every roll" do
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

    test "the pumpkin gained is an :sm chip (its icon); the result waits for the die" do
      row = %{die: :orange, gains: [{:chip, {:orange, 1}}], drew: [], number: nil}
      row = Map.merge(row, %{best?: false, choosing?: false})

      html =
        render_component(&QuacksWeb.CardRevealComponents.card_stage/1,
          id: "card-stage",
          card: :p12,
          reveals: %{0 => row},
          order: [0],
          seat: 0,
          names: %{0 => "Nick"}
        )

      doc = LazyHTML.from_fragment(html)
      gain = LazyHTML.query(doc, "[data-role=reveal-result] [data-gain=chip]")
      assert gain |> LazyHTML.query(".chip-token[data-chip-icon=orange]") |> Enum.count() == 1
      # app.css: `.stage-row:has(.stage-die) .stage-got` waits for `--die-roll`.
      assert doc |> LazyHTML.query(".stage-row .stage-die") |> Enum.count() == 1
      assert doc |> LazyHTML.query(".stage-row .stage-got") |> Enum.count() == 1
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

  describe "Flea Market waits after the choice" do
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

      skip_results(view)

      {:ok, %{game: game}} = GameServer.get(id)
      trade = Enum.find(Game.legal_actions(game, 0), &match?({:fortune, {:upgrade, _}}, &1))
      render_click(view, "action", %{"action" => QuacksWeb.ActionCode.encode(trade)})
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.player(game, 0).phase == :potions

      assert has_element?(view, "[data-role=card-stage][data-card=p13]")
      assert has_element?(view, "[data-role=card-reveal-row][data-seat='0']")
    end
  end

  describe "the final scores in columns" do
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

  defp herb_solo do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
    {:ok, view, _html} = live(browser("r39-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  # A solo game in the shop phase of round 1: the results wait to play.
  defp solo_results do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("r39-solo-#{System.unique_integer()}"), ~p"/g/#{id}")

    replace_game(id, fn g ->
      g = put_in(g.players[0].drawn, [{{:green, 1}, 12}, {{:purple, 1}, 11}])
      g = %{g | log: [{0, {:purple, 1, :vp}}, {0, {:green_rubies, 1}}, {:round_end, 0}]}
      H.put(g, 0, phase: :shop, coins: 10)
    end)

    {id, view}
  end

  # A desktop browser's settings (no phone flag since round 39).
  defp desktop(view),
    do: render_hook(view, "reveal_settings", %{"mode" => "step", "speed" => "normal"})

  describe "the evaluation in the context column" do
    test "a desktop browser plays the steps in the results stage over the bar, no overlay" do
      {_id, view} = solo_results()
      desktop(view)

      refute has_element?(view, "[data-role=reveal]")
      refute has_element?(view, "dialog[id^=reveal-]")
      assert has_element?(view, "footer[data-area=bar] #results-stage")
      assert has_element?(view, "footer[data-area=bar] #tile-stage [data-role=tile-skip]")
      assert has_element?(view, "footer[data-area=bar] #tile-stage [data-role=tile-next]")

      # Next steps through to the shop panel in the context column.
      Enum.find(1..10, fn _ ->
        view |> element("[data-role=tile-next]") |> render_click()
        not has_element?(view, "#tile-stage")
      end)

      refute has_element?(view, "#results-stage")
      assert has_element?(view, "[data-role=side-column] dialog#decision-shop[data-side=panel]")
    end

    test "the menu has no Results choice any more" do
      {_id, view} = solo_results()
      refute has_element?(view, "#reveal-settings [name=show]")
      refute has_element?(view, "#reveal-settings [name=phone]")
      refute has_element?(view, "#reveal-settings", "Overlay")
    end
  end

  describe "no results panel next to the stage" do
    test "the context column has no evaluation list while the steps play" do
      {_id, view} = solo_results()
      desktop(view)

      assert has_element?(view, "#results-stage")
      refute has_element?(view, "[data-role=results-panel]")
      refute has_element?(view, "[data-role=result-row]")
    end
  end

  describe "the left column" do
    test "the books and the witches are folded blocks, closed by default" do
      {_id, view} = herb_solo()

      assert has_element?(view, "#left-column.hidden.xl\\:flex[data-area=books]")
      assert has_element?(view, "#left-column > details#books-column:not([open])")
      assert has_element?(view, "#left-column > details#witches-column:not([open])")

      assert has_element?(
               view,
               "#witches-column > summary[data-role=fold-title]",
               "Herb witches"
             )

      # The page keeps a fold open across patches.
      assert has_element?(view, ~s(#witches-column[phx-mounted*="ignore_attrs"]))
      assert has_element?(view, ~s(#books-column[phx-mounted*="ignore_attrs"]))

      for witch <- ~w(s2 c4 g4),
          do: assert(has_element?(view, "#witches-column [data-witch=#{witch}]"))
    end

    test "a witch is called from the left column; the title counts the calls" do
      {_id, view} = herb_solo()

      assert has_element?(view, "#witches-column [data-role=witches-callable]", "1 to call")

      view |> element("#witches-column [data-witch=s2] button", "Call") |> render_click()

      assert has_element?(
               view,
               "#bar-pick-witch_offer [data-role=info-row]",
               "The silver witch drew:"
             )

      refute has_element?(view, "#witches-column [data-role=witches-callable]")
    end

    test "from 80rem the context column's witches sheet hides (app.css)" do
      {_id, view} = herb_solo()
      assert has_element?(view, "[data-role=side-column] > #sheet-witches.sheet-left-xl")
      # 64-80rem: the title is light on the dark column.
      assert has_element?(view, "#sheet-witches [data-role=witches-title].lg\\:text-parchment")

      css = File.read!("assets/css/app.css")
      assert css =~ ~s([data-role="side-column"] > .sheet-inline-lg.sheet-left-xl)
    end

    test "no herb witches: no witches fold" do
      {_id, view} = solo_results()
      assert has_element?(view, "#left-column > #books-column")
      refute has_element?(view, "#witches-column")
    end
  end

  describe "one list of a card's results" do
    test "Take a Chance has no old list of rolls in the context column" do
      {id, view} = herb_solo()

      replace_game(id, fn g ->
        %{g | fortune_card: :p12, log: [{0, {:fortune, :p12, {:vp, 2}}} | g.log]}
      end)

      refute has_element?(view, "[data-role=chance-panel]")
      css = File.read!("assets/css/app.css")
      refute css =~ ".chance-row"
      refute css =~ ".results-panel"
    end
  end
end
