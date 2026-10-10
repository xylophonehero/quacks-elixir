defmodule QuacksWeb.Round35EvalTest do
  @moduledoc """
  Round 35 (eval): the results stage (direction A) in the band above the bar's
  buttons: one row per player for the step on show, the reason and the result
  as icons; the bonus die rolls on its row; the last step is "Round scored".
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers
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

    test "round 37: the last step is the scoring space; Round scored waits for the recap" do
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

  describe "item 3: Auto is the default" do
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

      %{reveal: %{tick: ref}} = :sys.get_state(view.pid).socket.assigns
      send(view.pid, {:reveal_tick, ref})
      assert has_element?(view, "#results-stage[data-kind=#{second.kind}]")
    end
  end

  # Round 37: the rubies step follows the last step (the scoring space), since
  # "Round scored" moved to the recap after the shop.
  describe "item 5: rubies at the results' end" do
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
      assert has_element?(view, "#bar-rubies [data-role=rubies-keep]")
      assert has_element?(view, "#results-stage[data-collapsed]")
      refute has_element?(view, "[data-role=stage-row]")
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
      render_click(view, "action", %{"action" => QuacksWeb.GameLive.encode({:buy, []})})
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

  describe "items 6 and 7: each choice on its own book step" do
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
      %{slides: slides, index: index} = :sys.get_state(view.pid).socket.assigns.reveal
      slide = Enum.at(slides, index - 1)
      {slide.kind, slide[:book]}
    end

    defp act(view, action),
      do: render_click(view, "action", %{"action" => QuacksWeb.GameLive.encode(action)})

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
      assert :sys.get_state(view.pid).socket.assigns.reveal.index == 2
      act(view, {:droplet, :pot})

      # Green: only the green book's chips; the purple trade waits for its step.
      until_book(view, :green)
      assert has_element?(view, "#bar-chip-actions-1")
      refute has_element?(view, "#results-stage")
      {:ok, %{game: game}} = GameServer.get(id)
      legal = Game.legal_actions(game, 0)
      greens = Enum.filter(legal, &(TileReveal.choice_colour(&1) == :green))
      assert greens != [] and Enum.any?(legal, &(TileReveal.choice_colour(&1) == :purple))
      refute render(view) =~ QuacksWeb.GameLive.encode({:chip, {:purple_trade, 1}})

      # Done on green moves on to purple (the engine still waits for this seat).
      act(view, :chip_done)

      assert view |> element("#bar-chip-actions-1") |> render() =~
               QuacksWeb.GameLive.encode({:chip, {:purple_trade, 1}})

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

      tick = fn ->
        send(view.pid, {:reveal_tick, :sys.get_state(view.pid).socket.assigns.reveal.tick})
      end

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
      assert %{reveal: %{tiles: true}} = :sys.get_state(view.pid).socket.assigns
    end

    test "live/2: while choosing, a book with a choice has its step, no space yet" do
      {_id, game, _view} = choices_game()

      kinds =
        game |> TileReveal.live(Reveal.result_slides(game)) |> Enum.map(&{&1.kind, &1[:book]})

      assert {:book, :green} in kinds and {:book, :purple} in kinds
      refute Enum.any?(kinds, &(elem(&1, 0) in [:space, :standings]))
      assert TileReveal.choosing(game, :green) == [0]
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
