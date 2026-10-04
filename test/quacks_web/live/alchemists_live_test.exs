defmodule QuacksWeb.AlchemistsLiveTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [put: 2, replace_game: 2]
  import Phoenix.ConnTest, except: [put: 2]

  alias Quacks.GameServer

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "al-#{System.unique_integer()}")}
  end

  # A solo Alchemists game without cards; it waits in the patient choice.
  defp live_solo(conn) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, MapSet.new([:alchemists]))
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    {id, view}
  end

  # Past the patient choice with `patient`, then `fields` on seat 0 (and the game).
  defp with_patient(id, patient, fields, game_phase \\ nil) do
    replace_game(id, fn g ->
      g = put(%{g | phase: :potions}, patient: patient, phase: :potions)
      g = put(g, fields)
      if game_phase, do: %{g | phase: game_phase}, else: g
    end)
  end

  test "The Alchemists toggle makes locoweed III selectable", %{conn: conn} do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    card = "#book-picker-locoweed [data-role=book-card][data-set='3']"

    assert has_element?(view, "#alchemists")
    assert has_element?(view, "#{card}[aria-disabled]", "needs The Alchemists")

    view |> form("#books", alchemists: "true") |> render_change()
    refute has_element?(view, "#{card}[aria-disabled]")
    view |> form("#books", alchemists: "true", sets: %{locoweed: "3"}) |> render_change()
    assert {:ok, %{sets: %{locoweed: 3}, expansions: expansions}} = GameServer.get(id)
    assert MapSet.member?(expansions, :alchemists)

    # both expansions together
    view |> form("#books", alchemists: "true", expansion: "true") |> render_change()
    {:ok, table} = GameServer.get(id)
    assert MapSet.equal?(table.expansions, MapSet.new([:alchemists, :herb_witches]))

    # off again: III greys out and falls back to no locoweed
    view |> form("#books", alchemists: "false", expansion: "false") |> render_change()
    assert has_element?(view, "#{card}[aria-disabled]")
    {:ok, table} = GameServer.get(id)
    assert MapSet.size(table.expansions) == 0 and table.sets[:locoweed] == nil
  end

  test "the patient dialog shows 3 cards; a pick starts round 1", %{conn: conn} do
    {id, view} = live_solo(conn)

    assert has_element?(view, "[data-role=patient-choice]", "Choose your patient")

    picks =
      view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("[data-role=patient-pick]")

    assert Enum.count(picks) == 3

    assert has_element?(
             view,
             "[data-role=patient-pick] [data-role=slot-grid] li[data-space='10']"
           )

    refute has_element?(view, "[data-role=flask-strip]")

    view |> element("li:first-child > [data-role=patient-pick]") |> render_click()
    {:ok, %{game: game}} = GameServer.get(id)
    assert game.phase == :potions and game.players[0].patient in game.patients
    refute has_element?(view, "[data-role=patient-choice]")
    assert has_element?(view, "[data-role=patient-badge]")
    assert has_element?(view, "#sheet-patient [data-role=patient-card]")
  end

  test "the flask strip shows the essence marker and the reached slot", %{conn: conn} do
    {id, view} = live_solo(conn)
    with_patient(id, :carrot_nose, essence: 4)

    assert has_element?(view, "[data-role=flask-strip][data-essence='4'][data-spendable]")
    assert has_element?(view, "[data-role=flask-strip] li[aria-current=step]", "4")
    assert has_element?(view, "#sheet-patient [data-space='4'][data-reached]")
    assert has_element?(view, "[data-role=patient-badge]", "Carrot nose")
  end

  test "the essence choice sheet steps down and takes a space", %{conn: conn} do
    {id, view} = live_solo(conn)
    parts = %{colours: 2, locoweed: 0, white7: 0, neighbours: 0}

    replace_game(id, fn g ->
      g
      |> with_essence_choice()
      |> Map.update!(:log, &[{0, :stopped}, {0, {:essence, 2, parts}} | &1])
    end)

    assert has_element?(view, "[data-role=essence-choice]", "Essence: you reach space 2")
    assert has_element?(view, "[data-role=essence-parts]", "2 colours")
    assert has_element?(view, "[data-role=essence-pick]", "Space 2")
    assert has_element?(view, "[data-role=essence-choice]", "lay out 1")

    view |> element("button[aria-label='Lower space']") |> render_click()
    assert has_element?(view, "[data-role=essence-pick]", "Space 1")
    assert has_element?(view, "[data-role=essence-choice] [data-space='1'][data-reached]")

    view |> element("[data-role=essence-take]", "Take space 1") |> render_click()
    {:ok, %{game: game}} = GameServer.get(id)
    assert game.players[0].essence == 1
    refute has_element?(view, "[data-role=essence-choice]")
    view |> element(~s([data-role=player-chip][data-seat="0"])) |> render_click()
    assert has_element?(view, "#sheet-player-0 [data-role=result-line]", "Essence: space 2")
    assert has_element?(view, "#sheet-player-0 [data-role=result-line]", "Essence bonus: rat")
  end

  defp with_essence_choice(g) do
    g = put(%{g | phase: :essence}, patient: :nervousness)
    put(g, phase: :essence_choice, essence_pending: {:space, 2})
  end

  test "a patient offer opens under the drawn chip", %{conn: conn} do
    {id, view} = live_solo(conn)

    with_patient(id, :carrot_nose,
      essence: 3,
      drawn: [{{:orange, 1}, 3}],
      pot_index: 3,
      phase: :essence_offer,
      essence_pending: {:offers, [{:carrot, {:orange, 1}}]}
    )

    assert has_element?(view, "[aria-label='Patient offer']", "Carrot nose: you drew a pumpkin.")
    assert has_element?(view, "[aria-label='Patient offer'] [data-role=offer-chip]")
    assert has_element?(view, "button", "No")

    view
    |> element("button", "Spend 2 essence: pumpkin to the next ruby space")
    |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    assert game.players[0].essence == 1
    assert has_element?(view, "li", "Spent 2 essence: pumpkin to the next ruby space")
  end

  test "Nervousness lays chips out above Draw; Forgetfulness returns a pot chip", %{conn: conn} do
    {id, view} = live_solo(conn)
    with_patient(id, :nervousness, display: [{:green, 1}], essence: 3)

    assert has_element?(view, "[data-role=display] [data-role=display-chip]")
    view |> element("[data-role=display-chip]") |> render_click()
    {:ok, %{game: game}} = GameServer.get(id)
    assert game.players[0].display == [] and {{:green, 1}, 1} in game.players[0].drawn

    with_patient(id, :forgetfulness, essence: 3, drawn: [{{:red, 1}, 1}], pot_index: 1)
    assert has_element?(view, "[data-role=forget-button]", "Forget a chip")
    view |> element("[data-role=forget-chip]", "Return (−1)") |> render_click()
    {:ok, %{game: game}} = GameServer.get(id)
    assert game.players[0].essence == 2 and game.players[0].drawn == []
  end

  test "Ear worm draws with the Draw button", %{conn: conn} do
    {id, view} = live_solo(conn)

    with_patient(
      id,
      :ear_worm,
      [phase: :ear_worm, essence_pending: {:ear_worm, 2}],
      :essence
    )

    assert has_element?(view, "[data-role=ear-worm]", "Ear worm: draw 2 more, no explosion")
    refute has_element?(view, "[data-slot=draw][disabled]")
  end
end
