defmodule QuacksWeb.RevealTest do
  @moduledoc "Round 14 A: the reveal overlay's slides (`QuacksWeb.Reveal`), pure."
  use ExUnit.Case, async: true

  alias Quacks.Game
  alias QuacksWeb.Reveal

  # Newest first, like the engine. Seat 0: die, black, green, purple, scoring space;
  # seat 1: black and its scoring VP.
  @log [
    {1, {:pot_vp, 2, 10}},
    {0, {:pot_vp, 3, 13}},
    {0, {:pot_ruby, 13}},
    {0, {:purple, 2, :vp1_ruby}},
    {0, {:green_rubies, 1}},
    {1, {:black, :droplet}},
    {0, {:black, :droplet}},
    {0, {:bonus_die, {:vp, 2}}},
    {0, {:fortune, :b1, {:vp, 1}}},
    {:round_end, 0}
  ]

  @drawn0 [
    {{:green, 1}, 12},
    {{:purple, 1}, 11},
    {{:black, 1}, 9},
    {{:green, 2}, 5},
    {{:purple, 1}, 3}
  ]

  @drawn1 [{{:black, 1}, 8}, {{:black, 1}, 4}, {{:white, 2}, 2}]

  defp results_game do
    game = Game.new(seed: {1, 2, 3}, players: 2)
    game = put_in(game.players[0].drawn, @drawn0)
    game = put_in(game.players[1].drawn, @drawn1)
    game = put_in(game.players[0].pot_index, 12)
    %{game | log: @log, phase: :shopping}
  end

  test "the moment: the card at the round's start, the results in the shop, the end" do
    game = Game.new(seed: {1, 2, 3})
    assert Reveal.moment(game) == {:card, 1}
    assert Reveal.moment(%{game | phase: :shopping}) == {:results, 1}
    assert Reveal.moment(%{game | phase: :over, round: 9}) == {:final, 9}
    assert Reveal.moment(Game.new(seed: {1, 2, 3}, rules: %{fortune: false})) == nil
  end

  test "the card slide names the round's card" do
    game = Game.new(seed: {1, 2, 3})
    assert [%{kind: :card, round: 1, card: card}] = Reveal.slides(game, 0)
    assert card == game.fortune_card
  end

  test "the results: dice, books by colour and seat, scoring, more, summary" do
    slides = Reveal.slides(results_game(), 0)

    assert Enum.map(slides, &{&1.kind, &1[:book], &1[:seat]}) == [
             {:die, nil, 0},
             {:book, :green, 0},
             {:book, :black, 0},
             {:book, :black, 1},
             {:book, :purple, 0},
             {:scoring, nil, nil},
             {:more, nil, nil},
             {:summary, nil, nil}
           ]

    [die, green, black0, black1, purple, scoring, more, summary] = slides
    assert %{face: {:vp, 2}, vp: 2} = die

    # the chips that count (green: of the last two), oldest first, and the reward
    assert green.chips == [{:green, 1}]
    assert green.rubies == 1

    assert purple.chips == [{:purple, 1}, {:purple, 1}]
    assert %{vp: 1, rubies: 1} = purple

    # black compares with the neighbours, this seat first
    assert black0.compare == [{0, 1}, {1, 2}]
    assert black1.compare == [{1, 2}, {0, 1}]
    assert black0.droplet == 1

    assert [%{seat: 0, vp: 3, ruby: true}, %{seat: 1, vp: 2, ruby: false}] = scoring.rows
    assert [%{seat: 0, kind: :card, vp: 1}] = more.rows
    assert %{round: 1, last: false, rows: [%{seat: 0, updates: [_ | _]}, %{seat: 1}]} = summary
  end

  test "seat 1 sees its own book slides first among equals" do
    slides = Reveal.slides(results_game(), 1)
    blacks = for %{kind: :book, book: :black, seat: s} <- slides, do: s
    assert blacks == [1, 0]
  end

  test "the end of the game: the final scoring, then the podium" do
    game = Game.new(seed: {1, 2, 3}, players: 2)
    game = put_in(game.players[0].vp, 40)
    game = put_in(game.players[1].vp, 44)

    log = [
      {:round_end, 9},
      {1, {:pennies, 2}},
      {1, {:final_conversion, 7, 1, 3, 1}},
      {0, {:final_conversion, 4, 0, 1, 0}}
    ]

    game = %{game | log: log, phase: :over, round: 9}

    assert [%{kind: :final, rows: rows}, %{kind: :podium, ranked: ranked}] =
             Reveal.slides(game, 0)

    assert [%{seat: 0, coins: 4, coins_vp: 0}, %{seat: 1, rubies_vp: 1, pennies_vp: 2}] = rows
    assert ranked == [{1, 44, 1}, {0, 40, 2}]
  end

  test "Auto times scale with the speed" do
    slide = %{kind: :book}
    assert Reveal.duration(slide, Reveal.factor(:normal)) == 2600
    assert Reveal.duration(slide, Reveal.factor(:slower)) == 6500
    assert Reveal.beat_ms(:slow) == 720
    assert Reveal.speeds() == [:normal, :slow, :slower]
  end
end
