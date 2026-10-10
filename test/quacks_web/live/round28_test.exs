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
      view |> element("button[data-slot=draw]") |> render_click()
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
    alice |> element("#shop") |> render_change(%{"chips" => [QuacksWeb.ActionCode.encode(chip)]})

    assert has_element?(
             alice,
             "#shop input[checked][value='#{QuacksWeb.ActionCode.encode(chip)}']"
           )

    {:buy, [bob_chip]} = buy_of(game, 1)

    bob
    |> element("#shop")
    |> render_change(%{"chips" => [QuacksWeb.ActionCode.encode(bob_chip)]})

    bob |> element("[data-role=shop-buy]") |> render_click()
    assert {:ok, %{game: after_buy}} = GameServer.get(id)
    assert length(after_buy.log) > length(game.log)

    # alice's page got bob's buy, and her tick is still there
    _ = render(alice)

    assert has_element?(
             alice,
             "#shop input[checked][value='#{QuacksWeb.ActionCode.encode(chip)}']"
           )

    refute has_element?(alice, "[data-role=shop-buy][disabled]")
  end

  # Solo, round 2, Flea Market turned up with this bag.
  defp flea_market(bag) do
    {:ok, id} = GameServer.start(1, {1, 2, 3})
    {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")

    GameHelpers.replace_game(id, fn g ->
      g
      |> GameHelpers.put(0, bag: bag, drawn: [], pending: [])
      |> GameHelpers.put(fortune_deck: [:p13], round: 2)
      |> Game.start_round()
    end)

    view
  end

  test "Flea Market: the drawn chips are a picker; a chip that cannot go up says why" do
    view = flea_market([{:green, 1}, {:white, 1}, {:orange, 1}, {:red, 1}])
    # Round 31: the trades are bar buttons; the rows over the pot say why a chip stays.
    assert has_element?(view, "[data-role=bar-card] [data-choice=upgrade]")

    assert has_element?(
             view,
             "[id^=card-stage] [data-role=reveal-chip][title='white stays']"
           )

    refute has_element?(view, "#sheet-fortune-reveals [data-role=flea-result]")
  end

  test "Flea Market with nothing to trade up: all 4 chips, why, and the green 1" do
    view = flea_market(List.duplicate({:white, 1}, 4))
    refute has_element?(view, "[data-role=chip-pick]")

    assert has_element?(
             view,
             "#sheet-fortune-reveals [data-role=reveal-chip][title='white stays']"
           )

    assert has_element?(view, "#sheet-fortune-reveals [data-me] [data-gain=chip]")
    assert has_element?(view, "#sheet-fortune-reveals [data-role=flea-result]", "green 1")
  end
end
