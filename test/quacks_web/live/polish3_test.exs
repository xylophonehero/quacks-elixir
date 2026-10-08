defmodule QuacksWeb.Polish3Test do
  @moduledoc "Polish batch 3: lobby hero, fortune card face, patient glasses, shop, focus, steppers."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameHelpers, GameServer}
  alias Quacks.Rules.{Alchemists, Fortune}
  alias QuacksWeb.{AlchemistsComponents, GameComponents}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

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
    {:ok, view, _html} = live(browser("shopper-#{id}"), ~p"/g/#{id}")
    to_shop(id)
    render(view)
    view
  end

  describe "lobby" do
    test "a hero with the cauldron, the title and the tagline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "[data-role=lobby-hero] svg[data-icon=cauldron]")
      assert has_element?(view, "[data-role=lobby-hero] h1.font-hand", "Quacks")
      assert has_element?(view, "[data-role=lobby-hero]", "don't explode")
      assert has_element?(view, "#new-game", "Start")
      assert has_element?(view, "footer#credits", "game-icons.net")
    end

    test "open games are cards with seat dots and expansion badges", %{conn: conn} do
      {:ok, id} = GameServer.start(3, nil, %{}, %{}, MapSet.new([:herb_witches, :alchemists]))
      {:ok, base} = GameServer.start(2)
      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      card = "#game-#{id}[data-role=open-game]"
      assert count(html, "#{card} [data-role=seat-dot]") == 3
      assert count(html, "#{card} [data-role=seat-dot][data-taken]") == 0
      assert has_element?(view, card, "0 of 3 seated")
      assert has_element?(view, "#{card} [data-role=expansion-badge]", "Herb Witches")
      assert has_element?(view, "#{card} [data-role=expansion-badge]", "Alchemists")
      assert has_element?(view, ~s(#{card} a[href="/g/#{id}"]), "Join")

      assert has_element?(view, "#game-#{base} [data-role=expansion-badge]", "Base game")
    end

    test "a taken seat fills its dot" do
      {:ok, id} = GameServer.start(2)
      {:ok, 0} = GameServer.claim_seat(id, "host-#{id}")
      {:ok, view, _html} = live(browser("viewer-#{id}"), ~p"/")
      html = render(view)

      assert count(html, "#game-#{id} [data-role=seat-dot][data-taken]") == 1
      assert has_element?(view, "#game-#{id}", "Player 1's table")
    end
  end

  describe "fortune card" do
    test "every card has a motif in its colour band's card, and a Kalam title" do
      for %{id: id, name: name} <- Fortune.all() do
        html = render_component(&GameComponents.fortune_card/1, id: id)
        assert count(html, "[data-role=fortune-card] [data-role=card-motif][data-motif]") == 1
        assert html |> query("h2.font-hand") |> LazyHTML.text() =~ name
      end
    end

    test "the motif fits the card: a die for Take a Chance, a flask for Cauldron Bubble" do
      motif = fn id ->
        (&GameComponents.fortune_card/1)
        |> render_component(id: id)
        |> query("[data-role=card-motif]")
        |> LazyHTML.attribute("data-motif")
      end

      assert motif.(:p12) == ["die"]
      assert motif.(:b10) == ["flask"]
      assert motif.(:p1) == ["sparkle"]
    end

    test "the flip keeps its ids; the back carries the pattern" do
      html = render_component(&GameComponents.fortune_card/1, id: :b7, flip: true)
      assert count(html, "#card-flip-b7 .card-flip-inner .card-back[data-role=card-back]") == 1
      assert count(html, "#card-flip-b7 .card-front [data-role=fortune-card]") == 1
    end
  end

  describe "patients and essence" do
    test "the slot grid draws glasses with glyphs; the reached glass is ringed" do
      html = render_component(&AlchemistsComponents.slot_grid/1, id: :carrot_nose, reached: 7)

      assert count(html, "li[data-space]") == 10
      assert count(html, ~s(li[data-space="1"] [data-glyph=rat])) == 1
      assert count(html, ~s(li[data-space="7"][data-reached] [data-glyph=vp])) == 1
      # the words stay for screen readers
      assert html |> query(~s(li[data-space="7"] .sr-only)) |> LazyHTML.text() =~ "1 VP"
    end

    test "the patient card shows the patient's picture large" do
      html = render_component(&AlchemistsComponents.patient_card/1, id: :ear_worm)
      assert count(html, "[data-role=patient-card] svg.size-12[data-icon=ear_worm]") == 1
      assert html =~ Alchemists.get(:ear_worm).name
    end

    test "the essence strip is a rack of vials" do
      game = Game.new(seed: {1, 2, 3}, expansions: [:alchemists])
      game = GameHelpers.put(game, 0, patient: :carrot_nose, essence: 3)
      html = render_component(&AlchemistsComponents.flask_strip/1, game: game, seat: 0)

      assert count(html, "[data-role=flask-strip] [data-role=essence-rack] li") == 11
      assert count(html, "[data-role=essence-rack] [data-role=essence-marker]") == 1
    end
  end

  test "an exploded pot's brew is spoiled" do
    game = Game.new(seed: {1, 2, 3})
    calm = render_component(&GameComponents.pot/1, game: game, seat: 0)
    assert count(calm, "[data-role=brew]:not([data-spoiled])") == 1

    game = GameHelpers.put(game, 0, exploded?: true)
    html = render_component(&GameComponents.pot/1, game: game, seat: 0)
    assert count(html, "[data-role=brew][data-spoiled]") == 1
    assert html |> query("[data-role=groove]") |> LazyHTML.attribute("stroke-opacity") == ["0.7"]
  end

  describe "shop" do
    test "no Ingredient books line; each row has a label with the ingredient and its book" do
      view = shop_view()
      html = render(view)

      refute has_element?(view, "#decision-shop [data-role=books]")
      refute html |> query("#decision-shop") |> LazyHTML.text() =~ "Ingredient books:"

      assert count(html, "#shop [data-role=shop-row-label]") ==
               count(html, "#shop [data-role=shop-row]")

      assert has_element?(view, "#shop [data-role=shop-row-label]", "Garden spider")
      assert has_element?(view, "#shop [data-role=shop-row-label]", "book I")
    end
  end

  describe "focus on open" do
    test "every dialog has exactly one autofocus target" do
      view = shop_view()
      html = render(view)
      dialogs = html |> query("dialog") |> LazyHTML.attribute("id")
      assert "decision-shop" in dialogs

      for id <- dialogs do
        assert count(html, "dialog##{id} [autofocus]") == 1, "#{id} has not one autofocus"
      end
    end

    test "the shop opens on its focus target (Buy is disabled)" do
      view = shop_view()
      assert has_element?(view, "#decision-shop [data-role=focus-start][autofocus]")
      refute has_element?(view, "#decision-shop button[autofocus]")
    end

    test "with a witch call but no ruby options, Done is primary and takes the focus" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
      {:ok, view, _html} = live(browser("rubies-#{id}"), ~p"/g/#{id}")
      to_shop(id)
      GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, rubies: 0))
      {:ok, _} = GameServer.apply(id, 0, {:buy, []})
      render(view)

      assert has_element?(view, "#decision-rubies button[data-role=rubies-done][autofocus]")
      refute has_element?(view, "#decision-rubies [data-role=focus-start]")
    end
  end

  describe "options steppers" do
    test "− / + change a number house rule; the ends disable the button" do
      {:ok, view, _html} = live(browser("host-steppers"), ~p"/?step=rules")

      assert has_element?(view, ~s(#options input[type=hidden]#rules-explode_above[value="7"]))
      view |> element("[data-rule=explode_above] button[phx-value-to='8']") |> render_click()
      assert has_element?(view, "[data-rule=explode_above] [data-role=rule-value]", "8")

      view |> element("[data-rule=starting_rubies] button[phx-value-to='0']") |> render_click()
      assert has_element?(view, "[data-rule=starting_rubies] [data-role=rule-value]", "0")
      assert has_element?(view, "[data-rule=starting_rubies] button[phx-value-to='-1']:disabled")
    end

    test "step_rule ignores bad rules and values out of range" do
      rules = Game.default_rules()
      assert QuacksWeb.SetupComponents.step_rule(rules, "explode_above", "10") == rules
      assert QuacksWeb.SetupComponents.step_rule(rules, "rats", "1") == rules
      assert QuacksWeb.SetupComponents.step_rule(rules, "starting_rubies", "x") == rules
      assert QuacksWeb.SetupComponents.step_rule(rules, "explode_above", "5").explode_above == 5
    end
  end
end
