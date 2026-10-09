defmodule QuacksWeb.Round35BoardTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.Game

  describe "rat track labels" do
    defp track(vps) do
      game = Game.new(seed: {1, 2, 3}, players: length(vps))

      game =
        vps
        |> Enum.with_index()
        |> Enum.reduce(game, fn {vp, s}, g -> put_in(g.players[s].vp, vp) end)

      render_component(&QuacksWeb.GameComponents.rat_track/1, game: game, names: %{})
      |> LazyHTML.from_fragment()
    end

    defp texts(html, selector) do
      html |> LazyHTML.query(selector) |> Enum.map(&String.trim(LazyHTML.text(&1)))
    end

    test "every seat's VP shows at its dot" do
      html = track([30, 3, 12])
      assert texts(html, "[data-role=leader-vp]") == ["30"]
      assert Enum.sort(texts(html, "[data-role=track-vp]")) == ["12", "3"]
    end

    test "3 or more rats between neighbouring seats: no rat VPs in between" do
      # 30 vs 12: tails 12..28 = 9 rats; 12 vs 3: tails 4, 7, 10 = 3 rats.
      html = track([30, 3, 12])
      assert length(LazyHTML.query(html, "[data-role=track-rat]") |> Enum.to_list()) == 12
      assert Enum.all?(texts(html, "[data-role=track-rat]"), &(&1 == ""))
    end

    test "small gaps keep their rat VPs" do
      # 12 vs 8: tail 10 (1 rat); 8 vs 3: tails 7, 4 (2 rats).
      html = track([3, 12, 8])
      assert texts(html, "[data-role=track-rat]") == ~w(10 7 4)
    end

    test "mixed: the big gap is quiet, the small gap keeps its VPs" do
      # 20 vs 8: tails 18..10 = 5 rats (quiet); 8 vs 3: tails 7, 4 (shown).
      html = track([20, 8, 3])
      assert Enum.reject(texts(html, "[data-role=track-rat]"), &(&1 == "")) == ~w(7 4)
    end

    test "tails repeat after 50" do
      html = track([56, 50])
      assert texts(html, "[data-role=track-rat]") == ~w(54 51)
    end
  end
end
