defmodule QuacksWeb.RevealTest do
  @moduledoc "Round 14 A: the reveal overlay's slides (`QuacksWeb.Reveal`), pure."
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

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

  test "the results: one slide per scoring step, every seat on it, then the table" do
    slides = Reveal.slides(results_game(), 0)

    assert Enum.map(slides, &{&1.kind, &1[:book]}) == [
             {:die, nil},
             {:book, :black},
             {:book, :green},
             {:book, :purple},
             {:space, nil},
             {:results, nil},
             {:standings, nil}
           ]

    [die, black, green, purple, space, results, _standings] = slides

    # every slide has a row per seat, in VP order
    for slide <- [die, black, green, purple, space, results],
        do: assert(Enum.map(slide.rows, & &1.seat) == [0, 1])

    assert [%{rolls: [%{face: {:vp, 2}, vp: 2}], vp: 2}, %{rolls: [], vp: 0}] = die.rows

    # the chips that count (green: of the last two), oldest first, and the reward
    [g0, g1] = green.rows
    assert %{scored: true, chips: [{:green, 1}], rubies: 1} = g0
    assert %{scored: false, chips: [], vp: 0, rubies: 0} = g1

    [p0, _p1] = purple.rows
    assert %{chips: [{:purple, 1}, {:purple, 1}], vp: 1, rubies: 1} = p0

    # black: both seats score; each row compares with its neighbour
    [b0, b1] = black.rows
    assert %{scored: true, chips: [{:black, 1}], compare: [{1, 2}], droplet: 1} = b0
    assert %{scored: true, chips: [{:black, 1}, {:black, 1}], compare: [{0, 1}]} = b1

    # the scoring space: coins, VP, the ruby landing
    assert [%{seat: 0, vp: 3, rubies: 1}, %{seat: 1, vp: 2, rubies: 0}] = space.rows
    assert space.gains == %{0 => {3, 1}, 1 => {2, 0}}

    # the table: no space column; the card waits in the details
    assert %{round: 1, rows: [row0, row1]} = results
    refute Map.has_key?(row0, :space)

    assert %{
             seat: 0,
             vp: 3,
             ruby: true,
             die: [{:vp, 2}],
             updates: [_ | _],
             pot: [green: 2, black: 1, purple: 2]
           } = row0

    assert [%{kind: :card, vp: 1}] = row0.extra
    assert %{seat: 1, vp: 2, ruby: false, die: [], extra: []} = row1
    assert results.gains == %{0 => {1, 0}, 1 => {0, 0}}
  end

  test "a step nobody scores in has no slide: no black lines, no black slide" do
    game = results_game()
    log = Enum.reject(game.log, &match?({_, {:black, _}}, &1))
    kinds = %{game | log: log} |> Reveal.slides(0) |> Enum.map(&{&1.kind, &1[:book]})

    refute {:book, :black} in kinds
    assert {:book, :green} in kinds
  end

  test "two die rolls for one seat: one row, the faces side by side" do
    game = results_game()
    log = [{0, {:effect, {:green, 6}, {:bonus_die, :ruby}}} | game.log]
    [die | _] = Reveal.slides(%{game | log: log}, 0)

    assert %{kind: :die, rows: [row0, %{rolls: []}]} = die
    assert Enum.map(row0.rolls, & &1.face) == [{:vp, 2}, :ruby]
    assert %{vp: 2, rubies: 1} = row0
    assert die.gains[0] == {2, 1}
  end

  test "the scoring space marks who landed on a ruby" do
    game = results_game()
    log = [{1, {:pot_ruby, 10}} | game.log]
    space = %{game | log: log} |> Reveal.slides(0) |> Enum.find(&(&1.kind == :space))

    assert Enum.map(space.rows, &{&1.seat, &1.rubies}) == [{0, 1}, {1, 1}]
  end

  test "another book that paid gets its own slide, after purple" do
    game = results_game()
    game = put_in(game.players[1].drawn, [{{:blue, 2}, 9} | @drawn1])
    log = [{1, {:effect, {:blue, 4}, {:vp, 2}}} | game.log]
    slides = Reveal.slides(%{game | log: log}, 0)

    assert Enum.map(slides, &{&1.kind, &1[:book]}) |> Enum.take(6) == [
             {:die, nil},
             {:book, :black},
             {:book, :green},
             {:book, :purple},
             {:book, :blue},
             {:space, nil}
           ]

    blue = Enum.at(slides, 4)

    assert [%{seat: 0, scored: false}, %{seat: 1, scored: true, vp: 2, chips: [{:blue, 2}]}] =
             blue.rows

    # not twice: the table's details leave it out
    assert slides
           |> Enum.at(-2)
           |> Map.fetch!(:rows)
           |> Enum.all?(&(&1.extra |> Enum.all?(fn l -> l.kind != :other end)))
  end

  test "a results row's card line says its reward once (the log line's text)" do
    game = results_game()
    slides = Reveal.slides(game, 0)

    html =
      render_component(&QuacksWeb.RevealComponents.reveal_overlay/1,
        reveal: %{key: {:results, 1}, slides: slides, index: length(slides) - 2},
        names: %{0 => "Ann", 1 => "Bo"},
        seat: 0
      )

    [extra] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=reveal-extra]")
      |> Enum.to_list()

    text = extra |> LazyHTML.text() |> String.trim()
    assert text == QuacksWeb.GameComponents.label({:fortune, :b1, {:vp, 1}})
    refute text =~ "("
  end

  test "the running results: every slide's standings, the gains highlighted" do
    game = results_game()
    game = put_in(game.players[0].vp, 9)
    game = put_in(game.players[1].vp, 2)
    slides = Reveal.slides(game, 0)

    # Before: seat 0 had 9 - (2 + 1 + 3 + 1) = 2 VP, seat 1 had 0.
    [die | _] = slides
    assert die.standings == [%{seat: 0, vp: 4, gain: 2}, %{seat: 1, vp: 0, gain: 0}]

    results = Enum.at(slides, -2)
    assert results.standings == [%{seat: 0, vp: 9, gain: 1}, %{seat: 1, vp: 2, gain: 0}]

    # the space slide before it brought both seats' space VP
    space = Enum.at(slides, -3)
    assert space.standings == [%{seat: 0, vp: 8, gain: 3}, %{seat: 1, vp: 2, gain: 2}]
    assert Enum.map(results.rows, & &1.seat) == [0, 1]
  end

  test "the results slide ranks by VP, a tie to fewer rubies" do
    game = results_game()
    game = put_in(game.players[0].vp, 20)
    game = put_in(game.players[1].vp, 20)
    game = put_in(game.players[0].rubies, 3)
    game = put_in(game.players[1].rubies, 1)
    assert %{rows: [%{seat: 1}, %{seat: 0}]} = game |> Reveal.slides(0) |> Enum.at(-2)
  end

  test "the end of the game: the final scoring, the standings, then the podium" do
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

    assert [
             %{kind: :final, rows: rows},
             %{kind: :standings, last: false, rows: standings},
             %{kind: :podium, ranked: ranked}
           ] = Reveal.slides(game, 0)

    assert [%{seat: 0, coins: 4, coins_vp: 0}, %{seat: 1, rubies_vp: 1, pennies_vp: 2}] = rows
    assert ranked == [{1, 44, 1}, {0, 40, 2}]

    # Round 22: the standings go from before the final scoring to the end.
    assert [
             %{seat: 0, from_vp: 40, vp: 40},
             %{seat: 1, from_vp: 40, vp: 44, from_rank: 1, rank: 0}
           ] = standings
  end

  test "Auto times scale with the speed" do
    slide = %{kind: :book}
    assert Reveal.duration(slide, Reveal.factor(:normal)) == 3400
    assert Reveal.duration(slide, Reveal.factor(:slower)) == 8500
    assert Reveal.beat_ms(:slow) == 720
    assert Reveal.speeds() == [:normal, :slow, :slower]
  end
end
