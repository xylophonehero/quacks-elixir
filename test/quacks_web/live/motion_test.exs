defmodule QuacksWeb.MotionTest do
  @moduledoc """
  Animation batch 1: the ids and data the CSS motion needs (`docs/research/animations.md`
  §3 B1). The motion itself is CSS; these tests check only what the server renders.
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
    {view, id}
  end

  test "pot chips, the droplet and the pot have fixed ids that hold across draws" do
    {view, _id} = mount()
    assert has_element?(view, "svg#pot-0-lg.pot-lg")
    assert has_element?(view, "#droplet-0-lg[data-role=droplet][style*=translate]")
    assert has_element?(view, "#flask-0[data-role=flask]")

    view |> element("button", "Draw a chip") |> render_click()
    [first] = ids(render(view), "[data-role=pot-chip]")
    assert first =~ ~r/^pot-chip-0-\d+-1$/

    view |> element("button", "Draw a chip") |> render_click()
    chips = ids(render(view), "[data-role=pot-chip]")
    assert length(chips) == 2
    assert first in chips
  end

  test "the droplet moves by its translate, not by a new node" do
    game = Game.new(seed: {1, 2, 3})
    html = render_component(&GameComponents.pot/1, game: game)
    [before] = query(html, "#droplet-0-lg") |> LazyHTML.attribute("style")

    game = put_in(game.players[0].droplet, 3)
    html = render_component(&GameComponents.pot/1, game: game)
    assert has_element_html?(html, ~s(#droplet-0-lg[data-index="3"]))
    [later] = query(html, "#droplet-0-lg") |> LazyHTML.attribute("style")
    assert before != later
  end

  test "small pots, the rat stone and the explosion get their own ids" do
    game = Game.new(seed: {1, 2, 3}, players: 2)
    game = put_in(game.players[1].drawn, [{{:white, 1}, 4}, {{:orange, 1}, 1}])
    game = put_in(game.players[1].rat_stone, 2)
    game = put_in(game.players[1].exploded?, true)

    html = render_component(&GameComponents.pot/1, game: game, seat: 1, size: :sm)
    assert ids(html, "[data-role=pot-chip]") == ["pot-chip-1-1-0-sm", "pot-chip-1-4-0-sm"]
    assert has_element_html?(html, "#pot-chip-1-4-0-sm[data-order='0']")
    assert has_element_html?(html, "#rat-1-sm[data-role=rat-stone]")
    assert has_element_html?(html, "#cracked-rim-1-sm [data-role=puff]")

    html = render_component(&GameComponents.pot/1, game: game, seat: 1)
    assert ids(html, "[data-role=pot-chip]") == ["pot-chip-1-1-0", "pot-chip-1-4-0"]
  end

  test "the new card of the round turns over; the info sheet's card does not" do
    {view, id} = mount()
    {:ok, %{game: %{fortune_card: card}}} = GameServer.get(id)

    assert has_element?(
             view,
             "#card-round-1 #card-flip-#{card} .card-front [data-role=fortune-card]"
           )

    assert has_element?(view, "#card-flip-#{card} .card-back[aria-hidden=true]")
    refute has_element?(view, "#sheet-fortune [data-role=card-flip]")
  end

  test "VP and rubies tick: a stable counter and a pop keyed by the value" do
    {view, id} = mount()
    {:ok, %{game: game}} = GameServer.get(id)
    me = game.players[0]

    assert has_element?(view, ~s(dd#stat-vp[style="--n: #{me.vp}"] #stat-vp-#{me.vp}))
    assert has_element?(view, ~s(dd#stat-rubies[style="--n: #{me.rubies}"]))
    assert has_element?(view, "#stat-rubies-#{me.rubies}[aria-hidden=true]")
    assert has_element?(view, "dd#stat-vp .sr-only", "#{me.vp}")
  end

  test "the CSS has the motion keyframes and a reduced-motion fallback for them" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    for name <- ~w(chip-land pot-shake puff card-flip stat-pop) do
      assert css =~ "@keyframes #{name}"
    end

    [_, reduced] = String.split(css, "/* Reduced motion: fewer and gentler.", parts: 2)
    assert reduced =~ "@media (prefers-reduced-motion: reduce)"
    assert reduced =~ ~s(.pot-lg [data-role="pot-chip"])
    assert reduced =~ ".card-flip-inner"
  end

  defp has_element_html?(html, selector), do: not Enum.empty?(query(html, selector))
end
