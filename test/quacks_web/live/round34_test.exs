defmodule QuacksWeb.Round34Test do
  @moduledoc """
  Round 34 fixes: sticky sheet headers, rat tails on the second lap of the track.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp trio(vps) do
    {:ok, id} = GameServer.start(3, {1, 2, 3}, %{}, %{fortune: false})
    token = "r34-#{System.unique_integer()}"
    {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
    {:ok, _} = GameServer.add_bot(id, token)
    {:ok, _} = GameServer.add_bot(id, token)
    {:ok, _} = GameServer.begin(id, token)

    replace_game(id, fn g ->
      vps |> Enum.with_index() |> Enum.reduce(g, fn {vp, s}, g -> H.put(g, s, vp: vp) end)
    end)

    view
  end

  describe "sticky sheet headers" do
    test "the game's sheets mark their title row as the sticky head" do
      view = trio([0, 0, 0])

      for sheet <- ~w(sheet-books sheet-bag sheet-log sheet-menu) do
        assert has_element?(view, "##{sheet} .sheet-head"), sheet
      end
    end

    test "the head and the × are sticky; so is a New-game book page's heading" do
      css = File.read!("assets/css/app.css")
      assert css =~ ~r/\.sheet \.sheet-head \{\s*position: sticky;/
      assert css =~ ~r/\.sheet \.sheet-close \{\s*position: sticky;/
      assert css =~ ~r/\.book-heading \{\s*position: sticky;/
    end
  end

  describe "rat tails after 50" do
    test "the rat track counts the tails on the second lap" do
      # Nick's round-scored screen: 51 / 39 / 68. 51..67: tails after 51, 54, 57,
      # 60, 62, 64, 66 (7); 39..50: 40..48 (5) more, 12 rats, 13 steps.
      view = trio([51, 39, 68])
      assert has_element?(view, "#rat-track[data-steps='13']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='2'][data-step='0']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='0'][data-step='7']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='1'][data-step='12']")
    end
  end
end
