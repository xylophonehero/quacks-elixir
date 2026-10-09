defmodule QuacksWeb.Round33ContextTest do
  @moduledoc """
  Round 33 (context): the bar's choices wrap to two rows (no sideways scroll); an
  info row over the buttons in the evaluation; the chip actions, the bonus die and
  the droplet's free move live in the bar, not in a sheet; the test-tube droplet
  moves along the strip.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(rules) do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, Map.merge(%{fortune: false}, rules))
    {:ok, view, _html} = live(browser("r33-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  describe "item 1: the choices in two rows" do
    test "Choices, Choices: five buttons in two rows of three, no scroll" do
      {id, view} = solo(%{})

      replace_game(id, fn g ->
        %{g | phase: :fortune_choice, fortune_card: :p1} |> H.put(0, phase: :fortune_choice)
      end)

      grid = "#bar-card-1 [data-role=choice-grid][data-rows='2'].grid-cols-3"
      assert has_element?(view, grid)
      refute has_element?(view, "#bar-card-1 .overflow-x-auto")
      assert has_element?(view, "#{grid} button[data-choice=take]", "black 1")
      # The chip has its own box, so its value badge never covers the text.
      assert has_element?(view, "#{grid} button [data-role=choice-icon] .chip-token")
    end

    test "the grid: up to 4 in one row, 5 to 8 in two rows" do
      for {n, cols, rows} <- [{2, 2, 1}, {4, 4, 1}, {5, 3, 2}, {6, 3, 2}, {7, 4, 2}, {8, 4, 2}] do
        html =
          render_component(
            fn assigns ->
              ~H"""
              <QuacksWeb.GameLive.choice_grid count={@n}><span>x</span></QuacksWeb.GameLive.choice_grid>
              """
            end,
            n: n
          )

        assert html =~ "grid-cols-#{cols}"
        assert html =~ ~s(data-rows="#{rows}")
      end
    end
  end

  describe "item 3: the chip actions in the bar" do
    defp garden_spider do
      {id, view} = solo(%{})

      replace_game(id, fn g ->
        %{g | sets: Map.merge(g.sets, %{green: 2})}
        |> H.put(
          phase: :explosion_choice,
          exploded?: true,
          drawn: [{{:green, 1}, 10}, {{:green, 1}, 8}],
          pot_index: 10
        )
        |> H.apply!({:explosion_choice, :buy})
      end)

      {id, view}
    end

    test "no sheet: the info row names the book, the options are chip buttons, then Done" do
      {id, view} = garden_spider()
      bar = "footer [data-role=bar-chip-actions]"

      refute has_element?(view, "dialog#decision-chip_choice")
      refute has_element?(view, "[data-role=decision-button]")
      assert has_element?(view, "#{bar} [data-role=info-row]", "Garden spider: take one")
      assert has_element?(view, "#{bar} button[data-role=chip-action] .chip-token")
      assert has_element?(view, "#{bar} button[data-role=chip-action]", "Done")

      view
      |> element("#{bar} button[data-role=chip-action][aria-label^='Garden spider: take']")
      |> render_click()

      {:ok, %{game: game}} = GameServer.get(id)
      assert Enum.any?(game.log, &match?({0, {:chip, {:gain, _}}}, &1))
    end

    test "the white track's row gives way to the info row" do
      {_id, view} = garden_spider()
      refute has_element?(view, "[data-role=fuse-row]")
    end
  end

  describe "item 5: the droplet's free move in the bar" do
    test "the hawkmoth: the info row says what, the two moves are buttons; the strip stays" do
      {id, view} = solo(%{pot_side: :back})

      replace_game(id, fn g ->
        g
        |> H.put(droplet_moves: 1)
        |> Map.update!(:log, &[{0, {:black, :droplet_ruby}} | &1])
      end)

      refute has_element?(view, "dialog#decision-droplet_choice")

      assert has_element?(
               view,
               "#bar-droplet [data-role=info-row]",
               "Hawkmoth: droplet +1, +1 ruby"
             )

      assert has_element?(view, "#bar-droplet button[data-choice=pot]", "Pot droplet")
      assert has_element?(view, "#bar-droplet button[data-choice=tube]", "Bonus: 1 ruby")
      assert has_element?(view, "[data-area=tubes] svg[data-role=test-tubes]")

      view |> element("#bar-droplet button[data-choice=pot]") |> render_click()
      refute has_element?(view, "#bar-droplet")
    end
  end

  describe "item 6: the test-tube droplet moves along the strip" do
    test "the strip under the pot carries the hook and the glass it shows" do
      {id, view} = solo(%{pot_side: :back})
      hook = "#tubes-main[phx-hook='QuacksWeb.GameComponents.TubeDrop']"
      assert has_element?(view, ~s(#{hook}[data-tube="0"]))

      replace_game(id, &H.put(&1, droplet_moves: 1))
      view |> element("#bar-droplet button[data-choice=tube]") |> render_click()
      assert has_element?(view, ~s(#{hook}[data-tube="1"] [data-role=tube-droplet]))
    end

    test "the hook animates `translate` with WAAPI and does nothing with reduced motion" do
      src = File.read!("lib/quacks_web/components/game_components.ex")
      [hook] = Regex.run(~r/name=".TubeDrop">(.*?)<\/script>/s, src, capture: :all_but_first)
      assert hook =~ "d.animate("
      assert hook =~ "translate"
      assert hook =~ ~s[matchMedia("(prefers-reduced-motion: reduce)").matches) return]
    end
  end
end
