defmodule QuacksWeb.Round25Test do
  @moduledoc """
  Round 25: the presets at the foot of the Ingredient books page, the House rules
  row on the Expansions page, black chips by standings by default, and the corner
  card growing back with no flip. The manifest link is in `QuacksWeb.PwaTest`.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameServer
  alias Quacks.Rules.BookPresets

  doctest QuacksWeb.SetupComponents, import: true, only: [saved_rules: 1]

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp lobby(path) do
    {:ok, view, _html} = live(browser("r25-#{System.unique_integer()}"), path)
    view
  end

  describe "the Ingredient books page" do
    test "the presets come after the colour rows, every preset and Random" do
      view = lobby(~p"/?step=books")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#page-books #books, #page-books #presets-block")
        |> LazyHTML.attribute("id")

      assert ids == ["books", "presets-block"]

      for preset <- BookPresets.all() do
        assert has_element?(view, "#presets-block #preset-#{preset.id}", preset.name)
      end

      assert has_element?(view, "#presets-block #preset-random")
    end
  end

  describe "the House rules row" do
    test "round 29: is on New game after the expansion rows and the books row" do
      view = lobby(~p"/?step=players")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(
          "#page-players [data-role=expansion-cards], #page-players #to-books, #page-players #to-rules"
        )
        |> LazyHTML.attribute("data-role")

      assert ids == ["expansion-cards", "to-books", "to-rules"]
    end

    test "its page stays; Back from it goes to New game" do
      view = lobby(~p"/?step=players")
      view |> element("#to-rules") |> render_click()
      assert_patch(view, ~p"/?step=rules")
      assert has_element?(view, "#page-rules #options")

      view = lobby(~p"/?step=rules")
      view |> element("#flow-back") |> render_click()
      assert_patch(view, ~p"/?step=players")
    end
  end

  test "round 27: a new game counts black chips by neighbours again; standings is the other option" do
    assert Quacks.Game.default_rules().black_rule == :neighbours
    assert Quacks.Game.new(players: 3, seed: {1, 2, 3}).rules.black_rule == :neighbours

    view = lobby(~p"/?step=rules")
    assert has_element?(view, "#rules-black_rule-neighbours[checked]")
    assert has_element?(view, "#rules-black_rule-standings")
  end

  test "round 27: a config saved in rounds 25-26 does not keep the old standings default" do
    view = lobby(~p"/?step=rules")

    render_hook(view, "load_config", %{
      "v" => 25,
      "players" => 2,
      "rules" => %{"black_rule" => "standings"}
    })

    assert has_element?(view, "#rules-black_rule-neighbours[checked]")

    # A round-27 config keeps the choice and says its version.
    render_hook(view, "load_config", %{
      "v" => 27,
      "players" => 2,
      "rules" => %{"black_rule" => "standings"}
    })

    assert has_element?(view, "#rules-black_rule-standings[checked]")
    view |> element("#options") |> render_change(%{"rules" => %{"black_rule" => "neighbours"}})
    assert_push_event(view, "save_config", %{v: 27, rules: %{black_rule: "neighbours"}})
  end

  describe "the corner card grows back" do
    test "the grown card has no flip; the card transition grows it" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser("r25-#{System.unique_integer()}"), ~p"/g/#{id}")

      replace_game(id, fn g ->
        %{g | fortune_card: :b1, log: [{:fortune_drawn, :b1} | g.log]}
      end)

      # The new card turns over as it comes.
      assert has_element?(view, "#pot-card-1 [data-role=card-flip]")
      view |> element("#card-tap") |> render_click()
      refute has_element?(view, "#pot-card-1")

      # A tap on the corner card: the same card, big, with no flip.
      view |> element("#corner-card") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      assert has_element?(view, "#pot-card-1 [data-role=fortune-card]")
      refute has_element?(view, "#pot-card-1 [data-role=card-flip]")
      refute has_element?(view, "#pot-card-1 [data-role=card-back]")

      # A tap shrinks it again.
      view |> element("#card-tap") |> render_click()
      refute has_element?(view, "#pot-card-1")
    end
  end
end
