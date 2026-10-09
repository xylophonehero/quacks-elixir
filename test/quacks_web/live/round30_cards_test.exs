defmodule QuacksWeb.Round30CardsTest do
  @moduledoc "Round 30: the cards that draw chips show every player's chips and result."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias Quacks.Game.Fortune
  alias Quacks.GameHelpers
  alias QuacksWeb.{CardRevealComponents, TileReveal}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  # Two players, round 2, Less is More turned up: alice draws 5 white 1s (sum 5), bob
  # 5 green 2s (sum 10).
  defp less_is_more do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
    {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
    {:ok, _} = GameServer.begin(id, "alice-#{id}")

    GameHelpers.replace_game(id, fn g ->
      [a, b] = g.seats

      g
      |> GameHelpers.put(a, bag: List.duplicate({:white, 1}, 5), drawn: [], pending: [])
      |> GameHelpers.put(b, bag: List.duplicate({:green, 2}, 5), drawn: [], pending: [])
      |> GameHelpers.put(fortune_deck: [:p8], round: 2)
      |> Game.start_round()
    end)

    alice
  end

  test "Less is More: after the tap, one row per player, yours first, the lowest sum gold" do
    alice = less_is_more()
    alice |> element("#card-tap") |> render_click()

    # Round 31: the rows show under the grown card over the pot.
    rows = "#pot-card-reveals-2 [data-role=card-reveal-row]"
    assert has_element?(alice, rows, "You")
    assert has_element?(alice, "#{rows}:first-child[data-me][data-best]")
    assert has_element?(alice, "#{rows}[data-me] [data-role=reveal-number]", "5")
    assert has_element?(alice, "#{rows}[data-me] [data-gain=chip]")
    assert has_element?(alice, "#{rows}:not([data-me]) [data-role=reveal-number]", "10")
    assert has_element?(alice, "#{rows}:not([data-me]) [data-gain=rubies]")
    refute has_element?(alice, "#{rows}:not([data-me])[data-best]")
    assert has_element?(alice, "#{rows}[data-me] [data-role=reveal-chip]")
  end

  test "Less is More: the fortune sheet shows the same rows" do
    alice = less_is_more()
    assert has_element?(alice, "#sheet-fortune-reveals [data-role=card-reveal-row]")
  end

  test "the tile news shows each player's result once the card is gone" do
    game =
      Game.new(seed: {1, 2, 3}, players: 2, fortune: false)
      |> GameHelpers.put(0, bag: List.duplicate({:white, 1}, 5))
      |> GameHelpers.put(1, bag: List.duplicate({:green, 2}, 5))
      |> GameHelpers.put(fortune_card: :p8)
      |> Fortune.resolve()

    assert %{items: [{:card, :p8, nil, {:blue, 2}}]} = TileReveal.news(game, 0, nil)
    assert %{items: [{:rubies, 1}]} = TileReveal.news(game, 1, nil)
    assert TileReveal.news(game, 0, %{key: {:card, 1}}) == nil
  end

  test "card_reveals/1 fits 8 players: 8 rows, your row first" do
    reveals =
      Map.new(0..7, fn seat ->
        {seat,
         %{
           drew: List.duplicate({:orange, 1}, 5),
           number: 5 + seat,
           traded: nil,
           gains: if(seat == 0, do: [{:chip, {:blue, 2}}], else: [{:rubies, 1}]),
           best?: seat == 0,
           choosing?: false
         }}
      end)

    html =
      render_component(&CardRevealComponents.card_reveals/1,
        id: "r",
        card: :p8,
        reveals: reveals,
        order: Enum.to_list(0..7),
        seat: 3,
        names: Map.new(0..7, &{&1, "P#{&1}"})
      )

    doc = LazyHTML.from_fragment(html)
    rows = LazyHTML.query(doc, "[data-role=card-reveal-row]")
    assert Enum.count(rows) == 8
    assert rows |> Enum.at(0) |> LazyHTML.attribute("data-seat") == ["3"]
    assert doc |> LazyHTML.query("[data-best]") |> LazyHTML.attribute("data-seat") == ["0"]
  end

  test "card_reveals/1 shows nothing under a card that draws no chips" do
    html =
      render_component(&CardRevealComponents.card_reveals/1,
        id: "r",
        card: :p6,
        reveals: %{},
        order: [0, 1],
        seat: 0,
        names: %{}
      )

    refute html =~ "card-reveal-row"
  end
end
