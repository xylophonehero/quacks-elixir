defmodule QuacksWeb.MessagesTest do
  @moduledoc """
  What the page says: the log lines, the toasts, the live region, the report toast and the words of the game-over breakdown.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import QuacksWeb.LiveHelpers
  alias Quacks.GameServer
  alias Quacks.GameServer
  alias QuacksWeb.PanelComponents
  alias QuacksWeb.{GameText, PanelComponents}
  alias QuacksWeb.{GameText, PanelComponents}

  # The game process stops, as after a crash or the idle timeout.

  test "a visually hidden live region says the newest event" do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    view = open(browser("solo-#{id}"), id)
    assert has_element?(view, "#announcer.sr-only[aria-live=polite]")

    view |> element("button[data-slot=draw]") |> render_click()
    assert has_element?(view, "#announcer", ~r/^Drew \w+ \d/)
  end

  describe "text" do
    test "the game-over breakdown names witches, cards and pennies" do
      log = [
        {0, {:witch, :g1, {:vp, 4}}},
        {0, {:fortune, :p6, {:vp, 4}}},
        {0, {:pennies, 2}},
        {0, {:pot_vp, 3, 12}}
      ]

      assert GameText.vp_breakdown(log, 0, 14) ==
               [brewing: 3, witches: 4, cards: 4, pennies: 2, other: 1]

      assert GameText.vp_part_name(:pennies) == "Unused pennies"
      assert GameText.vp_part_hint(:other) =~ "no other part"
    end

    test "Second Chances logs the chips it put back; Stop and Stopped are one line" do
      log = [
        {0, {:fortune, :b3, {:drew, [{:white, 1}, {:green, 1}]}}},
        {1, :stopped},
        {1, :stop},
        {0, :stop}
      ]

      html =
        render_component(&PanelComponents.action_log/1, log: log, names: %{0 => "A", 1 => "B"})

      assert html =~ "Second Chances: put back white 1, green 1"
      assert length(String.split(html, "B: Stopped<")) == 2
      assert html =~ "A: Stopped<"
    end
  end

  # Take a seat from a page that closes at once (a browser that lost its cookie
  # afterwards): the seat stays, but no page holds it.

  test "a resume is one log line" do
    log = [{1, :resumed}, {1, :resume}, {1, :stopped}, {1, :stop}]
    html = render_component(&PanelComponents.action_log/1, log: log, names: %{1 => "B"})

    assert html =~ "B: Resumed brewing"
    refute html =~ "B: Resume brewing"
    assert html =~ "B: Stopped"
  end

  defp solo do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {id, open(browser(token("solo")), id)}
  end

  describe "toasts" do
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

  test "without GitHub the report toast says 'Saved locally', no path" do
    {_id, view} = solo()

    view
    |> form("#bug-report-form-0", report: %{text: "Chips vanished"})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Thanks. Saved locally.")
    refute render(view) =~ "bug-reports/"
  end

  defp log_html(log),
    do: render_component(&PanelComponents.action_log/1, log: log, names: %{0 => "A", 1 => "B"})

  describe "the log" do
    test "actions read in the past tense" do
      html =
        log_html([
          {0, {:buy, []}},
          {1, {:explosion_choice, :vp}},
          {1, {:exploded, 9}},
          {0, :stop},
          {0, :keep},
          {1, :witch_done}
        ])

      assert html =~ "A: Bought nothing"
      assert html =~ "B: Exploded: took the VP"
      assert html =~ "B: Exploded (white 9)"
      assert html =~ "A: Stopped<"
      assert html =~ "A: Mandrake: kept the white chip"
      assert html =~ "B: Kept the gold penny"
      refute html =~ "Buy nothing"
      refute html =~ "take the victory points"
    end

    test "an action that its event narrates is one line" do
      html = log_html([{0, {:returned, {:white, 1}}}, {0, :use_flask}])

      assert html =~ "A: Returned white 1 to the bag"
      refute html =~ "flask"
    end

    test "buttons keep the imperative" do
      assert GameText.label({:buy, []}) == "Buy nothing"
      assert GameText.label(:use_flask) == "Use flask"
    end
  end

  test "the toast sits above the bottom bar on phones" do
    html =
      render_component(&QuacksWeb.CoreComponents.flash/1,
        kind: :info,
        flash: %{"info" => "You are now the host."}
      )

    assert html =~ "bottom-28"
    assert html =~ "sm:top-20"
  end
end
