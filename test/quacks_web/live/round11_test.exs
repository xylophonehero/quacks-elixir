defmodule QuacksWeb.Round11Test do
  @moduledoc """
  Round 11 playtest fixes: the pot never moves (no status line, no ring legend, no
  flask hint), Stop and Draw in the context column from 64rem, hotkeys, the round's
  moving parts in the context column (Take a Chance, the results, Mandrake, the
  droplet's cause), the shop bar flush at the sheet's foot, and one grid with named
  areas.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers, as: H

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp token(name), do: "#{name}-#{System.unique_integer()}"

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

  defp key(view, key, meta \\ %{}),
    do: view |> element("#game") |> render_keydown(Map.put(meta, "key", key))

  defp drawn(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    length(game.players[0].drawn)
  end

  describe "A: nothing above or beside the pot comes and goes" do
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

    test "the name cards reserve the update chips' row" do
      {_id, view} = solo()
      assert has_element?(view, "#players-row.grid-rows-\\[auto_2\\.125rem_2\\.25rem\\]")
    end
  end

  describe "B: Stop and Draw" do
    test "the bar has Draw, Stop and (from 64rem) the flask, with key hints" do
      {_id, view} = solo()
      assert has_element?(view, "[data-role=action-bar] [data-slot=draw] kbd", "D")
      assert has_element?(view, "[data-role=action-bar] [data-slot=stop] kbd", "S")

      assert has_element?(
               view,
               "[data-role=action-bar] [data-slot=flask].max-lg\\:hidden\\! kbd",
               "F"
             )
    end

    test "an exploded pot shows its state where the buttons were (64rem)" do
      {id, view} = solo()
      replace_game(id, &H.put(&1, 0, exploded?: true, phase: :explosion_choice))
      assert has_element?(view, "[data-role=exploded-panel].lg\\:block", "Your pot exploded")
      assert has_element?(view, "[data-role=action-bar].lg\\:hidden")
    end
  end

  describe "C: hotkeys" do
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

    test "Enter takes the only primary button: the shop's Done" do
      {id, view} = solo()
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 0))
      key(view, "Enter")
      {:ok, %{game: game}} = GameServer.get(id)
      refute Game.phase(game, 0) == :shop
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

  describe "D: the context column" do
    test "the fortune teller tops it from 64rem, not under the pot" do
      {_id, view} = solo(%{})
      assert has_element?(view, "[data-role=side-column] > [data-role=fortune-panel].lg\\:flex")
      refute has_element?(view, "[id^=fortune-under-]")
    end

    test "Take a Chance: every seat's roll, one after the other" do
      {id, alice, _bob} = duo()

      replace_game(id, fn g ->
        g
        |> Map.put(:fortune_card, :p12)
        |> Map.update!(
          :log,
          &[{1, {:fortune, :p12, :ruby}}, {0, {:fortune, :p12, {:vp, 2}}} | &1]
        )
      end)

      panel = "[data-role=side-column] > [data-role=chance-panel].lg\\:block"

      assert has_element?(
               alice,
               ~s{#{panel} [data-role=chance-roll][data-seat="0"][data-beat="0"]},
               "You: 2 VP"
             )

      assert has_element?(
               alice,
               ~s{#{panel} [data-role=chance-roll][data-seat="1"][data-beat="2"]},
               "ruby"
             )
    end

    test "Mandrake's Keep sits in the bar's tray (the context column from 64rem) and works" do
      {id, alice, _bob} = duo()

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}])
      end)

      alice |> element("button[data-slot=draw]") |> render_click()

      assert has_element?(
               alice,
               "[data-area=bar] .game-tray [data-role=mandrake-undo] #keep-white"
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
               "[data-role=droplet-choice] [data-role=droplet-sources] [data-role=droplet-cause][aria-label='black 1']"
             )
    end
  end

  test "D2/D3: the bonus dice of the table roll one after the other, then the books" do
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
end
