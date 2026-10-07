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
    # Round 26: the books are picked in the spell book.
    {:ok, view, _html} = live(conn, ~p"/?seed=1,2,3&step=book&colour=locoweed")
    card = "#page-book-locoweed [data-role=book-card][data-set='3']"
    books = fn params -> view |> element("#books") |> render_change(params) end

    assert has_element?(view, "#alchemists")
    assert has_element?(view, "#{card}[aria-disabled]", "needs The Alchemists")

    books.(%{"alchemists" => "true", "sets" => %{}})
    refute has_element?(view, "#{card}[aria-disabled]")
    books.(%{"alchemists" => "true", "expansion" => "true", "sets" => %{"locoweed" => "3"}})
    assert has_element?(view, "#books [data-book=locoweed-3]")

    # off again: III greys out and falls back to no locoweed
    books.(%{"alchemists" => "false", "sets" => %{"locoweed" => "3"}})
    assert has_element?(view, "#{card}[aria-disabled]")
    assert has_element?(view, "#books [data-book=locoweed-off]")

    # both expansions together reach the game
    books.(%{"alchemists" => "true", "expansion" => "true", "sets" => %{"locoweed" => "3"}})
    render_click(view, "players", %{"count" => "1"})

    {:error, {:live_redirect, %{to: "/g/" <> id}}} =
      view |> element("#new-game") |> render_click()

    {:ok, %{game: game, expansions: expansions}} = GameServer.get(id)
    assert MapSet.equal?(expansions, MapSet.new([:alchemists, :herb_witches]))
    assert game.sets.locoweed == 3
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

  describe "the essence preview while brewing" do
    # 3 colours (orange, green, red) + white 3 + 4 = 7: reach 4; essence still 2.
    @pot [{{:white, 3}, 0}, {{:orange, 1}, 1}, {{:white, 4}, 2}, {{:green, 1}, 3}, {{:red, 1}, 4}]

    test "a ghost stands at colours + 1 for white 7; the marker stays", %{conn: conn} do
      {id, view} = live_solo(conn)
      with_patient(id, :carrot_nose, essence: 2, drawn: @pot)

      assert has_element?(view, "#essence-ghost-0-lg[data-space='4']", "now")
      view |> element(~s([data-role=player-chip][data-seat="0"])) |> render_click()
      assert has_element?(view, "#sheet-player-0 #essence-ghost-0-sm[data-space='4']")
      assert has_element?(view, "[data-role=flask-strip][data-essence='2']")
    end

    test "no ghost outside the brewing phase", %{conn: conn} do
      {id, view} = live_solo(conn)
      with_patient(id, :carrot_nose, [essence: 2, drawn: @pot], :essence)

      refute has_element?(view, "[data-role=essence-ghost]")
    end

    test "no ghost on an opponent's flask strip" do
      {:ok, id} =
        GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false}, MapSet.new([:alchemists]))

      browser = fn name -> init_test_session(build_conn(), player_token: name) end
      {:ok, alice, _} = live(browser.("alice-#{id}"), ~p"/g/#{id}")
      {:ok, _bob, _} = live(browser.("bob-#{id}"), ~p"/g/#{id}")
      alice |> element("button", "Start game") |> render_click()

      replace_game(id, fn g ->
        g =
          Quacks.GameHelpers.put(%{g | phase: :potions}, 0,
            patient: :carrot_nose,
            phase: :potions
          )

        Quacks.GameHelpers.put(g, 1, patient: :vampirism, drawn: @pot, phase: :potions)
      end)

      assert has_element?(alice, "#essence-ghost-0-lg[data-space='0']")
      alice |> element(~s([data-role=player-chip][data-seat="1"])) |> render_click()
      assert has_element?(alice, "#sheet-player-1 [data-role=flask-strip]")
      refute has_element?(alice, "#sheet-player-1 [data-role=essence-ghost]")
    end
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

    # a ruby to spend keeps the shop open (with nothing to do it would end the round)
    replace_game(id, &put(&1, rubies: 2))
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

  describe "round 15: glass rewards and opponents' patients" do
    test "the flask strip draws what every glass pays", %{conn: conn} do
      {id, view} = live_solo(conn)
      with_patient(id, :chicken_eyes, essence: 3)

      rewards = "[data-role=flask-strip] [data-role=glass-rewards]"

      for space <- 1..10 do
        assert has_element?(view, "#{rewards} li[data-space='#{space}'] [data-glyph]")
      end

      refute has_element?(view, "#{rewards} li[data-space='0'] [data-glyph]")
      assert has_element?(view, "#{rewards} li[data-space='1'] [data-glyph=ruby]")
      assert has_element?(view, "#{rewards} li[data-space='2'] [data-glyph=chip]")
      assert has_element?(view, "#{rewards} li[data-space='8'] [data-glyph=droplet]", "+2")
      assert has_element?(view, "#{rewards} li[data-space='3'][data-reached]")
    end

    test "VP glasses show the seal with the number; empty glasses show nothing", %{conn: conn} do
      {id, view} = live_solo(conn)
      with_patient(id, :carrot_nose, essence: 0)

      rewards = "[data-role=flask-strip] [data-role=glass-rewards]"
      assert has_element?(view, "#{rewards} li[data-space='10'] [data-glyph=vp]", "2")
      assert has_element?(view, "#{rewards} li[data-space='1'] [data-glyph=rat]")
      refute has_element?(view, "#{rewards} li[data-space='2'] [data-glyph]")
    end

    test "the player sheet shows an opponent's patient, glasses and fill" do
      {:ok, id} =
        GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false}, MapSet.new([:alchemists]))

      browser = fn name -> init_test_session(build_conn(), player_token: name) end
      {:ok, alice, _} = live(browser.("alice-#{id}"), ~p"/g/#{id}")
      {:ok, _bob, _} = live(browser.("bob-#{id}"), ~p"/g/#{id}")
      alice |> element("button", "Start game") |> render_click()

      replace_game(id, fn g ->
        g =
          Quacks.GameHelpers.put(%{g | phase: :potions}, 0,
            patient: :carrot_nose,
            phase: :potions
          )

        Quacks.GameHelpers.put(g, 1, patient: :vampirism, essence: 5, phase: :potions)
      end)

      chip = ~s([data-role=player-chip][data-seat="1"])
      assert has_element?(alice, "#{chip} [data-role=player-patient]")
      alice |> element(chip) |> render_click()

      card = "#sheet-player-1 [data-role=player-patient-card][data-patient=vampirism]"
      assert has_element?(alice, card, "Vampirism")
      assert has_element?(alice, card, "buy 1 chip")
      assert has_element?(alice, "#{card} [data-role=flask-strip][data-essence='5']")

      assert has_element?(
               alice,
               "#{card} [data-role=glass-rewards] li[data-space='5'][data-reached]"
             )

      assert has_element?(alice, "#{card} li[data-space='6'] [data-glyph=coin]", "6")
    end
  end
end
