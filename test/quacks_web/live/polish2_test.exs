defmodule QuacksWeb.Polish2Test do
  @moduledoc "Polish batch 2: stale broadcasts, shop, game over, stats, configure, round card."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameHelpers, GameServer}
  alias Quacks.Rules.Chips
  alias QuacksWeb.{GameComponents, GameLive}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(seed) do
    {:ok, id} = GameServer.start(1, seed)
    {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")
    {id, view}
  end

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.
  defp to_shop(id) do
    Enum.find_value(1..60, fn _ ->
      game = game(id)
      actions = Game.legal_actions(game, 0)

      if game.phase == :shopping do
        GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, coins: 30))
      else
        action =
          Enum.find([:stop, :chip_done, {:explosion_choice, :buy}], hd(actions), &(&1 in actions))

        {:ok, _} = GameServer.apply(id, 0, action)
        nil
      end
    end)
  end

  defp shop_view do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("shopper"), id)
    to_shop(id)
    render(view)
    view
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

  describe "shop" do
    test "a sticky footer holds the purse, Done and the buy with its count and price" do
      view = shop_view()
      footer = "#decision-shop [data-role=shop-footer].sticky"

      assert has_element?(view, "#{footer} [data-role=shop-total] .book-coin")

      assert has_element?(
               view,
               ~s(#{footer} [data-role=shop-total][aria-label="30 coins, 30 left after this buy"])
             )

      assert has_element?(view, "#{footer} [data-role=shop-done]", "Skip")
      refute has_element?(view, "#{footer} [data-role=shop-buy]")

      render_change(view, "select", %{"chips" => [GameLive.encode({:orange, 1})]})

      assert has_element?(
               view,
               "#{footer} button[data-role=shop-buy]:not(:disabled)",
               "Buy 1 · 3 coins"
             )

      chips = Enum.map([{:orange, 1}, {:blue, 1}], &GameLive.encode/1)
      render_change(view, "select", %{"chips" => chips})
      assert has_element?(view, "#{footer} button[data-role=shop-buy]", "Buy 2 · 8 coins")

      assert has_element?(
               view,
               ~s(#{footer} [data-role=shop-total][aria-label="30 coins, 22 left after this buy"])
             )
    end

    test "prices show a coin glyph; colours not for sale yet carry a lock" do
      view = shop_view()
      html = render(view)

      assert has_element?(view, "#shop [data-role=price] .book-coin")
      refute render(view) =~ ~r/\d+c\s*</
      # round 1: yellow (from round 2) and purple (from round 3) are locked
      assert count(html, "#shop label.shop-locked") ==
               length(Enum.filter(Chips.shop(), &(elem(&1, 0) in [:yellow, :purple])))

      assert count(html, "#shop label.shop-locked [data-role=tile-lock]") ==
               count(html, "#shop label.shop-locked")

      refute has_element?(view, "#shop label.shop-locked input:not(:disabled)")
    end
  end

  describe "game over" do
    defp final_game do
      game = %{Game.new(seed: {1, 2, 3}, players: 4) | phase: :over}

      log = [
        {2, {:pot_vp, 30, 40}},
        {2, {:bonus_die, {:vp, 2}}},
        {2, {:rubies_spent, :vp}},
        {2, {:final_conversion, 10, 2, 2, 1}},
        {0, {:pot_vp, 20, 30}},
        {0, {:essence_vp, 4}},
        {0, {:purple, 3, :vp2_droplet}},
        {1, {:pot_vp, 10, 20}},
        {3, {:pot_vp, 5, 10}}
      ]

      vps = %{0 => 26, 1 => 10, 2 => 40, 3 => 5}

      players =
        Map.new(game.players, fn {seat, p} -> {seat, %{p | vp: vps[seat]}} end)

      %{game | log: log ++ game.log, players: players}
    end

    defp render_over(seat) do
      render_component(&GameLive.game_over/1,
        game: final_game(),
        names: %{0 => "Ann", 1 => "Bo", 2 => "Cy", 3 => "Di"},
        players: 4,
        seat: seat
      )
    end

    test "the podium shows 2nd, 1st, 3rd; the winner wears the laurel; the rest are rows" do
      html = render_over(0)
      doc = LazyHTML.from_fragment(html)

      podium =
        doc |> LazyHTML.query("[aria-label=Podium] > li") |> LazyHTML.attribute("data-seat")

      assert podium == ["0", "2", "1"]

      places =
        doc |> LazyHTML.query("[aria-label=Podium] > li") |> LazyHTML.attribute("data-place")

      assert places == ["2", "1", "3"]
      assert count(html, ~s([data-seat="2"][data-place="1"] [data-role=crown])) == 1
      assert count(html, "[data-role=crown]") == 1
      assert count(html, ~s|ol:not([aria-label=Podium]) > li[data-seat="3"][data-place="4"]|) == 1
      assert html =~ "Cy wins!"
      assert render_over(2) =~ "You win!"
    end

    test "each player's VP breakdown comes from the log and adds up" do
      html = render_over(nil)
      doc = LazyHTML.from_fragment(html)

      parts = fn seat ->
        doc
        |> LazyHTML.query(~s([data-role=vp-breakdown][data-seat="#{seat}"] li))
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))
      end

      assert parts.(2) == [
               "Brewing +30",
               "Bonus die +2",
               "Rubies +1",
               "Final coins and rubies +3",
               "Other +4"
             ]

      assert parts.(0) == ["Brewing +20", "Chip actions +2", "Essence +4"]
      assert parts.(1) == ["Brewing +10"]

      for {seat, vp} <- final_game() |> Game.score() do
        assert final_game().log
               |> GameComponents.vp_breakdown(seat, vp)
               |> Enum.map(&elem(&1, 1))
               |> Enum.sum() == vp
      end
    end

    test "Play again is the primary button and takes the focus when the dialog opens" do
      html = render_over(0)
      assert count(html, "button[data-role=play-again][autofocus]") == 1
      assert count(html, "button[autofocus]") == 1
    end

    test "solo: the score as the title, with its breakdown" do
      game = %{Game.new(seed: {1, 2, 3}) | phase: :over}
      game = %{game | log: [{0, {:pot_vp, 12, 30}} | game.log]}
      game = put_in(game.players[0].vp, 12)

      html = render_component(&GameLive.game_over/1, game: game, names: %{}, players: 1)
      assert html =~ "victory points"
      assert count(html, "[aria-label=Podium]") == 0
      assert count(html, ~s([data-role=vp-breakdown] li[data-part=brewing])) == 1
    end
  end

  describe "stats strip" do
    test "icons with numbers; the words are for screen readers" do
      {_id, view} = solo({1, 2, 3})
      stats = "[data-role=stats]"

      assert has_element?(view, "#{stats} dt svg[data-icon=vp]")
      assert has_element?(view, "#{stats} dt svg[data-icon=ruby]")
      assert has_element?(view, "#{stats} dt svg[data-icon=flask]")
      assert has_element?(view, "#{stats} dt .sr-only", "VP")
      assert has_element?(view, "#{stats} dt .sr-only", "Rubies")
      assert has_element?(view, "#{stats} [data-role=flask-state]", "full")
      assert has_element?(view, "#{stats} dd#stat-vp.font-hand")
      refute has_element?(view, "#{stats} [data-role=stat-essence]")
    end

    test "with The Alchemists the strip shows the essence" do
      {id, view} = solo({1, 2, 3})

      GameHelpers.replace_game(id, fn g ->
        %{g | expansions: MapSet.new([:alchemists])}
      end)

      assert has_element?(view, "[data-role=stats] [data-role=stat-essence]", "0")
    end
  end

  describe "waiting panel" do
    test "Start game for the host once every seat is taken; the guest waits" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      host = open(browser("host"), id)
      bar = "[data-role=start-bar]"
      refute has_element?(host, "#{bar} [data-role=start-game]")
      assert has_element?(host, "#{bar} [data-role=fill-bots]")

      guest = open(browser("guest"), id)

      assert has_element?(
               host,
               "#{bar} button[data-role=start-game][phx-click=begin]",
               "Start game"
             )

      refute has_element?(guest, "#{bar} [data-role=start-game]")
      assert has_element?(guest, "#{bar} [data-role=waiting-for-host]")
    end

    test "the spell book: expansions are switch cards; books are compact tiles" do
      {:ok, host, _html} = live(browser("host"), ~p"/?step=books")

      for input <- ~w(expansion alchemists rules-pot_side) do
        assert has_element?(
                 host,
                 "[data-role=toggle-card] input##{input}.switch[type=checkbox]"
               )
      end

      assert has_element?(host, "#options input#rules-rats.switch")
      assert has_element?(host, "#options .segmented input.segment[type=radio]")
      tile = "#books [data-role=book-tile][data-colour=green]"
      assert has_element?(host, tile, "Garden spider")
      refute has_element?(host, "#{tile} [data-role=book-tiers]")
    end
  end

  describe "round moments" do
    test "a Round N title card enters once per round, and a tap hides it" do
      {_id, view} = solo({1, 2, 3})
      assert has_element?(view, "#round-title-1[data-role=round-title][phx-click]", "1")
    end

    test "the fuse says when the pot exploded, so it can burst" do
      {id, view} = solo({1, 2, 3})
      assert has_element?(view, ~s(#fuse-meter[data-exploded="false"]))

      GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, exploded?: true))
      send(view.pid, {:game, id, game(id)})
      assert has_element?(view, ~s(#fuse-meter[data-exploded="true"]))
    end
  end
end
