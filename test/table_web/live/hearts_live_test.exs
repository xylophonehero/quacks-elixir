defmodule TableWeb.HeartsLiveTest do
  @moduledoc """
  The Hearts pages: `/games` → `/games/hearts/new` → a room at
  `/games/hearts/<code>`, played against bots (they act at once in tests).
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import QuacksWeb.LiveHelpers

  alias Table.Server
  alias TableWeb.Components.Cards

  defp create(token, config) do
    config = Map.merge(%{opts: %{players: 4}, bots: 3, level: :heuristic, name: "Nick"}, config)
    {:ok, code} = Server.create("hearts", config, token)
    code
  end

  defp game(code), do: Server.state("hearts", code).game

  # Lets the room and the page take every message sent so far (bot ticks come at 0 ms).
  defp settle(view, code) do
    [{pid, _}] = Registry.lookup(Table.Registry, {"hearts", code})

    Enum.reduce_while(1..200, nil, fn _, last ->
      _ = :sys.get_state(pid)
      v = Server.state("hearts", code).version
      _ = render(view)
      if v == last, do: {:halt, v}, else: {:cont, v}
    end)
  end

  defp next_hand(view) do
    if has_element?(view, "#next-hand"), do: view |> element("#next-hand") |> render_click()
  end

  defp tap_card(view, card), do: view |> element("#ht-card-#{Cards.code(card)}") |> render_click()

  test "pick, set up, create: the room opens with you at seat 0", %{conn: conn} do
    conn = init_test_session(conn, player_token: token("host"))
    {:ok, games, _} = live(conn, "/games")
    assert has_element?(games, "#pick-quacks")

    {:ok, setup, _} = games |> element("#pick-hearts") |> render_click() |> follow_redirect(conn)
    setup |> element("#hearts-setup") |> render_change(%{"setup" => %{"players" => "5"}})
    assert has_element?(setup, "#bots-4:checked")

    {:ok, room, _} =
      setup
      |> form("#hearts-setup", setup: %{name: "Nick", players: "5", bots: "4"})
      |> render_submit()
      |> follow_redirect(conn)

    assert has_element?(room, "#ht[data-players='5']")
    assert has_element?(room, "#pass-bar")
    assert render(room) =~ "Hand 1"
  end

  test "the room code form finds a room, and a bad code says so", %{conn: conn} do
    conn = init_test_session(conn, player_token: token("host"))
    code = create(token("other"), %{})
    {:ok, games, _} = live(conn, "/games")

    assert {:error, {:live_redirect, %{to: to}}} =
             games |> form("#join-form", join: %{code: String.downcase(code)}) |> render_submit()

    assert to == "/games/hearts/#{code}"

    {:ok, games, _} = live(conn, "/games")
    games |> form("#join-form", join: %{code: "ZZZZZ"}) |> render_submit()
    assert render(games) =~ "No game with the code ZZZZZ"
  end

  test "a whole hand against 3 bots: pass, then play every trick", %{conn: conn} do
    me = token("me")
    code = create(me, %{})
    conn = init_test_session(conn, player_token: me)
    {:ok, view, _} = live(conn, "/games/hearts/#{code}")

    pass = game(code).hands[0] |> Enum.take(3)
    Enum.each(pass, &tap_card(view, &1))
    assert has_element?(view, "#pass-button:not([disabled])")
    view |> element("#pass-button") |> render_click()
    settle(view, code)
    assert game(code).phase == :playing

    play_hand(view, code, 1)

    assert has_element?(view, "#hearts-scores")
    assert has_element?(view, "#score-table [data-role=total]")
    view |> element("#next-hand") |> render_click()
    refute has_element?(view, "#hearts-scores")
    assert game(code).hand_no == 2
  end

  defp play_hand(view, code, hand) do
    _ =
      Enum.reduce_while(1..60, nil, fn _, _ ->
        settle(view, code)
        g = game(code)

        cond do
          g.hand_no > hand or g.phase == :over ->
            {:halt, :ok}

          g.phase == :playing and g.turn == 0 ->
            next_hand(view)
            tap_card(view, hd(Hearts.Game.legal_cards(g, 0)))
            {:cont, nil}

          true ->
            {:cont, nil}
        end
      end)

    g = game(code)
    assert g.hand_no > hand or g.phase == :over
  end

  test "a reload keeps your seat; a second browser takes the free seat; then watchers",
       %{conn: conn} do
    me = token("me")
    code = create(me, %{bots: 2})
    {:ok, a, _} = live(init_test_session(conn, player_token: me), "/games/hearts/#{code}")
    assert has_element?(a, "#hearts-invite")

    {:ok, a2, _} =
      live(init_test_session(build_conn(), player_token: me), "/games/hearts/#{code}")

    assert Server.state("hearts", code).seats[0].token == me
    assert has_element?(a2, "#pass-bar")

    friend = token("friend")

    {:ok, b, _} =
      live(init_test_session(build_conn(), player_token: friend), "/games/hearts/#{code}")

    assert Server.state("hearts", code).seats[1].token == friend
    assert has_element?(b, "#pass-bar")
    refute has_element?(b, "#hearts-invite")
    _ = render(a)
    refute has_element?(a, "#hearts-invite")

    {:ok, c, _} =
      live(init_test_session(build_conn(), player_token: token("x")), "/games/hearts/#{code}")

    assert render(c) =~ "You are watching"
    refute has_element?(c, "#pass-bar")
  end

  test "the page holds no card of another hand", %{conn: conn} do
    me = token("me")
    code = create(me, %{})
    {:ok, view, html} = live(init_test_session(conn, player_token: me), "/games/hearts/#{code}")
    g = game(code)

    for html <- [html, render(view)], seat <- 1..3, card <- g.hands[seat] do
      refute html =~ "ht-card-#{Cards.code(card)}\""
      refute html =~ "phx-value-card=\"#{Cards.code(card)}\""
    end

    for card <- g.hands[0], do: assert(has_element?(view, "#ht-card-#{Cards.code(card)}"))
  end

  test "a whole game to the end with 4 bots, then Play again", %{conn: conn} do
    me = token("me")
    code = create(me, %{opts: %{players: 5, target: 30}, bots: 4})
    {:ok, view, _} = live(init_test_session(conn, player_token: me), "/games/hearts/#{code}")

    Enum.reduce_while(1..40, nil, fn _, _ ->
      g = game(code)

      cond do
        g.phase == :over ->
          {:halt, :ok}

        g.phase == :passing and g.passes[0] == nil ->
          next_hand(view)
          Enum.each(Enum.take(g.hands[0], 3), &tap_card(view, &1))
          view |> element("#pass-button") |> render_click()
          settle(view, code)
          {:cont, nil}

        true ->
          play_hand(view, code, g.hand_no)
          {:cont, nil}
      end
    end)

    settle(view, code)
    assert game(code).phase == :over
    assert has_element?(view, "#hearts-over #final-ranking")
    view |> element("#play-again") |> render_click()
    settle(view, code)
    assert game(code).hand_no == 1
    refute has_element?(view, "#hearts-over")
  end
end
