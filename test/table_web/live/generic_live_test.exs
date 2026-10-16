defmodule TableWeb.GenericLiveTest do
  @moduledoc """
  The generic table: `/games` → `/games/generic/new?spec=crazy_eights` → a room at
  `/games/generic/<code>` with the scripted referee, played to the end against
  random bots (they act at once in tests).
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import QuacksWeb.LiveHelpers

  alias Table.Generic.Game
  alias Table.Server

  defp game(code), do: Server.state("generic", code).game

  defp settle(view, code) do
    [{pid, _}] = Registry.lookup(Table.Registry, {"generic", code})

    Enum.reduce_while(1..500, nil, fn _, last ->
      _ = :sys.get_state(pid)
      v = Server.state("generic", code).version
      _ = render(view)
      if v == last, do: {:halt, v}, else: {:cont, v}
    end)
  end

  test "pick, set up, create: the room opens with your hand and the prompt", %{conn: conn} do
    conn = init_test_session(conn, player_token: token("host"))
    {:ok, games, _} = live(conn, "/games")

    {:ok, setup, _} = games |> element("#pick-generic") |> render_click() |> follow_redirect(conn)
    setup |> element("#generic-setup") |> render_change(%{"setup" => %{"players" => "4"}})
    assert has_element?(setup, "#bots-3:checked")

    {:ok, room, _} =
      setup
      |> form("#generic-setup", setup: %{name: "Nick", players: "4", bots: "3"})
      |> render_submit()
      |> follow_redirect(conn)

    assert has_element?(room, "#generic-root[data-spec=crazy_eights]")
    assert has_element?(room, "#gt-z-hand-0 .tb-card[data-card]")
    assert has_element?(room, "#gt-z-hand-1[data-count='5']")
    assert has_element?(room, "#gt-z-deck")
    assert has_element?(room, "#generic-prompt[data-mine=true]")
    assert has_element?(room, "#choose-draw")
  end

  test "an unknown spec goes back to the games", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/games"}}} =
             live(conn, "/games/generic/new?spec=go_fish")
  end

  test "a whole game against 2 bots: play a lit card or draw until it ends", %{conn: conn} do
    me = token("me")
    config = %{opts: %{spec: "crazy_eights", players: 3}, bots: 2, level: :random, name: "Nick"}
    {:ok, code} = Server.create("generic", config, me)
    {:ok, view, _} = live(init_test_session(conn, player_token: me), "/games/generic/#{code}")

    result =
      Enum.reduce_while(1..400, nil, fn _, _ ->
        settle(view, code)
        g = game(code)

        case Game.status(g) do
          {:over, scores} ->
            {:halt, scores}

          {:playing, [0]} ->
            case Game.legal_actions(g, 0) do
              [{:play, _zone, card} | _] -> view |> element("#gt-card-#{card}") |> render_click()
              [{:choose, label} | _] -> view |> element("#choose-#{label}") |> render_click()
            end

            {:cont, nil}

          _ ->
            {:cont, nil}
        end
      end)

    assert %{} = result
    settle(view, code)
    assert has_element?(view, "#generic-over")

    assert has_element?(view, "#generic-ranking li", "Nick") or
             has_element?(view, "#generic-ranking li", "You")

    view |> element("#play-again") |> render_click()
    settle(view, code)
    refute has_element?(view, "#generic-over")
  end
end
