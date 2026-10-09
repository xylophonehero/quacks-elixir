defmodule QuacksWeb.Round34Test do
  @moduledoc """
  Round 34 fixes: sticky sheet headers, a chip that moves in the pot (green III)
  flies from its old space, rat tails on the second lap of the track.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers, as: H
  alias QuacksWeb.GameComponents

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

  describe "a chip that moves in the pot (green III)" do
    defp pot_chips(game) do
      render_component(&GameComponents.pot/1, game: game)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=pot-chip]")
      |> Enum.map(fn n ->
        {hd(LazyHTML.attribute(n, "id")), hd(LazyHTML.attribute(n, "data-order")),
         hd(LazyHTML.attribute(n, "data-index"))}
      end)
    end

    test "keeps its draw order on a new id at the new space: PotMotion flies it from there" do
      game = Game.new(seed: {1, 2, 3})
      drawn = [{{:green, 2}, 9}, {{:white, 3}, 7}, {{:white, 4}, 4}]
      before = put_in(game.players[0].drawn, drawn)
      moved = put_in(game.players[0].drawn, [{{:green, 2}, 11} | tl(drawn)])

      [{old_id, order, "9"}] = pot_chips(before) -- pot_chips(moved)
      [{new_id, ^order, "11"}] = pot_chips(moved) -- pot_chips(before)
      assert old_id != new_id

      js = File.read!("assets/js/app.js")
      assert js =~ "gone[0].dataset.order === added[0].dataset.order"
      assert js =~ "this.fly(added[0], this.pos(gone[0].dataset.index)"
    end
  end
end
