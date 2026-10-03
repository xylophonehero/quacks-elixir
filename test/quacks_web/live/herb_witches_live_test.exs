defmodule QuacksWeb.HerbWitchesLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias Quacks.Rules.{Chips, Witches}
  alias QuacksWeb.{GameComponents, GameLive, SetupComponents}

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "hw-#{System.unique_integer()}")}
  end

  # A solo expansion game without cards: seed 1,2,3 deals S2, C4 and G4.
  defp live_solo(conn) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    {id, view}
  end

  test "the host's toggle offers Sets 5–6 and 5 players", %{conn: conn} do
    {:ok, id} = GameServer.start(4)
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    assert has_element?(view, "button[aria-label='More players'][disabled]")
    refute has_element?(view, "select[name='sets[green]'] option[value='6']")

    view |> form("#books", expansion: "true") |> render_change()

    view
    |> form("#books", expansion: "true", sets: %{green: "5", black: "6", locoweed: "6"})
    |> render_change()

    assert has_element?(view, "select[name='sets[green]'] option[value='6']")
    assert has_element?(view, "select[name='sets[black]'] option", "Base")

    view |> element("button[aria-label='More players']") |> render_click()
    assert {:ok, %{status: :waiting, game: nil, max_players: 5}} = GameServer.get(id)
    assert has_element?(view, "[data-role=waiting-for-players]", "1 of 5 seated")

    # the creator may start alone
    view |> element("button", "Start game") |> render_click()
    {:ok, %{game: game, players: 1}} = GameServer.get(id)
    assert game.expansion == :herb_witches and game.seats == [0]
    assert %{green: 5, black: 6, locoweed: 6} = game.sets
  end

  test "parse_sets keeps Sets 5-6 and locoweed only with the expansion; black always" do
    params = %{"green" => "6", "black" => "5", "locoweed" => "9"}

    assert SetupComponents.parse_sets(params) == %{
             green: 1,
             blue: 1,
             red: 1,
             yellow: 1,
             purple: 1,
             black: 5
           }

    assert SetupComponents.parse_sets(params, true) ==
             %{green: 6, blue: 1, red: 1, yellow: 1, purple: 1, black: 5, locoweed: 5}
  end

  test "the page shows the 3 witches and the bowl; a call opens the silver offer", %{conn: conn} do
    {_id, view} = live_solo(conn)
    assert has_element?(view, "button[popovertarget=sheet-witches]", "Witches")
    assert has_element?(view, "#sheet-witches [data-role=witch-card]", "Draw 6 chips")
    assert has_element?(view, "#sheet-witches [data-witch=c4]")
    assert has_element?(view, "#sheet-witches [data-witch=g4]")
    # the bowl shows only once it has chips
    refute has_element?(view, "[data-role=bowl]")
    # witch calls are on the cards, not in the bottom bar
    refute has_element?(view, "section[aria-label=Actions] button", "witch")

    view |> element("#sheet-witches [data-witch=s2] button", "Call") |> render_click()
    assert has_element?(view, "[aria-label='Silver witch offer']", "The silver witch drew:")
    assert has_element?(view, "button", "Silver witch: return the rest to the bag")
    assert has_element?(view, "[data-witch=s2]", "penny spent")
    assert has_element?(view, "li", "Draw 6 chips: drew 6 chips")
  end

  test "the shop has the orange 6 and locoweed row and the copper witch", %{conn: conn} do
    {id, _view} = live_solo(conn)
    {:ok, _} = GameServer.apply(id, 0, :draw)
    {:ok, _} = GameServer.apply(id, 0, :stop)
    {:ok, %{game: game}} = GameServer.get(id)
    assert game.phase == :shopping

    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    html = view |> render() |> LazyHTML.from_fragment()

    rows = LazyHTML.query(html, "[data-role=shop-row]")

    labels =
      &(rows |> Enum.at(&1) |> LazyHTML.query("[aria-label]") |> LazyHTML.attribute("aria-label"))

    assert labels.(0) == ["orange 1", "orange 6"]
    assert labels.(-1) == ["locoweed 1"]

    assert has_element?(
             view,
             "#decision-shop [data-witch=c4] button",
             "Call the copper witch"
           )

    assert GameLive.shop_rows(:herb_witches) |> List.flatten() |> Enum.sort() ==
             Chips.shop(:herb_witches)
  end

  test "a base game shows no witches and no bowl", %{conn: conn} do
    {:ok, id} = GameServer.start(1, {1, 2, 3})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    refute has_element?(view, "[data-role=witch-card]")
    refute has_element?(view, "[data-role=bowl]")
  end

  test "every witch, choice book and Herb Witches log entry has a human label" do
    chip = {:green, 1}

    actions =
      [
        {:witch, :silver},
        {:witch, :copper},
        {:witch, :gold},
        {:witch, :silver, 1},
        {:witch, :silver, 2},
        {:witch, :silver, {:place, chip}},
        {:witch, :silver, :return_all},
        {:witch, :copper, {:upgrade, [chip, {:red, 2}]}},
        {:witch, :copper, {:buy, [chip], chip}},
        :witch_done,
        {:chip, :yellow_ruby},
        {:chip, {:starter, chip}},
        {:chip, {:buy, [chip, {:locoweed, 1}]}},
        {:red, {:place, chip}}
      ]

    outcomes = %{
      s1: :flask,
      s2: {:offer, 6},
      s3: {:return_white, 2},
      s4: :no_penalty,
      c1: {:upgrade, [chip]},
      c2: {:coins, 14},
      c3: {:copy, chip},
      c4: {:coins, 6},
      g1: {:vp, 7},
      g2: {:vp, 4},
      g3: {:rubies, 2},
      g4: :ruby_price
    }

    witch_events = for {id, outcome} <- outcomes, do: {:witch, id, outcome}

    effects = [
      {{:red, 5}, {:extra, 2}},
      {{:red, 6}, {:aside, chip}},
      {{:yellow, 5}, {:peek, chip}},
      {{:yellow, 6}, {:extra, 3}},
      {{:blue, 5}, {:vp, 2}},
      {{:blue, 6}, {:rubies, 1}},
      {{:green, 5}, {:starter, chip}},
      {{:green, 5}, {:first, chip}},
      {{:green, 6}, {:bonus_die, :ruby}},
      {{:purple, 5}, {:bought, [chip]}},
      {{:purple, 5}, {:vp, 3}},
      {{:purple, 6}, {:vp, 4}},
      {{:black, 5}, {:to_left, 1}},
      {{:black, 5}, :to_supply},
      {{:black, 5}, {:rubies, 2}},
      {{:black, 6}, :droplet},
      {{:black, 6}, :ruby},
      {{:black, 6}, :droplet_ruby},
      {{:locoweed, 5}, {:moves, 3}},
      {{:locoweed, 6}, {:copied, {:red, 4}}}
    ]

    events =
      [
        {:overflow, chip},
        {:bowl, [chip], 0},
        {:pennies, 4},
        {:rubies_spent, :droplet, 1},
        {:rubies_spent, :flask, 1},
        {:expansion, :herb_witches}
      ] ++ witch_events ++ for({book, detail} <- effects, do: {:effect, book, detail})

    for term <- actions ++ events do
      refute GameComponents.label(term) =~ ~r/^[:{]/, "no label for #{inspect(term)}"
    end

    for id <- Enum.flat_map([:silver, :copper, :gold], &Witches.ids/1),
        do: assert(Map.has_key?(outcomes, id))

    assert GameComponents.label({:witch, :g4, :ruby_price}) ==
             "Cheap rubies: droplet and flask cost 1 ruby"

    assert GameComponents.phase_name(:witch_choice) == "Gold witch"
    assert GameComponents.chip_name({:locoweed, 1}) == "locoweed"
  end

  test "the gold witch choice is a dialog with her card", %{conn: conn} do
    {id, view} = live_solo(conn)
    {:ok, %{game: game}} = GameServer.get(id)
    assert %{gold: :g4} = game.witches
    # G4 is called in the rubies turn: play to it
    {:ok, _} = GameServer.apply(id, 0, :draw)
    {:ok, _} = GameServer.apply(id, 0, :stop)
    {:ok, _} = GameServer.apply(id, 0, {:buy, []})

    assert has_element?(view, "#decision-shop [data-witch=g4]")
    view |> element("#decision-shop button", "Call the gold witch") |> render_click()
    assert has_element?(view, "li", "Cheap rubies: droplet and flask cost 1 ruby")
    assert Game.legal_actions(elem(GameServer.get(id), 1).game, 0) |> List.last() == :end_round
  end
end
