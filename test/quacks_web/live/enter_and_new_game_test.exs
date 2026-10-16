defmodule QuacksWeb.EnterAndNewGameTest do
  @moduledoc """
  G10 (architecture review §5.4): the Enter key takes the open decision's one
  primary button (`GameLive.enter_action/1`), and the solo menu's "New game" starts
  a game with the same books, house rules and expansions. #82 splits `GameLive`;
  these tests hold the behaviour through the split.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import QuacksWeb.LiveHelpers
  import QuacksWeb.RevealHelpers

  alias Quacks.{Game, GameHelpers, GameServer}
  alias QuacksWeb.ActionCode

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  defp enter(view), do: key(view, "Enter")

  # A solo game in the shop of round 1 with 30 coins, the results closed.
  defp in_shop do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser(token("enter")), id)

    %Game{phase: :shopping} = Enum.find_value(1..60, fn _ -> step_to_shop(id) end)
    GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, coins: 30))

    {id, skip_results(view)}
  end

  # One action towards the shop (stop, Done on a choice); the game once it is there.
  defp step_to_shop(id) do
    case game(id) do
      %Game{phase: :shopping} = g ->
        g

      g ->
        actions = Game.legal_actions(g, 0)
        action = Enum.find([:stop, :chip_done], hd(actions), &(&1 in actions))
        {:ok, _} = GameServer.apply(id, 0, action)
        nil
    end
  end

  describe "the Enter key" do
    test "in the shop with chips ticked it buys them" do
      {id, view} = in_shop()
      assert has_element?(view, "#decision-shop")

      render_change(view, "select", %{"chips" => [ActionCode.encode({:orange, 1})]})
      enter(view)
      assert {0, {:buy, [{:orange, 1}]}} in game(id).log
    end

    test "in the shop with nothing ticked it is Done: the round ends" do
      {id, view} = in_shop()
      enter(view)
      game = game(id)
      assert game.round == 2
      assert {0, {:buy, []}} in game.log
    end

    test "while typing in a field it does nothing" do
      {id, view} = in_shop()
      render_change(view, "select", %{"chips" => [ActionCode.encode({:orange, 1})]})
      before = game(id)

      key(view, "Enter", %{"typing" => true})
      assert game(id).log == before.log
    end
  end

  describe "New game (solo menu)" do
    test "starts a new solo game with the same books, rules and expansions; this browser sits in it" do
      sets = %{green: 2, black: 2}
      rules = %{fortune: false, pot_side: :back}
      {:ok, id} = GameServer.start(1, {1, 2, 3}, sets, rules, [:herb_witches])
      who = token("new-game")
      view = open(browser(who), id)
      old = game(id)

      assert {:error, {:live_redirect, %{to: "/g/" <> new_id}}} =
               view |> element("button[phx-click=new_game]") |> render_click()

      assert new_id != id
      {:ok, table} = GameServer.get(new_id)
      assert table.status == :playing

      assert {table.game.sets, table.game.rules, table.game.expansions} ==
               {old.sets, old.rules, old.expansions}

      assert table.game.seats == [0]
      assert GameServer.claim_seat(new_id, who, watch: false) == {:ok, 0}
    end
  end
end
