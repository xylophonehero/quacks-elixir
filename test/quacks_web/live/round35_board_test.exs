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

  describe "rats in the pot when the droplet moves" do
    alias Quacks.GameHelpers, as: H
    alias QuacksWeb.GameComponents

    defp rat_game do
      Game.new(seed: {1, 2, 3}, players: 2) |> H.put(1, rat_stone: 3, pot_index: 3)
    end

    test "before the first draw the rats follow the droplet" do
      game = rat_game() |> Game.move_droplet(1, 1)
      assert GameComponents.rat_spaces(game.players[1]) == [2, 3, 4]
      assert game.players[1].pot_index == 4
    end

    test "the first chip fixes the rat stone; a later move takes the first rat's space" do
      game = H.force_draws(rat_game(), 1, [{:white, 2}])
      assert game.players[1].rat_end == 3
      assert GameComponents.rat_spaces(game.players[1]) == [1, 2, 3]

      game = Game.move_droplet(game, 1, 1)
      assert GameComponents.rat_spaces(game.players[1]) == [2, 3]
      # Locoweed 5 still reads the distance moved at round start.
      assert game.players[1].rat_stone == 3

      game = Game.move_droplet(game, 1, 3)
      assert GameComponents.rat_spaces(game.players[1]) == []
    end

    test "the pot draws one pebble per rat space, keyed by its space" do
      game = H.force_draws(rat_game(), 1, [{:white, 2}]) |> Game.move_droplet(1, 1)

      html =
        render_component(&GameComponents.pot/1, game: game, seat: 1, size: :lg)
        |> LazyHTML.from_fragment()

      rats = LazyHTML.query(html, "[data-role=rat]")
      assert Enum.map(rats, &LazyHTML.attribute(&1, "data-index")) == [["2"], ["3"]]
    end
  end

  describe "chips back to the bag before the shop" do
    alias Quacks.GameServer

    test "the results keep the chips; closing them for the shop bags them" do
      {:ok, id} = GameServer.start(1, {10, 11, 12})

      {:ok, view, _html} =
        live(init_test_session(build_conn(), player_token: "r35-bag"), ~p"/g/#{id}")

      for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
      view |> element("button", "Stop") |> render_click()

      assert has_element?(view, "#pot-0-lg [data-role=pot-chip]")
      refute has_element?(view, "#pot-0-lg[data-bagged]")

      render_hook(view, "reveal_close", %{})
      assert has_element?(view, "#pot-0-lg[data-bagged]")
      refute has_element?(view, "#pot-0-lg [data-role=pot-chip]")
      assert has_element?(view, "#decision-shop")
    end

    test "the hook flies the chips to the bag and the shop waits for them" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ "toBag(gone)"
      assert js =~ "bagUntil - performance.now()"
    end
  end

  describe "test tubes" do
    test "the ruby and the VP are icons, no VP text; the rack is shorter" do
      html =
        render_component(&QuacksWeb.GameComponents.test_tubes/1, id: "t", tube: 0)
        |> LazyHTML.from_fragment()

      assert html |> LazyHTML.query("[data-role=glass-ruby][data-icon=ruby]") |> Enum.count() > 0
      assert html |> LazyHTML.query("[data-role=glass-vp][data-icon=vp]") |> Enum.count() > 0
      texts = html |> LazyHTML.query("text") |> Enum.map(&String.trim(LazyHTML.text(&1)))
      refute "VP" in texts

      assert LazyHTML.attribute(LazyHTML.query(html, "svg[data-role=test-tubes]"), "viewBox") == [
               "0 -18 364 72"
             ]
    end
  end
end
