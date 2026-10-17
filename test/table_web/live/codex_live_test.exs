defmodule TableWeb.CodexLiveTest do
  @moduledoc """
  The Codex sandbox pages: `/games` → `/games/codex/new` → a room at
  `/games/codex/<code>`. Hot-seat: one browser moves the cards of both sides.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import QuacksWeb.LiveHelpers

  alias Table.Server

  @key "codex"

  defp room(_ctx \\ %{}) do
    token = token("cx")
    {:ok, code} = Server.create(@key, %{opts: %{}, name: "Ann"}, token)
    {:ok, view, _} = live(browser(token), "/games/#{@key}/#{code}")
    %{view: view, code: code, token: token}
  end

  # The sandbox tests: free mode on.
  defp free_room do
    %{view: view} = r = room()
    view |> element("#cx-free") |> render_click()
    r
  end

  # A room with a prepared game (`Codex.TestHelpers`).
  defp room_with(game) do
    token = token("cx")
    {:ok, code} = Server.create(@key, %{opts: %{}, name: "Ann"}, token)
    [{pid, _}] = Registry.lookup(Table.Registry, {@key, code})
    :sys.replace_state(pid, &%{&1 | game: game})
    {:ok, view, _} = live(browser(token), "/games/#{@key}/#{code}")
    %{view: view, code: code}
  end

  defp game(code), do: Server.state(@key, code).game
  defp zone(code, seat, z), do: game(code).sides[seat].zones[z]

  test "pick, create: the room shows both sides", %{conn: conn} do
    conn = init_test_session(conn, player_token: token("host"))
    {:ok, games, _} = live(conn, "/games")
    assert has_element?(games, "#pick-codex")

    {:ok, setup, _} = games |> element("#pick-codex") |> render_click() |> follow_redirect(conn)

    assert {:error, {:live_redirect, %{to: "/games/codex/" <> _ = to}}} =
             setup |> form("#codex-setup", setup: %{name: "Ann"}) |> render_submit()

    {:ok, room, _} = live(conn, to)

    for seat <- [0, 1] do
      assert has_element?(room, "#cx-side-#{seat}")
      assert has_element?(room, "#cx-zone-#{seat}-hand")
      assert has_element?(room, "#cx-zone-#{seat}-in_play")
      assert has_element?(room, "#cx-zone-#{seat}-command")
      assert has_element?(room, "#cx-deck-#{seat}")
      assert has_element?(room, "#cx-discard-#{seat}")
      assert has_element?(room, "#cx-codex-#{seat}")
      assert has_element?(room, "#cx-workers-#{seat}")

      for slot <- Codex.Game.patrol_slots(),
          do: assert(has_element?(room, "#cx-slot-#{seat}-#{slot}"))
    end

    assert has_element?(room, "#cx-trash")
    assert has_element?(room, "#cx-workers-1-count", "5")
  end

  test "tap a card, tap a patrol slot: the card moves" do
    %{view: view, code: code} = free_room()
    [id | _] = zone(code, 0, :hand)

    view |> element("#cx-card-#{id}") |> render_click()
    assert has_element?(view, "#cx-actions")
    view |> element("#cx-slot-0-elite") |> render_click()

    assert zone(code, 0, :patrol).elite == id
    assert has_element?(view, "#cx-slot-0-elite #cx-card-#{id}")
    refute has_element?(view, "#cx-actions")
  end

  test "a drop from the hook moves a card to the other side's in play, at an index" do
    %{view: view, code: code} = free_room()
    [a, b | _] = zone(code, 0, :hand)

    render_hook(view, "move", %{
      "id" => to_string(a),
      "seat" => "1",
      "zone" => "in_play",
      "slot" => "",
      "index" => nil
    })

    render_hook(view, "move", %{
      "id" => to_string(b),
      "seat" => "1",
      "zone" => "in_play",
      "slot" => "",
      "index" => 0
    })

    assert zone(code, 1, :in_play) == [b, a]
    assert has_element?(view, "#cx-zone-1-in_play #cx-card-#{a}")
  end

  test "tokens on the selected card, to discard and trash" do
    %{view: view, code: code} = free_room()
    [hero] = zone(code, 0, :command)
    [a | _] = zone(code, 0, :hand)

    view |> element("#cx-card-#{hero}") |> render_click()
    view |> element("#cx-act-level-plus") |> render_click()
    view |> element("#cx-act-damage-plus") |> render_click()
    view |> element("#cx-act-exhaust") |> render_click()
    assert %{level: 2, damage: 1, exhausted: true} = game(code).cards[hero]
    assert has_element?(view, "#cx-act-level", "2")

    view |> element("#cx-act-plus-plus") |> render_click()
    view |> element("#cx-act-minus-plus") |> render_click()
    assert %{plus: 1, minus: 1} = game(code).cards[hero]

    view |> element("#cx-card-#{a}") |> render_click()
    view |> element("#cx-act-discard") |> render_click()
    assert hd(zone(code, 0, :discard)) == a

    view |> element("#cx-discard-0") |> render_click()
    assert has_element?(view, "#cx-drawer #cx-sheet-#{a}")
    view |> element("#cx-sheet-#{a}") |> render_click()
    refute has_element?(view, "#cx-drawer")
    view |> element("#cx-act-trash") |> render_click()
    assert game(code).trash == [a]
  end

  test "draw, counters, buildings, end turn and undo" do
    %{view: view, code: code} = free_room()

    view |> element("#cx-draw-0") |> render_click()
    assert length(zone(code, 0, :hand)) == 6
    view |> element("#cx-deck-1") |> render_click()
    assert length(zone(code, 1, :hand)) == 6

    view |> element("#cx-gold-0-plus") |> render_click()
    view |> element("#cx-hp-1-minus") |> render_click()
    assert has_element?(view, "#cx-gold-0", "5")
    assert has_element?(view, "#cx-hp-1", "19")

    view |> element("#cx-build-0") |> render_click()
    view |> element("#cx-toggle-building-tech_1") |> render_click()
    assert has_element?(view, "#cx-building-0-tech_1")

    view |> element("#cx-end-turn") |> render_click()
    assert game(code).active == 1
    # The table turns to the side that plays.
    assert has_element?(view, "#cx-pov-1[aria-pressed=true]")

    view |> element("#cx-undo") |> render_click()
    assert game(code).active == 0
    view |> element("#cx-undo") |> render_click()
    assert game(code).sides[0].tech_buildings == []
  end

  test "an error shows a flash and changes nothing" do
    %{view: view, code: code} = free_room()
    [a, b | _] = zone(code, 0, :hand)
    render_hook(view, "move", %{"id" => a, "seat" => "0", "zone" => "patrol", "slot" => "elite"})
    render_hook(view, "move", %{"id" => b, "seat" => "0", "zone" => "patrol", "slot" => "elite"})
    assert render(view) =~ "That patrol slot is taken"
    assert b in zone(code, 0, :hand)
  end

  test "the other side's hand shows backs until it is revealed; view as P2" do
    %{view: view, code: code} = room()
    [id | _] = zone(code, 1, :hand)
    assert has_element?(view, "#cx-card-#{id}[data-hidden]")
    view |> element("#cx-reveal") |> render_click()
    refute has_element?(view, "#cx-card-#{id}[data-hidden]")

    view |> element("#cx-pov-1") |> render_click()
    assert has_element?(view, "#cx-side-1[data-far=false]")
    [p1 | _] = zone(code, 0, :hand)
    assert has_element?(view, "#cx-card-#{p1}[data-hidden]")
  end

  test "a second browser watches" do
    %{code: code} = room()
    {:ok, other, _} = live(browser(token("bob")), "/games/#{@key}/#{code}")
    assert has_element?(other, "#cx-root")
    # A spectator has no actions: no End turn.
    refute has_element?(other, "#cx-end-turn")
    assert game(code).active == 0
  end

  describe "rules mode" do
    test "a new room is in rules mode: no sandbox controls, a hire button on a hand card" do
      %{view: view, code: code} = room()
      assert has_element?(view, "#cx-free[aria-pressed=false]")
      refute has_element?(view, "#cx-gold-0-plus")
      refute has_element?(view, "#cx-draw-0")
      assert has_element?(view, "#cx-hint")

      [id | _] = zone(code, 0, :hand)
      view |> element("#cx-card-#{id}") |> render_click()
      refute has_element?(view, "#cx-act-exhaust")
      view |> element("#cx-rule-hire") |> render_click()

      assert id in zone(code, 0, :workers)
      assert has_element?(view, "#cx-gold-0", "3")
      # One worker per turn.
      [other | _] = zone(code, 0, :hand)
      view |> element("#cx-card-#{other}") |> render_click()
      refute has_element?(view, "#cx-rule-hire")
    end

    test "a drop on the workers hires; a drop that is no legal action shows a flash" do
      %{view: view, code: code} = room()
      [a, b | _] = zone(code, 0, :hand)

      render_hook(view, "move", %{
        "id" => to_string(a),
        "seat" => "0",
        "zone" => "workers",
        "slot" => ""
      })

      assert a in zone(code, 0, :workers)

      html =
        render_hook(view, "move", %{
          "id" => to_string(b),
          "seat" => "1",
          "zone" => "discard",
          "slot" => ""
        })

      assert html =~ "not a legal action"
      assert b in zone(code, 0, :hand)
    end

    test "end turn: P2's turn, the table turns to P2" do
      %{view: view, code: code} = room()
      view |> element("#cx-end-turn") |> render_click()
      assert game(code).active == 1
      assert has_element?(view, "#cx-pov-1[aria-pressed=true]")
      assert has_element?(view, "#cx-gold-1", "5")
    end

    test "free mode on shows the sandbox controls; off hides them" do
      %{view: view} = room()
      view |> element("#cx-free") |> render_click()
      assert has_element?(view, "#cx-free[aria-pressed=true]")
      assert has_element?(view, "#cx-gold-0-plus")
      view |> element("#cx-free") |> render_click()
      refute has_element?(view, "#cx-gold-0-plus")
    end
  end

  describe "rules mode: play, patrol, attack" do
    import Codex.TestHelpers, only: [new: 0, place: 4, place: 5, gold: 3, ok!: 2]

    test "drag a unit from the hand to In play plays it; to a patrol slot patrols it" do
      {game, id} = place(gold(new(), 0, 9), 0, "older-brother", :hand)
      %{view: view, code: code} = room_with(game)

      render_hook(view, "move", %{
        "id" => to_string(id),
        "seat" => "0",
        "zone" => "in_play",
        "slot" => ""
      })

      assert id in zone(code, 0, :in_play)
      assert has_element?(view, "#cx-zone-0-in_play #cx-card-#{id}")

      render_hook(view, "move", %{
        "id" => to_string(id),
        "seat" => "0",
        "zone" => "patrol",
        "slot" => "squad_leader"
      })

      assert zone(code, 0, :patrol).squad_leader == id
    end

    test "a spell with a target: Play… then tap the glowing target" do
      {game, spark} = place(gold(new(), 0, 9), 0, "spark", :hand)
      {game, _} = place(game, 0, "troq-bashar", :in_play)
      {game, target} = place(game, 1, "tenderfoot", :patrol, :elite)
      %{view: view, code: code} = room_with(game)

      view |> element("#cx-card-#{spark}") |> render_click()
      view |> element("#cx-rule-play-pick") |> render_click()
      assert has_element?(view, "#cx-pick")
      assert has_element?(view, "#cx-card-#{target}.cx-targetable")
      view |> element("#cx-card-#{target}") |> render_click()

      assert game(code).cards[target].damage == 1
      refute has_element?(view, "#cx-pick")
    end

    test "attack: Attack… then the base" do
      {game, a} = place(new(), 0, "timely-messenger", :hand)
      game = ok!(game, {:play, a, []})
      %{view: view, code: code} = room_with(game)

      view |> element("#cx-card-#{a}") |> render_click()
      view |> element("#cx-rule-attack") |> render_click()
      assert has_element?(view, "#cx-hp-1-target")
      view |> element("#cx-hp-1-target") |> render_click()

      assert game(code).sides[1].base_hp == 19
      assert game(code).cards[a].exhausted
    end

    test "Cancel ends a pick" do
      {game, a} = place(new(), 0, "timely-messenger", :hand)
      game = ok!(game, {:play, a, []})
      %{view: view} = room_with(game)
      view |> element("#cx-card-#{a}") |> render_click()
      view |> element("#cx-rule-attack") |> render_click()
      view |> element("#cx-pick-cancel") |> render_click()
      refute has_element?(view, "#cx-pick")
      assert has_element?(view, "#cx-rule-attack")
    end
  end
end
