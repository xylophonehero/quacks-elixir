defmodule QuacksWeb.Round31BoardTest do
  @moduledoc """
  Round 31 (board): the 💥 burst for an explosion, the board numbers and the
  VP crown, and the draw flight from the bag to the pot.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.Game
  alias Quacks.Rules.PotTrack
  alias QuacksWeb.Icons

  defp pot_doc do
    game = Game.new(seed: {1, 2, 3})

    (&QuacksWeb.GameComponents.pot/1)
    |> render_component(game: game, seat: game.players |> Map.keys() |> Enum.min())
    |> LazyHTML.from_fragment()
  end

  defp space(doc, index), do: LazyHTML.query(doc, "[data-space='#{index}']")

  # The `{x, y}` of a `translate(x y)`.
  defp xy(transform) do
    [x, y] = Regex.run(~r/translate\(([-\d.]+) ([-\d.]+)\)/, transform, capture: :all_but_first)
    {String.to_float(x), String.to_float(y)}
  end

  describe "the 💥 burst" do
    test "the explosion symbol is our layered burst, not explosion-rays" do
      sprite = render_component(&Icons.sprite/1, %{})
      [symbol] = Regex.run(~r{<symbol id="icon-explosion".*?</symbol>}s, sprite)

      for colour <- ~w(#d6322c #f28a1e #ffd94a), do: assert(symbol =~ colour)
      assert length(Regex.scan(~r/<path/, symbol)) == 3
    end
  end

  describe "board numbers" do
    test "each space number is centred: no hand offsets, central baseline, lining tabular figures" do
      numbers = LazyHTML.query(pot_doc(), "[data-role=space-number]")

      assert Enum.count(numbers) == PotTrack.last() + 1

      for attr <- ~w(x y dy), do: assert(LazyHTML.attribute(numbers, attr) == [])
      assert LazyHTML.attribute(numbers, "dominant-baseline") |> Enum.uniq() == ["central"]
      assert LazyHTML.attribute(numbers, "text-anchor") |> Enum.uniq() == ["middle"]

      for class <- LazyHTML.attribute(numbers, "class"),
          do: assert(class =~ "lining-nums" and class =~ "tabular-nums" and class =~ "font-sans")
    end

    test "the VP is a small crown tag radially outward, not a gold seal" do
      doc = pot_doc()
      index = Enum.find(1..PotTrack.last(), &(PotTrack.at(&1).vp >= 10))
      [transform] = space(doc, index) |> LazyHTML.attribute("transform")

      [tag] =
        space(doc, index)
        |> LazyHTML.query("[data-role=vp-tag]")
        |> LazyHTML.attribute("transform")

      {sx, sy} = xy(transform)
      {tx, ty} = xy(tag)
      # outward: the tag's offset points away from the pot centre
      assert sx * tx + sy * ty > 0
      # clear of the number but on the space's own rim
      assert :math.sqrt(tx * tx + ty * ty) > 15 and :math.sqrt(tx * tx + ty * ty) < 32

      html = LazyHTML.to_html(doc)
      refute html =~ "vp-gold"
      assert space(doc, index) |> LazyHTML.query("[data-role=vp-tag] path") |> Enum.count() == 1
    end

    test "a ruby mark sits radially inward of its number" do
      doc = pot_doc()
      index = Enum.find(1..PotTrack.last(), &PotTrack.at(&1).ruby?)
      [transform] = space(doc, index) |> LazyHTML.attribute("transform")
      [x] = space(doc, index) |> LazyHTML.query("[data-icon=ruby]") |> LazyHTML.attribute("x")
      [y] = space(doc, index) |> LazyHTML.query("[data-icon=ruby]") |> LazyHTML.attribute("y")

      {sx, sy} = xy(transform)
      {rx, ry} = {String.to_float(x) + 7, String.to_float(y) + 7}
      assert sx * rx + sy * ry < 0
    end
  end
end
