defmodule QuacksWeb.R10UiTest do
  @moduledoc """
  Round 10 rendering: the droplet and each rat tail are full pieces on their own
  spaces, the fortune card is a portrait card, the log lives behind the menu, and
  the name cards show each player's pieces.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.{PanelComponents, PotComponents, TileComponents}

  defp query(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  defp attrs(html, selector, attr), do: html |> query(selector) |> LazyHTML.attribute(attr)

  describe "pot" do
    test "the droplet is a full piece on its space" do
      game = Game.new(seed: {1, 2, 3}, players: 2)
      game = put_in(game.players[0].droplet, 2)

      for size <- [:lg, :sm] do
        html = render_component(&PotComponents.pot/1, game: game, size: size)
        assert count(html, ~s(#droplet-0-#{size}[data-role=droplet][data-index="2"])) == 1
        assert count(html, ~s(#droplet-0-#{size} circle[r="19"])) == 1
      end
    end

    test "one rat piece per rat tail, on each space after the droplet" do
      game = Game.new(seed: {1, 2, 3}, players: 2)
      game = put_in(game.players[1].droplet, 2)
      game = put_in(game.players[1].rat_stone, 3)
      game = put_in(game.players[1].drawn, [{{:white, 1}, 6}])

      for size <- [:lg, :sm] do
        html = render_component(&PotComponents.pot/1, game: game, seat: 1, size: size)
        assert count(html, "[data-role=rat]") == 3
        assert attrs(html, "[data-role=rat]", "data-index") == ~w(3 4 5)
        # Round 35: a rat's id names its space.
        assert attrs(html, "[data-role=rat]", "id") == for(t <- 3..5, do: "rat-1-#{size}-#{t}")
        # The first chip lands after the last rat.
        assert attrs(html, "[data-role=pot-chip]", "data-index") == ["6"]
      end
    end

    test "no rat pieces without rat tails" do
      html = render_component(&PotComponents.pot/1, game: Game.new(seed: {1, 2, 3}))
      assert count(html, "[data-role=rat]") == 0
    end
  end

  test "the fortune card and its header tile are portrait cards" do
    html = render_component(&PanelComponents.fortune_card/1, id: :b3)
    assert count(html, "[data-role=fortune-card].card-portrait") == 1

    html = render_component(&PanelComponents.fortune_card/1, id: :b3, flip: true)
    assert count(html, "#card-flip-b3 [data-role=fortune-card].card-portrait") == 1

    html = render_component(&PanelComponents.fortune_tile/1, id: :b3)
    assert count(html, "[data-role=fortune-tile].card-portrait") == 1
    assert count(html, "[data-role=fortune-tile] [data-icon=bag]") == 1
  end

  test "the log is behind the menu, not in the desktop column" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    {:ok, view, _html} = live(init_test_session(build_conn(), player_token: "solo"), ~p"/g/#{id}")

    assert has_element?(view, "#sheet-log[popover]")
    refute has_element?(view, "[data-role=side-column] #sheet-log")
    refute has_element?(view, "#sheet-log.sheet-inline-lg")
    assert has_element?(view, ~s(#sheet-menu button[popovertarget="sheet-log"]), "Log")
    [class] = attrs(render(view), ~s(#sheet-menu button[popovertarget="sheet-log"]), "class")
    refute class =~ "lg:hidden"
  end

  describe "name card" do
    test "shows rubies and the flask" do
      game = Game.new(seed: {1, 2, 3}, players: 2)
      game = put_in(game.players[1].rubies, 3)
      game = put_in(game.players[1].flask, false)
      html = render_component(&TileComponents.player_chip/1, game: game, seat: 1, name: "Bob")

      assert count(html, "[data-role=player-chip] [data-role=player-vp]") == 1
      assert html |> query("[data-role=player-rubies]") |> LazyHTML.text() =~ "3"
      assert count(html, ~s([data-role=player-flask][data-flask="empty"])) == 1
      assert count(html, "[data-role=player-rats]") == 0
      assert count(html, "[data-role=player-essence]") == 0
      assert count(html, "[data-role=player-tube]") == 0
    end

    test "shows rat tails, essence and the test tube when those are in play" do
      game = Game.new(seed: {1, 2, 3}, players: 2, expansions: [:alchemists])
      game = put_in(game.rules.pot_side, :back)
      game = put_in(game.players[1].rat_stone, 4)
      game = put_in(game.players[1].essence, 2)
      game = put_in(game.players[1].tube, 5)
      html = render_component(&TileComponents.player_chip/1, game: game, seat: 1, name: "Bob")

      assert html |> query("[data-role=player-rats]") |> LazyHTML.text() =~ "4"
      assert html |> query("[data-role=player-essence]") |> LazyHTML.text() =~ "2"
      assert html |> query("[data-role=player-tube]") |> LazyHTML.text() =~ "5"
      assert count(html, ~s([data-role=player-flask][data-flask="full"])) == 1
    end
  end
end
