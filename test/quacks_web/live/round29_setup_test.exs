defmodule QuacksWeb.Round29SetupTest do
  @moduledoc """
  Round 29 (setup and menu): one New game page with a row per expansion (switch
  and Customise), the books and House rules rows, dots on changed settings.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.Game.Essence
  alias Quacks.GameServer
  alias Quacks.Rules.Alchemists

  defp lobby(path) do
    conn = init_test_session(build_conn(), player_token: "r29-#{System.unique_integer()}")
    {:ok, view, _html} = live(conn, path)
    view
  end

  describe "New game: one main page" do
    test "the rows say the defaults; no dot and Customise is off while an expansion is off" do
      view = lobby(~p"/?step=players")
      assert has_element?(view, "#row-expansion", "Witch cards")
      assert has_element?(view, "#row-alchemists", "Patients and essence")
      assert has_element?(view, "#row-rules-pot_side", "Test tubes")
      assert has_element?(view, "#to-books", "Beginner (Set 1)")
      assert has_element?(view, "#to-rules", "As in the rulebook")
      refute has_element?(view, "#page-players [data-role=changed-dot]")
      assert has_element?(view, "#customise-expansion[aria-disabled]")
      assert has_element?(view, "#customise-alchemists[aria-disabled]")
      # The pot's reverse side has nothing to customise.
      refute has_element?(view, "#customise-rules-pot_side")
    end

    test "Herb Witches: on, Customise opens the witches page; a pick puts a dot on the row" do
      view = lobby(~p"/?step=players")
      view |> element("#books") |> render_change(%{"expansion" => "true", "sets" => %{}})
      assert has_element?(view, "#row-expansion", "Random witches")
      refute has_element?(view, "#customise-expansion[aria-disabled]")

      view |> element("#customise-expansion") |> render_click()
      assert_patch(view, ~p"/?step=witches")
      assert has_element?(view, "#page-witches.flex #witch-link-copper")
      refute has_element?(view, "#page-books #witch-link-copper")

      view |> element("#witch-link-copper") |> render_click()
      assert_patch(view, ~p"/?step=witch&colour=copper")

      view
      |> element("#books")
      |> render_change(%{"expansion" => "true", "witches" => %{"copper" => "c1"}})

      assert has_element?(view, "#row-expansion", "1 of 3 picked")
      assert has_element?(view, "#customise-expansion [data-role=changed-dot]")
    end

    test "Alchemists: Customise opens the patients page; your patient puts a dot" do
      view = lobby(~p"/?seed=1,2,3&step=players")
      view |> element("#books") |> render_change(%{"alchemists" => "true", "sets" => %{}})
      assert has_element?(view, "#row-alchemists", "Patient: random")

      view |> element("#customise-alchemists") |> render_click()
      assert_patch(view, ~p"/?step=patients")
      assert has_element?(view, "#page-patients.flex #lobby-patient")

      [a | _] = Essence.dealt({1, 2, 3})
      view |> element("#lobby-patient") |> render_change(%{"patient" => to_string(a)})
      assert has_element?(view, "#customise-alchemists [data-role=changed-dot]")
      assert has_element?(view, "#row-alchemists", Alchemists.get(a).name)
    end

    test "books and house rules: a change puts a dot on the row" do
      view = lobby(~p"/?step=players")
      view |> element("#preset-set2") |> render_click()
      assert has_element?(view, "#to-books [data-role=changed-dot]")

      view |> element("#options") |> render_change(%{"rules" => %{"explode_above" => "9"}})
      assert has_element?(view, "#to-rules [data-role=changed-dot]")
      assert has_element?(view, "#to-rules", "1 changed")

      # The pot side has its own row; it is no house rule change.
      view = lobby(~p"/?step=players")
      view |> element("#options") |> render_change(%{"rules" => %{"pot_side" => "true"}})
      assert has_element?(view, "#to-rules", "As in the rulebook")
    end

    test "the Customise pages keep the bar: Back goes to New game, Start works" do
      for step <- ~w(witches patients books rules) do
        view = lobby("/?step=#{step}")
        assert has_element?(view, "#flow-bar #new-game", "Start")
        view |> element("#flow-back") |> render_click()
        assert_patch(view, ~p"/?step=players")
      end
    end
  end

  describe "the waiting panel: Share and the room code" do
    test "Share is the primary button with title, text and link; Copy link is the fallback" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      view = lobby(~p"/g/#{id}")

      assert has_element?(view, "#invite [data-role=room-code].font-hand", id)
      assert has_element?(view, "#share-game.share-only.bg-gold", "Share")
      assert has_element?(view, "#invite [data-role=copy-link].share-fallback", "Copy link")

      [click] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#share-game")
        |> LazyHTML.attribute("phx-click")

      assert click =~ "quacks:share"
      assert click =~ "Room code: #{id}"
      assert click =~ ~s("title":"Quacks")
      assert click =~ "/g/#{id}"
    end
  end

  test "New game and Start are the gold primary; the cauldron stays on Start" do
    css = File.read!("assets/css/app.css")
    [rule] = Regex.run(~r/\.start-button,\n\.flow-button \{[^}]*\}/, css)
    assert rule =~ "background: var(--color-gold)"
    assert rule =~ "color: var(--color-ink)"

    view = lobby(~p"/?step=players")
    assert has_element?(view, "#new-game.start-button svg")
    assert has_element?(view, "#new-game-flow.flow-button")
  end
end
