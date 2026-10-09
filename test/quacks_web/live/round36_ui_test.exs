defmodule QuacksWeb.Round36UiTest do
  @moduledoc """
  Round 36 (ui): chip choices as chips, Ghost's breath V in a sheet, pot chips as
  targets, the short second tile row centred, the peeked chip over the bag and the
  scoring space's pulse when the chip lands.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  doctest QuacksWeb.GameComponents, import: true, only: [loop_start: 3]

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(sets \\ %{}, expansion \\ nil) do
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

  describe "item 4: the short second tile row is centred" do
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

  describe "item 6: the scoring space pulses when the chip lands" do
    test "the draw's flight hides the gold space and the ring, then pops them" do
      js = File.read!("assets/js/app.js")

      assert js =~ "if (s0 !== 1) this.scoringPulse(460)"
      assert js =~ ~s([data-role=next-space], [data-role=scoring-ring][data-seat=)
      assert js =~ "delay: after"
      # Reduced motion: `fly` returns before the flight, so no pulse.
      assert js =~ "lift = 70) {\n    if (reduced()) return"
    end

    test "the pot marks its scoring space and this seat's ring" do
      {_id, view} = solo()
      view |> element("[data-role=action-bar] button", "Draw") |> render_click()

      assert has_element?(view, "#pot-0-lg [data-role=next-space]")
      assert has_element?(view, "#pot-0-lg [data-role=scoring-ring][data-seat='0']")
    end
  end

  describe "item 5: Mandrake V's peeked chip over the bag" do
    defp log(g, entries), do: %{g | log: Enum.reverse(entries) ++ g.log}

    test "the peeked chip shows over the bag until the next draw" do
      {id, view} = solo(%{yellow: 5}, :herb_witches)
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
    {id, view} = solo(%{}, expansion)

    replace_game(id, fn g ->
      %{g | sets: Map.merge(g.sets, sets)}
      |> H.put(phase: :explosion_choice, exploded?: true, drawn: drawn, pot_index: 40)
      |> H.apply!({:explosion_choice, :buy})
    end)

    {id, view}
  end

  defp logged?(id, pattern) do
    {:ok, %{game: game}} = GameServer.get(id)
    Enum.any?(game.log, pattern)
  end

  describe "item 1: chip choices are chips to tap" do
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
      {id, view} = solo()

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

  describe "item 2: Ghost's breath V in a sheet like the shop" do
    test "the buys are tiles to tick; Take sends the ticked buy" do
      {id, view} =
        chip_choice(%{purple: 5}, [{{:purple, 1}, 40}, {{:purple, 1}, 30}], :herb_witches)

      sheet = "dialog#decision-purple-buy-1[data-pot] [data-role=purple-buy]"
      assert has_element?(view, "#{sheet} [data-role=purple-buy-row] input[type=checkbox]")
      assert has_element?(view, "#{sheet} [data-role=purple-buy-take]:disabled")
      assert has_element?(view, "[data-role=bar-chip-actions] [data-role=purple-buy-open]")
      assert has_element?(view, "[data-role=bar-chip-actions] [data-role=chip-action]", "Done")

      view
      |> element("#purple-buy-1")
      |> render_change(%{"chips" => [QuacksWeb.GameLive.encode({:green, 1})]})

      view |> element("#{sheet} [data-role=purple-buy-take]") |> render_click()
      assert logged?(id, &match?({0, {:chip, {:buy, [{:green, 1}]}}}, &1))
    end
  end

  describe "item 3: a choice about pot chips is a tap on the chip in the pot" do
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

  describe "item 7: an everyone-card's results in the results stage" do
    test "the rows sit in the parchment panel over the bar, not under the card" do
      {id, view} = solo()

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
end
