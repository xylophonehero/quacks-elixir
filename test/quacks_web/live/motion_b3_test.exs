defmodule QuacksWeb.MotionB3Test do
  @moduledoc """
  Animation batch 3 (`docs/research/animations.md` §3 B3): what the chip flight hook
  and the opt-in view transition need from the server. The motion itself is WAAPI
  and CSS; these tests check only what the server renders and pushes.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.GameComponents

  defp query(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  defp ids(html, selector), do: html |> query(selector) |> LazyHTML.attribute("id")

  defp mount do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    {:ok, view, _html} = live(init_test_session(build_conn(), player_token: "solo"), ~p"/g/#{id}")
    view
  end

  test "only your large pot carries the hook, the space positions and the ghost layer" do
    game = Game.new(seed: {1, 2, 3}, players: 2)

    lg = render_component(&GameComponents.pot/1, game: game)
    assert ids(lg, "svg[phx-hook=PotMotion]") == ["pot-0-lg"]
    assert ids(lg, "#pot-0-lg > g[data-role=pot-fx][phx-update=ignore]") == ["pot-fx-0"]
    assert Enum.count(query(lg, "[data-space][data-x][data-y]")) == 54
    assert lg |> query(~s([data-space="0"])) |> LazyHTML.attribute("data-x") == ["0.0"]

    sm = render_component(&GameComponents.pot/1, game: game, seat: 1, size: :sm)
    assert Enum.empty?(query(sm, "[phx-hook]"))
    assert Enum.empty?(query(sm, "[data-role=pot-fx], [data-space][data-x]"))
  end

  test "a chip on a space a returned chip left gets a new id, so it lands again" do
    game = Game.new(seed: {1, 2, 3})
    white = {{:white, 2}, 5}
    first = %{game | log: [{0, {:drew, {:white, 2}, 5}} | game.log]}
    first = put_in(first.players[0].drawn, [white])
    html = render_component(&GameComponents.pot/1, game: first)
    assert ids(html, "[data-role=pot-chip]") == ["pot-chip-0-5-1"]

    # the flask puts the white back; the next chip lands on the same space
    again = %{
      first
      | log: [{0, {:drew, {:orange, 1}, 5}}, {0, {:returned, {:white, 2}}} | first.log]
    }

    again = put_in(again.players[0].drawn, [{{:orange, 1}, 5}])
    html = render_component(&GameComponents.pot/1, game: again)
    assert ids(html, "[data-role=pot-chip]") == ["pot-chip-0-5-2"]
    assert has_element_html?(html, ~s(#pot-chip-0-5-2[data-index="5"][data-order="0"]))
  end

  test "a draw keeps the earlier chips' ids; a new chip is the only new id" do
    view = mount()
    view |> element("button[data-slot=draw]") |> render_click()
    before = ids(render(view), "[data-role=pot-chip]")
    view |> element("button[data-slot=draw]") |> render_click()
    later = ids(render(view), "[data-role=pot-chip]")

    assert length(later -- before) == 1
    assert before -- later == []
  end

  test "the round change, and only it, asks for a view transition on the round counter" do
    view = mount()
    assert has_element?(view, ".round-counter[data-role=round-counter]", "1 / 9")

    for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
    refute_push_event(view, "quacks:vt", _)
    view |> element("button", "Stop") |> render_click()
    view |> element("[data-role=shop-done]") |> render_click()

    assert_push_event(view, "quacks:vt", %{})
    assert has_element?(view, "[data-role=round-counter]", "2 / 9")
  end

  test "the CSS names the round counter and (round 22) the card; the hook is small and honours reduced motion" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
    assert css =~ "view-transition-name: round-counter"
    # round 22: the card's name only while a `card` transition runs
    assert css =~ "html:active-view-transition-type(card) .pot-card"
    assert css =~ "view-transition-name: fortune-card"

    js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
    [_, hook] = String.split(js, "// The large pot's motion", parts: 2)
    [hook, _] = String.split(hook, "const csrfToken", parts: 2)
    # the scoring sequence (ruby flights, skip keys, rats in) grew it from 6 000;
    # round 31's draw flight in the top layer to 9 000; round 32's droplet hop and
    # flask fill to 9 500; round 34's move in the pot (green III) to 10 000
    assert byte_size(hook) < 10_000
    assert hook =~ ~s{matchMedia("(prefers-reduced-motion: reduce)")}
    assert js =~ "!reduced()"
  end

  defp has_element_html?(html, selector), do: not Enum.empty?(query(html, selector))
end
