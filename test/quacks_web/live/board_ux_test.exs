defmodule QuacksWeb.BoardUxTest do
  @moduledoc "Seat colours, scoring rings, the flask, the action bar and the round results."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.GameComponents

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp query(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  # A player detail sheet renders its body once its chip in the players row is tapped.
  defp open_player(view, seat),
    do: view |> element(~s([data-role=player-chip][data-seat="#{seat}"])) |> render_click()

  test "each seat has its colour on the cards, the lines and the rings" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    _bob = open(browser("bob"), id)
    {:ok, _} = GameServer.begin(id, "alice")

    open_player(alice, 1)
    assert has_element?(alice, ~s(article.border-player-1[data-seat="1"]))
    assert has_element?(alice, ~s([data-role=player-chip][data-seat="1"] .bg-player-1))
    # Alice's big pot rings both scoring spaces, each in its seat's colour
    html = render(alice)

    for seat <- [0, 1] do
      [stroke] =
        html
        |> query(~s(div.relative svg [data-role=scoring-ring][data-seat="#{seat}"]))
        |> LazyHTML.attribute("stroke")

      assert stroke == "var(--color-player-#{seat})"
    end
  end

  test "two seats on one scoring space split the ring into two arcs" do
    game = Game.new(seed: {1, 2, 3}, players: 2)
    html = render_component(&GameComponents.pot/1, game: game, rings: %{0 => 5, 1 => 5})

    arcs = query(html, ~s([data-space="5"] [data-role=scoring-ring]))
    assert Enum.count(arcs) == 2
    assert LazyHTML.attribute(arcs, "data-seat") == ["0", "1"]
    assert Enum.all?(LazyHTML.attribute(arcs, "stroke-dasharray"), &(&1 != nil))

    # alone on a space: one full ring, no dashes
    html = render_component(&GameComponents.pot/1, game: game, rings: %{0 => 5, 1 => 9})
    assert count(html, ~s{[data-space="9"] [data-role=scoring-ring]:not([stroke-dasharray])}) == 1
  end

  test "an exploded player gets the badge and a cracked rim" do
    game = Game.new(seed: {1, 2, 3}, players: 2)
    game = put_in(game.players[1].exploded?, true)

    html =
      render_component(&GameComponents.player_card/1, game: game, seat: 1, name: "Bob")

    assert count(html, "[data-role=exploded-badge]") == 1
    assert count(html, ~s(svg[data-exploded="true"] [data-role=cracked-rim])) == 1

    html = render_component(&GameComponents.player_chip/1, game: game, seat: 1, name: "Bob")
    assert count(html, "[data-role=player-state][data-state=exploded]") == 1

    html = render_component(&GameComponents.pot/1, game: game, seat: 0)
    assert count(html, ~s(svg[data-exploded="false"])) == 1
    assert count(html, "[data-role=cracked-rim]") == 0
  end

  test "the flask is a button only while it can be used" do
    game = Game.new(seed: {1, 2, 3})

    html = render_component(&GameComponents.pot/1, game: game, flask: :full)
    assert count(html, ~s([data-role=flask][data-usable="false"][role=img])) == 1
    assert count(html, "[data-role=flask][phx-click]") == 0

    html =
      render_component(&GameComponents.pot/1, game: game, flask: :full, flask_click: "abc")

    assert count(
             html,
             ~s([data-role=flask][data-usable="true"][role=button][phx-click=action][phx-value-action=abc][aria-label])
           ) == 1

    # other players' pots draw no flask
    assert render_component(&GameComponents.pot/1, game: game, size: :sm)
           |> count("[data-role=flask]") == 0
  end

  test "the action bar keeps its Stop and Draw slots, disabled when not legal" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = open(browser("solo"), id)

    assert has_element?(view, "[data-role=action-bar] button[data-slot=stop][disabled]", "Stop")
    assert has_element?(view, "[data-role=action-bar] button[data-slot=draw]:not([disabled])")
    refute has_element?(view, "button", "Use flask")

    for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
    view |> element("button", "Stop") |> render_click()

    # while everyone shops the bar goes (QA V4: the shop has its own buttons)
    assert has_element?(view, "dd", "Shop")
    refute has_element?(view, "[data-role=action-bar]")
  end

  test "the round results: the reveal overlay, then lines in the card's sheet, from the shop to the round end" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = open(browser("solo"), id)
    refute has_element?(view, "#reveal-results-1")
    refute has_element?(view, "#round-results")

    for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
    view |> element("button", "Stop") |> render_click()

    # Round 12: no update chips on the card; round 14: the reveal overlay ends the replay.
    refute has_element?(view, "[data-role=update-chip]")
    assert has_element?(view, "dialog#reveal-results-1")
    render_hook(view, "reveal_close", %{})

    view |> element(~s([data-role=player-chip][data-seat="0"])) |> render_click()
    assert has_element?(view, "#sheet-player-0 [data-role=round-results]", "Round 1 results")
    assert has_element?(view, "#sheet-player-0 [data-role=result-line]", "Bonus die:")
    assert has_element?(view, "#sheet-player-0 [data-role=result-total]", ~r/Total: \+\d+ VP/)

    # with one ruby there is nothing left to do after the buy: the round ends at once
    view |> element("[data-role=shop-done]") |> render_click()
    refute has_element?(view, "#reveal-results-1")
    refute has_element?(view, "#sheet-player-0 [data-role=round-results]")
  end
end
