defmodule QuacksWeb.QaFixes3Test do
  @moduledoc """
  QA pass 3 (`docs/research/qa3-2026-10-04.md`): shop tiles in the 64rem side panel
  (Q1), toasts that close by themselves (Q2, G7), no bare "Done" (Q3, N4), round 9
  words (Q4, N5), counters that start from the old values (Q5), the die on the pot
  corner (Q6), rejoin rules (Q7), the report toast (Q8), and the glitches G4, G6,
  V1 to V5.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers, as: H
  alias QuacksWeb.Replay

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp token(name), do: "#{name}-#{System.unique_integer()}"

  defp solo do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {id, open(browser(token("solo")), id)}
  end

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    alice = open(browser(token("alice")), id)
    bob = open(browser(token("bob")), id)
    alice |> element("button", "Start game") |> render_click()
    {id, alice, bob}
  end

  # A round with a bonus die, a ruby and VP lines (newest first, like the engine).
  @log [
    {0, {:pot_vp, 3, 13}},
    {0, {:pot_ruby, 13}},
    {0, {:green_rubies, 1}},
    {0, {:bonus_die, {:vp, 1}}},
    {0, {:drew, {:green, 1}, 12}},
    {:round_end, 0}
  ]

  defp scored(g),
    do:
      g
      |> H.put(0, phase: :shop, coins: 30, vp: 10, rubies: 4, drawn: [{{:green, 1}, 12}])
      |> Map.put(:log, @log)

  test "Q1: from 64rem a shop tile is chip, value and price; the price never shrinks" do
    {id, view} = solo()
    replace_game(id, &H.put(&1, 0, phase: :shop, coins: 30))

    assert has_element?(
             view,
             "#shop label [data-role=tile-name].sr-only.sm\\:not-sr-only.lg\\:sr-only"
           )

    refute has_element?(view, "#shop [data-role=tile-name].xl\\:sr-only")
    assert has_element?(view, "#shop label.min-w-0 [data-role=price].shrink-0")
  end

  describe "Q2/G7: toasts" do
    test "the host toast goes after its timer, not before a newer toast's" do
      {:ok, id} = GameServer.start(3)
      bob = open(browser(token("bob")), id)
      alice = open(browser(token("alice")), id)
      ref = Process.monitor(bob.pid)
      GenServer.stop(bob.pid)
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}

      assert has_element?(alice, "#flash-info", "You are now the host.")
      send(alice.pid, {:clear_info, "Some older toast."})
      assert has_element?(alice, "#flash-info", "You are now the host.")
      send(alice.pid, {:clear_info, "You are now the host."})
      refute has_element?(alice, "#flash-info")
    end

    test "toasts sit under the header from sm, above the bottom bar on phones, and fade out" do
      html =
        render_component(&QuacksWeb.CoreComponents.flash/1,
          kind: :info,
          flash: %{"info" => "Hi."}
        )

      assert html =~ "bottom-28"
      assert html =~ "sm:top-20 sm:left-4"
      refute html =~ "sm:right-4"
      assert html =~ "phx-remove"
    end
  end

  describe "Q3/N4: no bare Done" do
    test "a ruby spend that leaves nothing to do ends the seat's round" do
      {id, view} = solo()
      replace_game(id, &H.put(&1, 0, phase: :rubies, coins: 0, rubies: 2))
      render_hook(view, "seen", %{"kind" => "results", "round" => 1})

      view
      |> element("dialog#decision-rubies button", "Spend 2 rubies: droplet +1")
      |> render_click()

      assert {:ok, %{game: %Game{round: 2}}} = GameServer.get(id)
      refute has_element?(view, "[data-role=round-done]")
    end

    test "while the beats play the seat waits" do
      {id, _view} = solo()
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 0, rubies: 0))
      assert {:ok, %{game: %Game{round: 1}}} = GameServer.get(id)
    end
  end

  describe "Q4/N5: round 9 has no shop" do
    test "the pill, the line and the back button speak of the final scoring" do
      {id, alice, _bob} = duo()

      replace_game(id, fn g ->
        g |> H.put(0, round: 9, phase: :shop, coins: 0, rubies: 3) |> H.put(1, rubies: 0)
      end)

      render_hook(alice, "seen", %{"kind" => "results", "round" => 9})
      html = render(alice)
      assert html =~ "Final scoring"
      refute html =~ "Everyone shops"
      assert has_element?(alice, "[data-role=turn]", "Final scoring")
      assert has_element?(alice, "[data-role=decision-button]", "Back to final scoring")
      assert has_element?(alice, "dialog#decision-rubies button", "2 rubies → 1 VP")
    end

    test "brewing names the VP, not coins; the explosion's coins say they become VP" do
      {id, view} = solo()
      replace_game(id, &H.put(&1, 0, round: 9))
      refute has_element?(view, "[data-role=next-reward]", "coin")
      assert has_element?(view, "[data-role=next-reward]", "VP")

      replace_game(id, &H.put(&1, 0, phase: :explosion_choice, exploded?: true))
      assert has_element?(view, "button", "converted to VP at the end")
      refute has_element?(view, "button", "to spend")
    end
  end

  test "Q5: during the replay the counters start from the values before the round" do
    {id, view} = solo()
    game = replace_game(id, &scored/1)
    before = Replay.before(game, 0)

    assert before == %{vp: 10 - 3 - 1, rubies: 4 - 1 - 1}
    assert has_element?(view, ~s(#stat-vp[data-from="#{before.vp}"]))
    assert has_element?(view, ~s(#stat-rubies[data-from="#{before.rubies}"]))

    assert has_element?(
             view,
             ~s([data-role=player-chip][data-seat="0"] [data-role=player-vp] .stat-tick[data-from="#{before.vp}"])
           )

    css = File.read!("assets/css/app.css")
    assert css =~ "@keyframes stat-count"
    assert css =~ ":root:has(#players-row.replay-done) .stat-tick[data-from]"

    render_hook(view, "seen", %{"kind" => "results", "round" => 1})
    refute has_element?(view, ".stat-tick[data-from]")
  end

  test "Q6: from 64rem the bonus die lies on the pot corner, not in the side column" do
    {id, view} = solo()
    replace_game(id, &scored/1)

    assert has_element?(
             view,
             "[data-role=pot-area] [data-role=replay-die-corner].absolute.lg\\:flex [data-role=replay-die]"
           )

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("[data-role=replay-die]")
           |> Enum.count() ==
             2
  end

  describe "Q7: rejoin" do
    defp lost_seat do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      alice = token("alice")
      task = Task.async(fn -> GameServer.claim_seat(id, alice) end)
      {:ok, 0} = Task.await(task)
      ref = Process.monitor(task.pid)
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}
      bob = open(browser(token("bob")), id)
      {:ok, _} = GameServer.begin(id, alice)
      GameServer.rename(id, 0, "Alice")
      {id, bob}
    end

    test "only after 30 s away, and with the seat's name typed" do
      {id, bob} = lost_seat()
      stranger = open(browser(token("stranger")), id)

      assert {:ok, %{absent: [0], rejoinable: []}} = GameServer.get(id)
      refute has_element?(stranger, "[data-role=rejoin-seat]")
      assert {:error, :present} = GameServer.rejoin(id, "x", 0, "Alice")

      H.age_away(id)
      assert has_element?(stranger, ~s([data-role=rejoin-seat][data-seat="0"]), "Rejoin as Alice")
      assert has_element?(stranger, "#rejoin-form-0.hidden input#rejoin-name-0")

      stranger |> form("#rejoin-form-0", rejoin: %{name: "Alicia"}) |> render_submit()
      assert has_element?(stranger, "#flash-error", "not the seat's name")
      assert has_element?(stranger, "[data-role=spectator]")

      stranger |> form("#rejoin-form-0", rejoin: %{name: "  aLiCe "}) |> render_submit()
      refute has_element?(stranger, "[data-role=spectator]")
      assert has_element?(stranger, "#flash-info", "Welcome back, Alice.")
      assert has_element?(bob, "#flash-info", "Someone rejoined as Alice.")
    end

    test "CONTEXT.md names the limitation" do
      assert File.read!("docs/CONTEXT.md") =~ "there is no identity"
    end
  end

  test "Q8: without GitHub the report toast says 'Saved locally', no path" do
    {_id, view} = solo()

    view
    |> form("#bug-report-form-0", report: %{text: "Chips vanished"})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Thanks. Saved locally.")
    refute render(view) =~ "bug-reports/"
  end

  describe "glitches" do
    test "G4: the phone pot sits in the middle of its box (equal bands)" do
      css = File.read!("assets/css/app.css")
      assert css =~ "margin-top: calc((100cqh - 100cqmin) / 2);"
    end

    test "G6/V4: on phones the card tile is in the header row, beside the books button" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      view = open(browser(token("g6")), id)

      assert has_element?(
               view,
               "header [data-role=fortune-tile].lg\\:hidden + button[data-role=open-books]"
             )

      refute has_element?(view, "[data-role=pot-area] [data-role=fortune-tile]")
    end

    test "V1: the YOU pill does not shrink; the phase pill may" do
      {_id, alice, _bob} = duo()
      assert has_element?(alice, "[data-role=you-are].shrink-0")
      refute has_element?(alice, "[data-role=you-are].min-w-0")
      assert has_element?(alice, "header dd.truncate")
    end

    test "V2/V3: the state badge sits beside the initial; a bot is an icon on phones" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      alice = token("alice")
      view = open(browser(alice), id)
      {:ok, _} = GameServer.add_bot(id, alice)
      view |> element("button", "Start game") |> render_click()

      assert has_element?(view, "[data-role=player-chip] [data-role=player-state].-right-2\\.5")

      assert has_element?(
               view,
               "[data-role=player-name] [data-role=bot-badge] .hero-cpu-chip-micro.sm\\:hidden"
             )

      assert has_element?(
               view,
               "[data-role=player-name] [data-role=bot-badge] .max-sm\\:sr-only",
               "bot"
             )
    end

    test "V5: the rings on the pot have a legend with every player" do
      {_id, alice, _bob} = duo()
      assert has_element?(alice, "[data-role=ring-legend]", "Scoring rings:")
      assert has_element?(alice, ~s([data-role=ring-legend] [data-role=seat-dot][data-seat="1"]))

      {_id, view} = solo()
      refute has_element?(view, "[data-role=ring-legend]")
    end
  end
end
