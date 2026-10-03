defmodule QuacksWeb.UiRound4Test do
  @moduledoc """
  Round 4 playtest fixes: the black book in every game, the remembered
  configuration, one dialog for the new card and its choice, the shop tiles and
  the round results before the shop.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.GameComponents

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  # Play seat 0 of a solo game to the shop.
  defp to_shop(id) do
    Enum.find_value(1..60, fn _ ->
      {:ok, %{game: game}} = GameServer.get(id)
      actions = Game.legal_actions(game, 0)

      if game.phase == :shopping do
        # coins to buy with: a seat that can buy nothing skips the shop
        Quacks.GameHelpers.replace_game(id, &Quacks.GameHelpers.put(&1, 0, coins: 30))
      else
        action =
          Enum.find([:stop, :chip_done, {:explosion_choice, :buy}], hd(actions), &(&1 in actions))

        {:ok, _} = GameServer.apply(id, 0, action)
        nil
      end
    end)
  end

  test "the black book is offered without the expansion and reaches the game" do
    {:ok, id} = GameServer.start(2)
    view = open(browser("host"), id)

    refute has_element?(view, "#expansion[checked]")
    assert has_element?(view, "input[name='sets[black]'][value='5']")
    assert has_element?(view, "input[name='sets[black]'][value='6']")

    view |> form("#books", sets: %{black: "6"}) |> render_change()
    view |> element("button", "Start game") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    assert game.expansion == nil
    assert game.sets.black == 6
  end

  test "the host's changes go to the browser; a fresh screen takes them back once" do
    {:ok, id} = GameServer.start(2)
    host = open(browser("host"), id)
    assert has_element?(host, "#config-memory[phx-hook=ConfigMemory][data-fresh]")

    saved = %{
      "players" => 9,
      "sets" => %{"green" => "3", "black" => "5", "blue" => "bad"},
      "rules" => %{"rats" => "false", "explode_above" => "42"},
      "expansion" => false
    }

    render_hook(host, "load_config", saved)
    {:ok, table} = GameServer.get(id)
    assert table.max_players == 8
    assert %{green: 3, black: 5, blue: 1} = table.sets
    assert %{rats: false, explode_above: 7} = table.rules
    refute has_element?(host, "#config-memory[data-fresh]")

    # once configured, a second load changes nothing; junk is ignored
    render_hook(host, "load_config", %{saved | "sets" => %{"green" => "4"}})
    render_hook(host, "load_config", %{"players" => "x"})
    assert {:ok, %{sets: %{green: 3}}} = GameServer.get(id)

    # every host change is pushed to the browser in the form's shape
    host |> form("#books", sets: %{green: "2"}) |> render_change()

    assert_push_event(host, "save_config", %{
      players: 8,
      sets: %{green: "2", black: "5"},
      rules: %{rats: "false"},
      expansion: false
    })

    # a joiner has no memory hook
    joiner = open(browser("joiner"), id)
    refute has_element?(joiner, "#config-memory")
  end

  test "a card with a choice is one dialog: the card, its offer and the buttons" do
    # seed 30,30,30 with 2 players deals a purple card with a choice for both seats
    {:ok, id} = GameServer.start(2, {30, 30, 30})
    alice = open(browser("alice"), id)
    _bob = open(browser("bob"), id)
    alice |> element("button", "Start game") |> render_click()

    refute has_element?(alice, "#decision-fortune_choice")
    assert has_element?(alice, "dialog#card-round-1 [data-role=fortune-card]")

    assert has_element?(
             alice,
             "#card-round-1 [data-role=fortune-card]",
             "Fortune teller · resolve now"
           )

    assert has_element?(alice, "#card-round-1 section[aria-label=Actions] button", "No thanks")
    refute has_element?(alice, "#card-round-1 form[method=dialog] button", "OK")
    # the footer button opens the card's dialog
    assert has_element?(alice, "footer button[phx-click*='card-round-1']")

    alice |> element("#card-round-1 button", "No thanks") |> render_click()
    # answered: the same dialog is a plain card again, without the "now"
    assert has_element?(alice, "#card-round-1 form[method=dialog] button", "OK")
    refute has_element?(alice, "#card-round-1", "resolve now")
  end

  test "the card band: blue is for this round, purple says nothing more" do
    blue = render_component(&GameComponents.fortune_card/1, id: :b1)
    purple = render_component(&GameComponents.fortune_card/1, id: :p1)

    assert blue =~ "Fortune teller · this round"
    assert purple =~ "Fortune teller"
    refute purple =~ "Fortune teller ·"

    assert render_component(&GameComponents.fortune_card/1, id: :p1, choice: true) =~
             "resolve now"
  end

  test "the round results come first; the shop opens when they close" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("solo"), id)
    to_shop(id)
    render(view)

    # results open themselves and hand over to the shop, which waits
    assert has_element?(view, "dialog#round-results[data-then-open=decision-shop]")
    assert has_element?(view, "dialog#round-results[phx-mounted*='quacks:modal']")
    assert has_element?(view, "dialog#decision-shop #shop")
    refute has_element?(view, "dialog#decision-shop[phx-mounted*='quacks:modal']")
    # the footer still opens the shop at any time
    assert has_element?(view, "footer button", "Open the shop")

    # a reload while shopping keeps the order
    view = open(browser("solo"), id)
    assert has_element?(view, "dialog#round-results[data-then-open=decision-shop]")
    refute has_element?(view, "dialog#decision-shop[phx-mounted*='quacks:modal']")

    # after Done there is no shop to hand over to
    view |> element("#decision-shop [data-role=shop-done]") |> render_click()
    refute has_element?(view, "dialog#round-results[data-then-open]")
  end

  test "shop tiles: a tapped chip is outlined with a check, the others dim" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("solo"), id)
    to_shop(id)
    render(view)

    chip = {:orange, 1}
    render_change(view, "select", %{"chips" => [QuacksWeb.GameLive.encode(chip)]})

    checked = ~s(#shop input[value="#{QuacksWeb.GameLive.encode(chip)}"][checked])
    assert has_element?(view, checked)
    assert has_element?(view, "#shop label.has-checked\\:ring-\\[3px\\] input[checked]")
    # another orange is not a legal second chip: its tile is dimmed and disabled
    assert has_element?(view, "#shop label.opacity-40 input:disabled")
  end

  test "a chip offer has an info button with the books of the colours offered" do
    game = Game.new(seed: {1, 2, 3}, sets: %{red: 2})
    offer = [[{:white, 1}, {:red, 2}], [{:place, {:blue, 1}}, :return_all, {:rubies, 2}]]

    html =
      render_component(&QuacksWeb.GameLive.offer_books/1, id: "books-x", game: game, offer: offer)

    assert html =~ ~s(popovertarget="books-x")
    assert html =~ ~s(data-book="red-2")
    assert html =~ ~s(data-book="blue-1")
    refute html =~ ~s(data-book="white)

    assert render_component(&QuacksWeb.GameLive.offer_books/1,
             id: "y",
             game: game,
             offer: [:stop]
           ) == ""
  end
end
