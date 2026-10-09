defmodule QuacksWeb.ReplayTest do
  @moduledoc """
  Animation batch 2: the step-B replay (`docs/research/animations.md` §3 B2). The
  motion is CSS; these tests check the beats, marks and elements the server renders.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.{GameComponents, Replay}

  # Newest first, like the engine: die → black → green → purple → scoring space.
  @log [
    {0, {:pot_vp, 3, 13}},
    {0, {:pot_ruby, 13}},
    {0, {:purple, 2, :vp1_ruby}},
    {0, {:green_rubies, 1}},
    {0, {:black, :droplet}},
    {0, {:bonus_die, :droplet}},
    {0, {:drew, {:green, 1}, 12}},
    {:round_end, 0}
  ]

  @drawn [
    {{:green, 1}, 12},
    {{:purple, 1}, 11},
    {{:black, 1}, 9},
    {{:green, 2}, 5},
    {{:purple, 1}, 3}
  ]

  defp game(players \\ 1) do
    game = Game.new(seed: {1, 2, 3}, players: players)
    game = put_in(game.players[0].drawn, @drawn)
    %{game | log: @log}
  end

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)
  defp has?(html, selector), do: not Enum.empty?(query(html, selector))

  test "beats follow the engine order; the die takes two beats" do
    lines = Replay.beats(game(), 0)

    assert Enum.map(lines, &{&1.beat, &1.kind}) == [
             {0, :die},
             {2, :black},
             {3, :green},
             {4, :purple},
             {5, :space},
             {6, :space}
           ]

    assert Replay.next_beat(lines) == 7
    assert Replay.next_beat([], 3) == 3
    assert hd(lines).face == :droplet
    assert Enum.at(lines, 1).text =~ "Hawkmoth"
  end

  test "marks: green on the last two, every purple and black chip, droplet, ring" do
    lines = Replay.beats(game(), 0)

    assert Enum.map(lines, & &1.marks) == [
             [:droplet],
             [9, :droplet],
             [12],
             [11, 3],
             [:ring],
             [:ring]
           ]

    # the die lights its droplet when it lands; a mark keeps its first beat
    assert Replay.highlights(lines) == %{
             :droplet => 1,
             9 => 2,
             12 => 3,
             11 => 4,
             3 => 4,
             :ring => 5
           }
  end

  test "the pot lights the marked chips, the droplet and the scoring ring on their beat" do
    game = game()
    beats = game |> Replay.beats(0) |> Replay.highlights()
    html = render_component(&GameComponents.pot/1, game: game, beats: beats)

    assert has?(
             html,
             ~s([data-role=pot-chip][data-index='12'] [data-role=beat-ring][data-beat="3"][style="--beat: 3"])
           )

    assert has?(
             html,
             ~s([data-role=pot-chip][data-index='3'] [data-role=beat-ring][data-beat="4"])
           )

    assert has?(html, ~s(#droplet-0-lg [data-role=beat-ring][data-beat="1"]))
    ring = Game.scoring_index(game, 0)
    assert has?(html, ~s([data-space="#{ring}"] [data-role=beat-ring][data-beat="5"]))
    refute has?(html, "[data-role=pot-chip][data-index='5'] [data-role=beat-ring]")

    html = render_component(&GameComponents.pot/1, game: game)
    refute has?(html, "[data-role=beat-ring]")
  end

  test "update chips: how the brew ended, then the VP, rubies and droplet sums on their last beat" do
    assert Replay.updates(game(), 0) == [
             %{kind: :stopped, text: "stopped", beat: 0},
             %{kind: :droplet, text: "+2", beat: 2},
             %{kind: :rubies, text: "+3", beat: 5},
             %{kind: :vp, text: "+4 VP", beat: 6}
           ]

    exploded = put_in(game().players[0].exploded?, true)
    assert hd(Replay.updates(exploded, 0)) == %{kind: :exploded, text: "exploded", beat: 0}

    nothing = %{game() | log: [{:round_end, 0}]}
    assert Replay.updates(nothing, 0) == [%{kind: :stopped, text: "stopped", beat: 0}]
    assert Replay.last_beat(game()) == 6
  end

  test "the name card has no update chips; its counters tick on their beats (round 14: no timer)" do
    game = game()

    html =
      render_component(&GameComponents.player_chip/1,
        game: game,
        seat: 0,
        name: "Ann",
        updates: Replay.updates(game, 0),
        ticks: true
      )

    refute has?(html, "[data-role=update-chip]")
    refute has?(html, "[data-role=replay-timer]")
    assert has?(html, ".stat-tick")

    html =
      render_component(&GameComponents.player_chip/1,
        game: game,
        seat: 0,
        name: "Ann",
        updates: Replay.updates(game, 0)
      )

    refute has?(html, ".stat-tick")
  end

  test "the player sheet lists the result lines with the die face and the totals" do
    html = render_component(&GameComponents.result_lines/1, game: game(), seat: 0)
    assert length(query(html, "[data-role=result-line]") |> Enum.to_list()) == 6

    assert has?(
             html,
             ~s([data-role=result-line][data-kind=die] [data-role=die][data-face=droplet])
           )

    assert has?(html, "[data-role=result-total]")
    refute has?(html, "[data-beat]")
  end

  test "the replay plays once: Skip ends it and marks the round as seen" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    {:ok, view, _html} = live(init_test_session(build_conn(), player_token: "solo"), ~p"/g/#{id}")

    for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
    view |> element("button", "Stop") |> render_click()

    # round 14: the reveal overlay holds the replay open; its end ends it
    assert has_element?(view, "dialog#reveal-results-1 [data-role=reveal-slide]")
    refute has_element?(view, "#players-row.replay-done")
    refute has_element?(view, "[data-role=replay-timer]")

    html = render(view)
    {:ok, %{game: game}} = GameServer.get(id)
    last = Replay.last_beat(game)

    # every pot flash lands within the replay
    for beat <- attr(html, "#pot-0-lg [data-role=beat-ring]", "data-beat") do
      assert String.to_integer(beat) <= last
    end

    view |> element("#reveal-skip") |> render_click()
    view |> element("#reveal-next") |> render_click()
    assert has_element?(view, "#players-row.replay-done")
    refute has_element?(view, "dialog#reveal-results-1")
    assert {:ok, %{seen: %{0 => %{results: 1}}}} = GameServer.get(id)
  end

  test "the CSS has the replay keyframes, the replay end and a reduced-motion fallback" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    for name <- ~w(update-in beat-glow), do: assert(css =~ "@keyframes #{name}")
    assert css =~ "calc(var(--beat-lead) + var(--beat) * var(--beat-step))"
    assert css =~ "--beat-step: calc(var(--beat-ms) * 1ms)"
    refute css =~ ".replay-timer"

    [_, reduced] = String.split(css, "/* Reduced motion: fewer and gentler.", parts: 2)
    assert reduced =~ ~s([data-role="beat-ring"])
  end
end
