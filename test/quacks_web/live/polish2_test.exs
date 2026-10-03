defmodule QuacksWeb.Polish2Test do
  @moduledoc "Polish batch 2: stale broadcasts, shop, game over, stats, configure, round card."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(seed) do
    {:ok, id} = GameServer.start(1, seed)
    {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")
    {id, view}
  end

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  test "an older broadcast that comes after a newer game does not roll the page back" do
    {id, view} = solo({1, 2, 3})
    old = game(id)

    view |> element("button[data-slot=draw]") |> render_click()
    new = game(id)
    white = Game.white_sum(new, 0)
    assert white > 0

    send(view.pid, {:game, id, new})
    send(view.pid, {:game, id, old})

    assert has_element?(view, ~s(#fuse-meter[data-white="#{white}"]))
  end
end
