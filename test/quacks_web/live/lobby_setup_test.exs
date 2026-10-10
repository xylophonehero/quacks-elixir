defmodule QuacksWeb.LobbySetupTest do
  @moduledoc """
  The New game flow: the expansions and books pages, the House rules row, the patient picker, Start straight into the game, the waiting panel, the viewport lock and book tiers.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  alias Quacks.Game.Essence
  alias Quacks.GameServer
  alias Quacks.Rules.Alchemists
  alias Quacks.Rules.BookPresets
  alias Quacks.{Game, GameServer}
  alias QuacksWeb.PanelComponents

  describe "the expansions list, the Games page and Full screen on a phone" do
    setup %{conn: conn} do
      %{conn: init_test_session(conn, player_token: "r21-#{System.unique_integer()}")}
    end

    test "the expansions are a list of rows (round 29: on New game)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?step=players")

      # A row: icon, title and line, Customise, the switch on the right.
      assert has_element?(view, "#page-players [data-role=expansion-cards].grid")
      assert has_element?(view, "#page-players #row-expansion[data-role=expansion-row]")

      ids =
        view
        |> element("#page-players [data-role=expansion-cards]")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("input[type=checkbox]")
        |> LazyHTML.attribute("id")

      assert ids == ~w(expansion alchemists rules-pot_side)
      assert has_element?(view, "#page-players #to-rules.page-link")
      assert has_element?(view, "#page-players #to-books.page-link")
    end

    test "the Games page is one screen on a phone: the list scrolls, New game at the foot",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # `.lobby-screen[data-step=home]` (app.css) holds the hero and the book.
      assert has_element?(view, ".lobby-screen[data-step=home] [data-role=lobby-hero]")
      assert has_element?(view, ".lobby-screen[data-step=home] #spell-book #page-home")
      assert has_element?(view, "#page-home ul#games.games-list")
      assert has_element?(view, "#page-home #games-scroll + .page-foot #new-game-flow")

      # Another page: the screen's data-step follows the URL.
      {:ok, view, _html} = live(conn, ~p"/?step=players")
      assert has_element?(view, ".lobby-screen[data-step=players]")
    end

    test "Full screen: an icon on the Games page, a button in the game menu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # app.js handles `data-role=fullscreen`; app.css shows the toggle only with
      # `html[data-fullscreen]` and swaps the icon on `:fullscreen`.
      assert has_element?(
               view,
               "#page-home .book-heading button#fullscreen-lobby.fullscreen-toggle[data-role=fullscreen]"
             )

      assert has_element?(view, "#fullscreen-lobby .when-windowed.hero-arrows-pointing-out")
      assert has_element?(view, "#fullscreen-lobby .when-fullscreen.hero-arrows-pointing-in")
      assert has_element?(view, "#fullscreen-lobby .sr-only", "Full screen")

      {:ok, id} = Quacks.GameServer.start(1, {1, 2, 3})
      {:ok, view, _html} = live(conn, ~p"/g/#{id}")

      assert has_element?(
               view,
               "#sheet-menu button#fullscreen-menu.fullscreen-toggle[data-role=fullscreen][type=button]",
               "Full screen"
             )

      assert has_element?(view, "#fullscreen-menu .when-fullscreen", "Exit full screen")
    end
  end

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp css, do: File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

  describe "the viewport lock" do
    test "the game root and the lobby root carry the locked classes" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, game, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/g/#{id}")
      assert has_element?(game, "main[data-layout=full] > .game-grid")

      {:ok, lobby, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/")
      assert has_element?(lobby, "main[data-layout=full] > .lobby-root .lobby-screen #spell-book")
    end

    test "the roots are the screen: 100dvh, width 100%, overflow clip" do
      css = css()

      assert css =~
               ".game-grid,\n.lobby-root {\n  width: 100%;\n  height: 100dvh;\n  overflow: clip;"

      assert css =~ "body {\n  overscroll-behavior: none;"
      # The pages scroll, not the document.
      assert css =~ ".book-page {\n  min-height: 0;\n  overflow-y: auto;"
      refute css =~ ~r/\d+vw\b/
      refute css =~ ~r/\d+vh\b/
      refute css =~ "calc(100dvh - 2rem - 20px)"
    end

    test "the landscape layouts need a wide screen, not only a short one" do
      css = css()
      landscape = ~r/\(orientation: landscape\) and \(max-height: 30rem\)(.{0,30})/

      for [_, rest] <- Regex.scan(landscape, css) do
        assert rest =~ "and (min-width: 35rem)"
      end

      refute css =~ "@media (width < 64rem) and (height < 32rem) {"
    end

    test "the keyboard resizes only the visual viewport" do
      {:ok, _lobby, html} = live(browser("r23-#{System.unique_integer()}"), ~p"/")
      assert html =~ "interactive-widget=resizes-visual"
    end

    test "the Games page: the list, the install button and the credits scroll together" do
      {:ok, view, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/")
      assert has_element?(view, "#page-home #games-scroll > ul#games")
      assert has_element?(view, "#page-home #games-scroll > #install-app")
      assert has_element?(view, "#page-home #games-scroll > footer#credits")
      assert has_element?(view, "#page-home #games-scroll + .page-foot #new-game-flow")
    end
  end

  describe "the New game flow: Back and Start on every page" do
    test "every page of the flow has the bar: the summary, Back, Start" do
      for path <- ~w(/?step=players /?step=witches /?step=patients /?step=rules /?step=books
                     /?step=book&colour=green) do
        {:ok, view, _html} = live(browser("r23-#{System.unique_integer()}"), path)
        refute has_element?(view, "#flow-bar[hidden]"), path
        assert has_element?(view, "#flow-bar [data-role=setup-summary]", "2 players"), path
        assert has_element?(view, "#flow-bar #flow-back", "Back"), path
        assert has_element?(view, "#flow-bar #new-game[phx-click=start]", "Start"), path
      end

      # The pages have no Back arrow of their own any more.
      {:ok, view, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/?step=rules")
      refute has_element?(view, ".book-heading [data-role=back]")
    end

    test "Back on New game goes to Games; from 64rem the books page's Back goes there too" do
      {:ok, view, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/?step=players")
      view |> element("#flow-back") |> render_click()
      assert_patch(view, ~p"/")

      {:ok, view, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/?step=books")
      assert has_element?(view, "#flow-back.lg\\:hidden")
      assert has_element?(view, "#flow-back-home.max-lg\\:hidden[href='/']")
      view |> element("#flow-back") |> render_click()
      assert_patch(view, ~p"/?step=players")
    end

    test "the rows show the current choice; the open page's row is marked" do
      {:ok, view, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/?step=books")
      assert has_element?(view, "#to-books[data-open]", "Beginner")
      assert has_element?(view, "#row-expansion", "Witch cards")
      view |> form("#books", expansion: "true") |> render_change()
      assert has_element?(view, "#row-expansion", "Random witches")
      assert has_element?(view, "#flow-bar [data-role=setup-summary]", "2 players · Herb Witches")

      view |> element("#options") |> render_change(%{"rules" => %{"explode_above" => "9"}})
      assert has_element?(view, "[data-role=rules-summary]", "1 changed")
    end

    test "Start works from a colour page" do
      {:ok, view, _html} =
        live(browser("r23-#{System.unique_integer()}"), ~p"/?step=book&colour=green")

      {:error, {:live_redirect, %{to: "/g/" <> _id}}} =
        view |> element("#new-game") |> render_click()
    end
  end

  doctest QuacksWeb.SetupComponents, import: true, only: [saved_rules: 1]

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

  doctest QuacksWeb.AlchemistsComponents

  @seed {1, 2, 3}

  defp browser_2(name),
    do: init_test_session(build_conn(), player_token: "#{name}-#{System.unique_integer()}")

  defp alchemists(view),
    do: view |> element("#books") |> render_change(%{"alchemists" => "true", "sets" => %{}})

  defp start(view) do
    {:error, {:live_redirect, %{to: "/g/" <> id = to}}} =
      view |> element("#new-game") |> render_click()

    {id, to}
  end

  describe "the spell book's patient picker" do
    test "shows with The Alchemists only: Random and the 3 the seed deals" do
      {:ok, view, _html} = live(browser_2("p1"), ~p"/?seed=1,2,3&step=patients")
      refute has_element?(view, "#lobby-patient")

      alchemists(view)
      assert has_element?(view, "#page-patients #lobby-patient")
      assert has_element?(view, "#lobby-patient [data-patient=random] input[checked]")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#lobby-patient [data-role=patient-option]")
        |> LazyHTML.attribute("data-patient")

      assert ids == ["random" | Enum.map(Essence.dealt(@seed), &Atom.to_string/1)]
    end

    test "a picked patient is yours at once; the game skips your choice" do
      [_a, b, _c] = Essence.dealt(@seed)
      {:ok, view, _html} = live(browser_2("p2"), ~p"/?seed=1,2,3&step=patients")
      alchemists(view)
      view |> element("#lobby-patient") |> render_change(%{"patient" => to_string(b)})
      assert has_element?(view, "#lobby-patient [data-patient=#{b}] input[checked]")

      # a crafted id that is not dealt is Random
      render_change(view, "patient", %{"patient" => "nope"})
      assert has_element?(view, "#lobby-patient [data-patient=random] input[checked]")
      view |> element("#lobby-patient") |> render_change(%{"patient" => to_string(b)})

      render_click(view, "players", %{"count" => "1"})
      {id, _to} = start(view)
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.player(game, 0).patient == b
      assert game.round == 1 and game.phase != :patient_choice
    end
  end

  describe "Start goes straight into the game" do
    test "every seat filled (host and bots): the game page, no waiting panel" do
      conn = browser_2("straight")
      {:ok, view, _html} = live(conn, ~p"/?seed=1,2,3")
      alchemists(view)

      view
      |> element(~s([data-role=seat-slot][data-seat="1"] [data-role=add-bot]))
      |> render_click()

      {id, to} = start(view)
      assert {:ok, %{status: :playing}} = GameServer.get(id)
      {:ok, game_view, _html} = live(conn, to)
      refute has_element?(game_view, "#waiting-panel")
      # Random by default: the host never waits on a patient dialog.
      refute has_element?(game_view, "[data-role=patient-choice]")
    end

    test "an open seat: the waiting panel; the joiner picks a colour and a patient" do
      [a, b, _c] = Essence.dealt(@seed)
      host_conn = browser_2("host")
      {:ok, view, _html} = live(host_conn, ~p"/?seed=1,2,3")
      alchemists(view)
      view |> element("#lobby-patient") |> render_change(%{"patient" => to_string(a)})
      {id, to} = start(view)

      {:ok, host, _html} = live(host_conn, to)
      assert has_element?(host, "#waiting-panel [data-role=waiting-for-players]", "1 of 2 seated")
      assert has_element?(host, "#waiting-panel [data-role=share-link]")
      assert has_element?(host, "#waiting-patient [data-patient=#{a}] input[checked]")
      refute has_element?(host, "#books")
      refute has_element?(host, "#options")

      {:ok, guest, _html} = live(browser_2("guest"), to)
      assert has_element?(guest, ~s([data-seat="1"] [data-role=colour-picker]))
      assert has_element?(guest, "#waiting-patient [data-patient=random] input[checked]")
      guest |> element("#waiting-patient") |> render_change(%{"patient" => to_string(b)})
      assert {:ok, %{patient_picks: %{0 => ^a, 1 => ^b}}} = GameServer.get(id)

      host |> element("[data-role=start-game]") |> render_click()
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.player(game, 0).patient == a
      assert Game.player(game, 1).patient == b
      assert has_element?(guest, "button[data-slot=draw]")
    end

    test "no Alchemists: no patient picker in the waiting panel" do
      {:ok, id} = GameServer.create(%{players: 2}, "host-np", @seed)

      {:ok, view, _html} =
        live(init_test_session(build_conn(), player_token: "host-np"), ~p"/g/#{id}")

      assert has_element?(view, "#waiting-panel")
      refute has_element?(view, "#waiting-patient")
    end
  end

  defp lobby_2(path) do
    conn = init_test_session(build_conn(), player_token: "r29-#{System.unique_integer()}")
    {:ok, view, _html} = live(conn, path)
    view
  end

  describe "New game: one main page" do
    test "the rows say the defaults; no dot and Customise is off while an expansion is off" do
      view = lobby_2(~p"/?step=players")
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
      view = lobby_2(~p"/?step=players")
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
      view = lobby_2(~p"/?seed=1,2,3&step=players")
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
      view = lobby_2(~p"/?step=players")
      view |> element("#preset-set2") |> render_click()
      assert has_element?(view, "#to-books [data-role=changed-dot]")

      view |> element("#options") |> render_change(%{"rules" => %{"explode_above" => "9"}})
      assert has_element?(view, "#to-rules [data-role=changed-dot]")
      assert has_element?(view, "#to-rules", "1 changed")

      # The pot side has its own row; it is no house rule change.
      view = lobby_2(~p"/?step=players")
      view |> element("#options") |> render_change(%{"rules" => %{"pot_side" => "true"}})
      assert has_element?(view, "#to-rules", "As in the rulebook")
    end

    test "the Customise pages keep the bar: Back goes to New game, Start works" do
      for step <- ~w(witches patients books rules) do
        view = lobby_2("/?step=#{step}")
        assert has_element?(view, "#flow-bar #new-game", "Start")
        view |> element("#flow-back") |> render_click()
        assert_patch(view, ~p"/?step=players")
      end
    end
  end

  describe "the waiting panel: Share and the room code" do
    test "Share is the primary button with title, text and link; Copy link is the fallback" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      view = lobby_2(~p"/g/#{id}")

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

    view = lobby_2(~p"/?step=players")
    assert has_element?(view, "#new-game.start-button svg")
    assert has_element?(view, "#new-game-flow.flow-button")
  end

  describe "book tiers by player count and the pot-side checkbox" do
    setup %{conn: conn} do
      %{conn: init_test_session(conn, player_token: "round7-#{System.unique_integer()}")}
    end

    # Round 26: the books are picked in the spell book (its colour pages).
    defp configure(conn, players) do
      {:ok, view, _html} = live(conn, ~p"/?step=books")
      render_click(view, "players", %{"count" => to_string(players)})
      view
    end

    defp rows(html, selector),
      do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

    test "the black tile shows only the rows for the table size" do
      for {players, shown, hidden} <- [
            {1, "1+ black", "same count"},
            {2, "same count", "more than both"},
            {3, "more than both", "1+ black"},
            {6, "more than 1 neighbour", "same count"}
          ] do
        html =
          render_component(&PanelComponents.book_tile/1, colour: :black, set: 1, players: players)

        assert html =~ shown
        refute html =~ hidden
      end

      html = render_component(&PanelComponents.book_list/1, books: [black: 1], players: 2)
      assert rows(html, "[data-role=book-tiers] tr") == 2
    end

    test "the spell book follows the player stepper", %{conn: conn} do
      view = configure(conn, 2)
      # The tiles are compact; the colour page's card has the tier table.
      black = "#page-book-black [data-set='1'] [data-role=book-tiers]"
      picker = black
      assert has_element?(view, black, "same count")
      assert has_element?(view, picker, "same count")

      render_click(view, "players", %{"count" => "3"})
      assert has_element?(view, black, "more than both")
      refute has_element?(view, black, "same count")
      refute has_element?(view, picker, "same count")

      render_click(view, "players", %{"count" => "1"})
      assert has_element?(view, black, "1+ black")
      refute has_element?(view, black, "more than both")
    end

    test "picker cards show the same tier tables as the tiles", %{conn: conn} do
      view = configure(conn, 2)

      for {colour, set, row} <- [
            {:purple, 1, "3+ purple"},
            {:purple, 2, "2 purple"},
            {:purple, 3, "space 10–19"},
            {:purple, 4, "a 1-chip → a 4-chip"},
            {:green, 2, "blue 1 or red 1"},
            {:red, 1, "1–2 orange"},
            {:yellow, 3, "3rd yellow"},
            {:yellow, 4, "4th+ yellow"}
          ] do
        assert has_element?(
                 view,
                 "#page-book-#{colour} [data-set='#{set}'] [data-role=book-tiers]",
                 row
               )
      end

      refute has_element?(view, "#page-book-green [data-set='1'] [data-role=book-tiers]")
    end

    test "orange books carry no text: tile, picker card and book list", %{conn: conn} do
      for set <- [1, 2] do
        html = render_component(&PanelComponents.book_tile/1, colour: :orange, set: set)
        assert rows(html, "[data-role=book-tile] > p") == 0
        assert html =~ "Pumpkin"
      end

      html = render_component(&PanelComponents.book_tile/1, colour: :orange, set: 2)
      assert rows(html, "[data-role=chip]") == 2 or html =~ "22"

      html = render_component(&PanelComponents.book_list/1, books: [orange: 2])
      refute html =~ "No action"
      refute html =~ "·"

      view = configure(conn, 2)
      card = "#page-book-orange [data-set='2']"
      assert has_element?(view, card, "22")
      refute has_element?(view, "#{card} span.text-sm")
    end

    test "the pot-side checkbox sits beside the expansion and still sets the house rule",
         %{conn: conn} do
      view = configure(conn, 2)
      assert has_element?(view, "[data-role=expansion-cards] #expansion[form=books]")
      assert has_element?(view, ~s([data-role=expansion-cards] #rules-pot_side[form="options"]))
      refute has_element?(view, "#options #rules-pot_side")

      view |> element("#options") |> render_change(%{"rules" => %{"pot_side" => "true"}})
      assert has_element?(view, "#rules-pot_side[checked]")
    end
  end
end
