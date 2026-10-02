defmodule QuacksWeb.GameLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.Game
  alias Quacks.Rules.Chips
  alias QuacksWeb.{GameComponents, GameLive}

  @pot_chip "[data-role=pot-chip]"

  defp mount(conn), do: live(conn, ~p"/?seed=1,2,3")

  defp pot_chips(view), do: view |> render() |> count(@pot_chip)

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  # The first legal action is the first action button on the page.
  defp first_action(html) do
    [_, encoded] = Regex.run(~r/phx-value-action="([^"]+)"/, html)
    encoded
  end

  test "mounts round 1 with a Draw button and the seed", %{conn: conn} do
    {:ok, view, html} = mount(conn)
    assert html =~ "1 / 9"
    assert html =~ "Seed"
    assert html =~ "1,2,3"
    assert has_element?(view, "button", "Draw a chip")
    assert pot_chips(view) == 0
  end

  test "Draw places a chip in the pot and Undo takes it back", %{conn: conn} do
    {:ok, view, _html} = mount(conn)

    view |> element("button", "Draw a chip") |> render_click()
    assert pot_chips(view) == 1
    assert has_element?(view, "li", ~r/Drew white \d → space \d/)
    refute has_element?(view, "li", "Draw a chip")

    view |> element("button", "Undo") |> render_click()
    assert pot_chips(view) == 0
  end

  test "a malformed action payload shows a flash and does not crash", %{conn: conn} do
    {:ok, view, _html} = mount(conn)

    html = render_click(view, "action", %{"action" => "not-base64!!"})
    assert html =~ "That move could not be read."
    assert Process.alive?(view.pid)
  end

  test "a well-formed but illegal action shows a flash", %{conn: conn} do
    {:ok, view, _html} = mount(conn)

    html = render_click(view, "action", %{"action" => GameLive.encode(:stop)})
    assert html =~ "Stop is not allowed right now."
    assert pot_chips(view) == 0
  end

  test "decode rejects payloads that would create functions or atoms" do
    assert {:error, :bad_action} = GameLive.decode("@@@")
    fun = :erlang.term_to_binary(fn -> :boom end) |> Base.url_encode64(padding: false)
    assert {:error, :bad_action} = GameLive.decode(fun)
    assert {:ok, {:buy, [{:green, 2}]}} = GameLive.decode(GameLive.encode({:buy, [{:green, 2}]}))
  end

  test "clicking the first legal action until the end reaches game over", %{conn: conn} do
    {:ok, view, html} = mount(conn)

    html =
      Enum.reduce_while(1..500, html, fn _, html ->
        if html =~ "Game over",
          do: {:halt, html},
          else: {:cont, render_click(view, "action", %{"action" => first_action(html)})}
      end)

    assert html =~ "Game over"
    assert html =~ "victory points"
    assert has_element?(view, "button", "New game")
    refute has_element?(view, "button", "Draw a chip")

    view |> element("section button", "New game") |> render_click()
    assert has_element?(view, "button", "Draw a chip")
  end

  # A shop with 7 coins: seed 10,11,12 draws white 2, 3, 1 (index 6, scoring space 7).
  defp mount_shop(conn) do
    {:ok, view, _html} = live(conn, ~p"/?seed=10,11,12")
    for _ <- 1..3, do: view |> element("button", "Draw a chip") |> render_click()
    view |> element("button", "Stop") |> render_click()
    assert has_element?(view, "dd", "Shop")
    assert render(view) =~ "7 coins to spend"
    view
  end

  defp select(view, chips),
    do: render_change(view, "select", %{"chips" => Enum.map(chips, &GameLive.encode/1)})

  defp checkbox(chip), do: ~s(#shop input[value="#{GameLive.encode(chip)}"])

  defp bag_size(view) do
    [_, n] = Regex.run(~r/Bag \((\d+) chips\)/, render(view))
    String.to_integer(n)
  end

  test "the pot draws each chip on its recorded space", %{conn: _conn} do
    game = %{Game.new(seed: {1, 2, 3}) | drawn: [{{:red, 2}, 4}, {{:orange, 1}, 1}]}
    html = render_component(&GameComponents.pot/1, game: game)
    assert count(html, ~s([data-space="4"] #{@pot_chip}[aria-label="red 2"])) == 1
    assert count(html, ~s([data-space="1"] #{@pot_chip}[aria-label="orange 1"])) == 1
    assert count(html, ~s([data-space="3"] #{@pot_chip})) == 0
    assert count(html, @pot_chip) == 2
  end

  test "the crow skull strip lists duplicate offers; the buttons list each chip once" do
    game = %{
      Game.new(seed: {1, 2, 3})
      | phase: :blue_choice,
        pending: [{:white, 1}, {:white, 1}]
    }

    html = render_component(&GameComponents.blue_offer/1, pending: game.pending)
    assert count(html, ~s([data-role="offer-chip"][aria-label="white 1"])) == 2
    assert Game.legal_actions(game) == [{:place, {:white, 1}}, :return_all]
  end

  test "shop: tick two chips, buy them, the bag grows", %{conn: conn} do
    view = mount_shop(conn)
    before = bag_size(view)
    assert has_element?(view, "button:disabled", "Buy selected")
    assert has_element?(view, checkbox({:orange, 1}) <> ":not(:disabled)")
    assert has_element?(view, checkbox({:yellow, 1}) <> ":disabled")
    assert has_element?(view, checkbox({:green, 2}) <> ":disabled")

    select(view, [{:orange, 1}])
    assert has_element?(view, checkbox({:orange, 1}) <> ":checked")
    assert has_element?(view, "[data-role=shop-total]", "Selected: 3 coins. Remaining: 4 of 7.")
    assert has_element?(view, checkbox({:green, 1}) <> ":not(:disabled)")

    select(view, [{:orange, 1}, {:green, 1}])
    assert has_element?(view, "[data-role=shop-total]", "Selected: 7 coins. Remaining: 0 of 7.")
    assert has_element?(view, "button:not(:disabled)", "Buy selected")
    # with two ticked, every other box is disabled
    assert count(render(view), "#shop input:disabled") == length(Chips.shop()) - 2

    view |> element("button", "Buy selected") |> render_click()
    assert has_element?(view, "dd", "Rubies")
    assert has_element?(view, "li", "Bought green 1 + orange 1")
    assert bag_size(view) == before + 2
  end

  test "shop: a selection the engine rejects cannot be bought", %{conn: conn} do
    view = mount_shop(conn)
    # a crafted change event with two greens (same colour) and an unaffordable total
    select(view, [{:green, 1}, {:green, 2}])
    assert has_element?(view, "button:disabled", "Buy selected")
    assert has_element?(view, "[data-role=shop-total]", "Selected: 12 coins. Remaining: -5 of 7.")

    view |> element("button", "Buy nothing") |> render_click()
    assert has_element?(view, "dd", "Rubies")
  end

  test "every engine action in the choice phases has a human label" do
    for action <- [:return_white, :keep, {:place, {:white, 1}}, :return_all] do
      refute GameComponents.label(action) =~ ~r/^[:{]/
    end
  end
end
