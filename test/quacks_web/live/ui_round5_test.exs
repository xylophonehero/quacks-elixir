defmodule QuacksWeb.UiRound5Test do
  @moduledoc """
  Nick's fourth game: the round summary shows the Fortune Teller card's outcome (the die of Take a Chance) and, in round 9, the final
  buying power.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.Game
  alias Quacks.GameHelpers, as: H
  alias QuacksWeb.GameComponents

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  defp results(game),
    do:
      render_component(&GameComponents.round_results/1, game: game, names: %{0 => "A", 1 => "B"})

  test "the summary shows the Take a Chance die per seat, not the rats (round start)" do
    game =
      Game.new(seed: {1, 2, 3}, players: 2, fortune: false)
      |> H.put(0, vp: 3)
      |> H.put(1, vp: 12)

    game = %{
      game
      | round: 2,
        log: [
          {0, {:fortune, :p8, {:drew, [{:white, 1}, {:white, 2}]}}},
          {1, {:fortune, :p12, :droplet}},
          {0, {:fortune, :p12, {:vp, 2}}} | game.log
        ]
    }

    html = results(game)
    assert html =~ "Take a Chance: rolled the die: 2 VP"
    assert html =~ "Take a Chance: rolled the die: droplet +1"
    assert html =~ "Less is More: drew white 1, white 2 (sum 3)"
    refute html =~ "Rats next round"
    assert count(html, "[data-role=result-rats]") == 0
    assert count(html, "[data-role=result-buying-power]") == 0
  end

  test "round 9: final buying power from the coins and rubies, or the log" do
    game =
      Game.new(seed: {1, 2, 3}, players: 2, fortune: false)
      |> H.put(0, coins: 17, rubies: 5)
      |> H.put(1, coins: 1, rubies: 0)

    game = %{game | round: 9, log: [{1, {:final_conversion, 12, 2, 3, 1}} | game.log]}

    html = results(game)
    assert html =~ "Final buying power: 17 coins → 3 VP, 5 rubies → 2 VP"
    assert html =~ "Final buying power: 12 coins → 2 VP, 3 rubies → 1 VP"
    assert count(html, "[data-role=result-rats]") == 0
  end

  test "solo has no rats" do
    html = render_component(&GameComponents.round_results/1, game: Game.new(seed: {1, 2, 3}))
    assert count(html, "[data-role=result-rats]") == 0
  end

  test "a tiered book shows its tiers as a table on the tile and in the book list" do
    html = render_component(&GameComponents.book_tile/1, colour: :purple, set: 2)
    assert count(html, "[data-role=book-tiers] tr") == 3
    assert html =~ "green 1 · blue 2 · 3 VP · droplet +1"

    html = render_component(&GameComponents.book_list/1, books: [purple: 2, green: 1])
    assert count(html, "[data-book=purple-2] [data-role=book-tiers]") == 1
    assert count(html, "[data-book=green-1] [data-role=book-tiers]") == 0
  end
end
