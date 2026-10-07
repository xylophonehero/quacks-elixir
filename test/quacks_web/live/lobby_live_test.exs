defmodule QuacksWeb.LobbyLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer
  alias Quacks.Rules.Books

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "lobby-#{System.unique_integer()}")}
  end

  test "the lobby is a spell book of pages, one per step", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "[data-bookmark]")
    assert has_element?(view, "#spell-book[data-step=home]")

    # Every page is in the DOM; the server hides all but the step's page on a phone.
    for page <- ~w(home players expansions rules books book-green book-locoweed) do
      assert has_element?(view, "#page-#{page}")
    end

    assert has_element?(view, "#page-home.flex #room-code-form #room-code")
    assert has_element?(view, "#page-home #new-game-flow[href='/?step=players']", "New game")
    assert has_element?(view, "#page-players.hidden")

    # New game: count, seats, you, Public, then Expansions and Ingredient books,
    # each with a line on the current choice. Round 25: no House rules row here.
    assert has_element?(view, "#page-players [data-role=count]", "2")
    assert has_element?(view, "#page-players #seat-name")
    assert has_element?(view, "#page-players [data-role=colour-picker]")
    assert has_element?(view, "#page-players #public[checked]")
    refute has_element?(view, "#page-players #to-rules")
    assert has_element?(view, "#page-players #to-expansions", "Base game")
    assert has_element?(view, "#page-players #to-books", "Beginner (Set 1)")
    # Expansions: the three rows, then the House rules row (round 25).
    assert has_element?(
             view,
             "#page-expansions [data-role=expansion-cards] [data-role=toggle-card]"
           )

    assert has_element?(view, "#page-expansions #expansion[form=books]")
    assert has_element?(view, "#page-expansions #rules-pot_side[form=options]")
    assert has_element?(view, "#page-expansions #to-rules", "Default rules")
    refute has_element?(view, "#page-expansions #to-books")
    # One bar for the flow, under the pages, hidden on the Games page.
    assert has_element?(view, "#flow-bar[hidden] #new-game", "Start")
    assert has_element?(view, "#page-rules #options")
    # Books: presets, the tiles as links to the colour pages, no sheets.
    assert has_element?(view, "#page-books #preset-beginner[aria-pressed=true]")
    assert has_element?(view, "#page-books #preset-random")
    assert has_element?(view, "#page-books #book-link-green[href='/?step=book&colour=green']")
    refute has_element?(view, "#book-picker-green")
    assert has_element?(view, "#page-book-green [data-role=book-card] input[form=books]")

    {:ok, view, _html} = live(conn, ~p"/?page=join")
    assert has_element?(view, "#spell-book[data-step=home]")
  end

  test "New game is a flow of pages: the three rows, Back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#new-game-flow") |> render_click()
    assert_patch(view, ~p"/?step=players")
    assert has_element?(view, "#page-players.flex")
    assert has_element?(view, "#page-home.hidden")

    refute has_element?(view, "#flow-bar[hidden]")

    view |> element("#to-expansions") |> render_click()
    assert_patch(view, ~p"/?step=expansions")
    assert has_element?(view, "#page-expansions.flex")

    {:ok, view, _html} = live(conn, ~p"/?step=expansions")
    view |> element("#to-rules") |> render_click()
    assert_patch(view, ~p"/?step=rules")
    assert has_element?(view, "#page-rules.flex")

    # The visit began on New game, so Back on a step is the browser's history.
    assert view |> element("#flow-back") |> render() =~ "quacks:back"

    # Opened at a deep step, Back patches to the parent page: New game.
    {:ok, view, _html} = live(conn, ~p"/?step=books")
    assert has_element?(view, "#page-books.flex")
    view |> element("#flow-back") |> render_click()
    assert_patch(view, ~p"/?step=players")

    # A bad step is home; a witch page without The Herb Witches is the books page.
    {:ok, view, _html} = live(conn, ~p"/?step=nope")
    assert has_element?(view, "#page-home.flex")
    {:ok, view, _html} = live(conn, ~p"/?step=witch&colour=copper")
    assert has_element?(view, "#page-books.flex")
  end

  test "a book tile opens its colour's page; a pick applies and goes back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?step=books")

    view |> element("#book-link-green") |> render_click()
    assert_patch(view, ~p"/?step=book&colour=green")
    assert has_element?(view, "#page-book-green.flex")

    assert has_element?(
             view,
             "#page-book-green [data-role=book-card][data-set='1'] input[checked]"
           )

    # The cards belong to #books: a pick is that form's change.
    view |> element("#books") |> render_change(%{"sets" => %{"green" => "4"}})
    assert books(view)["green"] == "4"

    assert has_element?(
             view,
             "#page-book-green [data-role=book-card][data-set='4'] input[checked]"
           )

    # The list was the page before: a pick goes back in the history.
    assert view |> element("#page-book-green [data-set='4'] input") |> render() =~ "quacks:back"

    # Opened at the colour page directly, a pick patches to the list.
    {:ok, direct, _html} = live(conn, ~p"/?step=book&colour=green")

    assert direct |> element("#page-book-green [data-set='4'] input") |> render() =~
             "/?step=books"

    # The witch pages follow the same pattern with The Herb Witches.
    view |> element("#books") |> render_change(%{"expansion" => "true", "sets" => %{}})
    assert has_element?(view, "#witch-link-copper[href='/?step=witch&colour=copper']")
    view |> element("#witch-link-copper") |> render_click()

    assert has_element?(
             view,
             "#page-witch-copper.flex [data-role=witch-option] input[form=books]"
           )
  end

  test "a preset applies its books; a manual change is Custom; saved with the config",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?step=books")
    assert has_element?(view, "[data-role=preset-label]", "Beginner (Set 1)")

    view |> element("#preset-set3") |> render_click()
    assert_push_event(view, "save_config", %{preset: "set3"})
    assert has_element?(view, "#preset-set3[aria-pressed=true]")

    assert books(view) |> Map.drop(~w(orange black locoweed)) |> Map.values() |> Enum.uniq() == [
             "3"
           ]

    view |> element("#books") |> render_change(%{"sets" => %{"green" => "4", "blue" => "3"}})
    assert has_element?(view, "[data-role=preset-label]", "Custom")
    refute has_element?(view, "[data-role=preset][aria-pressed=true]")

    # A preset turns on the expansion it needs.
    view |> element("#preset-strategic") |> render_click()
    assert has_element?(view, "#expansion[checked]")
    assert books(view)["green"] == "5"
    assert books(view)["purple"] == "4"

    # The saved config brings the preset back.
    render_hook(view, "load_config", %{
      "sets" => %{
        "green" => "2",
        "blue" => "2",
        "red" => "2",
        "yellow" => "2",
        "purple" => "2",
        "black" => "1"
      }
    })

    assert has_element?(view, "#preset-set2[aria-pressed=true]")
  end

  test "Start with an open seat opens the table at the configure screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#rename-form") |> render_change(%{"name" => "Ann"})
    render_click(view, "colour", %{"colour" => "3"})
    render_click(view, "players", %{"count" => "3"})

    view
    |> element("[data-role=seat-slot][data-seat=\"2\"] [data-role=add-bot]")
    |> render_click()

    view |> element("#table-form") |> render_change(%{"public" => "false"})
    view |> element("#options") |> render_change(%{"rules" => %{"explode_above" => "9"}})

    assert has_element?(view, "[data-role=setup-summary]", "3 players · 1 bot · private")
    assert has_element?(view, "[data-role=setup-summary]", "1 seat waits for a player")

    {:error, {:live_redirect, %{to: "/g/" <> id = to}}} =
      view |> element("#new-game") |> render_click()

    {:ok, game_view, _html} = live(conn, to)
    assert has_element?(game_view, "[data-role=waiting-for-players]", "2 of 3 seated")
    assert has_element?(game_view, "button[phx-click=begin]", "Start game")
    {:ok, table} = GameServer.get(id)
    assert table.names[0] == "Ann"
    assert table.colours[0] == 3
    assert Map.keys(table.bots) == [2]
    refute table.public
    assert table.rules.explode_above == 9
  end

  test "Start with every seat taken begins the game at once", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?seed=1,2,3")

    view
    |> element("[data-role=seat-slot][data-seat=\"1\"] [data-role=add-bot]")
    |> render_click()

    assert has_element?(view, "[data-role=setup-summary]", "begins at once")

    {:error, {:live_redirect, %{to: "/g/" <> id}}} =
      view |> element("#new-game") |> render_click()

    assert {:ok, %{status: :playing, seed: {1, 2, 3}}} = GameServer.get(id)
  end

  test "Random picks a valid book per colour; Beginner goes back to book I", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    picks =
      for _ <- 1..15 do
        view |> element("#preset-random") |> render_click()
        books(view)
      end

    for picked <- picks do
      assert picked["locoweed"] == "off"
      assert picked["black"] in ~w(1 2 3)
      assert picked["orange"] in ~w(1 2)
      assert picked["green"] in ~w(1 2 3 4 5 6)
    end

    assert length(Enum.uniq(picks)) > 1

    # With The Alchemists locoweed is in play too.
    view |> element("#books") |> render_change(%{"alchemists" => "true", "sets" => %{}})
    view |> element("#preset-random") |> render_click()
    assert books(view)["locoweed"] in ~w(1 2 3 4 5 6)
    assert has_element?(view, "#preset-random[aria-pressed=true]")

    view |> element("#preset-beginner") |> render_click()
    assert books(view) |> Map.delete("locoweed") |> Map.values() |> Enum.uniq() == ["1"]
  end

  test "the book opens with the browser's last settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "load_config", %{
      "players" => 4,
      "bots" => [1, 3, 6],
      "public" => false,
      "colour" => 5,
      "sets" => %{"green" => "4"},
      "expansion" => true
    })

    assert has_element?(view, "[data-role=count]", "4")
    assert has_element?(view, "[data-role=seat-slot][data-seat=\"1\"] [data-role=remove-bot]")
    assert has_element?(view, "[data-role=seat-slot][data-seat=\"3\"] [data-role=remove-bot]")
    refute has_element?(view, "#public[checked]")
    assert has_element?(view, "[data-role=witch-pickers]")
    assert has_element?(view, ~s([data-role=colour-picker] [data-colour="5"][aria-pressed=true]))
  end

  test "the Join page lists public games and yours: Join, Resume, Watch, live", %{conn: conn} do
    {:ok, open} = GameServer.start(3)
    {:ok, hidden} = GameServer.create(%{players: 3, public: false}, "someone-else")
    {:ok, running} = GameServer.create(%{players: 2, bots: [1]}, "someone-else")
    {:ok, view, _html} = live(conn, ~p"/?page=join")

    assert has_element?(view, "#game-#{open}", "0 of 3 seated")
    assert has_element?(view, ~s(#game-#{open} a[href="/g/#{open}"]), "Join")
    refute has_element?(view, "#game-#{hidden}")
    assert has_element?(view, "#game-#{running} [data-role=game-status]", "Round 1 of 9")
    assert has_element?(view, "#game-#{running} [data-role=game-action]", "Watch")

    {:ok, new_id} = GameServer.start(2)
    assert has_element?(view, "#game-#{new_id}")
  end

  test "your own private game shows with Resume", %{conn: conn} do
    token = get_session(conn, :player_token)
    {:ok, mine} = GameServer.create(%{players: 3, public: false}, token)
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#game-#{mine} [data-role=game-action]", "Resume")
  end

  test "a room code (or a game link) joins that game; a bad one says so", %{conn: conn} do
    {:ok, id} = GameServer.create(%{players: 2, public: false}, "someone-else")
    {:ok, view, _html} = live(conn, ~p"/")

    {:error, {:live_redirect, %{to: to}}} =
      view |> element("#room-code-form") |> render_submit(%{"code" => " #{String.upcase(id)} "})

    assert to == "/g/#{id}"

    {:ok, view, _html} = live(conn, ~p"/")

    {:error, {:live_redirect, %{to: ^to}}} =
      view
      |> element("#room-code-form")
      |> render_submit(%{"code" => "https://quacks.example/g/#{id}"})

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#room-code-form") |> render_submit(%{"code" => "zzzzzz"})
    assert render(view) =~ "No game has the room code"
  end

  test "the host's Options set house rules for the game", %{conn: conn} do
    # A fixed seed: some random first fortunes open a choice, which hides the fuse.
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")

    view
    |> element("#options")
    |> render_change(%{"rules" => %{"explode_above" => "9", "rats" => "false"}})

    render_click(view, "players", %{"count" => "1"})
    view |> element("button", "Start game") |> render_click()

    assert has_element?(view, ~s(#fuse-meter[data-white="0"][data-limit="9"]), "0 / 9")
    assert has_element?(view, "[data-role=house-rules]", "explodes above 9 · no rats")
  end

  test "a default game shows no house rules", %{conn: conn} do
    {:ok, id} = GameServer.start(1)
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    refute has_element?(view, "[data-role=house-rules]")
  end

  test "parse_rules keeps the default for a missing or bad value" do
    rules =
      QuacksWeb.SetupComponents.parse_rules(%{"explode_above" => "12", "die" => "no_orange"})

    assert rules == %{Quacks.Game.default_rules() | die: :no_orange}

    assert QuacksWeb.SetupComponents.parse_rules(%{
             "starting_rubies" => "0",
             "fortune" => "false"
           }) ==
             %{Quacks.Game.default_rules() | starting_rubies: 0, fortune: false}
  end

  test "the black chips by standings rule: an Options radio, the house-rules line and the book",
       %{conn: conn} do
    {:ok, id} = GameServer.start(3, {1, 2, 3})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    # Round 25: standings is the default.
    assert has_element?(view, "#rules-black_rule-standings[checked]")

    view
    |> element("#options")
    |> render_change(%{"rules" => %{"black_rule" => "neighbours", "fortune" => "false"}})

    assert has_element?(view, "#rules-black_rule-neighbours[checked]")
    assert {:ok, %{rules: %{black_rule: :neighbours}}} = GameServer.get(id)

    assert QuacksWeb.SetupComponents.parse_rules(%{"black_rule" => "standings"}).black_rule ==
             :standings

    book = Books.get({:black, 1}, %{black_rule: :standings})
    assert book.text =~ "ranked above you"
    assert Books.get({:black, 1}, %{black_rule: :neighbours}).text =~ "other players"

    render_click(view, "players", %{"count" => "1"})
    view |> element("button", "Start game") |> render_click()
    assert has_element?(view, "[data-role=house-rules]", "black chips by neighbours")
  end

  # The book each colour's tile shows now: "1".."6", or "off".
  defp books(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#books [data-role=book-tile]")
    |> Enum.map(fn tile ->
      [colour, set] = tile |> LazyHTML.attribute("data-book") |> hd() |> String.split("-")
      {colour, set}
    end)
    |> Map.new()
  end
end
