defmodule QuacksWeb.UiRound3Test do
  @moduledoc """
  The board from Nick's second game: controls around the pot, the players row and
  sheets, the new-card dialog, the bag in the shop, VP tags, the copy link, the
  game-over actions and the shop that ends itself.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer, Player}
  alias Quacks.Rules.{Fortune, PotTrack}
  alias QuacksWeb.{GameComponents, GameLive}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  # A player detail sheet renders its body once its chip in the players row is tapped.
  defp open_player(view, seat),
    do: view |> element(~s([data-role=player-chip][data-seat="#{seat}"])) |> render_click()

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  # Seed 10,11,12 draws white 2, 3, 1: stop there for a shop with 7 coins.
  defp to_shop(view) do
    for _ <- 1..3, do: view |> element("button", "Draw a chip") |> render_click()
    view |> element("button", "Stop") |> render_click()
    view
  end

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    {:ok, _} = GameServer.begin(id, "alice")
    {id, alice, bob}
  end

  test "the controls sit around the pot; the bottom bar has only Stop and Draw" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{}, :herb_witches)
    view = open(browser("solo"), id)

    assert has_element?(view, "[data-role=pot-area] [data-role=bag-button].right-0.bottom-0")
    # phones: the card tile sits in the header row (QA 3, G6), not on the pot's rim
    assert has_element?(view, "header [data-role=fortune-tile].lg\\:hidden")
    refute has_element?(view, "[data-role=pot-area] [data-role=fortune-tile]")
    assert has_element?(view, "[data-role=pot-area] [data-role=witches-button].top-0.left-0")

    assert has_element?(
             view,
             ~s{[data-role=pot-area] svg [data-role=flask][transform="translate(-222 214)"]}
           )

    html = render(view)
    # Stop, Draw, and the flask button (shown from 64rem only).
    assert count(html, "footer.game-bar button") == 3
    assert count(html, "footer.game-bar [popovertarget]") == 0
  end

  test "a new fortune card opens once per round, and not without cards" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = open(browser("solo"), id)
    {:ok, %{game: %{fortune_card: card}}} = GameServer.get(id)

    # round 14: the card shows in the reveal overlay, one slide
    assert has_element?(view, "dialog#reveal-card-1[phx-mounted] [data-kind=card]")

    assert has_element?(
             view,
             "#reveal-card-1 [data-role=fortune-card]",
             Fortune.card(card).name
           )

    assert has_element?(view, "#reveal-card-1 #reveal-next", "Close")
    refute has_element?(view, "#reveal-card-1 #reveal-skip")

    # later renders keep the same overlay: it does not open again
    view |> element("button", "Draw a chip") |> render_click()
    assert count(render(view), "[data-role=reveal]") == 1

    view |> element("#reveal-next") |> render_click()
    refute has_element?(view, "[data-role=reveal]")
    to_shop_rest(view)
    assert has_element?(view, "li", "— Round 1 over —")
    refute has_element?(view, "#reveal-card-1")
    assert has_element?(view, "dialog#reveal-card-2[phx-mounted]")

    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false})
    view = open(browser("solo2"), id)
    refute has_element?(view, "[data-role=reveal]")
    refute has_element?(view, "[data-role=fortune-tile]")
  end

  # The rest of `to_shop/1` after one draw, then "Done" (round over).
  defp to_shop_rest(view) do
    for _ <- 1..2, do: view |> element("button", "Draw a chip") |> render_click()
    view |> element("button", "Stop") |> render_click()
    view |> element("[data-role=shop-done]") |> render_click()
  end

  test "the players row: one chip per seat, yours marked; a tap opens the detail sheet" do
    {_id, alice, _bob} = duo()

    # an outlined pill (seat-colour ring, parchment fill), not a gold button look-alike
    assert has_element?(alice, "[data-role=you-are] .ring-player-0.bg-parchment", "Player 1")
    refute has_element?(alice, "[data-role=you-are] .bg-player-0")
    assert has_element?(alice, "[data-role=my-seat].border-player-0")

    html = render(alice)
    assert count(html, "[data-role=players-row] [data-role=player-chip]") == 2

    assert has_element?(
             alice,
             ~s([data-role=player-chip][data-seat="0"][data-you].ring-player-0),
             "you"
           )

    refute has_element?(alice, ~s([data-role=player-chip][data-seat="1"][data-you]))

    assert has_element?(
             alice,
             ~s([data-role=player-chip][data-seat="1"][popovertarget="sheet-player-1"] [data-role=player-state]),
             "brewing"
           )

    sheet = ~s(#sheet-player-1[popover] article[data-seat="1"])
    # the sheet's body renders only while it is open
    refute has_element?(alice, sheet)
    open_player(alice, 1)
    assert has_element?(alice, "#{sheet} svg[aria-label='Pot track']")
    assert has_element?(alice, "#{sheet} [data-role=player-bag]", "In the bag: 9")
    assert has_element?(alice, "#{sheet} [data-role=player-bag] [aria-label='white 1']")
    assert has_element?(alice, "#{sheet} dt", "Rubies")
    assert has_element?(alice, "#{sheet} dt", "Flask")
  end

  test "the shop shows every chip you own, as counts" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = browser("solo") |> open(id) |> to_shop()

    {:ok, %{game: game}} = GameServer.get(id)
    me = game.players[0]
    # the pot, the bag and any chip the round gave (the bonus die)
    owned = length(Player.pot_chips(me) ++ me.bag)
    assert owned >= 9
    assert has_element?(view, "#decision-shop [data-role=shop-bag]", "Your chips: #{owned}")
    assert has_element?(view, "#decision-shop [data-role=shop-bag] [aria-label='white 1']")
    assert has_element?(view, "#decision-shop [data-role=shop-bag] [data-role=chip-count]", "×4")
  end

  test "every space with VP shows its VP tag, at every screen width" do
    html = render_component(&GameComponents.pot/1, game: Game.new(seed: {1, 2, 3}))
    with_vp = Enum.count(0..PotTrack.last(), &(PotTrack.at(&1).vp > 0))

    assert count(html, "[data-role=vp-tag]") == with_vp
    refute html =~ "hidden sm:inline"
  end

  test "Copy link dispatches quacks:copy with the share link and says Copied" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    view = open(browser("alice"), id)

    [click] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=copy-link]")
      |> LazyHTML.attribute("phx-click")

    assert click =~ "quacks:copy"
    assert click =~ "/g/#{id}"

    assert view |> element("[data-role=copy-link]") |> render_click() =~ "Copied"
    send(view.pid, :uncopied)
    assert has_element?(view, "[data-role=copy-link]", "Copy link")

    # the menu has it too, once the game runs
    _bob = open(browser("bob"), id)
    {:ok, _} = GameServer.begin(id, "alice")
    assert has_element?(view, "#sheet-menu [data-role=copy-link]", "Copy link")
  end

  test "game over: buying power per player, Play again and Return to lobby" do
    game = %{Game.new(seed: {1, 2, 3}, players: 2) | phase: :over}

    game = %{
      game
      | log: [{1, {:final_conversion, 7, 1, 3, 1}}, {0, {:final_conversion, 3, 2}} | game.log]
    }

    game = game |> put_in([Access.key(:players), 0, Access.key(:vp)], 5)
    game = game |> put_in([Access.key(:players), 1, Access.key(:vp)], 2)

    html =
      render_component(&GameLive.game_over/1,
        game: game,
        names: %{0 => "Ann", 1 => "Bo"},
        players: 2
      )

    assert html =~ "Ann wins!"
    assert count(html, ~s([data-role=final-score][data-seat="0"][data-place="1"])) == 1
    assert count(html, ~s([data-seat="0"] [data-role=buying-power])) == 1
    assert html =~ ~r/Final coins and rubies\s*<span[^>]*>\+5</
    assert html =~ ~r/Final coins and rubies\s*<span[^>]*>\+2</
    assert count(html, "button[data-role=play-again][phx-click=play_again]:not([disabled])") == 1
    assert count(html, "button[data-role=return-to-lobby][phx-click=lobby]") == 1

    {_id, alice, _bob} = duo()
    assert {:error, {:live_redirect, %{to: "/"}}} = render_click(alice, "lobby")
  end

  defp buy_orange(view) do
    view
    |> element("#shop")
    |> render_change(%{"chips" => [GameLive.encode({:orange, 1})]})

    view |> element("button[data-role=shop-buy]") |> render_click()
    view
  end

  test "a buy ends the shop when no ruby can be spent; otherwise the rubies step opens" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = browser("solo") |> open(id) |> to_shop() |> buy_orange()
    assert has_element?(view, "li", "— Round 1 over —")

    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{starting_rubies: 3})
    view = browser("rich") |> open(id) |> to_shop()
    # the round results were closed (their close sends "seen")
    render_hook(view, "seen", %{"kind" => "results", "round" => 1})
    view = buy_orange(view)

    refute has_element?(view, "#decision-shop")
    assert has_element?(view, "dialog#decision-rubies[phx-mounted*='quacks:modal']")
    assert has_element?(view, "#decision-rubies [data-role=shop-rubies] button", "droplet +1")
    refute has_element?(view, "#decision-rubies #shop")
    refute has_element?(view, "li", "— Round 1 over —")

    view |> element("#decision-rubies [data-role=rubies-done]", "Keep rubies") |> render_click()
    assert has_element?(view, "li", "— Round 1 over —")
  end
end
