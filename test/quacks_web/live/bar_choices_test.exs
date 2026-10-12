defmodule QuacksWeb.BarChoicesTest do
  @moduledoc """
  The choices in the bar: the crow skull's chips, a white pick over the limit, the toadstools beside the pot, the shop always buys, Choices Choices as a chip row, chip choices as chips, Ghost's breath V in a sheet, Mandrake, pot chips as targets and an everyone-card's results.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.Game
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias QuacksWeb.BarComponents

  defp solo(rules) do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, Map.merge(%{fortune: false}, rules))
    {:ok, view, _html} = live(browser("r35-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  describe "the crow skull in the bottom row" do
    # Round 40: the info row takes the white track's place on phones; from 64rem
    # the bar keeps the white track and Stop / Draw (`crow_skull_choice_test.exs`).
    test "the drawn chips and Skip in one row" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))

      row = "footer section[data-role=bar-blue][phx-hook$='FromBag'][phx-remove]"
      assert has_element?(view, "#{row} button[data-pool-chip] .chip-token")
      assert has_element?(view, "#{row} [data-role=blue-skip]", "Skip")
      assert has_element?(view, "#{row} [data-role=info-row]")
      assert has_element?(view, "[data-role=fuse-row].max-lg\\:hidden")
      assert has_element?(view, "[data-role=action-bar].max-lg\\:hidden")
    end

    test "a tap places the chip; Skip returns them all" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))

      view |> element("[data-role=bar-blue] button[aria-label*='red 1']") |> render_click()
      refute has_element?(view, "[data-role=bar-blue]")
      assert has_element?(view, "[data-role=action-bar]")

      replace_game(id, &H.put(&1, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))
      view |> element("[data-role=blue-skip]") |> render_click()
      refute has_element?(view, "[data-role=bar-blue]")
    end
  end

  describe "the toadstools beside the pot" do
    test "stack in a column" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, aside: [{:red, 1}, {:red, 2}]))

      assert has_element?(view, "[data-role=beside-pot].flex-col [data-role=aside-chip]")
      refute has_element?(view, "[data-role=beside-pot].-space-x-1\\.5")
    end
  end

  describe "the shop's book text scrolls into view" do
    test "the info button asks the sheet to show the opened text" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, phase: :shop, coins: 10))

      assert has_element?(
               view,
               "#decision-shop [data-role=book-info][phx-click*='quacks:reveal'][phx-click*='#shop-book-0']"
             )
    end
  end

  describe "the shop always buys" do
    test "no Skip: Buy is the one button, disabled until a chip is ticked" do
      {id, view} = solo(%{})
      replace_game(id, &H.put(&1, phase: :shop, coins: 10))

      refute has_element?(view, "#decision-shop [data-role=shop-done]")
      refute has_element?(view, "#decision-shop button", "Skip")
      assert has_element?(view, "#decision-shop [data-role=shop-buy]:disabled")
    end

    test "too few coins for any chip: only then Nothing to buy" do
      # The page skips the buy step when nothing is affordable (unless a copper
      # witch acts there), so the shop itself is checked here.
      {id, _view} = solo(%{})
      game = replace_game(id, &H.put(&1, phase: :shop, coins: 2))
      html = render_component(&QuacksWeb.ShopComponents.shop/1, game: game, seat: 0, selected: [])
      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query("[data-role=shop-done]") |> LazyHTML.text() =~ "Nothing to buy"
      assert doc |> LazyHTML.query("[data-role=shop-buy]") |> Enum.empty?()
    end
  end

  describe "Choices, Choices as a chip row" do
    test "the black chip, the 2-chips and a ruby with 3, in the bottom row only" do
      {id, view} = solo(%{})

      replace_game(id, fn g ->
        %{g | phase: :fortune_choice, fortune_card: :p1} |> H.put(0, phase: :fortune_choice)
      end)

      row = "footer section[data-role=bar-card][data-card=p1]"
      assert has_element?(view, "#{row} button[data-choice=take] [aria-label='black 1']")
      assert has_element?(view, "#{row} button[data-choice=take] [aria-label='red 2']")
      assert has_element?(view, "#{row} button [data-role=ruby-count]", "3")
      refute has_element?(view, "#{row} [data-role=info-row]")
      refute has_element?(view, "#{row} [data-role=choice-grid]")

      view |> element("#{row} button[data-choice=rubies]") |> render_click()
      refute has_element?(view, row)
      {:ok, %{game: game}} = GameServer.get(id)
      assert game.players[0].rubies == 4
    end
  end

  describe "what everyone took after an everyone-card" do
    defp p1(g),
      do:
        %{g | phase: :fortune_choice, fortune_card: :p1}
        |> Map.update!(
          :players,
          &Map.new(&1, fn {s, p} -> {s, %{p | phase: :fortune_choice}} end)
        )

    test "solo: after the choice the card grows with the row; Continue shrinks it" do
      {id, view} = solo(%{})
      replace_game(id, &p1/1)
      refute has_element?(view, "[data-role=card-stage]")

      view |> element("[data-card=p1] button[data-choice=rubies]") |> render_click()

      # Round 36: the rows are in the results stage, not under the card.
      row = "[data-role=card-stage][data-card=p1] [data-role=card-reveal-row]"

      assert has_element?(view, "#{row}[data-me=true] [data-role=seat-disc]")
      assert has_element?(view, "#{row} [data-gain=rubies]", "+3")
      assert has_element?(view, "#card-continue")

      view |> element("#card-continue") |> render_click()
      refute has_element?(view, "[data-role=card-stage]")
    end

    test "two players: the one who chose sees the other still choosing, then the take" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, alice, _} = live(browser("r35-alice-#{id}"), ~p"/g/#{id}")
      {:ok, bob, _} = live(browser("r35-bob-#{id}"), ~p"/g/#{id}")
      alice |> element("button", "Start game") |> render_click()
      replace_game(id, &p1/1)

      alice |> element("[data-card=p1] button[data-choice=rubies]") |> render_click()
      rows = "[data-role=card-stage] [data-role=card-reveal-row]"
      assert has_element?(alice, "#{rows}[data-seat='1']", "choosing")

      bob |> element("[data-card=p1] button[aria-label*='black 1']") |> render_click()
      assert has_element?(alice, "#{rows}[data-seat='1'] [data-gain=chip] [aria-label='black 1']")
      assert has_element?(bob, "#{rows}[data-seat='0'] [data-gain=rubies]", "+3")
    end
  end

  doctest QuacksWeb.TileComponents, import: true, only: [loop_start: 3]

  defp solo_2(sets \\ %{}, expansion \\ nil) do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, sets, %{fortune: false}, expansion)
    {:ok, view, _html} = live(browser("r36-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  # A table of `players` seats: this browser and bots, started.
  defp table(players) do
    {:ok, id} = GameServer.start(players, {1, 2, 3})
    token = "r36-#{System.unique_integer()}"
    {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
    for _ <- 2..players, do: {:ok, _seat} = GameServer.add_bot(id, token)
    view |> element("button", "Start game") |> render_click()
    {id, view}
  end

  describe "the short second tile row is centred" do
    test "5 seats: 6 half columns, row 2 starts half a column in" do
      {_id, view} = table(5)

      assert has_element?(view, "#players-row[style*='repeat(6,']")

      assert has_element?(
               view,
               "[data-role=player-chip][data-seat='0'][style*='grid-column: 1 / span 2']"
             )

      assert has_element?(
               view,
               "[data-role=player-chip][data-seat='3'][style*='grid-column: 4 / span 2']"
             )

      assert has_element?(
               view,
               "[data-role=player-chip][data-seat='4'][style*='grid-column: 2 / span 2']"
             )
    end

    test "6 seats: row 2 fills the row" do
      {_id, view} = table(6)

      assert has_element?(
               view,
               "[data-role=player-chip][data-seat='5'][style*='grid-column: 1 / span 2']"
             )
    end
  end

  describe "the scoring space pulses when the chip lands" do
    # Round 37 replaced the pulse with the old ring's shrink and the new ring's
    # growth (`QuacksWeb.Round37BoardTest`).

    test "the pot marks its scoring space and this seat's ring" do
      {_id, view} = solo_2()
      view |> element("[data-role=action-bar] button", "Draw") |> render_click()

      assert has_element?(view, "#pot-0-lg [data-role=next-space]")
      assert has_element?(view, "#pot-0-lg [data-role=scoring-ring][data-seat='0']")
    end
  end

  describe "Mandrake V's peeked chip over the bag" do
    defp log(g, entries), do: %{g | log: Enum.reverse(entries) ++ g.log}

    test "the peeked chip shows over the bag until the next draw" do
      {id, view} = solo_2(%{yellow: 5}, :herb_witches)
      refute has_element?(view, "[data-role=peek-chip]")

      replace_game(id, fn g ->
        g
        |> H.put(drawn: [{{:yellow, 1}, 3}], pot_index: 3)
        |> log([
          {0, {:drew, {:yellow, 1}, 1}},
          {0, {:effect, {:yellow, 5}, {:peek, {:green, 2}}}}
        ])
      end)

      assert has_element?(view, "[data-role=pot-area] [data-role=peek-chip][data-chip='green 2']")
      assert has_element?(view, "[data-role=peek-chip].peek-rise .chip-token")

      replace_game(id, &log(&1, [{0, {:drew, {:orange, 1}, 4}}]))
      refute has_element?(view, "[data-role=peek-chip]")

      # A new round: last round's peek is gone before the first draw.
      replace_game(
        id,
        &log(&1, [{0, {:effect, {:yellow, 5}, {:peek, {:red, 1}}}}, {:round_end, 1}])
      )

      refute has_element?(view, "[data-role=peek-chip]")
    end

    test "rises out of the bag; reduced motion: a fade" do
      css = File.read!("assets/css/app.css")
      assert css =~ "@keyframes peek-rise"
      assert css =~ ~r/no-preference\) \{\n  \.peek-rise \{\n    animation: peek-rise/
    end
  end

  # Step B's chip choices of `sets` on the pot `drawn` (an explosion that took the coins).
  defp chip_choice(sets, drawn, expansion \\ nil) do
    {id, view} = solo_2(%{}, expansion)

    replace_game(id, fn g ->
      %{g | sets: Map.merge(g.sets, sets)}
      |> H.put(phase: :explosion_choice, exploded?: true, drawn: drawn, pot_index: 40)
      |> H.apply!({:explosion_choice, :buy})
    end)

    {id, play_until(view, "[data-role=bar-chip-actions]")}
  end

  defp logged?(id, pattern) do
    {:ok, %{game: game}} = GameServer.get(id)
    Enum.any?(game.log, pattern)
  end

  describe "chip choices are chips to tap" do
    test "Garden spider II: the chips, then Done, no chip buttons with text" do
      {id, view} = chip_choice(%{green: 2}, [{{:green, 2}, 10}])
      bar = "[data-role=bar-chip-actions] [data-role=chip-row]"

      assert has_element?(
               view,
               "#{bar} button[data-role=chip-option][data-chip='blue 1'] .chip-token"
             )

      assert has_element?(view, "#{bar} button[data-role=chip-option][data-chip='red 1']")
      assert has_element?(view, "#{bar} button[data-role=chip-action]", "Done")

      view |> element("#{bar} [data-chip='red 1']") |> render_click()
      assert logged?(id, &match?({0, {:chip, {:gain, {:red, 1}}}}, &1))
    end

    test "a card's upgrade shows the chip it becomes on the chip's edge" do
      {id, view} = solo_2()

      replace_game(id, fn g ->
        g
        |> H.put(fortune_card: :p13, phase: :fortune_choice, pending: [{:green, 1}])
        |> Map.put(:phase, :fortune_choice)
      end)

      option = "[data-role=bar-card] [data-role=chip-option][data-choice=upgrade]"
      assert has_element?(view, "#{option}[data-chip='green 1'] [data-role=chip-option-to]")
      assert has_element?(view, "[data-role=bar-card] [data-choice=skip]")
    end

    test "the silver witch's chips are chips to tap, Return the rest a button" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
      {:ok, view, _html} = live(browser("r36-s2-#{id}"), ~p"/g/#{id}")
      view |> element("#sheet-witches [data-witch=s2] button", "Call") |> render_click()

      row = "#bar-pick-witch_offer [data-role=chip-row]"
      assert has_element?(view, "#{row} button[data-role=chip-option] .chip-token")
      assert has_element?(view, "#{row} [data-role=pick-action]", "Return the rest")
    end
  end

  describe "Ghost's breath V in a sheet like the shop" do
    test "the buys are tiles to tick; Take sends the ticked buy" do
      {id, view} =
        chip_choice(%{purple: 5}, [{{:purple, 1}, 40}, {{:purple, 1}, 30}], :herb_witches)

      # Round 39: a panel in the context area; Take is in the bar.
      panel = "#purple-buy-panel-1[data-role=purple-buy]"
      assert has_element?(view, "#{panel} input[type=checkbox]")
      take = "[data-role=bar-chip-actions] [data-role=purple-buy-take]"
      assert has_element?(view, "#{take}:disabled")
      assert has_element?(view, "[data-role=bar-chip-actions] [data-role=chip-action]", "Done")

      view
      |> element("#purple-buy-1")
      |> render_change(%{"chips" => [QuacksWeb.ActionCode.encode({:green, 1})]})

      view |> element(take) |> render_click()
      assert logged?(id, &match?({0, {:chip, {:buy, [{:green, 1}]}}}, &1))
    end
  end

  describe "a choice about pot chips is a tap on the chip in the pot" do
    test "Ghost's breath IV, one swap: the green chip glows, a tap swaps it" do
      {id, view} = chip_choice(%{purple: 4}, [{{:purple, 1}, 10}, {{:green, 1}, 8}])

      target = "#pot-0-lg [data-role=pot-chip].pot-target[data-target]"
      assert has_element?(view, "#{target} [data-role=target-glow]")
      refute has_element?(view, "#pot-0-lg [data-index='10'][data-target]")
      assert has_element?(view, "[data-role=bar-chip-actions] [data-role=tap-pot]")

      view |> element(target) |> render_click()
      assert logged?(id, &match?({0, {:chip, {:upgrade, {:green, 1}, {:green, 2}}}}, &1))
    end

    test "Ghost's breath IV, two swaps: the tap shows them in the bar, Back closes" do
      purples = for i <- 10..12, do: {{:purple, 1}, i}
      {id, view} = chip_choice(%{purple: 4}, purples ++ [{{:green, 1}, 8}])

      view |> element("#pot-0-lg [data-target][phx-click=pot_pick]") |> render_click()
      row = "[data-role=bar-chip-actions] [data-role=chip-row]"
      assert has_element?(view, "#{row} [data-role=chip-option][data-chip='green 2']")
      assert has_element?(view, "#{row} [data-role=chip-option][data-chip='green 4']")

      view |> element("#{row} [data-role=pot-pick-back]") |> render_click()
      refute has_element?(view, "#{row} [data-role=chip-option]")

      view |> element("#pot-0-lg [data-target][phx-click=pot_pick]") |> render_click()
      view |> element("#{row} [data-chip='green 4']") |> render_click()
      assert logged?(id, &match?({0, {:chip, {:upgrade, {:green, 1}, {:green, 4}}}}, &1))
    end

    test "Chicken eyes: the 1-chips glow in the pot, No in the bar" do
      {:ok, id} =
        GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, MapSet.new([:alchemists]))

      {:ok, view, _html} = live(browser("r36-al-#{id}"), ~p"/g/#{id}")

      replace_game(id, fn g ->
        %{g | phase: :essence}
        |> H.put(
          patient: :chicken_eyes,
          phase: :essence_bonus,
          essence_pending: {:swap, 1, 2},
          drawn: [{{:green, 1}, 3}, {{:orange, 1}, 2}],
          pot_index: 3
        )
      end)

      assert has_element?(view, "[data-role=bar-essence-swap] [data-role=essence-pass]")
      refute has_element?(view, "dialog#decision-essence_bonus")
      view |> element("#pot-0-lg [data-index='3'][data-target]") |> render_click()
      assert logged?(id, &match?({0, {:essence, {:swap, {:green, 1}}}}, &1))
    end
  end

  describe "an everyone-card's results in the results stage" do
    test "the rows sit in the parchment panel over the bar, not under the card" do
      {id, view} = solo_2()

      replace_game(id, fn g ->
        %{g | phase: :fortune_choice, fortune_card: :p1}
        |> Map.update!(
          :players,
          &Map.new(&1, fn {s, p} -> {s, %{p | phase: :fortune_choice}} end)
        )
      end)

      view |> element("[data-card=p1] button[data-choice=rubies]") |> render_click()

      stage = "section#card-stage-1.results-stage[data-role=card-stage]"
      assert has_element?(view, "#{stage} [data-role=stage-title]", "Choices, Choices")
      assert has_element?(view, "#{stage} [data-role=card-reveal-row][data-me=true]", "You")
      assert has_element?(view, "#{stage} [data-role=reveal-result] [data-gain=rubies]")
      refute has_element?(view, "[data-role=pot-card] [data-role=card-reveals]")
    end
  end

  describe "a white pick that takes the pot over the limit" do
    defp picks_html(game, actions, pool) do
      render_component(&BarComponents.chip_picks/1,
        actions: actions,
        pool: pool,
        game: game,
        me: game.players[0]
      )
    end

    test "the crow skull warns 'explodes!' on that chip only" do
      game =
        Game.new(seed: {1, 2, 3}, fortune: false)
        |> H.put(drawn: [{{:white, 3}, 3}, {{:white, 2}, 5}])

      html =
        picks_html(game, [{:place, {:white, 3}}, {:place, {:white, 1}}], [
          {:white, 3},
          {:white, 1}
        ])

      doc = LazyHTML.from_fragment(html)
      assert [warning] = Enum.to_list(LazyHTML.query(doc, "[data-role=explode-warning]"))
      assert LazyHTML.text(warning) =~ "explodes!"
      assert html =~ ~s(data-over="explodes")
      assert html =~ "Crow skull: place white 3: explodes the pot"
      # the safe chip says what a tap does
      assert LazyHTML.text(LazyHTML.query(doc, "[data-role=pick-verb]")) =~ "Place"
    end

    test "Safety Procedure says the chip goes over the limit but cannot explode" do
      game =
        Game.new(seed: {1, 2, 3}, fortune: false)
        |> H.put(fortune_card: :b7, drawn: [{{:white, 3}, 3}, {{:white, 2}, 5}])

      html =
        picks_html(game, [{:fortune, {:place, {:white, 3}}}, {:fortune, :return_all}], [
          {:white, 3}
        ])

      assert html =~ "over 7, safe"
      assert html =~ ~s(data-over="safe")
      refute html =~ "explodes!"
    end
  end

  defp duo(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, rules)
    alice = open(browser("alice-#{id}"), id)
    bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {id, alice, bob}
  end

  describe "Mandrake" do
    test "the server put the white chip back; the button keeps it, once" do
      {id, alice, bob} = duo()

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}])
      end)

      alice |> element("button[data-slot=draw]") |> render_click()
      refute has_element?(alice, "#decision-yellow_choice")
      assert has_element?(alice, "[data-role=mandrake-undo] #keep-white")
      refute has_element?(bob, "#keep-white")

      alice |> element("#keep-white") |> render_click()
      refute has_element?(alice, "#keep-white")
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.pot_chips(game, 0) == [{:yellow, 1}, {:white, 1}]
    end

    test "the button goes once another seat acts" do
      {id, alice, bob} = duo()

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}])
      end)

      alice |> element("button[data-slot=draw]") |> render_click()
      assert has_element?(alice, "#keep-white")
      bob |> element("button[data-slot=draw]") |> render_click()
      refute has_element?(alice, "#keep-white")
      assert GameServer.keep_white(id, 0) == {:error, :too_late}
    end
  end
end
