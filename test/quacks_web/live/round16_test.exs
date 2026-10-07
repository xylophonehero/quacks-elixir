defmodule QuacksWeb.Round16Test do
  @moduledoc "Round 16 C: the rat track between the name cards and the pot."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  # A 3-player game, two seats bots, begun; `vps` per seat.
  defp trio(rules, vps) do
    {:ok, id} = GameServer.start(3, {1, 2, 3}, %{}, Map.merge(%{fortune: false}, rules))
    token = "r16-#{System.unique_integer()}"
    {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
    {:ok, _} = GameServer.add_bot(id, token)
    {:ok, _} = GameServer.add_bot(id, token)
    {:ok, _} = GameServer.begin(id, token)

    replace_game(id, fn g ->
      vps |> Enum.with_index() |> Enum.reduce(g, fn {vp, s}, g -> H.put(g, s, vp: vp) end)
    end)

    view
  end

  test "every seat's dot in its step, the rats between with their VP (round 22)" do
    # Seat 0 (me) on 3, seat 1 on 12, seat 2 on 8: tails after 10, 7, 4 → 3 rats.
    view = trio(%{}, [3, 12, 8])
    assert has_element?(view, "#rat-track[data-steps='4']")
    assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='1'][data-step='0']")
    assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='2'][data-step='1']")
    assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='0'][data-step='3']")

    html = view |> element("#rat-track") |> render()
    rats = html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-role=track-rat]")
    assert Enum.map(rats, &(&1 |> LazyHTML.text() |> String.trim())) == ~w(10 7 4)
    assert html =~ "Player 1 3 VP, 3 rats"
  end

  test "no track with the rats rule off" do
    view = trio(%{rats: false}, [3, 12, 8])
    refute has_element?(view, "#rat-track")
  end

  test "no track solo" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("r16-solo"), ~p"/g/#{id}")
    refute has_element?(view, "#rat-track")
  end
end
