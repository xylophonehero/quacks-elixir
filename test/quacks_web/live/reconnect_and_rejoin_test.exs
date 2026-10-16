defmodule QuacksWeb.ReconnectAndRejoinTest do
  @moduledoc """
  Reloads, lost seats and rejoins: a reload keeps what the seat closed, a lost seat, a spectator who takes it back, the rejoin rules, stale broadcasts and a game whose server is gone.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2, send_game_update: 3]
  import QuacksWeb.LiveHelpers
  alias Quacks.Game
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp duo do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser("alice-#{id}"), id)
    bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {id, alice, bob}
  end

  # The game process stops, as after a crash or the idle timeout.
  defp stop_server(id) do
    [{pid, _}] = Registry.lookup(Quacks.GameRegistry, id)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
  end

  describe "a game whose server is gone" do
    test "a move goes to the lobby with a flash, without a crash" do
      {:ok, id} = GameServer.start(1, {10, 11, 12})
      view = open(browser("solo-#{id}"), id)
      stop_server(id)

      view |> element("button[data-slot=draw]") |> render_click()
      flash = assert_redirect(view, ~p"/")
      assert flash["error"] == "This game has ended."
    end

    test "a seat change broadcast after the stop also goes to the lobby" do
      {id, alice, _bob} = duo()
      stop_server(id)

      send(alice.pid, {:names, id, %{}})
      assert_redirect(alice, ~p"/")
    end

    test "the waiting room's rename goes to the lobby" do
      {:ok, id} = GameServer.start(2, {1, 2, 3})
      view = open(browser("host-#{id}"), id)
      stop_server(id)

      view |> form("#rename-form", name: "Nick") |> render_change()
      assert_redirect(view, ~p"/")
    end
  end

  defp solo(seed) do
    {:ok, id} = GameServer.start(1, seed)
    {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")
    {id, view}
  end

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.

  defp game(id) do
    {:ok, %{game: game}} = GameServer.get(id)
    game
  end

  test "an older broadcast that comes after a newer game does not roll the page back" do
    {id, view} = solo({1, 2, 3})
    old = game(id)

    view |> element("button[data-slot=draw]") |> render_click()
    new = game(id)
    white = Game.white_sum(new, 0)
    assert white > 0

    send_game_update(view.pid, id, new)
    send_game_update(view.pid, id, old)

    assert has_element?(view, ~s(#fuse-meter[data-white="#{white}"]))
  end

  defp auto_open?(view, dialog),
    do: has_element?(view, "dialog#{dialog}[phx-mounted*='quacks:modal']")

  describe "a reload keeps what the seat closed" do
    test "the round's card opens once; after it closed, a reload leaves it closed" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      token = "card-#{System.unique_integer()}"
      view = open(browser(token), id)

      # round 24: the card hovers over the pot until a tap
      assert has_element?(view, "#pot-card-1")
      assert has_element?(view, "#card-continue")

      view |> element("#card-tap") |> render_click()
      assert {:ok, %{seen: %{0 => %{card: 1}}}} = GameServer.get(id)

      reloaded = open(browser(token), id)
      refute has_element?(reloaded, "#pot-card-1")
      refute has_element?(reloaded, "#card-tap")
    end

    test "the replay plays once; after that, a reload opens the shop" do
      {:ok, id} = GameServer.start(1, {10, 11, 12})
      token = "results-#{System.unique_integer()}"
      view = open(browser(token), id)
      for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
      view |> element("button", "Stop") |> render_click()

      assert has_element?(view, "#tile-stage")
      refute has_element?(view, "#players-row.replay-done")
      refute auto_open?(view, "#decision-shop")

      render_hook(view, "seen", %{"kind" => "results", "round" => 1})

      reloaded = open(browser(token), id)
      refute has_element?(reloaded, "#tile-stage")
      assert has_element?(reloaded, "#players-row.replay-done")
      refute has_element?(reloaded, "[data-role=replay-timer]")
      assert auto_open?(reloaded, "#decision-shop")
    end

    test "a stale or foreign 'seen' does nothing" do
      {:ok, id} = GameServer.start(1, {1, 2, 3})
      view = open(browser("stale-#{System.unique_integer()}"), id)
      render_hook(view, "seen", %{"kind" => "bogus", "round" => 1})
      render_hook(view, "seen", %{"kind" => "card", "round" => "1"})
      assert {:ok, %{seen: seen}} = GameServer.get(id)
      assert seen == %{}
    end
  end

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

  describe "a lost seat" do
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

      # round 14: no reveal overlay for a spectator
      refute has_element?(watcher, "[data-role=reveal]")
      refute has_element?(watcher, "dialog#card-round-1")

      replace_game(id, &H.put(&1, 0, phase: :shop))
      assert has_element?(watcher, "#players-row.replay-done")
      refute has_element?(watcher, "[data-role=reveal]")
    end
  end

  describe "rejoin" do
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
end
