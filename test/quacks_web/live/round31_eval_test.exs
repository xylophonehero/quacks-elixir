defmodule QuacksWeb.Round31EvalTest do
  @moduledoc """
  Round 31 (item 6): the evaluation on the tiles applies one update per step.
  The scoring space plays as three steps (coins, VP, rubies), and a tile, the rat
  track, the pot and the ruby counter show the values before a step until Next.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.{Reveal, TileReveal}

  defp browser(token), do: init_test_session(build_conn(), player_token: token)

  defp to_shop(id) do
    Enum.find_value(1..120, fn _ ->
      {:ok, %{game: game}} = GameServer.get(id)

      if game.phase == :shopping do
        true
      else
        seat = Enum.find(game.seats, &(Game.legal_actions(game, &1) -- [:resume] != []))
        actions = Game.legal_actions(game, seat) -- [:resume]
        pick = [:stop, :chip_done, {:explosion_choice, :vp}, :draw]
        {:ok, _} = GameServer.apply(id, seat, Enum.find(pick, hd(actions), &(&1 in actions)))
        nil
      end
    end)
  end

  # Two seats brew far enough that the scoring space pays VP, then the tiles play.
  defp duo_on_tiles do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
    {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    for _ <- 1..4, seat <- [0, 1], do: GameServer.apply(id, seat, :draw)
    to_shop(id)

    render_hook(alice, "reveal_settings", %{
      "mode" => "step",
      "speed" => "normal",
      "show" => "tiles"
    })

    {:ok, %{game: game}} = GameServer.get(id)
    {game, alice}
  end

  defp step_label(view),
    do:
      view
      |> element("[data-role=tile-step]")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> String.trim()

  defp next_until(view, label) do
    Enum.find(1..10, fn _ ->
      step_label(view) == label or
        (view |> element("[data-role=tile-next]") |> render_click() && step_label(view) == label)
    end)
  end

  test "the scoring space splits into coins, VP and rubies steps, one update each" do
    space = %{
      kind: :space,
      rows: [
        %{seat: 0, coins: 6, vp: 1, rubies: 1, exploded: false, choice: nil},
        %{seat: 1, coins: 4, vp: 0, rubies: 0, exploded: false, choice: nil}
      ],
      gains: %{0 => {1, 1}, 1 => {0, 0}}
    }

    assert [coins, vp, rubies] = TileReveal.slides([space])
    assert {coins.part, vp.part, rubies.part} == {:coins, :vp, :rubies}
    assert coins.gains == %{0 => {0, 0}, 1 => {0, 0}}
    assert vp.gains == %{0 => {1, 0}, 1 => {0, 0}}
    assert rubies.gains == %{0 => {0, 1}, 1 => {0, 0}}
    assert TileReveal.badges(coins, 0) == [{:coins, 6}]
    assert TileReveal.badges(vp, 0) == [{:vp, 1}]
    assert TileReveal.badges(vp, 1) == []
    assert TileReveal.badges(rubies, 0) == [{:rubies, 1}]

    assert Enum.map([coins, vp, rubies], &TileReveal.label/1) == [
             "Coins",
             "Victory points",
             "Rubies"
           ]

    # A part nobody gets has no step.
    none = put_in(space, [:rows, Access.all(), :rubies], 0)
    assert none |> List.wrap() |> TileReveal.slides() |> Enum.map(& &1.part) == [:coins, :vp]
  end

  test "a tile shows the VP before the VP step until Next, then the VP after it" do
    {game, view} = duo_on_tiles()
    slides = game |> Reveal.slides(0) |> TileReveal.slides()
    index = Enum.find_index(slides, &(&1[:part] == :vp))
    assert index && index > 0, "a step before the VP step"

    {seat, {gain, 0}} =
      Enum.find(slides |> Enum.at(index) |> Map.get(:gains), fn {_s, {v, _}} -> v > 0 end)

    {before, _} = TileReveal.totals(game, slides, index - 1)[seat]

    next_until(view, TileReveal.label(Enum.at(slides, index - 1)))
    assert has_element?(view, "#tile-vp-#{seat}-#{before}")
    refute has_element?(view, "#tile-vp-#{seat}-#{before + gain}")
    # The pot plays this step's own update only: no VP tag before the VP step.
    refute has_element?(view, "[data-role=vp-float]")

    view |> element("[data-role=tile-next]") |> render_click()
    assert step_label(view) == "Victory points"
    assert has_element?(view, "#tile-vp-#{seat}-#{before + gain}")
  end

  test "the pot's droplet and the ruby counter follow the steps" do
    {game, view} = duo_on_tiles()
    slides = game |> Reveal.slides(0) |> TileReveal.slides()
    droplets = TileReveal.droplets(game, slides, 0)
    {_vp, rubies} = TileReveal.totals(game, slides, 0)[0]

    assert has_element?(view, ".pot-lg [data-role=droplet][data-index='#{droplets[0]}']")
    assert view |> element("#stat-rubies .sr-only") |> render() =~ ">#{rubies}<"
  end
end
