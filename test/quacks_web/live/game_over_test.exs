defmodule QuacksWeb.GameOverTest do
  @moduledoc """
  The game-over page: buying power and the chart per player, the winner's title, Play again, Lobby and Share.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.{Game, GameServer}
  alias Quacks.{Game, GameServer}
  alias QuacksWeb.GameText

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.

  describe "game over" do
    defp final_game do
      game = %{Game.new(seed: {1, 2, 3}, players: 4) | phase: :over}

      log = [
        {2, {:pot_vp, 30, 40}},
        {2, {:bonus_die, {:vp, 2}}},
        {2, {:rubies_spent, :vp}},
        {2, {:final_conversion, 10, 2, 2, 1}},
        {0, {:pot_vp, 20, 30}},
        {0, {:essence_vp, 4}},
        {0, {:purple, 3, :vp2_droplet}},
        {1, {:pot_vp, 10, 20}},
        {3, {:pot_vp, 5, 10}}
      ]

      vps = %{0 => 26, 1 => 10, 2 => 40, 3 => 5}

      players =
        Map.new(game.players, fn {seat, p} -> {seat, %{p | vp: vps[seat]}} end)

      %{game | log: log ++ game.log, players: players}
    end

    # Round 31: the score chart over the pot (`FinalComponents.final_board/1`).
    defp render_over(seat, bots \\ %{}) do
      render_component(&QuacksWeb.FinalComponents.final_board/1,
        game: final_game(),
        names: %{0 => "Ann", 1 => "Bo", 2 => "Cy", 3 => "Di"},
        bots: bots,
        seat: seat
      )
    end

    test "the chart lists every seat in final order; the winner's title" do
      html = render_over(0)
      doc = LazyHTML.from_fragment(html)
      rows = LazyHTML.query(doc, "[data-role=final-score]")
      assert LazyHTML.attribute(rows, "data-seat") == ["2", "0", "1", "3"]
      assert LazyHTML.attribute(rows, "data-place") == ["1", "2", "3", "4"]
      # The totals count up from the round-9 VP (Cy: 40 with 3 final VP).
      assert count(html, ~s([data-seat="2"] [data-role=final-vp][data-from="37"])) == 1
      assert html =~ "Cy wins!"
      assert render_over(2) =~ "You win!"
    end

    test "this browser's place has a ring and \"you\"" do
      html = render_over(2)
      assert count(html, ~s([data-role=final-score][data-seat="2"] [data-role=you])) == 1
      assert count(html, "[data-role=you]") == 1
      assert count(html, ~s([data-role=final-score][data-seat="2"].ring-gold)) == 1
      assert count(render_over(nil), "[data-role=you]") == 0

      # The replay viewed from a bot's seat: that seat is "you", not a bot.
      html = render_over(2, %{1 => :balanced, 2 => :balanced})
      assert html =~ "You win!"
      assert count(html, ~s([data-seat="2"] [data-role=bot-badge])) == 0
      assert count(html, ~s([data-seat="1"] [data-role=bot-badge])) == 1

      for {seat, vp} <- final_game() |> Game.score() do
        assert final_game().log
               |> GameText.vp_breakdown(seat, vp)
               |> Enum.map(&elem(&1, 1))
               |> Enum.sum() == vp
      end
    end

    test "the bar: Play again is the primary button, then Lobby and Share" do
      html =
        render_component(&QuacksWeb.FinalComponents.final_actions/1,
          game: final_game(),
          names: %{},
          share_url: "http://x/g/1"
        )

      assert count(html, "button[data-role=play-again]") ==
               1

      assert count(html, "button[data-role=return-to-lobby]") == 1
      assert count(html, "button[data-role=share-result][aria-label]") == 1
    end

    test "solo: the score as the title" do
      game = %{Game.new(seed: {1, 2, 3}) | phase: :over}
      game = %{game | log: [{0, {:pot_vp, 12, 30}} | game.log]}
      game = put_in(game.players[0].vp, 12)

      html = render_component(&QuacksWeb.FinalComponents.final_board/1, game: game, names: %{})
      assert html =~ "victory points"
      assert count(html, "[data-role=final-score]") == 1
    end
  end

  # A player detail sheet renders its body once its chip in the players row is tapped.

  # Seed 10,11,12 draws white 2, 3, 1: stop there for a shop with 7 coins.

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    {:ok, _} = GameServer.begin(id, "alice")
    {id, alice, bob}
  end

  # The rest of `to_shop_2/1` after one draw, then "Done" (round over).

  test "game over: buying power per player, Play again and Return to lobby" do
    game = %{Game.new(seed: {1, 2, 3}, players: 2) | phase: :over}

    game = %{
      game
      | log: [{1, {:final_conversion, 7, 1, 3, 1}}, {0, {:final_conversion, 3, 2}} | game.log]
    }

    game = game |> put_in([Access.key(:players), 0, Access.key(:vp)], 5)
    game = game |> put_in([Access.key(:players), 1, Access.key(:vp)], 2)

    names = %{0 => "Ann", 1 => "Bo"}

    # Round 31: the score chart over the pot, Play again / Lobby in the bar.
    html =
      render_component(&QuacksWeb.FinalComponents.final_board/1, game: game, names: names) <>
        render_component(&QuacksWeb.FinalComponents.final_actions/1, game: game, names: names)

    assert html =~ "Ann wins!"
    assert count(html, ~s([data-role=final-score][data-seat="0"][data-place="1"])) == 1
    # Round 29 (F3): no VP breakdown under the podium.
    assert count(html, "[data-role=buying-power]") == 0
    assert count(html, "button[data-role=play-again][phx-click=play_again]:not([disabled])") == 1
    assert count(html, "button[data-role=return-to-lobby][phx-click=lobby]") == 1

    {_id, alice, _bob} = duo()
    assert {:error, {:live_redirect, %{to: "/"}}} = render_click(alice, "lobby")
  end

  # A 2-player game without fortune cards, started by alice.
  defp duo_2(seed \\ {1, 2, 3}, rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, seed, %{}, rules)
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    alice |> element("button", "Start game") |> render_click()
    {id, alice, bob}
  end

  test "Play again takes both players to the next game" do
    {id, alice, bob} = duo_2()
    replace_game(id, &H.put(&1, phase: :over))

    {:error, {:live_redirect, %{to: "/g/" <> new_id}}} =
      alice
      |> element("[data-role=game-over-actions] button", "Play again")
      |> render_click()

    assert {"/g/" <> ^new_id, _flash} = assert_redirect(bob)
    assert {:ok, %{status: :waiting, names: %{0 => _, 1 => _}}} = GameServer.get(new_id)
  end
end
