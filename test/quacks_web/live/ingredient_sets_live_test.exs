defmodule QuacksWeb.IngredientSetsLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [force_draws: 2]

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.{GameComponents, GameText, PotComponents, TileComponents}

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "sets-#{System.unique_integer()}")}
  end

  # Play seat 0 until the shop opens: stop as soon as possible, skip every choice.
  defp to_shop(id) do
    Enum.reduce_while(1..60, nil, fn _, _ ->
      {:ok, %{game: game}} = GameServer.get(id)
      actions = Game.legal_actions(game, 0)

      if game.phase == :shopping do
        {:halt, game}
      else
        preferred = [:stop, :chip_done, {:explosion_choice, :buy}]
        action = Enum.find(preferred, hd(actions), &(&1 in actions))
        {:ok, _} = GameServer.apply(id, 0, action)
        {:cont, nil}
      end
    end)
  end

  test "the host picks green 2; the shop shows green 1 at 6 coins", %{conn: conn} do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{green: 2})
    {:ok, game_view, _html} = live(conn, ~p"/g/#{id}")

    {:ok, %{game: game}} = GameServer.get(id)
    assert game.sets == %{green: 2, blue: 1, red: 1, yellow: 1, purple: 1, black: 1}
    assert %Game{phase: :shopping} = to_shop(id)
    render(game_view)

    assert has_element?(game_view, "[data-role=books]", "yellow 1 · green 2 · black 1")
    assert has_element?(game_view, "#shop label", ~r/green 1\s+6c/)
    assert has_element?(game_view, "#shop label", ~r/green 4\s+18c/)
  end

  test "a bad set from the form falls back to Set 1" do
    assert QuacksWeb.SetupComponents.parse_sets(%{"green" => "9", "red" => "2", "blue" => %{}}) ==
             %{green: 1, blue: 1, red: 2, yellow: 1, purple: 1, black: 1}
  end

  test "a protected explosion shows in the player sheet and the log" do
    g = Game.new(seed: {1, 2, 3}, fortune: false, sets: %{blue: 2})
    g = Quacks.GameHelpers.put(g, drawn: [{{:white, 3}, 3}, {{:white, 3}, 0}], pot_index: 3)
    g = force_draws(g, [{:blue, 2}, {:white, 3}])

    assert render_component(&TileComponents.player_card/1, game: g, seat: 0, name: "A") =~
             "Exploded (protected)"

    assert render_component(&GameComponents.action_log/1, log: g.log) =~
             "Crow skull: protected, kept VP and coins"
  end

  test "every chip effect, chip choice and red action has a label" do
    effects = [
      {{:green, 2}, {:gain, {:orange, 1}}},
      {{:green, 3}, {:moved_last, 3}},
      {{:green, 4}, {:droplet, 2}},
      {{:blue, 2}, {:protect, 2}},
      {{:blue, 2}, :protected_explosion},
      {{:blue, 3}, :ruby},
      {{:blue, 4}, {:vp, 4}},
      {{:red, 2}, {:aside, {:red, 1}}},
      {{:red, 3}, {:extra, 2}},
      {{:red, 4}, :white_plus1},
      {{:yellow, 2}, {:doubled, 4}},
      {{:yellow, 3}, {:limit, 8}},
      {{:yellow, 4}, {:extra, 3}},
      {{:purple, 2}, {:trade, 2}},
      {{:purple, 3}, {:vp, 6}},
      {{:purple, 4}, {:upgrade, {:blue, 2}, {:blue, 4}}}
    ]

    actions = [
      {:chip, {:gain, {:red, 1}}},
      {:chip, {:pay_ruby_move, 1}},
      {:chip, {:purple_trade, 3}},
      {:chip, {:upgrade, {:green, 1}, {:green, 2}}},
      :chip_done,
      {:red, {:place, {:red, 2}}},
      {:red, {:keep, {:red, 2}}},
      {:red, {:return, {:red, 2}}}
    ]

    for {book, detail} <- effects,
        entry <- [{:effect, book, detail}, {1, {:effect, book, detail}}] do
      refute GameText.label(entry) =~ ~r/^[:{]/
    end

    for action <- actions, do: refute(GameText.label(action) =~ ~r/^[:{]/)

    assert GameText.label({:effect, {:blue, 2}, :protected_explosion}) ==
             "Crow skull: protected, kept VP and coins"
  end

  test "red set 2: the chips beside the pot are shown" do
    g = Game.new(seed: {1, 2, 3}, fortune: false, sets: %{red: 2})
    g = force_draws(g, [{:white, 1}, {:red, 2}])
    assert g.players[0].aside == [{:red, 2}]

    html = render_component(&PotComponents.aside/1, chips: g.players[0].aside)
    assert html =~ "Beside the pot" and html =~ ~s(aria-label="red 2")
    assert GameText.label({:red, {:place, {:red, 2}}}) =~ "place red 2"
  end
end
