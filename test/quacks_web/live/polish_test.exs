defmodule QuacksWeb.PolishTest do
  @moduledoc "Polish batch 1: the white fuse, button variants, the action bar and the explosion choice."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Game.Potions
  alias Quacks.Rules.PotTrack
  alias QuacksWeb.{CoreComponents, GameComponents}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(seed) do
    {:ok, id} = GameServer.start(1, seed)
    {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")
    {id, view}
  end

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  test "the fuse meter shows the white total, one notch per point up to the limit" do
    {id, view} = solo({1, 2, 3})
    assert has_element?(view, ~s(#fuse-meter[data-white="0"][data-limit="7"]), "White 0 / 7")

    view |> element("button[data-slot=draw]") |> render_click()
    view |> element("button[data-slot=draw]") |> render_click()

    game = game(id)
    white = Game.white_sum(game, 0)
    limit = Potions.explode_above(game, 0)
    html = render(view)

    assert has_element?(view, ~s(#fuse-meter[data-white="#{white}"]), "White #{white} / #{limit}")
    assert count(html, "#fuse-meter .fuse-notch") == limit
    assert count(html, ~s(#fuse-meter .fuse-notch[data-lit="true"])) == min(white, limit)
  end

  test "the fuse turns amber one point before the limit and red at it" do
    game = Game.new(seed: {1, 2, 3})
    level = fn white -> fuse_level(put_in(game.players[0].drawn, whites(white))) end

    assert level.(5) == "safe"
    assert level.(6) == "warn"
    assert level.(7) == "danger"
    assert fuse_level(put_in(game.players[0].exploded?, true)) == "danger"
  end

  test "the bar shows what the next space pays" do
    {id, view} = solo({1, 2, 3})
    space = PotTrack.at(Game.scoring_index(game(id), 0))
    coins = if space.coins == 1, do: "1 coin", else: "#{space.coins} coins"
    assert has_element?(view, "[data-role=next-reward]", "Next: #{coins}")
  end

  test "button variants: primary gold, secondary parchment, ghost text, default for the table" do
    render = fn variant ->
      render_component(&CoreComponents.button/1,
        variant: variant,
        inner_block: [%{inner_block: fn _, _ -> "Go" end}]
      )
    end

    assert render.(:primary) =~ "bg-gold"
    assert render.(:secondary) =~ "bg-parchment-light"
    assert render.(:secondary) =~ "ring-ink/25"
    refute render.(:ghost) =~ "bg-gold"
    assert render.(:ghost) =~ "hover:underline"
    assert render.(nil) =~ "ring-parchment/45"

    for variant <- [nil, :primary, :secondary, :ghost] do
      html = render.(variant)
      assert html =~ "active:scale-[.98]"
      assert html =~ "focus-visible:outline-droplet"
      assert html =~ "disabled:saturate-[.3]"
    end
  end

  test "the explosion choice says how many VP and coins" do
    {id, view} = solo({1, 2, 3})
    explode(view)

    me = game(id).players[0]
    space = PotTrack.at(Player.scoring_index(me))

    assert has_element?(
             view,
             "#decision-explosion_choice [data-role=decision-actions] button",
             "Take VP (+#{space.vp})"
           )

    assert has_element?(
             view,
             "#decision-explosion_choice [data-role=decision-actions] button",
             "Take coins (#{space.coins} to spend)"
           )
  end

  # Draw until the explosion choice opens (the starting bag holds 14 white points).
  defp explode(view) do
    exploded? =
      Enum.reduce_while(1..20, false, fn _, _ ->
        if has_element?(view, "#decision-explosion_choice") do
          {:halt, true}
        else
          view |> element("button[data-slot=draw]") |> render_click()
          {:cont, false}
        end
      end)

    assert exploded?
  end

  defp whites(sum), do: for(i <- 1..sum, do: {{:white, 1}, i})

  defp fuse_level(game) do
    html = render_component(&GameComponents.fuse_meter/1, game: game, seat: 0)

    [level] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#fuse-meter")
      |> LazyHTML.attribute("data-level")

    level
  end
end
