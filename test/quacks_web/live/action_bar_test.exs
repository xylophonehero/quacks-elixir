defmodule QuacksWeb.ActionBarTest do
  @moduledoc """
  The bottom bar: Stop and Draw, the fuse meter, hotkeys, the reward line, the waiting state, the choices in the bar, the free droplet move, Continue, round 9's Stir! and the chips of a choice as controls.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers
  alias Quacks.Game
  alias Quacks.Game.Potions
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.Player
  alias Quacks.Rules.PotTrack
  alias QuacksWeb.ActionCode
  alias QuacksWeb.BarComponents
  alias QuacksWeb.TileComponents

  defp solo(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, rules)
    {id, open(browser(token("solo")), id)}
  end

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    alice = open(browser(token("alice")), id)
    bob = open(browser(token("bob")), id)
    alice |> element("button", "Start game") |> render_click()
    {id, alice, bob}
  end

  defp drawn(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    length(game.players[0].drawn)
  end

  describe "nothing above or beside the pot comes and goes" do
    test "no status line, no rats line, no ring legend, no flask hint" do
      {id, alice, _bob} = duo()
      replace_game(id, &(&1 |> H.put(0, rat_stone: 2)))

      refute has_element?(alice, "[data-role=turn]")
      refute has_element?(alice, "[data-role=round-rats]")
      refute has_element?(alice, "[data-role=ring-legend]")
      refute render(alice) =~ "Everyone brews at the same time."

      alice |> element("button[data-slot=draw]") |> render_click()
      refute has_element?(alice, "[data-role=flask-hint]")
    end

    test "the page is one grid of named areas; the moving parts are absolute" do
      {_id, view} = solo()

      for area <- ~w(header players pot context bar),
          do: assert(has_element?(view, "#game.game-grid > [data-area=#{area}]"))

      assert has_element?(view, "[data-area=pot] .pot-box [data-role=pot-area]")
      assert has_element?(view, "[data-area=bar] .game-tray")

      css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
      assert css =~ ~s{grid-template-areas: "header" "players" "notices" "pot" "bar";}
      assert css =~ "@media (orientation: landscape) and (max-height: 30rem)"
      assert css =~ ~s{"books pot bar";}
    end

    test "the tiles have a fixed height: no update chips" do
      {_id, view} = solo()
      assert has_element?(view, "#players-row [data-role=player-chip].h-\\[3\\.25rem\\]")

      assert has_element?(
               view,
               "[data-role=player-chip] [data-role=player-stats].h-\\[18px\\].overflow-hidden"
             )
    end
  end

  describe "Stop and Draw" do
    test "the bar has Draw, Stop and (from 64rem) the flask, with key hints" do
      {_id, view} = solo()
      assert has_element?(view, "[data-role=action-bar] [data-slot=draw] kbd", "d")
      assert has_element?(view, "[data-role=action-bar] [data-slot=stop] kbd", "s")

      assert has_element?(
               view,
               "[data-role=action-bar] [data-slot=flask].max-lg\\:hidden\\! kbd",
               "f"
             )
    end

    test "an exploded pot shows its state where the buttons were (64rem)" do
      {id, view} = solo()
      replace_game(id, &H.put(&1, 0, exploded?: true, phase: :explosion_choice))
      assert has_element?(view, "[data-role=exploded-panel].lg\\:block", "Your pot exploded")
      # Round 29: the explosion's choice takes the place of the buttons.
      refute has_element?(view, "[data-role=action-bar]")
      assert has_element?(view, "[data-role=bar-explosion]")
    end
  end

  describe "hotkeys" do
    test "d draws, Space draws, s stops" do
      {id, view} = solo()
      key(view, "d")
      assert drawn(id) == 1
      key(view, " ")
      assert drawn(id) == 2
      key(view, "s")
      # Solo: the stop ends the brew, so the round goes on to the shop.
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.phase(game, 0) == :shop
    end

    test "ignored when not legal, while typing, or with a modal open" do
      {id, view} = solo()
      key(view, "d", %{"typing" => true})
      key(view, "d", %{"modal" => true})
      key(view, " ", %{"control" => true})
      key(view, "f")
      key(view, "x")
      assert drawn(id) == 0
      refute render(view) =~ "not allowed"

      # In the shop Draw is not legal: the key does nothing.
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 3))
      key(view, "d")
      assert drawn(id) == 0
    end

    test "a spectator's keys do nothing" do
      {id, _alice, _bob} = duo()
      watcher = open(browser(token("watcher")), id)
      key(watcher, "d")
      assert drawn(id) == 0
    end

    test "app.js sends where the focus is with each keydown" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ "keydown: e => ({"
      assert js =~ ~s{modal: !!document.querySelector("dialog:modal")}
    end
  end

  describe "the context column" do
    test "the fortune teller tops it from 64rem, not under the pot" do
      {_id, view} = solo(%{})
      assert has_element?(view, "[data-role=side-column] > [data-role=fortune-panel].lg\\:flex")
      refute has_element?(view, "[id^=fortune-under-]")
    end

    # Round 39: the old list of rolls is gone; the card's rows show in the results
    # stage (round 36), the one list of what the card did.
    test "Take a Chance: no second list of the rolls in the context column" do
      {id, alice, _bob} = duo()

      replace_game(id, fn g ->
        g
        |> Map.put(:fortune_card, :p12)
        |> Map.update!(
          :log,
          &[{1, {:fortune, :p12, :ruby}}, {0, {:fortune, :p12, {:vp, 2}}} | &1]
        )
      end)

      refute has_element?(alice, "[data-role=chance-panel]")
      refute has_element?(alice, "[data-role=chance-roll]")
    end

    test "Mandrake's Keep sits in the bar's tray (the context column from 64rem) and works" do
      {id, alice, _bob} = duo()

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}])
      end)

      alice |> element("button[data-slot=draw]") |> render_click()

      assert has_element?(
               alice,
               "[data-role=bag-button] ~ [data-role=mandrake-undo] #keep-white"
             )

      alice |> element("#keep-white") |> render_click()
      refute has_element?(alice, "#keep-white")
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.pot_chips(game, 0) == [{:yellow, 1}, {:white, 1}]
    end

    test "the droplet choice shows the chip that caused it" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false, pot_side: :back})
      view = open(browser(token("drop")), id)

      replace_game(id, fn g ->
        g
        |> H.put(0, phase: :droplet_choice, droplet_moves: 1)
        |> Map.update!(:log, &[{0, {:black, :droplet}} | &1])
      end)

      assert has_element?(
               view,
               "#bar-droplet [data-role=info-row] [data-role=droplet-cause][aria-label='black 1']"
             )
    end
  end

  test "the bonus dice of the table roll one after the other, then the books" do
    {id, _alice, _bob} = duo()

    game =
      replace_game(id, fn g ->
        Map.put(g, :log, [
          {1, {:green_rubies, 1}},
          {0, {:green_rubies, 1}},
          {1, {:bonus_die, :ruby}},
          {0, {:bonus_die, {:vp, 1}}},
          {:round_end, 0}
        ])
      end)

    assert [%{kind: :die, beat: 0}, %{kind: :green, beat: 4}] = QuacksWeb.Replay.beats(game, 0)
    assert [%{kind: :die, beat: 2}, %{kind: :green, beat: 4}] = QuacksWeb.Replay.beats(game, 1)
  end

  test "E: the shop's bar sits flush at the sheet's foot" do
    {id, view} = solo()
    replace_game(id, &H.put(&1, 0, phase: :shop, coins: 10))
    assert has_element?(view, "[data-role=shop-footer].sticky.bottom-0")
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
    assert css =~ ~s{.sheet:has([data-role="shop-footer"]) {\n  padding-bottom: 0;}
  end

  defp solo_2 do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("solo-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  describe "the reward line" do
    test "sits beside the white meter and always names the VP" do
      {_id, view} = solo_2()

      # Round 29: one row, the meter then the reward.
      assert has_element?(view, "[data-role=fuse-row] > #fuse-meter + [data-role=reward-line]")
      assert has_element?(view, "[data-role=reward-line].h-7 [data-role=next-reward]", "Reward:")
      assert has_element?(view, "[data-role=next-reward]", "0 VP")
    end

    test "shows the chance that the next draw explodes, 0% when it cannot" do
      {id, view} = solo_2()
      assert has_element?(view, "[data-role=explode-chance][data-percent=\"0\"]", "Explode: 0%")

      # 6 white in the pot, limit 7: the 3-white of two chips explodes (50%).
      replace_game(id, fn g ->
        H.put(g, 0,
          drawn: [{{:white, 3}, 3}, {{:white, 3}, 1}],
          bag: [{:white, 3}, {:orange, 1}],
          starters: []
        )
      end)

      assert has_element?(view, "[data-role=explode-chance][data-percent=\"50\"]", "Explode: 50%")

      replace_game(id, &H.put(&1, 0, phase: :stopped))
      assert has_element?(view, "[data-role=explode-chance][data-percent=\"0\"]")
    end
  end

  describe "the b key" do
    test "toggles the bag sheet; not while typing or with a modal open" do
      {_id, view} = solo_2()
      key(view, "b")
      assert_push_event(view, "quacks:toggle", %{id: "sheet-bag"})
      key(view, "B")
      assert_push_event(view, "quacks:toggle", %{id: "sheet-bag"})

      key(view, "b", %{"typing" => true})
      key(view, "b", %{"modal" => true})
      refute_push_event(view, "quacks:toggle", _, 50)
    end

    test "app.js toggles the popover the server names" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ ~s{window.addEventListener("phx:quacks:toggle"}
      assert js =~ "togglePopover()"
    end

    test "the key hints are lowercase; the bag button names its key" do
      {_id, view} = solo_2()
      assert has_element?(view, "[data-slot=draw] kbd", "d")
      assert has_element?(view, "[data-role=bag-button][aria-keyshortcuts=b]")
    end
  end

  describe "the shop bar" do
    test "fits its sheet: its parts may shrink, Buy's Enter hint needs the room" do
      {id, view} = solo_2()
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 20))
      assert has_element?(view, "[data-role=shop-footer].min-w-0")
      assert has_element?(view, "[data-role=shop-buy].min-w-0")

      view
      |> element("#shop")
      |> render_change(%{"chips" => [QuacksWeb.ActionCode.encode({:orange, 1})]})

      assert has_element?(view, "[data-role=shop-buy].min-w-0 span.truncate", "Buy")

      # Round 35: nothing ticked, Buy stays (disabled); there is no Skip.
      view |> element("#shop") |> render_change(%{"chips" => []})
      assert has_element?(view, "[data-role=shop-buy]:disabled")
    end
  end

  describe "the pot" do
    test "a ruby space has its gem on the lower left, mirroring the VP tag" do
      {_id, view} = solo_2()
      html = render(view)
      assert html =~ ~s(x="-21.5")
      refute html =~ ~s(y="-27")
    end
  end

  describe "Draw" do
    test "the button says Draw, next to Stop" do
      {_id, view} = solo_2()
      assert has_element?(view, "[data-role=action-bar] button[data-slot=draw]", "Draw")
      refute has_element?(view, "button[data-slot=draw]", "a chip")
      assert has_element?(view, "[data-role=action-bar] button[data-slot=stop]", "Stop")
    end
  end

  describe "waiting" do
    test "after Stop the phase pill says Waiting; Draw stays, greyed, with no names" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, alice, _} = live(browser("alice"), ~p"/g/#{id}")
      {:ok, _bob, _} = live(browser("bob"), ~p"/g/#{id}")
      {:ok, _} = GameServer.begin(id, "alice")

      alice |> element("button[data-slot=draw]") |> render_click()
      alice |> element("button[data-slot=stop]") |> render_click()

      assert has_element?(alice, "header dd", "Waiting")
      assert has_element?(alice, "button[data-slot=draw][disabled]", "Draw")
      refute has_element?(alice, "button[data-slot=draw]", "bob")
    end
  end

  describe "the shop's Skip" do
    test "nothing ticked: Buy is the one button, disabled; ticked: Buy" do
      {id, view} = solo_2()
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 20))

      assert has_element?(view, "[data-role=shop-buy].flex-1:disabled", "Buy")
      refute has_element?(view, "[data-role=shop-done]")

      view
      |> element("#shop")
      |> render_change(%{"chips" => [ActionCode.encode({:orange, 1})]})

      assert has_element?(view, "[data-role=shop-buy]:not(:disabled)", "Buy 1")
      refute has_element?(view, "[data-role=shop-done]")
    end
  end

  describe "reward and risk beside the white meter" do
    test "icons for coins, VP, ruby and the risk; the menu's Risk picks Percent, Chips or Off" do
      {id, view} = solo_2()

      # 6 white in the pot, limit 7: the 3-white of two chips explodes.
      replace_game(id, fn g ->
        H.put(g, 0,
          drawn: [{{:white, 3}, 3}, {{:white, 3}, 1}],
          bag: [{:white, 3}, {:orange, 1}],
          starters: []
        )
      end)

      row = "[data-role=fuse-row] > [data-role=reward-line]"
      assert has_element?(view, "#{row} [data-role=reward-coins] use[href='#icon-coin']")
      assert has_element?(view, "#{row} [data-role=reward-vp] use[href='#icon-vp']")
      assert has_element?(view, "#{row} [data-role=explode-chance] use[href='#icon-explosion']")

      # Default: Percent.
      assert has_element?(view, "input#reveal-risk-percent[checked]")
      assert has_element?(view, "[data-role=explode-chance]", "50%")

      view |> element("#reveal-settings") |> render_change(%{"risk" => "chips"})
      assert has_element?(view, "[data-role=explode-chance]", "1/2")
      refute has_element?(view, "[data-role=explode-chance]", "%")

      view |> element("#reveal-settings") |> render_change(%{"risk" => "off"})
      refute has_element?(view, "[data-role=explode-chance]")
      assert has_element?(view, "[data-role=reward-vp]")
    end

    test "app.js keeps the risk in this browser" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ ~s{localStorage.setItem("quacks:risk"}
    end
  end

  describe "the explosion's beat and choice in the bar" do
    test "BOOM over the pot, then Take VP / Take coins where Stop and Draw were; no sheet" do
      {id, view} = solo_2()
      replace_game(id, &H.put(&1, 0, phase: :explosion_choice, exploded?: true))

      assert has_element?(view, "[data-role=pot-area] #boom-1.boom[phx-hook=Boom]", "BOOM")
      refute has_element?(view, "dialog#decision-explosion_choice")
      refute has_element?(view, "[data-role=decision-button]")
      refute has_element?(view, "[data-role=action-bar]")

      bar = "[data-role=bar-explosion].bar-choice-late"
      assert has_element?(view, "#{bar} button[data-choice=vp] use[href='#icon-vp']")
      assert has_element?(view, "#{bar} button[data-choice=buy] use[href='#icon-coin']")
      assert has_element?(view, "#{bar} button[data-choice=vp]", "Score now, no coins")
      assert has_element?(view, "#{bar} button[data-choice=buy]", "Shop, no VP")

      view |> element("#{bar} button[data-choice=vp]") |> render_click()
      refute has_element?(view, "[data-role=bar-explosion]")

      assert GameServer.get(id)
             |> elem(1)
             |> Map.fetch!(:game)
             |> then(& &1.players[0].explosion_choice) == :vp
    end

    test "app.js buzzes only in the Boom hook, guarded" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert length(String.split(js, "navigator.vibrate(")) == 2
      assert js =~ ~s{typeof navigator.vibrate === "function"}
      assert js =~ "navigator.vibrate([40, 30, 90])"
    end
  end

  describe "the ruby choice in the bar" do
    test "Skip, test tube, flask, pot in one row; each paying button says 2 and the ruby" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false, pot_side: :back})
      {:ok, view, _} = live(browser("r29-rubies"), ~p"/g/#{id}")
      replace_game(id, &H.put(&1, 0, phase: :rubies, coins: 0, rubies: 2, flask: true))
      skip_results(view)

      refute has_element?(view, "dialog#decision-rubies")
      bar = "#bar-rubies.flex"
      # On the tiles the results' stage stays: "Keep" keeps the rubies (round 39).
      assert has_element?(view, "#{bar} > button:nth-child(1)[data-role=rubies-keep]", "Keep")

      assert has_element?(
               view,
               "#{bar} > button:nth-child(2)[data-ruby=tube] use[href='#icon-tube']"
             )

      assert has_element?(
               view,
               "#{bar} > button:nth-child(3)[data-ruby=flask] use[href='#icon-flask']"
             )

      assert has_element?(
               view,
               "#{bar} > button:nth-child(4)[data-ruby=droplet] use[href='#icon-pot']"
             )

      for use <- ~w(tube flask droplet) do
        assert has_element?(view, "#{bar} button[data-ruby=#{use}] use[href='#icon-ruby']")
        assert has_element?(view, "#{bar} button[data-ruby=#{use}]", "2")
      end

      # The flask is full: disabled, and it says why.
      assert has_element?(view, "#{bar} button[data-ruby=flask][disabled]", "Flask full")
      refute has_element?(view, "#{bar} button[data-ruby=droplet][disabled]")

      # Same height as Stop / Draw: the pot does not move.
      assert has_element?(view, "#bar-rubies[class*='*:min-h-12']")

      view |> element("#{bar} button[data-ruby=droplet]") |> render_click()
      refute has_element?(view, "#bar-rubies")
    end

    test "the gold witch's price (G4: 1 ruby) shows on the buttons" do
      {id, view} = solo_2()
      replace_game(id, &H.put(&1, 0, phase: :rubies, coins: 0, rubies: 1, ruby_price: 1))
      skip_results(view)
      assert has_element?(view, "#bar-rubies button[data-ruby=droplet]:not([disabled])", "1")
      refute has_element?(view, "#bar-rubies button[data-ruby=tube]")
    end
  end

  describe "the evaluation steps in the bar" do
    # Two seats brew to the shop: each stops (or answers what it must).
    defp to_shop(id) do
      Enum.find_value(1..120, fn _ ->
        {:ok, %{game: game}} = GameServer.get(id)

        if game.phase == :shopping do
          true
        else
          seat = Enum.find(game.seats, &(Quacks.Game.legal_actions(game, &1) -- [:resume] != []))
          actions = Quacks.Game.legal_actions(game, seat) -- [:resume]
          pick = [:stop, :chip_done, {:explosion_choice, :vp}, :draw]
          {:ok, _} = GameServer.apply(id, seat, Enum.find(pick, hd(actions), &(&1 in actions)))
          nil
        end
      end)
    end

    test "the step's name, Skip and Next sit in the bar; no pill over the pot" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, alice, _} = live(browser("alice-#{id}"), ~p"/g/#{id}")
      {:ok, _bob, _} = live(browser("bob-#{id}"), ~p"/g/#{id}")
      {:ok, _} = GameServer.begin(id, "alice-#{id}")
      {:ok, _} = GameServer.apply(id, 0, :draw)
      {:ok, _} = GameServer.apply(id, 1, :draw)
      to_shop(id)

      render_hook(alice, "reveal_settings", %{
        "mode" => "step",
        "speed" => "normal",
        "phone" => true
      })

      assert has_element?(alice, "footer #tile-stage[data-kind] [data-role=tile-step]")
      assert has_element?(alice, "footer #tile-stage", "Step 1 of")

      assert has_element?(
               alice,
               "footer #tile-stage[class*='*:min-h-12'] button[data-role=tile-next]",
               "Next"
             )

      assert has_element?(alice, "footer #tile-stage button[data-role=tile-skip]", "Skip")
      refute has_element?(alice, "[data-role=pot-area] #tile-stage")
      refute has_element?(alice, "[data-role=decision-button]")

      alice |> element("[data-role=tile-skip]") |> render_click()
      refute has_element?(alice, "#tile-stage")
    end
  end

  defp solo_3(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, rules)
    {:ok, view, _html} = live(browser("r30-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  defp new_card(card) do
    {id, view} = solo_3()

    replace_game(id, fn g ->
      %{g | fortune_card: card, log: [{:fortune_drawn, card} | g.log]}
    end)

    {id, view}
  end

  describe "Continue while the card hovers" do
    test "one Continue takes the place of Stop and Draw; it dismisses the card" do
      {_id, view} = new_card(:b1)

      assert has_element?(view, "button#card-continue[phx-click=card_tap]", "Continue")
      assert has_element?(view, "[data-role=action-bar].hidden")

      view |> element("#card-continue") |> render_click()
      refute has_element?(view, "#pot-card-1")
      refute has_element?(view, "#card-continue")
      refute has_element?(view, "[data-role=action-bar].hidden")
      assert has_element?(view, "[data-role=action-bar] [data-slot=draw]")
    end

    test "the grown corner card shows Continue too; Continue shrinks it" do
      {_id, view} = new_card(:b1)
      view |> element("#card-continue") |> render_click()

      view |> element("#corner-card") |> render_click()
      assert has_element?(view, "#card-continue")
      assert has_element?(view, "[data-role=action-bar].hidden")

      view |> element("#card-continue") |> render_click()
      refute has_element?(view, "#card-continue")
      refute has_element?(view, "[data-role=action-bar].hidden")
    end

    test "Enter does the same" do
      {_id, view} = new_card(:b1)
      render_hook(view, "hotkey", %{"key" => "Enter", "typing" => false})
      refute has_element?(view, "#card-continue")
      refute has_element?(view, "[data-role=action-bar].hidden")
    end
  end

  describe "the reward row keeps its slots" do
    # A game whose scoring space pays a ruby, or not, by moving the droplet.
    defp game_with_ruby(ruby?) do
      g = Game.new(seed: {1, 2, 3}, fortune: false)

      Enum.find_value(0..20, fn d ->
        g = Quacks.GameHelpers.put(g, pot_index: d)
        if PotTrack.at(Game.scoring_index(g, 0)).ruby? == ruby?, do: g
      end)
    end

    test "the ruby slot is always there: dim without a ruby, lit with one" do
      without = render_component(&BarComponents.reward_line/1, game: game_with_ruby(false))
      with = render_component(&BarComponents.reward_line/1, game: game_with_ruby(true))

      assert without =~ ~r/data-role="reward-ruby" data-ruby="false"/
      assert without =~ "opacity-25"
      refute without =~ ">ruby<"
      assert with =~ ~r/data-role="reward-ruby" data-ruby="true"/
      assert with =~ ">ruby<"
    end

    test "the numbers have fixed widths" do
      html = render_component(&BarComponents.reward_line/1, game: game_with_ruby(false))
      assert html =~ "tabular-nums"
      assert html =~ ~s(<span class="min-w-[2ch] text-left">)
      assert html =~ ~s(class="min-w-[4.5ch] text-left")

      chips =
        render_component(&BarComponents.reward_line/1, game: game_with_ruby(false), risk: :chips)

      assert chips =~ ~s(class="min-w-[5ch] text-left")
    end

    test "the tile's pot space and VP and the ruby badge reserve two digits" do
      g = game_with_ruby(false)
      tile = render_component(&TileComponents.player_chip/1, game: g, seat: 0, name: "A")
      assert tile =~ ~r/class="tile-space min-w-\[1.2em\]/
      assert tile =~ ~r/class="min-w-\[1.2em\] pr-px text-right"\s+data-role="vp-number"/

      badge = render_component(&TileComponents.ruby_badge/1, rubies: 3)
      assert badge =~ "min-w-[1.2em]"
    end
  end

  describe "one red explosion icon" do
    test "the bar's risk and an exploded tile use the same red icon" do
      g = Game.new(seed: {1, 2, 3}, fortune: false)
      bar = render_component(&BarComponents.reward_line/1, game: g)
      assert bar =~ ~r/class="text-ruby size-5"[^>]*data-icon="explosion"/

      g = Quacks.GameHelpers.put(g, exploded?: true)
      tile = render_component(&TileComponents.player_chip/1, game: g, seat: 0, name: "A")

      assert tile =~
               ~r/data-state="exploded".*class="text-ruby size-4[^"]*"[^>]*data-icon="explosion"/s

      refute tile =~ "stroke=\"#ffd25a\""
    end
  end

  describe "Continue opens a card's result" do
    # Two players, round 2, Less is More (as in round30_cards_test.exs).
    test "Less is More: Continue opens the result rows, like a tap on the card" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      {:ok, alice, _html} = live(browser("alice-#{id}"), ~p"/g/#{id}")
      {:ok, _bob, _html} = live(browser("bob-#{id}"), ~p"/g/#{id}")
      {:ok, _} = GameServer.begin(id, "alice-#{id}")

      replace_game(id, fn g ->
        [a, b] = g.seats

        g
        |> Quacks.GameHelpers.put(a, bag: List.duplicate({:white, 1}, 5), drawn: [], pending: [])
        |> Quacks.GameHelpers.put(b, bag: List.duplicate({:green, 2}, 5), drawn: [], pending: [])
        |> Quacks.GameHelpers.put(fortune_deck: [:p8], round: 2)
        |> Game.start_round()
      end)

      skip_results(alice)

      # Round 31: the rows show under the grown card over the pot, no sheet; the
      # next Continue shrinks it.
      alice |> element("#card-continue") |> render_click()
      assert has_element?(alice, "#card-stage-2 [data-role=card-reveal-row]", "You")
      refute has_element?(alice, "dialog#reveal-card-2")
      alice |> element("#card-continue") |> render_click()
      refute has_element?(alice, "#pot-card-2")
    end
  end

  defp solo_4(rules) do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, Map.merge(%{fortune: false}, rules))
    {:ok, view, _html} = live(browser("r33-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  describe "the choices in two rows" do
    test "Choices, Choices: one row of chips, no scroll" do
      {id, view} = solo_4(%{})

      replace_game(id, fn g ->
        %{g | phase: :fortune_choice, fortune_card: :p1} |> H.put(0, phase: :fortune_choice)
      end)

      refute has_element?(view, "#bar-card-1 [data-role=choice-grid]")
      refute has_element?(view, "#bar-card-1 .overflow-x-auto")
      assert has_element?(view, "#bar-card-1 button[data-choice=take] .chip-token")
    end

    test "the grid: up to 4 in one row, 5 to 8 in two rows" do
      for {n, cols, rows} <- [{2, 2, 1}, {4, 4, 1}, {5, 3, 2}, {6, 3, 2}, {7, 4, 2}, {8, 4, 2}] do
        html =
          render_component(
            fn assigns ->
              ~H"""
              <QuacksWeb.BarComponents.choice_grid count={@n}>
                <span>x</span>
              </QuacksWeb.BarComponents.choice_grid>
              """
            end,
            n: n
          )

        assert html =~ "grid-cols-#{cols}"
        assert html =~ ~s(data-rows="#{rows}")
      end
    end
  end

  describe "the chip actions in the bar" do
    defp garden_spider do
      {id, view} = solo_4(%{})

      replace_game(id, fn g ->
        %{g | sets: Map.merge(g.sets, %{green: 2})}
        |> H.put(
          phase: :explosion_choice,
          exploded?: true,
          drawn: [{{:green, 1}, 10}, {{:green, 1}, 8}],
          pot_index: 10
        )
        |> H.apply!({:explosion_choice, :buy})
      end)

      {id, view}
    end

    test "no sheet: the info row names the book, the options are chip buttons, then Done" do
      {id, view} = garden_spider()
      bar = "footer [data-role=bar-chip-actions]"

      refute has_element?(view, "dialog#decision-chip_choice")
      refute has_element?(view, "[data-role=decision-button]")
      assert has_element?(view, "#{bar} [data-role=info-row]", "Garden spider: take one")
      # Round 36: the chips are chips to tap.
      assert has_element?(view, "#{bar} button[data-role=chip-option] .chip-token")
      assert has_element?(view, "#{bar} button[data-role=chip-action]", "Done")

      view
      |> element("#{bar} button[data-role=chip-option][aria-label^='Garden spider: take']")
      |> render_click()

      {:ok, %{game: game}} = GameServer.get(id)
      assert Enum.any?(game.log, &match?({0, {:chip, {:gain, _}}}, &1))
    end

    test "the white track's row gives way to the info row" do
      {_id, view} = garden_spider()
      refute has_element?(view, "[data-role=fuse-row]")
    end
  end

  describe "the droplet's free move in the bar" do
    test "the hawkmoth: the info row says what, the two moves are buttons; the strip stays" do
      {id, view} = solo_4(%{pot_side: :back})

      replace_game(id, fn g ->
        g
        |> H.put(droplet_moves: 1)
        |> Map.update!(:log, &[{0, {:black, :droplet_ruby}} | &1])
      end)

      refute has_element?(view, "dialog#decision-droplet_choice")

      assert has_element?(
               view,
               "#bar-droplet [data-role=info-row]",
               "Hawkmoth: droplet +1, +1 ruby"
             )

      assert has_element?(view, "#bar-droplet button[data-choice=pot]", "Pot droplet")
      assert has_element?(view, "#bar-droplet button[data-choice=tube]", "Bonus: 1 ruby")
      assert has_element?(view, "[data-area=tubes] svg[data-role=test-tubes]")

      view |> element("#bar-droplet button[data-choice=pot]") |> render_click()
      refute has_element?(view, "#bar-droplet")
    end
  end

  describe "the test-tube droplet moves along the strip" do
    test "the strip under the pot carries the hook and the glass it shows" do
      {id, view} = solo_4(%{pot_side: :back})
      hook = "#tubes-main[phx-hook='QuacksWeb.PotComponents.TubeDrop']"
      assert has_element?(view, ~s(#{hook}[data-tube="0"]))

      replace_game(id, &H.put(&1, droplet_moves: 1))
      view |> element("#bar-droplet button[data-choice=tube]") |> render_click()
      assert has_element?(view, ~s(#{hook}[data-tube="1"] [data-role=tube-droplet]))
    end

    test "the hook animates `translate` with WAAPI and does nothing with reduced motion" do
      src = File.read!("lib/quacks_web/components/pot_components.ex")
      [hook] = Regex.run(~r/name=".TubeDrop">(.*?)<\/script>/s, src, capture: :all_but_first)
      assert hook =~ "d.animate("
      assert hook =~ "translate"
      assert hook =~ ~s[matchMedia("(prefers-reduced-motion: reduce)").matches) return]
    end
  end

  describe "the sweep" do
    test "the Mandrake's choice is in the bar: Back to bag and Keep" do
      {id, view} = solo_4(%{})
      replace_game(id, &H.put(&1, phase: :yellow_choice))

      bar = "footer #bar-pick-yellow_choice"
      refute has_element?(view, "dialog#decision-yellow_choice")
      assert has_element?(view, "#{bar} [data-role=info-row]", "Mandrake")
      assert has_element?(view, "#{bar} button[aria-label^='Mandrake: put']", "Back to bag")
      assert has_element?(view, "#{bar} button[aria-label^='Mandrake: keep']", "Keep")
    end

    test "the crow skull: chips in the bar" do
      {id, view} = solo_4(%{})
      replace_game(id, &H.put(&1, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))

      assert has_element?(view, "footer [data-role=bar-blue] [data-pool-chip]")
      assert has_element?(view, "[data-role=fuse-row]")
      refute has_element?(view, "dialog#decision-blue_choice")
    end

    test "the shop, the patient and the essence space keep their sheet" do
      {id, view} = solo_4(%{})
      replace_game(id, &H.put(&1, phase: :shop, coins: 10))
      assert has_element?(view, "dialog#decision-shop")
    end
  end

  defp pick(action),
    do: ~s(button[data-role=chip-pick][phx-value-action="#{ActionCode.encode(action)}"])

  test "a seat that exploded and took the VP gets OK, then the rubies; no shop" do
    {id, view} = solo_2()

    replace_game(
      id,
      &H.put(&1, 0, phase: :shop, exploded?: true, explosion_choice: :vp, rubies: 2)
    )

    refute has_element?(view, "dialog#decision-shop")
    # Round 29: the rubies are in the bar, no dialog to open.
    assert has_element?(view, "#bar-rubies")
    render_hook(view, "reveal_close", %{})
    refute_push_event(view, "quacks:open", %{to: "#decision-rubies"})
  end

  test "a seat with no coins to spend skips the shop too; with coins it shops" do
    {id, view} = solo_2()
    replace_game(id, &H.put(&1, 0, phase: :shop, coins: 0, rubies: 2))
    skip_results(view)
    refute has_element?(view, "dialog#decision-shop")
    assert has_element?(view, "#bar-rubies")

    replace_game(id, &H.put(&1, 0, coins: 10))
    assert has_element?(view, "dialog#decision-shop #shop")
    render_hook(view, "reveal_close", %{})
    assert_push_event(view, "quacks:open", %{to: "#decision-shop"})
  end

  test "the crow skull offer: the chips are the buttons; Return all stays text" do
    {id, view} = solo_2()
    replace_game(id, &H.put(&1, 0, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))

    # Round 33: in the bar, the chips are buttons, then Return all (round 35: Skip).
    bar = "[data-role=bar-blue]"
    refute has_element?(view, "dialog#decision-blue_choice")
    place = &~s(#{bar} button[phx-value-action="#{ActionCode.encode({:place, &1})}"])
    assert has_element?(view, "#{place.({:red, 1})} .chip-token")
    assert has_element?(view, place.({:white, 1}))
    assert has_element?(view, "#{bar} button[aria-label^='Crow skull: return all']", "Skip")

    view |> element(place.({:red, 1})) |> render_click()
    {:ok, %{game: game}} = GameServer.get(id)
    assert {:red, 1} in Game.pot_chips(game, 0)
  end

  test "any 2-value chip: one chip per colour, in shop row order" do
    game =
      Game.new(seed: {1, 2, 3}, fortune: false)
      |> H.put(fortune_card: :p1, phase: :fortune_choice)

    game = %{game | phase: :fortune_choice}
    actions = Game.legal_actions(game, 0)

    html =
      render_component(&BarComponents.chip_picks/1,
        actions: actions,
        game: game,
        me: game.players[0]
      )

    chips =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("button[data-role=chip-pick] [aria-label]")
      |> LazyHTML.attribute("aria-label")

    assert chips == ["blue 2", "red 2", "green 2", "black 1"]
    assert count(html, pick({:fortune, {:take, {:green, 2}}})) == 1
    # "Take 3 rubies" has no chip: a text button outside the picks
    assert count(html, "button[data-role=chip-pick]") == 4
  end

  test "toadstool Set 2: one row per chip with Place, Keep and Return" do
    {id, view} = solo_2()

    replace_game(id, fn g ->
      %{g | sets: Map.put(g.sets, :red, 2)} |> H.put(0, phase: :red_choice, pending: [{:red, 2}])
    end)

    bar = "#bar-pick-red_choice"
    assert has_element?(view, "#{bar} [data-role=info-row] [aria-label='red 2']")

    for {kind, text} <- [place: "Place", keep: "Keep", return: "Return"] do
      action = ActionCode.encode({:red, {kind, {:red, 2}}})
      assert has_element?(view, ~s(#{bar} button[phx-value-action="#{action}"]), text)
    end

    refute has_element?(view, "dialog#decision-red_choice")
  end

  defp solo_2(seed) do
    {:ok, id} = GameServer.start(1, seed)
    {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")
    {id, view}
  end

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  # Draw until the explosion choice opens (the starting bag holds 14 white points).
  defp explode(view) do
    exploded? =
      Enum.reduce_while(1..20, false, fn _, _ ->
        if has_element?(view, "[data-role=bar-explosion]") do
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
    html = render_component(&BarComponents.fuse_meter/1, game: game, seat: 0)

    [level] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#fuse-meter")
      |> LazyHTML.attribute("data-level")

    level
  end

  test "the fuse meter shows the white total, one notch per point up to the limit" do
    {id, view} = solo_2({1, 2, 3})
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
    {id, view} = solo_2({1, 2, 3})
    space = PotTrack.at(Game.scoring_index(game(id), 0))
    coins = if space.coins == 1, do: "1 coin", else: "#{space.coins} coins"

    assert has_element?(
             view,
             "[data-role=reward-line] [data-role=next-reward]",
             "Reward: #{coins}"
           )

    assert has_element?(view, "[data-role=next-reward]", "#{space.vp} VP")
  end

  test "the explosion choice says how many VP and coins" do
    {id, view} = solo_2({1, 2, 3})
    explode(view)

    me = game(id).players[0]
    space = PotTrack.at(Player.scoring_index(me))

    # Round 29: in the bar, not a sheet.
    assert has_element?(
             view,
             "[data-role=bar-explosion] button[data-choice=vp]",
             "Take VP +#{space.vp}"
           )

    assert has_element?(
             view,
             "[data-role=bar-explosion] button[data-choice=buy]",
             "Take coins #{space.coins}"
           )
  end

  # Take a seat from a page that closes at once (a browser that lost its cookie
  # afterwards): the seat stays, but no page holds it.

  test "a droplet move says so in the status line and on the seat" do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    alice = open(browser(token("alice")), id)
    bob = open(browser(token("bob")), id)
    alice |> element("button", "Start game") |> render_click()

    replace_game(id, &H.put(&1, 0, droplet_moves: 1))

    refute has_element?(alice, "[data-role=turn]")

    assert has_element?(
             bob,
             ~s([data-role=player-chip][data-seat="0"] [data-role=player-state][data-state=droplet])
           )
  end

  defp duo_2(rules) do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, rules)
    alice = open(browser("alice-#{id}"), id)
    bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {id, alice, bob}
  end

  describe "rubies last, the free droplet move" do
    test "the droplet choice says the move is free and where it came from" do
      {id, alice, _bob} = duo_2(%{fortune: false, pot_side: :back})

      replace_game(id, fn g ->
        g
        |> H.put(0, phase: :buy, coins: 10, rubies: 4, droplet_moves: 1)
        |> Map.update!(:log, &[{0, {:black, :droplet}}, {0, {:bonus_die, :droplet}} | &1])
      end)

      render_click(alice, "seen", %{"kind" => "results", "round" => 1})
      # Round 33: the bar's info row names the causes; the moves are buttons.
      assert has_element?(alice, "#bar-droplet [data-role=info-row]", "Move your pot droplet")
      assert has_element?(alice, "[data-role=droplet-sources]", "Hawkmoth: droplet +1")
      assert has_element?(alice, "[data-role=droplet-sources]", "Bonus die")

      # the droplet first, then the buy, then the rubies
      render_click(alice, "action", %{"action" => QuacksWeb.ActionCode.encode({:droplet, :tube})})
      assert has_element?(alice, "dialog#decision-shop")
      refute has_element?(alice, "dialog#decision-rubies")

      render_click(alice, "action", %{"action" => QuacksWeb.ActionCode.encode({:buy, []})})
      # Round 29: the rubies are in the bar.
      assert has_element?(
               alice,
               "#bar-rubies button[data-ruby=tube]:not([disabled])",
               "Test tube"
             )
    end
  end

  # A player detail sheet renders its body once its chip in the players row is tapped.

  # Seed 10,11,12 draws white 2, 3, 1: stop there for a shop with 7 coins.

  # The rest of `to_shop_2/1` after one draw, then "Done" (round over).

  test "the controls sit around the pot; the bottom bar has only Stop and Draw" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{}, :herb_witches)
    view = open(browser("solo"), id)

    assert has_element?(view, "[data-role=pot-area] [data-role=bag-button].right-0.bottom-0")
    # round 22: the card in the pot's top left corner, the witches below it
    refute has_element?(view, "header [data-role=fortune-tile]")

    assert has_element?(
             view,
             "[data-role=pot-area] [data-role=pot-corner].top-0.left-0 #corner-card + [data-role=witches-button]"
           )

    assert has_element?(
             view,
             ~s{[data-role=pot-area] svg [data-role=flask][transform="translate(-222 214)"]}
           )

    html = render(view)
    # Stop, Draw, and the flask button (shown from 64rem only).
    # Round 30: Continue shows while the round's card hovers.
    assert count(html, "footer.game-bar button:not(#card-continue)") == 3
    assert count(html, "footer.game-bar [popovertarget]") == 0
  end

  # A 2-player game without fortune cards, started by alice.
  defp duo_4(seed \\ {1, 2, 3}, rules \\ %{fortune: false}) do
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

  test "a Stir! banner; a pick locks Draw and Stop; no Resume" do
    {id, alice, bob} = duo_4()

    replace_game(id, fn g ->
      g
      |> H.put(round: 9)
      |> H.put(0, bag: [{:orange, 1}, {:orange, 1}])
      |> H.put(1, drawn: [{{:orange, 1}, 2}], pot_index: 2, bag: [{:white, 1}, {:orange, 1}])
    end)

    skip_results(alice)

    for view <- [alice, bob] do
      assert has_element?(view, "[data-role=stir]", "Stir! Everyone draws together.")
    end

    assert state(alice, 0) =~ "deciding"
    alice |> element("button[data-slot=draw]") |> render_click()

    assert has_element?(alice, "button[data-slot=draw][disabled]")
    assert has_element?(alice, "button[data-slot=stop][disabled]")

    refute has_element?(alice, "[data-role=turn]")

    assert state(bob, 0) =~ "chosen"
    assert state(bob, 1) =~ "deciding"

    # bob stops: the step resolves, alice draws again; bob's stop is final
    bob |> element("button", "Stop") |> render_click()
    assert has_element?(alice, "button[data-slot=draw]:not([disabled])")
    refute has_element?(bob, "button", "Resume")
    assert has_element?(bob, "button[data-slot=stop][disabled]", "Stop")
  end
end
