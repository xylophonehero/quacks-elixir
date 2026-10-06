defmodule QuacksWeb.Round20Test do
  @moduledoc """
  Round 20: the evaluation is one slide per scoring step with every seat on it (die,
  books, scoring space), the overlay is full screen on phones,.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Quacks.Game
  alias QuacksWeb.{Reveal, RevealComponents}

  # Newest first. Seat 0: two dice (the base die and G6), black, the space with a
  # ruby; seat 1: black and its scoring VP.
  @log [
    {1, {:pot_vp, 2, 10}},
    {0, {:pot_vp, 3, 13}},
    {0, {:pot_ruby, 13}},
    {1, {:black, :droplet}},
    {0, {:black, :droplet}},
    {0, {:effect, {:green, 6}, {:bonus_die, :ruby}}},
    {0, {:bonus_die, {:vp, 2}}},
    {:round_end, 0}
  ]

  defp game do
    game = Game.new(seed: {1, 2, 3}, players: 2)
    game = put_in(game.players[0].drawn, [{{:green, 1}, 12}, {{:black, 1}, 9}])
    game = put_in(game.players[1].drawn, [{{:black, 1}, 8}, {{:black, 1}, 4}])
    game = put_in(game.players[0].pot_index, 12)
    %{game | log: @log, phase: :shopping}
  end

  defp render_slide(kind) do
    slides = Reveal.slides(game(), 0)
    index = Enum.find_index(slides, &(&1.kind == kind))

    render_component(&RevealComponents.reveal_overlay/1,
      reveal: %{key: {:results, 1}, slides: slides, index: index},
      names: %{0 => "Ann", 1 => "Bo"},
      seat: 0
    )
    |> LazyHTML.from_fragment()
  end

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  test "the steps: die, black, the space, then the table and the standings" do
    assert game() |> Reveal.slides(0) |> Enum.map(& &1.kind) ==
             [:die, :book, :space, :results, :standings]
  end

  test "the die slide: a row per seat, two dice side by side for seat 0" do
    doc = render_slide(:die)
    assert count(doc, "[data-role=reveal-step-row]") == 2
    assert count(doc, ~s([data-role=reveal-step-row][data-seat="0"] [data-role=die])) == 2
    assert count(doc, ~s([data-role=reveal-step-row][data-seat="1"][data-scored=false])) == 1
  end

  test "the black slide: both seats, their chips and the neighbour compared" do
    doc = render_slide(:book)
    assert count(doc, ~s([data-seat="1"] [data-role=reveal-chips] [data-chip-icon=black])) == 2
    assert count(doc, ~s([data-seat="0"] [data-role=reveal-compare] [data-seat="1"])) == 1
    assert count(doc, ~s([data-seat="0"] [data-reward=droplet])) == 1
  end

  test "the space slide: coins, VP, and the ruby on the row that landed on one" do
    doc = render_slide(:space)
    assert count(doc, ~s([data-seat="0"] [data-role=reveal-ruby-landing])) == 1
    assert count(doc, ~s([data-seat="1"] [data-role=reveal-ruby-landing])) == 0
    assert count(doc, "[data-role=reveal-coins] [data-icon=coin]") == 2
  end

  test "the overlay is full screen on phones" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
    assert css =~ ~r/@media \(width < 40rem\) \{\s+\.sheet\.reveal-sheet \{\s+inset: 0;/
  end
end
