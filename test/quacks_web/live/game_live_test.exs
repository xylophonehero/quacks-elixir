defmodule QuacksWeb.GameLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias QuacksWeb.GameLive

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
    assert has_element?(view, "li", "Draw a chip")

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

  test "every engine action in the choice phases has a human label" do
    for action <- [:return_white, :keep, {:place, {:white, 1}}, :return_all] do
      refute QuacksWeb.GameComponents.label(action) =~ ~r/^[:{]/
    end
  end

end
