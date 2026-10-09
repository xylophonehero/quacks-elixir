defmodule QuacksWeb.Round30BarTest do
  @moduledoc """
  Round 30 (bar + pot): Continue in the contextual button area while the round's
  card waits over the pot, a reward row that keeps the ruby's slot, fixed number
  widths, and one red explosion icon in the bar and on the tiles.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.{Game, GameServer}
  alias Quacks.Rules.PotTrack
  alias QuacksWeb.GameComponents

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, rules)
    {:ok, view, _html} = live(browser("r30-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  defp new_card(card) do
    {id, view} = solo()

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
      without = render_component(&GameComponents.reward_line/1, game: game_with_ruby(false))
      with = render_component(&GameComponents.reward_line/1, game: game_with_ruby(true))

      assert without =~ ~r/data-role="reward-ruby" data-ruby="false"/
      assert without =~ "opacity-25"
      refute without =~ ">ruby<"
      assert with =~ ~r/data-role="reward-ruby" data-ruby="true"/
      assert with =~ ">ruby<"
    end

    test "the numbers have fixed widths" do
      html = render_component(&GameComponents.reward_line/1, game: game_with_ruby(false))
      assert html =~ "tabular-nums"
      assert html =~ ~s(<span class="min-w-[2ch] text-left">)
      assert html =~ ~s(class="min-w-[4.5ch] text-left")

      chips =
        render_component(&GameComponents.reward_line/1, game: game_with_ruby(false), risk: :chips)

      assert chips =~ ~s(class="min-w-[5ch] text-left")
    end

    test "the tile's pot space and VP and the ruby badge reserve two digits" do
      g = game_with_ruby(false)
      tile = render_component(&GameComponents.player_chip/1, game: g, seat: 0, name: "A")
      assert tile =~ ~r/class="tile-space min-w-\[1.2em\]/
      assert tile =~ ~r/class="min-w-\[1.2em\] text-right"\s+data-role="vp-number"/

      badge = render_component(&GameComponents.ruby_badge/1, rubies: 3)
      assert badge =~ "min-w-[1.2em]"
    end
  end

  describe "one red explosion icon" do
    test "the bar's risk and an exploded tile use the same red icon" do
      g = Game.new(seed: {1, 2, 3}, fortune: false)
      bar = render_component(&GameComponents.reward_line/1, game: g)
      assert bar =~ ~r/class="text-ruby size-5"[^>]*data-icon="explosion"/

      g = Quacks.GameHelpers.put(g, exploded?: true)
      tile = render_component(&GameComponents.player_chip/1, game: g, seat: 0, name: "A")

      assert tile =~
               ~r/data-state="exploded".*class="text-ruby size-5[^"]*"[^>]*data-icon="explosion"/s

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

      # Round 31: the rows show under the grown card over the pot, no sheet; the
      # next Continue shrinks it.
      alice |> element("#card-continue") |> render_click()
      assert has_element?(alice, "#pot-card-reveals-2 [data-role=card-reveal-row]", "You")
      refute has_element?(alice, "dialog#reveal-card-2")
      alice |> element("#card-continue") |> render_click()
      refute has_element?(alice, "#pot-card-2")
    end
  end
end
