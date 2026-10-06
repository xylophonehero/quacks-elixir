defmodule QuacksWeb.QaFixes2Test do
  @moduledoc """
  QA pass 2 (`docs/research/qa2-2026-10-04.md`): the Options section keeps its open
  state (N1), a handed-over table keeps its settings (N2), one log line per resume
  (N3), no empty rubies step (N4), the droplet status line (N5), a lost seat can be
  taken back and a spectator gets no stacked dialogs (N6), the colour under a
  card's chip picks, and the glitches G1 to G3.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers, as: H
  alias QuacksWeb.{AlchemistsComponents, GameComponents, GameLive}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp token(name), do: "#{name}-#{System.unique_integer()}"

  defp auto_open?(view, dialog),
    do: has_element?(view, "dialog#{dialog}[phx-mounted*='quacks:modal']")

  # Take a seat from a page that closes at once (a browser that lost its cookie
  # afterwards): the seat stays, but no page holds it.
  defp claim_and_leave(id, token) do
    task = Task.async(fn -> GameServer.claim_seat(id, token) end)
    {:ok, seat} = Task.await(task)
    ref = Process.monitor(task.pid)
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}
    # the server saw the page go before this call
    {:ok, _table} = GameServer.get(id)
    seat
  end

  describe "N1: the Options section" do
    test "the browser keeps its open state while the host steps" do
      {:ok, id} = GameServer.start(2)
      host = open(browser(token("host")), id)

      details = "details#options-section[phx-mounted*=ignore_attrs][phx-mounted*=open]"
      assert has_element?(host, details)

      host
      |> element("#options-section button[aria-label='Starting rubies: more']")
      |> render_click()

      assert has_element?(host, details)
    end
  end

  describe "N2: host handover" do
    test "the new host does not load its saved settings; the creator still may" do
      {:ok, id} = GameServer.start(3)
      bob = open(browser(token("bob")), id)
      alice = open(browser(token("alice")), id)

      assert has_element?(bob, "#config-memory[data-fresh]")

      ref = Process.monitor(bob.pid)
      GenServer.stop(bob.pid)
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}

      assert render(alice) =~ "You are now the host."
      assert has_element?(alice, "#config-memory")
      refute has_element?(alice, "#config-memory[data-fresh]")

      render_hook(alice, "load_config", %{"players" => 5, "expansion" => true})
      {:ok, table} = GameServer.get(id)
      assert table.max_players == 3
      assert MapSet.size(table.expansions) == 0
    end
  end

  test "N3: a resume is one log line" do
    log = [{1, :resumed}, {1, :resume}, {1, :stopped}, {1, :stop}]
    html = render_component(&GameComponents.action_log/1, log: log, names: %{1 => "B"})

    assert html =~ "B: Resumed brewing"
    refute html =~ "B: Resume brewing"
    assert html =~ "B: Stopped"
  end

  describe "N4: the rubies step" do
    test "with nothing to spend the round ends by itself once the replay played" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      view = open(browser(token("rubies")), id)
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 0, rubies: 1))

      refute has_element?(view, "dialog#decision-rubies")
      refute has_element?(view, "#players-row[data-on-replay-end*=decision]")
      refute has_element?(view, "[data-role=decision-button]")
      # the beats still play: the round waits
      assert {:ok, %{game: %Game{round: 1}}} = GameServer.get(id)
      assert has_element?(view, "[data-role=replay-timer]")

      # QA 3, N4: no bare "Done" after the replay
      render_hook(view, "seen", %{"kind" => "results", "round" => 1})
      assert {:ok, %{game: %Game{round: 2}}} = GameServer.get(id)
    end

    test "with a ruby option it opens" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      view = open(browser(token("rubies")), id)
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 0, rubies: 2))

      assert has_element?(view, "dialog#decision-rubies [data-role=shop-rubies]")
    end
  end

  test "N5: a droplet move says so in the status line and on the seat" do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    alice = open(browser(token("alice")), id)
    bob = open(browser(token("bob")), id)
    alice |> element("button", "Start game") |> render_click()

    replace_game(id, &H.put(&1, 0, droplet_moves: 1))

    refute has_element?(alice, "[data-role=turn]")

    assert has_element?(
             bob,
             ~s([data-role=player-chip][data-seat="0"] [data-role=player-state][data-state=droplet])
           )
  end

  describe "N6: a lost seat" do
    test "the server knows which human seats have no page" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      alice = token("alice")
      seat = claim_and_leave(id, alice)
      {:ok, _} = GameServer.add_bot(id, alice)

      assert {:ok, %{absent: [^seat], rejoinable: []}} = GameServer.get(id)
      H.age_away(id)
      assert {:ok, %{absent: [^seat], rejoinable: [^seat]}} = GameServer.get(id)
      assert {:error, :invalid} = GameServer.rejoin(id, "stranger", 1, "Bot")
      assert {:ok, ^seat} = GameServer.rejoin(id, "alice-new", seat, "player 1")
      # the test process is the new page
      assert {:ok, %{absent: [], creator: ^seat}} = GameServer.get(id)
      assert {:error, :present} = GameServer.rejoin(id, "someone-else", seat, "Player 1")
      assert {:error, :seated} = GameServer.rejoin(id, "alice-new", seat, "Player 1")
    end

    test "a disconnected render (its HTTP process lives on) does not hold the seat" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      {:ok, seat} = GameServer.claim_seat(id, token("static"), watch: false)
      assert {:ok, %{absent: [^seat]}} = GameServer.get(id)
    end

    test "a spectator takes back an absent seat and plays it" do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      alice = token("alice")
      claim_and_leave(id, alice)
      bob = open(browser(token("bob")), id)
      {:ok, _} = GameServer.begin(id, alice)

      # Alice comes back without her cookie: all seats are taken.
      lost = open(browser(token("alice-again")), id)
      assert has_element?(lost, "[data-role=spectator]")
      H.age_away(id)
      assert has_element?(lost, ~s([data-role=rejoin-seat][data-seat="0"]), "Rejoin as Player 1")
      refute has_element?(lost, ~s([data-role=rejoin-seat][data-seat="1"]))
      refute has_element?(bob, "[data-role=rejoin]")

      lost |> form("#rejoin-form-0", rejoin: %{name: "Player 1"}) |> render_submit()
      refute has_element?(lost, "[data-role=spectator]")
      assert has_element?(lost, "[data-role=my-seat]")
      assert has_element?(lost, "button[data-slot=draw]:not([disabled])")
    end

    test "a spectator sees no card or results open by themselves" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      _player = open(browser(token("solo")), id)
      watcher = open(browser(token("watcher")), id)

      assert has_element?(watcher, "dialog#card-round-1")
      refute auto_open?(watcher, "#card-round-1")

      replace_game(id, &H.put(&1, 0, phase: :shop))
      assert has_element?(watcher, "#players-row.replay-done")
      refute has_element?(watcher, "[data-role=replay-timer]")
      refute has_element?(watcher, "#players-row[data-on-replay-end]")
    end
  end

  test "a card's 'take one' chips carry their colour word" do
    game =
      Game.new(seed: {1, 2, 3}, fortune: false)
      |> H.put(fortune_card: :p10, phase: :fortune_choice)

    # Rat-a-Tat: take one 4-chip (or the VP)
    actions = for colour <- [:blue, :red, :yellow], do: {:fortune, {:take, {colour, 4}}}

    html =
      render_component(&GameLive.chip_picks/1,
        actions: [{:fortune, :vp} | actions],
        game: game,
        me: game.players[0]
      )

    words =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=pick-colour]")
      |> Enum.map(&LazyHTML.text/1)

    assert Enum.map(words, &String.trim/1) == ~w(blue red yellow)
  end

  describe "glitches" do
    test "G1: the decision button hides while a dialog is open" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      view = open(browser(token("g1")), id)
      replace_game(id, &H.put(&1, 0, phase: :explosion_choice, exploded?: true))

      assert has_element?(
               view,
               "[data-role=decision-button][class*='[body:has(dialog[open])_&]:invisible']"
             )
    end

    test "G2: a locked shop tile has the lock, and its price is struck through" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      view = open(browser(token("g2")), id)
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 30))

      assert has_element?(view, "#shop label.shop-locked [data-role=tile-lock]")
      assert has_element?(view, "#shop label.shop-locked [data-role=price]")

      css = File.read!("assets/css/app.css")
      assert css =~ ~s(.shop-locked > [data-role="price"] {\n  text-decoration: line-through;)
    end

    test "G3: a glass VP bonus is the laurel seal, not a coin" do
      html = render_component(&AlchemistsComponents.slot_grid/1, id: :carrot_nose, reached: 7)

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s(li[data-space="7"] [data-glyph=vp] use[href="#icon-vp"]))
             |> Enum.count() == 1
    end
  end
end
