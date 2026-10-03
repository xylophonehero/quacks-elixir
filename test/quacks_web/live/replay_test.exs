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

  test "result lines carry --beat in order, the die line a rolling die" do
    html = render_component(&GameComponents.round_results/1, game: game())
    beats = attr(html, "[data-role=result-line]", "data-beat")
    assert beats == ~w(0 2 3 4 5 6)
    assert attr(html, "[data-role=result-line]", "style") == Enum.map(beats, &"--beat: #{&1}")
    assert attr(html, "[data-role=result-total]", "data-beat") == ["7"]

    assert has?(
             html,
             ~s([data-role=result-line][data-kind=die] [data-role=die][data-face=droplet])
           )

    assert has?(html, "[data-role=die] .die-strip")
    assert has?(html, "[data-role=result-line] .die-text")
    assert has?(html, "button#round-results-skip[data-role=replay-skip][phx-click*=replay-done]")
  end

  test "multiplayer: my block first, line by line; each other seat one beat after" do
    game = game(2)
    game = put_in(game.players[1].drawn, @drawn)

    log =
      Enum.map(@log, fn
        {0, entry} -> {1, entry}
        other -> other
      end)

    game = %{game | log: log ++ [{0, {:pot_vp, 1, 4}}]}
    names = %{0 => "Ann", 1 => "Bob"}

    html = render_component(&GameComponents.round_results/1, game: game, names: names, me: 1)
    assert attr(html, "section > [data-seat]", "data-seat") == ["1", "0"]
    assert attr(html, "section > [data-seat]", "data-beat") == ["8"]
    assert attr(html, ~s([data-seat="1"] [data-role=result-line]), "data-beat") == ~w(0 2 3 4 5 6)
    refute has?(html, ~s([data-seat="0"] [data-role=result-line][data-beat]))
    refute has?(html, ~s([data-seat="0"] [data-role=die]))
  end

  test "the results dialog replays once: Skip and closing finish it" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    {:ok, view, _html} = live(init_test_session(build_conn(), player_token: "solo"), ~p"/g/#{id}")

    for _ <- 1..3, do: view |> element("button", "Draw a chip") |> render_click()
    view |> element("button", "Stop") |> render_click()

    assert has_element?(view, "dialog#round-results[data-on-close*=replay-done]")
    assert has_element?(view, "#round-results-skip[phx-click*=replay-done]")

    assert has_element?(
             view,
             "#round-results [data-role=result-line][data-beat='0'] [data-role=die]"
           )

    html = render(view)

    beats =
      html
      |> attr("#round-results [data-role=result-line]", "data-beat")
      |> Enum.map(&String.to_integer/1)

    assert beats == Enum.sort(beats) and beats != []

    # every pot flash belongs to a line's beat (the die's lands one beat later)
    for beat <- attr(html, "#pot-0-lg [data-role=beat-ring]", "data-beat") do
      assert String.to_integer(beat) in Enum.flat_map(beats, &[&1, &1 + 1])
    end
  end

  test "the CSS has the replay keyframes, Skip and a reduced-motion fallback" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    for name <- ~w(beat-in die-roll die-land beat-glow), do: assert(css =~ "@keyframes #{name}")
    assert css =~ "calc(var(--beat-lead) + var(--beat) * var(--beat-step))"
    assert css =~ "#round-results.replay-done [data-beat]"

    [_, reduced] = String.split(css, "/* Reduced motion: fewer and gentler.", parts: 2)
    assert reduced =~ "#round-results [data-beat] {"
    assert reduced =~ "#round-results [data-beat] .die-strip"
    assert reduced =~ ~s([data-role="beat-ring"])
  end
end
