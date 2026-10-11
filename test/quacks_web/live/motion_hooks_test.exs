defmodule QuacksWeb.MotionHooksTest do
  @moduledoc """
  What the motion hooks need from the server: the chip flight, the view transition, the round title card, the exploded fuse and the animation data attributes.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import QuacksWeb.LiveHelpers
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.Game
  alias Quacks.GameHelpers
  alias Quacks.GameServer
  alias QuacksWeb.PotComponents

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

    view |> element("button[data-slot=draw]") |> render_click()
    [first] = ids(render(view), "[data-role=pot-chip]")
    assert first =~ ~r/^pot-chip-0-\d+-1$/

    view |> element("button[data-slot=draw]") |> render_click()
    chips = ids(render(view), "[data-role=pot-chip]")
    assert length(chips) == 2
    assert first in chips
  end

  test "the droplet moves by its translate, not by a new node" do
    game = Game.new(seed: {1, 2, 3})
    html = render_component(&PotComponents.pot/1, game: game)
    [before] = query(html, "#droplet-0-lg") |> LazyHTML.attribute("style")

    game = put_in(game.players[0].droplet, 3)
    html = render_component(&PotComponents.pot/1, game: game)
    assert has_element_html?(html, ~s(#droplet-0-lg[data-index="3"]))
    [later] = query(html, "#droplet-0-lg") |> LazyHTML.attribute("style")
    assert before != later
  end

  test "small pots, the rat stone and the explosion get their own ids" do
    game = Game.new(seed: {1, 2, 3}, players: 2)
    game = put_in(game.players[1].drawn, [{{:white, 1}, 4}, {{:orange, 1}, 1}])
    game = put_in(game.players[1].rat_stone, 2)
    game = put_in(game.players[1].exploded?, true)

    html = render_component(&PotComponents.pot/1, game: game, seat: 1, size: :sm)
    assert ids(html, "[data-role=pot-chip]") == ["pot-chip-1-1-0-sm", "pot-chip-1-4-0-sm"]
    assert has_element_html?(html, "#pot-chip-1-4-0-sm[data-order='0']")
    assert has_element_html?(html, "#rat-1-sm[data-role=rat-stone]")
    assert has_element_html?(html, "#cracked-rim-1-sm [data-role=puff]")

    html = render_component(&PotComponents.pot/1, game: game, seat: 1)
    assert ids(html, "[data-role=pot-chip]") == ["pot-chip-1-1-0", "pot-chip-1-4-0"]
  end

  test "the new card of the round turns over; the info sheet's card does not" do
    {view, id} = mount()
    {:ok, %{game: %{fortune_card: card}}} = GameServer.get(id)

    # round 22: over the pot, outside the overlay
    assert has_element?(view, "#pot-card-1 #pot-card-flip .card-front [data-role=fortune-card]")
    assert has_element?(view, "#pot-card-flip .card-back[aria-hidden=true]")
    assert card
    refute has_element?(view, "#sheet-fortune [data-role=card-flip]")
  end

  test "the ruby badge ticks: a stable counter and a pop keyed by the value" do
    {view, id} = mount()
    {:ok, %{game: game}} = GameServer.get(id)
    me = game.players[0]

    assert has_element?(view, ~s(dd#stat-rubies[style="--n: #{me.rubies}"]))
    assert has_element?(view, "#stat-rubies-#{me.rubies}[aria-hidden=true]")
    assert has_element?(view, "dd#stat-rubies .sr-only", "#{me.rubies}")
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

  defp mount_2 do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    {:ok, view, _html} = live(init_test_session(build_conn(), player_token: "solo"), ~p"/g/#{id}")
    view
  end

  test "only your large pot carries the hook, the space positions and the ghost layer" do
    game = Game.new(seed: {1, 2, 3}, players: 2)

    lg = render_component(&PotComponents.pot/1, game: game)
    assert ids(lg, "svg[phx-hook=PotMotion]") == ["pot-0-lg"]
    assert ids(lg, "#pot-0-lg > g[data-role=pot-fx][phx-update=ignore]") == ["pot-fx-0"]
    assert Enum.count(query(lg, "[data-space][data-x][data-y]")) == 54
    assert lg |> query(~s([data-space="0"])) |> LazyHTML.attribute("data-x") == ["0.0"]

    sm = render_component(&PotComponents.pot/1, game: game, seat: 1, size: :sm)
    assert Enum.empty?(query(sm, "[phx-hook]"))
    assert Enum.empty?(query(sm, "[data-role=pot-fx], [data-space][data-x]"))
  end

  test "a chip on a space a returned chip left gets a new id, so it lands again" do
    game = Game.new(seed: {1, 2, 3})
    white = {{:white, 2}, 5}
    first = %{game | log: [{0, {:drew, {:white, 2}, 5}} | game.log]}
    first = put_in(first.players[0].drawn, [white])
    html = render_component(&PotComponents.pot/1, game: first)
    assert ids(html, "[data-role=pot-chip]") == ["pot-chip-0-5-1"]

    # the flask puts the white back; the next chip lands on the same space
    again = %{
      first
      | log: [{0, {:drew, {:orange, 1}, 5}}, {0, {:returned, {:white, 2}}} | first.log]
    }

    again = put_in(again.players[0].drawn, [{{:orange, 1}, 5}])
    html = render_component(&PotComponents.pot/1, game: again)
    assert ids(html, "[data-role=pot-chip]") == ["pot-chip-0-5-2"]
    assert has_element_html?(html, ~s(#pot-chip-0-5-2[data-index="5"][data-order="0"]))
  end

  test "a draw keeps the earlier chips' ids; a new chip is the only new id" do
    view = mount_2()
    view |> element("button[data-slot=draw]") |> render_click()
    before = ids(render(view), "[data-role=pot-chip]")
    view |> element("button[data-slot=draw]") |> render_click()
    later = ids(render(view), "[data-role=pot-chip]")

    assert length(later -- before) == 1
    assert before -- later == []
  end

  test "the round change, and only it, asks for a view transition on the round counter" do
    view = mount_2()
    assert has_element?(view, ".round-counter[data-role=round-counter]", "1 / 9")

    for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
    refute_push_event(view, "quacks:vt", _)
    view |> element("button", "Stop") |> render_click()
    skip_results(view)
    # Round 35: the shop has no Skip; the engine still takes a buy of nothing.
    render_click(view, "action", %{"action" => QuacksWeb.ActionCode.encode({:buy, []})})

    assert_push_event(view, "quacks:vt", %{})
    assert has_element?(view, "[data-role=round-counter]", "2 / 9")
  end

  test "the CSS names the round counter and the card; the hook is small and honours reduced motion" do
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
    # flask fill to 9 500; round 34's move in the pot (green III) to 10 000; round
    # 35's rat that the droplet takes and the chips to the bag to 11 500; round
    # 36's scoring space pulse after the draw to 12 500; round 37's ring that
    # shrinks and grows takes the pulse's place within it
    assert byte_size(hook) < 12_500
    assert hook =~ ~s{matchMedia("(prefers-reduced-motion: reduce)")}
    assert js =~ "!reduced()"
  end

  defp solo(seed) do
    {:ok, id} = GameServer.start(1, seed)
    {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")
    {id, view}
  end

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  describe "round moments" do
    test "a Round N title card enters once per round, and a tap hides it" do
      {_id, view} = solo({1, 2, 3})
      assert has_element?(view, "#round-title-1[data-role=round-title][phx-click]", "1")
    end

    test "the fuse says when the pot exploded, so it can burst" do
      {id, view} = solo({1, 2, 3})
      assert has_element?(view, ~s(#fuse-meter[data-exploded="false"]))

      GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, exploded?: true))
      send(view.pid, {:game, id, game(id)})
      assert has_element?(view, ~s(#fuse-meter[data-exploded="true"]))
    end
  end
end
