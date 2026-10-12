defmodule QuacksWeb.CardRevealTest do
  @moduledoc """
  The fortune card: once per round over the pot, a plain card, a card with a result or a choice for every seat, the corner card that grows back, the card face, every player's chips under a card that draws chips, chip actions on every rung and the install hint.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.Game
  alias Quacks.Game.Fortune
  alias Quacks.GameHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.Rules.Fortune, as: RulesFortune
  alias QuacksWeb.BarComponents
  alias QuacksWeb.CardRevealComponents
  alias QuacksWeb.PanelComponents
  alias QuacksWeb.TileReveal

  defp solo(rules) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, rules)
    {:ok, view, _html} = live(browser("r24-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  # A game with no cards, then a card turns up with `log` entries since it came.
  defp new_card(card, entries) do
    {id, view} = solo(%{fortune: false})

    replace_game(id, fn g ->
      %{g | fortune_card: card, log: entries ++ [{:fortune_drawn, card} | g.log]}
    end)

    {id, view}
  end

  describe "a plain card: no sheet, a tap dismisses it" do
    test "the card hovers with a caption; a tap shrinks it into the corner" do
      {id, view} = new_card(:b1, [])

      assert has_element?(view, "[data-role=pot-area] #pot-card-1.pot-card-reveal")
      assert has_element?(view, "#pot-card-1 [data-role=card-caption]", "Tap to continue")
      assert has_element?(view, "button#card-tap[phx-click=card_tap]")
      refute has_element?(view, "dialog#reveal-card-1")

      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "#pot-card-1")
      refute has_element?(view, "#card-tap")
      assert has_element?(view, "#corner-card")
      assert {:ok, %{seen: %{0 => %{card: 1}}}} = GameServer.get(id)
    end

    test "Enter dismisses it too" do
      {_id, view} = new_card(:b1, [])
      render_hook(view, "hotkey", %{"key" => "Enter", "typing" => false})
      refute has_element?(view, "#pot-card-1")
    end

    test "the caption fades after 2 s; it hides in the card transition" do
      css = File.read!("assets/css/app.css")
      assert css =~ "card-caption-in 300ms ease-out 800ms both,"
      assert css =~ "card-caption-out 400ms ease-out 2800ms forwards;"
      assert css =~ "html:active-view-transition-type(card) .card-caption"
    end
  end

  describe "a card with a result or a choice" do
    # Round 31: no result sheet; the card shrinks and a toast says what it did.
    test "the tap shrinks the card; a toast says what it did" do
      {_id, view} = new_card(:p2, [{0, {:fortune, :p2, :droplet}}])

      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "dialog#reveal-card-1")
      refute has_element?(view, "#pot-card-1")
      assert has_element?(view, "#card-toast-1", "Drop It: Droplet +1")
    end

    # Round 31: the choice is in the bar at once, the card over the pot.
    test "the choice is in the bar; the card stays over the pot until the choice" do
      {id, view} = solo(%{fortune: false})

      replace_game(id, fn g ->
        g |> H.put(fortune_card: :p1, phase: :fortune_choice) |> Map.put(:phase, :fortune_choice)
      end)

      refute has_element?(view, "dialog#card-round-1")
      refute has_element?(view, "#card-tap")
      assert has_element?(view, "#pot-card-1")
      # Round 35: the ruby with its 3 in the chip row.
      assert has_element?(view, "#bar-card-1 [data-choice=rubies]", "3")

      view |> element("#bar-card-1 [data-choice=rubies]") |> render_click()
      # Round 35: the card stays, grown, with what everyone took; Continue shrinks it.
      assert has_element?(view, "#card-stage-1[data-role=card-stage]")
      view |> element("#card-continue") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "#pot-card-1")
      assert {:ok, %{seen: %{0 => %{card: 1}}}} = GameServer.get(id)
    end

    test "a card that draws chips: the card stays over the pot, the trade in the bar" do
      {id, view} = solo(%{fortune: false})

      replace_game(id, fn g ->
        g
        |> H.put(fortune_card: :p13, phase: :fortune_choice, pending: [{:green, 1}])
        |> Map.put(:phase, :fortune_choice)
      end)

      assert has_element?(view, "#pot-card-1")
      refute has_element?(view, "#card-tap")
      assert has_element?(view, "#bar-card-1 [data-choice=upgrade]")
      assert has_element?(view, "#bar-card-1 [data-choice=skip]")
    end
  end

  describe "the corner card grows back" do
    test "a tap on the corner card grows it; a tap shrinks it again" do
      {_id, view} = new_card(:b1, [])
      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})

      view |> element("#corner-card") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      assert has_element?(view, "#pot-card-1.pot-card-reveal [data-role=card-caption]")
      refute has_element?(view, "#reveal-card-1")

      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "#pot-card-1")
    end

    test "the card's text stays in the menu" do
      {_id, view} = new_card(:b1, [])
      refute has_element?(view, "#corner-card[popovertarget]")

      assert has_element?(
               view,
               "#sheet-menu [data-role=menu-fortune][popovertarget=sheet-fortune]"
             )

      assert has_element?(view, "#sheet-fortune [data-role=fortune-card]")
    end
  end

  describe "the rat track" do
    test "the leader's VP shows once above the leader's dot" do
      {:ok, id} = GameServer.start(3, {1, 2, 3}, %{}, %{fortune: false})
      token = "r24-rats-#{System.unique_integer()}"
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      {:ok, _} = GameServer.add_bot(id, token)
      {:ok, _} = GameServer.add_bot(id, token)
      {:ok, _} = GameServer.begin(id, token)

      replace_game(id, fn g ->
        [2, 30, 11]
        |> Enum.with_index()
        |> Enum.reduce(g, fn {vp, s}, g -> H.put(g, s, vp: vp) end)
      end)

      leader = "#rat-track [data-role=leader-vp]"
      assert has_element?(view, leader, "30")
      html = view |> element("#rat-track") |> render()

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-role=leader-vp]")
             |> Enum.count() == 1

      # The leader's step is the first: its x is half a step.
      assert has_element?(view, ~s(#{leader}[style*="0.0385"]))
      # The other dots keep their tooltips.
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='0'][title]")
    end
  end

  describe "chip actions: every rung" do
    # Step B with `pot` in the pot (the explosion's buy path runs the evaluation).
    defp chip_actions(sets, pot, fields \\ []) do
      {id, view} = solo(%{fortune: false})

      replace_game(id, fn g ->
        %{g | sets: Map.merge(g.sets, sets)}
        |> H.put([phase: :explosion_choice, exploded?: true, drawn: pot, pot_index: 10] ++ fields)
        |> H.apply!({:explosion_choice, :buy})
      end)

      play_until(view, "[data-role=bar-chip-actions]")
    end

    # Round 33: the chip actions are a step in the bar (info row + buttons), no sheet.
    test "Ghost's breath II: trade 1 and 2 are buttons, trade 3 is greyed with a reason" do
      view = chip_actions(%{purple: 2}, [{{:purple, 1}, 10}, {{:purple, 1}, 8}])
      bar = "[data-role=bar-chip-actions]"
      refute has_element?(view, "dialog#decision-chip_choice")

      assert has_element?(view, "#{bar} button[data-role=chip-action]:not([disabled])", "Trade 1")
      assert has_element?(view, "#{bar} button[data-role=chip-action]:not([disabled])", "Trade 2")

      off = "#{bar} button[data-role=ladder-rung-off][disabled]"
      assert has_element?(view, off, "Trade 3")
      assert has_element?(view, off, "needs 3 purple")
      assert has_element?(view, "#{off}[aria-label*='needs 3 purple, you have 2']")

      assert has_element?(view, "#{bar} button[data-role=chip-action]", "Done")

      view |> element("#{bar} button[data-role=chip-action]", "Trade 2") |> render_click()
      refute has_element?(view, bar)
    end

    test "Garden spider IV: a rung over the rubies is greyed" do
      view =
        chip_actions(%{green: 4}, [{{:green, 1}, 10}, {{:green, 1}, 8}], rubies: 1)

      bar = "[data-role=bar-chip-actions]"
      assert has_element?(view, "#{bar} button[data-role=chip-action]:not([disabled])", "Pay 1")
      assert has_element?(view, "#{bar} button[data-role=ladder-rung-off]", "needs 2 rubies")
    end

    test "Ghost's breath IV: the tiers the pot does not reach are greyed" do
      view =
        chip_actions(%{purple: 4}, [{{:purple, 1}, 10}, {{:green, 1}, 8}])

      bar = "[data-role=bar-chip-actions]"
      # Round 36: the swaps are taps on the pot chip.
      assert has_element?(view, "#pot-0-lg [data-role=pot-chip][data-target]")
      off = "#{bar} button[data-role=ladder-rung-off]"
      assert has_element?(view, "#{off}[aria-label*='a 2-chip → a 4-chip']")
      assert has_element?(view, off, "needs 3 purple")
    end
  end

  describe "the install hint" do
    test "the lobby has the browser-menu hint, hidden until app.js shows it" do
      conn = browser("r24-install-#{System.unique_integer()}")
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(
               view,
               "#install-app .pwa-menu-hint[data-role=install-menu-hint]",
               "Install from your browser menu: ⋮ → Install app"
             )

      assert has_element?(view, "#install-app .pwa-install[data-role=install]")
      assert has_element?(view, "#install-app .pwa-ios-hint[data-role=install-hint]")
    end

    test "app.js shows it 3 s after load without a prompt; CSS keys it on data-install" do
      js = File.read!("assets/js/app.js")
      assert js =~ ~s{installState("menu")}
      assert js =~ "}, 3000)"
      assert js =~ "!installFired && !standalone"

      css = File.read!("assets/css/app.css")
      assert css =~ ~s{html[data-install="menu"] .pwa-menu-hint {\n  display: block;}
    end
  end

  # Two players, round 2, Less is More turned up: alice draws 5 white 1s (sum 5), bob
  # 5 green 2s (sum 10).
  defp less_is_more do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
    {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
    {:ok, _} = GameServer.begin(id, "alice-#{id}")

    GameHelpers.replace_game(id, fn g ->
      [a, b] = g.seats

      g
      |> GameHelpers.put(a, bag: List.duplicate({:white, 1}, 5), drawn: [], pending: [])
      |> GameHelpers.put(b, bag: List.duplicate({:green, 2}, 5), drawn: [], pending: [])
      |> GameHelpers.put(fortune_deck: [:p8], round: 2)
      |> Game.start_round()
    end)

    skip_results(alice)

    alice
  end

  test "Less is More: after the tap, one row per player, yours first, the lowest sum gold" do
    alice = less_is_more()
    alice |> element("#card-tap") |> render_click()

    # Round 31: the rows show under the grown card over the pot.
    rows = "#card-stage-2 [data-role=card-reveal-row]"
    assert has_element?(alice, rows, "You")
    assert has_element?(alice, "#{rows}:first-child[data-me][data-best]")
    assert has_element?(alice, "#{rows}[data-me] [data-role=reveal-number]", "5")
    assert has_element?(alice, "#{rows}[data-me] [data-gain=chip]")
    assert has_element?(alice, "#{rows}:not([data-me]) [data-role=reveal-number]", "10")
    assert has_element?(alice, "#{rows}:not([data-me]) [data-gain=rubies]")
    refute has_element?(alice, "#{rows}:not([data-me])[data-best]")
    assert has_element?(alice, "#{rows}[data-me] [data-role=reveal-chip]")
  end

  test "Less is More: the fortune sheet shows the same rows" do
    alice = less_is_more()
    assert has_element?(alice, "#sheet-fortune-reveals [data-role=card-reveal-row]")
  end

  test "the tile news shows each player's result once the card is gone" do
    game =
      Game.new(seed: {1, 2, 3}, players: 2, fortune: false)
      |> GameHelpers.put(0, bag: List.duplicate({:white, 1}, 5))
      |> GameHelpers.put(1, bag: List.duplicate({:green, 2}, 5))
      |> GameHelpers.put(fortune_card: :p8)
      |> Fortune.resolve()

    assert %{items: [{:card, :p8, nil, {:blue, 2}}]} = TileReveal.news(game, 0, nil)
    assert %{items: [{:rubies, 1}]} = TileReveal.news(game, 1, nil)
    assert TileReveal.news(game, 0, %{key: {:card, 1}}) == nil
  end

  test "card_reveals/1 fits 8 players: 8 rows, your row first" do
    reveals =
      Map.new(0..7, fn seat ->
        {seat,
         %{
           drew: List.duplicate({:orange, 1}, 5),
           number: 5 + seat,
           traded: nil,
           gains: if(seat == 0, do: [{:chip, {:blue, 2}}], else: [{:rubies, 1}]),
           best?: seat == 0,
           choosing?: false
         }}
      end)

    html =
      render_component(&CardRevealComponents.card_reveals/1,
        id: "r",
        card: :p8,
        reveals: reveals,
        order: Enum.to_list(0..7),
        seat: 3,
        names: Map.new(0..7, &{&1, "P#{&1}"})
      )

    doc = LazyHTML.from_fragment(html)
    rows = LazyHTML.query(doc, "[data-role=card-reveal-row]")
    assert Enum.count(rows) == 8
    assert rows |> Enum.at(0) |> LazyHTML.attribute("data-seat") == ["3"]
    assert doc |> LazyHTML.query("[data-best]") |> LazyHTML.attribute("data-seat") == ["0"]
  end

  test "card_reveals/1 shows nothing under a card that draws no chips" do
    html =
      render_component(&CardRevealComponents.card_reveals/1,
        id: "r",
        card: :p6,
        reveals: %{},
        order: [0, 1],
        seat: 0,
        names: %{}
      )

    refute html =~ "card-reveal-row"
  end

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.

  describe "fortune card" do
    test "every card has a motif in its colour band's card, and a Kalam title" do
      for %{id: id, name: name} <- RulesFortune.all() do
        html = render_component(&PanelComponents.fortune_card/1, id: id)
        assert count(html, "[data-role=fortune-card] [data-role=card-motif][data-motif]") == 1
        assert html |> query("h2.font-hand") |> LazyHTML.text() =~ name
      end
    end

    test "the motif fits the card: a die for Take a Chance, a flask for Cauldron Bubble" do
      motif = fn id ->
        (&PanelComponents.fortune_card/1)
        |> render_component(id: id)
        |> query("[data-role=card-motif]")
        |> LazyHTML.attribute("data-motif")
      end

      assert motif.(:p12) == ["die"]
      assert motif.(:b10) == ["flask"]
      assert motif.(:p1) == ["sparkle"]
    end

    test "the flip keeps its ids; the back carries the pattern" do
      html = render_component(&PanelComponents.fortune_card/1, id: :b7, flip: true)
      assert count(html, "#card-flip-b7 .card-flip-inner .card-back[data-role=card-back]") == 1
      assert count(html, "#card-flip-b7 .card-front [data-role=fortune-card]") == 1
    end
  end

  # Take a seat from a page that closes at once (a browser that lost its cookie
  # afterwards): the seat stays, but no page holds it.

  test "a card's 'take one' chips carry their colour word" do
    game =
      Game.new(seed: {1, 2, 3}, fortune: false)
      |> H.put(fortune_card: :p10, phase: :fortune_choice)

    # Rat-a-Tat: take one 4-chip (or the VP)
    actions = for colour <- [:blue, :red, :yellow], do: {:fortune, {:take, {colour, 4}}}

    html =
      render_component(&BarComponents.chip_picks/1,
        actions: [{:fortune, :vp} | actions],
        game: game,
        me: game.players[0]
      )

    words =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=pick-colour]")
      |> Enum.map(&LazyHTML.text/1)

    assert Enum.map(words, &String.trim/1) == ~w(blue red yellow)
  end

  test "a decision waits for the round's new card, which opens it on close" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser(token("alice")), id)
    _bob = open(browser(token("bob")), id)
    alice |> element("button", "Start game") |> render_click()
    replace_game(id, &H.put(&1, 0, droplet_moves: 1))

    # Round 33: the droplet choice is in the bar; it waits for the card too.
    refute has_element?(alice, "dialog#decision-droplet_choice")
    assert has_element?(alice, "#pot-card-1 [data-role=card-caption]")
    alice |> element("#card-tap") |> render_click()
    assert has_element?(alice, "#bar-droplet button[data-choice=pot]")
  end

  # A player detail sheet renders its body once its chip in the players row is tapped.

  # Seed 10,11,12 draws white 2, 3, 1: stop there for a shop with 7 coins.

  # The rest of `to_shop_2/1` after one draw, then "Done" (round over).
  defp to_shop_rest(view) do
    for _ <- 1..2, do: view |> element("button[data-slot=draw]") |> render_click()
    view |> element("button", "Stop") |> render_click()
    skip_results(view)
    # Round 35: the shop has no Skip; the engine still takes a buy of nothing.
    render_click(view, "action", %{"action" => QuacksWeb.ActionCode.encode({:buy, []})})
  end

  test "a new fortune card opens once per round, and not without cards" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = open(browser("solo"), id)
    {:ok, %{game: %{fortune_card: card}}} = GameServer.get(id)

    # round 22: the card hovers over the pot; round 24: no sheet, a tap goes on
    assert has_element?(
             view,
             "[data-role=pot-area] #pot-card-1 [data-role=fortune-card]",
             RulesFortune.card(card).name
           )

    refute has_element?(view, "[data-role=reveal]")
    assert has_element?(view, "#card-tap")

    # later renders keep the same card: it does not open again
    view |> element("button[data-slot=draw]") |> render_click()
    assert has_element?(view, "#pot-card-1 [data-role=card-caption]")

    view |> element("#card-tap") |> render_click()
    refute has_element?(view, "#card-tap")
    to_shop_rest(view)
    assert has_element?(view, "li", "— Round 1 over —")
    # Round 37: the last round's recap plays before the new card.
    skip_results(view)
    refute has_element?(view, "#pot-card-1")
    assert has_element?(view, "#pot-card-2 [data-role=card-caption]")

    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false})
    view = open(browser("solo2"), id)
    refute has_element?(view, "[data-role=reveal]")
    refute has_element?(view, "[data-role=fortune-tile]")
  end

  # A 2-player game without fortune cards, started by alice.
  defp duo_2(seed, rules) do
    {:ok, id} = GameServer.start(2, seed, %{}, rules)
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    alice |> element("button", "Start game") |> render_click()
    {id, alice, bob}
  end

  defp state(view, seat),
    do:
      view
      |> element(~s([data-role=player-chip][data-seat="#{seat}"] [data-role=player-state]))
      |> render()

  test "a card choice opens for every seat at once; who answered sees who still decides" do
    # seed 86,86,86 with 2 players deals a card with a choice for both seats
    {_id, alice, bob} = duo_2({86, 86, 86}, %{})

    # Round 31: the choice is in each seat's bar, no dialog.
    for view <- [alice, bob] do
      assert has_element?(view, "#bar-card-1 [data-choice=skip]")
      refute has_element?(view, "dialog#card-round-1")
    end

    alice |> element("#bar-card-1 [data-choice=skip]") |> render_click()
    refute has_element?(alice, "#bar-card-1")
    refute has_element?(alice, "[data-role=turn]")
    assert has_element?(bob, "#bar-card-1 [data-choice=skip]")
    assert state(alice, 1) =~ "choosing"
  end
end
