defmodule QuacksWeb.Round28Test do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameHelpers, GameServer}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  # Two seats in the shop, both with coins to spend.
  defp duo_in_shop do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice"), id)
    bob = open(browser("bob"), id)
    {:ok, _} = GameServer.begin(id, "alice")

    for view <- [alice, bob] do
      view |> element("button", "Draw a chip") |> render_click()
      view |> element("button", "Stop") |> render_click()
    end

    GameHelpers.replace_game(id, fn g ->
      Enum.reduce([0, 1], g, &GameHelpers.put(&2, &1, coins: 30))
    end)

    {:ok, %{game: game}} = GameServer.get(id)
    {id, alice, bob, game}
  end

  defp buy_of(game, seat) do
    game
    |> Game.legal_actions(seat)
    |> Enum.find(&match?({:buy, [_]}, &1))
  end

  test "a buy of another seat keeps this seat's shop selection" do
    {id, alice, bob, game} = duo_in_shop()
    assert has_element?(alice, "dialog#decision-shop")

    {:buy, [chip]} = buy_of(game, 0)
    alice |> element("#shop") |> render_change(%{"chips" => [QuacksWeb.GameLive.encode(chip)]})
    assert has_element?(alice, "#shop input[checked][value='#{QuacksWeb.GameLive.encode(chip)}']")

    {:buy, [bob_chip]} = buy_of(game, 1)
    bob |> element("#shop") |> render_change(%{"chips" => [QuacksWeb.GameLive.encode(bob_chip)]})
    bob |> element("[data-role=shop-buy]") |> render_click()
    assert {:ok, %{game: after_buy}} = GameServer.get(id)
    assert length(after_buy.log) > length(game.log)

    # alice's page got bob's buy, and her tick is still there
    _ = render(alice)
    assert has_element?(alice, "#shop input[checked][value='#{QuacksWeb.GameLive.encode(chip)}']")
    refute has_element?(alice, "[data-role=shop-buy][disabled]")
  end
end
