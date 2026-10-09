defmodule QuacksWeb.FortuneLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias Quacks.Rules.Fortune
  alias QuacksWeb.GameComponents

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "fortune-#{System.unique_integer()}")}
  end

  defp live_game(conn, seed) do
    {:ok, id} = GameServer.start(1, seed)
    live(conn, ~p"/g/#{id}")
  end

  test "seed 1,2,3 shows B7 Safety Procedure as a blue card", %{conn: conn} do
    {:ok, view, _html} = live_game(conn, {1, 2, 3})
    assert has_element?(view, "[data-role=fortune-card][data-colour=blue]", "Safety Procedure")
    assert has_element?(view, "[data-role=fortune-card]", "draw up to 5 tokens")
    assert has_element?(view, "li", "Fortune teller: Safety Procedure")
  end

  test "seed 10,11,12 shows B8 Lucky Devil", %{conn: conn} do
    {:ok, view, _html} = live_game(conn, {10, 11, 12})
    assert has_element?(view, "[data-role=fortune-card][data-colour=blue]", "Lucky Devil")
  end

  test "a purple choice: seed 30,30,30 opens with P6 Boomberry Cleanse", %{conn: conn} do
    {:ok, view, _html} = live_game(conn, {30, 30, 30})
    assert has_element?(view, "[data-role=fortune-card][data-colour=purple]", "Boomberry Cleanse")
    assert has_element?(view, "dd", "Fortune teller")
    assert has_element?(view, "button[data-slot=draw][disabled]", "Draw")

    view |> element("button", "Score 4 VP") |> render_click()

    assert has_element?(view, "li", "Boomberry Cleanse: +4 VP")
    refute has_element?(view, "button[data-slot=draw][disabled]")
    assert has_element?(view, "dd", "Brewing")
  end

  test "P13 Flea Market shows the 4 drawn chips (seed 2,2,2)", %{conn: conn} do
    {:ok, view, _html} = live_game(conn, {2, 2, 2})
    assert has_element?(view, "[aria-label='Fortune teller offer']", "Flea Market drew:")
    assert view |> render() |> count("[data-role=offer-chip]") == 4

    assert has_element?(
             view,
             "button[data-role=chip-pick][aria-label='Trade green 1 for the next value up']"
           )
  end

  test "B7 Safety Procedure: stopping offers chips to place (seed 1,2,3)", %{conn: conn} do
    {:ok, view, _html} = live_game(conn, {1, 2, 3})
    view |> element("button[data-slot=draw]") |> render_click()
    view |> element("button", "Stop") |> render_click()

    assert has_element?(view, "[aria-label='Fortune teller offer']", "Safety Procedure drew:")
    view |> element("button", "Safety Procedure: return all to the bag") |> render_click()
    assert has_element?(view, "li", "Safety Procedure: returned all chips to the bag")
  end

  test "multiplayer: every seat with a card choice gets its buttons at once" do
    game = Game.new(seed: {30, 30, 30}, players: 2)
    assert game.phase == :fortune_choice
    assert [{:fortune, _} | _] = Game.legal_actions(game, 0)
    assert [{:fortune, _} | _] = Game.legal_actions(game, 1)
  end

  @card_actions [
    {:take, {:green, 2}},
    :rubies,
    :vp,
    :remove_white,
    {:rats_back, 2},
    :droplet,
    {:upgrade, {:green, 1}},
    :skip,
    :restart_round,
    :return_white,
    {:place, {:white, 1}},
    :return_all
  ]

  test "every fortune action shape has a human label, for every card" do
    for choice <- @card_actions, card <- [nil | Fortune.ids(4)] do
      refute GameComponents.label({:fortune, choice}, card) =~ ~r/^[:{]/
    end

    assert GameComponents.label({:fortune, :vp}, :p6) == "Score 4 VP"

    assert GameComponents.label({:fortune, {:take, {:green, 1}}}, :p3) ==
             "Trade 1 ruby for green 1"
  end

  test "every fortune log line has a human label" do
    outcomes = [
      :droplet,
      {:take, {:green, 2}},
      :restart_round,
      {:place, {:red, 1}},
      :return_all,
      {:vp, 2},
      :flask,
      :return_white,
      :ruby,
      :rubies,
      :skip,
      :remove_white,
      {:rats, 3},
      {:rats_back, 1},
      {:upgrade, {:green, 1}},
      :orange
    ]

    for outcome <- outcomes do
      line = GameComponents.label({:fortune, :p1, outcome})
      assert "Choices, Choices: " <> text = line
      refute text =~ ~r/^[:{]/
    end

    assert GameComponents.label({:fortune_drawn, :b7}) == "Fortune teller: Safety Procedure"
    assert GameComponents.label({:fortune_skipped, :p7}) =~ "Infestation"

    assert GameComponents.label({:fortune, :p11, :droplet}) ==
             "Decisions, Decisions...: droplet +2"
  end

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
end
