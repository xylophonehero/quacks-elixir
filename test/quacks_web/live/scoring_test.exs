defmodule QuacksWeb.ScoringTest do
  @moduledoc """
  The scoring sequence on the pot (handoff quacks-scoring): the result lines play
  as beats on the pot pieces (rubies fly, VP tags float, the droplet slides, the
  die rolls beside the pot), on the same beats as the update chips. The motion is
  CSS and `PotMotion`; these tests check what the server renders.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.{ChipComponents, PotComponents, Replay, TileComponents}

  # Newest first, like the engine: die → black → green → purple → scoring space.
  @log [
    {0, {:pot_vp, 3, 13}},
    {0, {:pot_ruby, 13}},
    {0, {:purple, 2, :vp1_ruby}},
    {0, {:green_rubies, 1}},
    {0, {:black, :droplet_ruby}},
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

  defp game do
    game = Game.new(seed: {1, 2, 3}, players: 1)
    game = put_in(game.players[0].drawn, @drawn)
    %{game | log: @log}
  end

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)
  defp has?(html, selector), do: not Enum.empty?(query(html, selector))

  test "pot effects in log order: rubies leave the droplet, the chips, the space" do
    effects = game() |> Replay.beats(0) |> Replay.pot_effects()

    assert Enum.map(effects, &{&1.kind, &1.at, &1.beat}) == [
             {:ruby, :droplet, 2},
             {:ruby, 12, 3},
             {:ruby, 11, 4},
             {:vp, 11, 4},
             {:ruby, :ring, 5},
             {:vp, :ring, 6}
           ]

    assert Enum.at(effects, 3).text == "+1 VP"
    assert List.last(effects).text == "+3 VP"
  end

  test "the pot renders each flight and VP tag on its beat; the droplet slides on its own" do
    game = game()
    lines = Replay.beats(game, 0)

    html =
      render_component(&PotComponents.pot/1,
        game: game,
        beats: Replay.highlights(lines),
        effects: Replay.pot_effects(lines)
      )

    assert attr(html, "[data-role=ruby-flight]", "data-beat") == ~w(2 3 4 5)
    assert attr(html, "[data-role=vp-float]", "style") == ["--beat: 4", "--beat: 6"]
    # the hook's attributes: where the gem starts, how long it waits after its beat
    assert attr(html, "[data-role=ruby-flight]", "data-wait") == ~w(300 0 0 0)
    assert html |> attr("[data-role=ruby-flight]", "data-x") |> Enum.all?(&(&1 != ""))
    assert has?(html, ~s(#pot-0-lg[data-slide-beat="1"][style="--slide-beat: 1"]))

    html = render_component(&PotComponents.pot/1, game: game, beats: Replay.highlights(lines))
    refute has?(html, "[data-role=ruby-flight], [data-role=vp-float], [data-slide-beat]")
  end

  test "the bonus die beside the pot and the counters wait for their beats" do
    game = game()
    [die | _] = Replay.beats(game, 0)

    html = render_component(&ChipComponents.replay_die/1, lines: [die], class: "flex")

    assert has?(
             html,
             ~s([data-role=replay-die][style="--beat: 0"] [data-role=die][data-face=droplet])
           )

    html =
      render_component(&TileComponents.ruby_badge/1,
        rubies: game.players[0].rubies,
        beats: %{rubies: 5}
      )

    assert has?(html, ~s(#stat-rubies[data-beat="5"]))

    html = render_component(&TileComponents.ruby_badge/1, rubies: game.players[0].rubies)
    refute has?(html, ".stat-tick[data-beat]")
  end

  test "a scored round plays on the pot; the reveal overlay's end ends it" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    {:ok, view, _html} = live(init_test_session(build_conn(), player_token: "solo"), ~p"/g/#{id}")

    for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
    view |> element("button", "Stop") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    lines = Replay.beats(game, 0)
    html = render(view)

    assert length(query(html, "#pot-0-lg [data-role=ruby-flight]") |> Enum.to_list()) ==
             Enum.count(Replay.pot_effects(lines), &(&1.kind == :ruby))

    assert has?(html, "#reveal-next") and has?(html, "#pot-0-lg[phx-hook=PotMotion]")

    for %{kind: kind, beat: beat} <- Replay.updates(game, 0), kind == :rubies do
      assert has?(html, ~s(#stat-#{kind}[data-beat="#{beat}"]))
    end

    if Enum.any?(lines, &(&1.kind == :die)), do: assert(has?(html, "[data-role=replay-die]"))

    # a new replay clears the `replay-done` JS added at the end of the last one
    assert has?(
             html,
             ~s(#replay-start-#{game.round}[phx-mounted*=remove_class][phx-mounted*=replay-done])
           )

    render_hook(view, "reveal_close", %{})
    html = render(view)
    assert has?(html, "#players-row.replay-done")
    refute has?(html, "[data-role=ruby-flight], [data-role=vp-float], [data-role=replay-die]")
    refute has?(html, ".stat-tick[data-beat], [data-slide-beat]")
  end

  test "PotMotion flies the rubies on the beat of the menu's speed (round 14: no skip keys)" do
    js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
    [_, hook] = String.split(js, "const PotMotion", parts: 2)

    for text <- ~w{flights() [data-role=ruby-flight] dataset.beat dataset.wait ratsIn() --beat-ms} do
      assert hook =~ text
    end

    refute js =~ "quacks:skips"
    refute js =~ "replay-skip"
  end

  test "the CSS: the end completes everything, the speed sets the beats, reduced motion is instant" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    refute css =~ ":root[data-fast-beats]"
    assert css =~ "--die-roll: calc(var(--beat-ms) * 1.5556ms)"
    assert css =~ "@keyframes vp-float"
    assert css =~ "@keyframes die-roll"
    assert css =~ ~s{:root:has(#players-row.replay-done) :is([data-role="ruby-flight"]}
    assert css =~ ":root:has(#players-row.replay-done) :is(.replay-die, .replay-die *)"

    [_, reduced] = String.split(css, "/* Reduced motion: fewer and gentler.", parts: 2)
    assert reduced =~ ~s([data-role="vp-float"])
    assert reduced =~ ~s([data-role="ruby-flight"])
    assert reduced =~ ".replay-die,"
    assert reduced =~ ".pot-lg[data-slide-beat]"
  end
end
