defmodule QuacksWeb.Round37BoardTest do
  @moduledoc """
  Round 37 (board): the crow skull's choice explained in the bar, the value
  badge of a large chip, the scoring ring that shrinks and grows on a draw, and
  the spoon (index 53) that no chip covers.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.Game
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias QuacksWeb.{ChipComponents, GameComponents}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("r37-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  defp blue(id, pending),
    do: replace_game(id, &H.put(&1, phase: :blue_choice, pending: pending))

  describe "item 6: the crow skull's choice" do
    # Round 40 moved the hint to the info row and made the chips one size
    # (`crow_skull_choice_test.exs`).
    test "the drawn chips lie on a cloth" do
      {id, view} = solo()
      blue(id, [{:orange, 1}, {:white, 3}, {:yellow, 1}, {:blue, 2}])

      row = "footer section[data-role=bar-blue]"
      assert has_element?(view, "#{row} [data-role=blue-tray] [data-role=blue-cloth]")
      assert view |> render() |> count("#{row} [data-role=blue-tray] button[data-pool-chip]") == 4
    end

    test "as the row leaves, the cloth and hint fade but the chips fly" do
      css = File.read!("assets/css/app.css")
      assert css =~ ".bar-to-bag [data-role=info-row],"
      assert css =~ ".bar-to-bag [data-role=blue-cloth] {"
      assert css =~ ".blue-cloth {"
    end
  end

  describe "item 7: the value badge at every chip size" do
    test "each size with a badge places and sizes it" do
      for {size, class} <- [sm: "size-4", md: "size-[18px]", lg: "size-5"] do
        html = render_component(&ChipComponents.chip/1, chip: {:white, 3}, size: size)

        [badge] =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("[data-role=chip-value]")
          |> Enum.to_list()

        classes = badge |> LazyHTML.attribute("class") |> hd() |> String.split()
        assert class in classes, "#{size}: #{inspect(classes)}"
        assert Enum.any?(classes, &String.contains?(&1, "-bottom-")), "#{size} is not placed"
      end
    end
  end

  describe "item 9: the scoring ring on a draw" do
    test "the old marks shrink and fade, the new ones grow and fade in after the landing" do
      js = File.read!("assets/js/app.js")

      # round 39: the flight sets the wait; `updated` moves the marks
      assert js =~ "this.wait = 460"
      refute js =~ "scoringPulse"
      assert js =~ "[{scale: 1, opacity: 1}, {scale: 0.85, opacity: 0}]"
      assert js =~ "[{scale: 0.85, opacity: 0}, {scale: 1, opacity: 1}]"
      assert js =~ "delay: after"
      # the old marks are copied before the patch (`snapshot` in beforeUpdate)
      assert js =~ "this.oldMarks = this.marks()"
    end
  end

  describe "item 13: the spoon is not a space" do
    defp pot(game), do: render_component(&GameComponents.pot/1, game: game)

    defp spoon(html),
      do: html |> LazyHTML.from_fragment() |> LazyHTML.query("g[data-space='53']")

    test "no disc on the spoon, but its coins and VP show" do
      game = Game.new(seed: {1, 2, 3}, rules: %{fortune: false})
      html = spoon(pot(game))

      assert LazyHTML.attribute(html, "data-spoon") == ["true"]
      assert html |> LazyHTML.query("circle[r='22']") |> Enum.empty?()
      assert html |> LazyHTML.text() =~ "35"
      assert html |> LazyHTML.query("[data-role=vp-tag]") |> LazyHTML.text() =~ "15"

      other =
        pot(game)
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("g[data-space='52'] circle[r='22']")

      refute Enum.empty?(other)
    end

    test "a chip on the last space (52) rings the spoon as the scoring space" do
      game = Game.new(seed: {1, 2, 3}, rules: %{fortune: false})
      game = H.put(game, drawn: [{{:orange, 1}, 52}], pot_index: 52)
      html = spoon(pot(game))

      assert html |> LazyHTML.query("[data-role=scoring-ring]") |> Enum.count() == 1
      assert html |> LazyHTML.query("[data-role=next-space]") |> Enum.count() == 1
      assert html |> LazyHTML.query("[data-role=pot-chip]") |> Enum.empty?()
    end
  end

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
end
