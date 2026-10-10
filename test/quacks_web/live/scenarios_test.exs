defmodule QuacksWeb.ScenariosTest do
  @moduledoc """
  Every scenario (`Quacks.Scenarios`): it builds (a seed reaches its goal and every
  step's engine check passes), it opens on the real game page through
  `/dev/scenarios/<kind>/<id>`, and the step bar walks it: each step shows the step
  bar at that step and the step's key elements. A failure names the step.

  Each test writes its result for the index (`Quacks.Scenarios.record/2`). With
  `SCENARIO_SNAPSHOTS=1` each step's HTML goes to
  `tmp/scenarios/snapshots/<kind>-<id>/<n>-<label>.html`. One scenario:
  `mix test test/quacks_web/live/scenarios_test.exs --only scenario:card/p12`.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{GameServer, Scenarios}
  alias Quacks.Rules.{Alchemists, Books, Fortune, Witches}
  alias Quacks.Scenarios.Script

  test "the index lists every item, marks the hand-written ones and links each", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/scenarios")

    for e <- Scenarios.all() do
      row = "#scenario-#{String.replace(Scenarios.key(e), "/", "-")}"
      assert has_element?(view, "#{row} a[href='#{Scenarios.path(e)}']")
      assert has_element?(view, "#{row} [data-role=hand-written]") == e.hand
    end

    assert Enum.count(Scenarios.all(), & &1.hand) >= 10
  end

  test "the catalog has every card, book, patient and witch" do
    keys = MapSet.new(Scenarios.all(), &Scenarios.key/1)

    for %{id: id} <- Fortune.all(), do: assert("card/#{id}" in keys)
    for {c, set} <- Books.keys(), do: assert("chip/#{c}/#{set}" in keys)
    for id <- Alchemists.patients(), do: assert("patient/#{id}" in keys)

    for colour <- [:silver, :copper, :gold],
        id <- Witches.ids(colour),
        do: assert("witch/#{colour}/#{id}" in keys)
  end

  test "an unknown scenario is a 404", %{conn: conn} do
    assert conn |> get("/dev/scenarios/card/nope") |> response(404)
  end

  test "?step=N opens at that step", %{conn: conn} do
    conn = init_test_session(conn, player_token: "scenario-step")
    "/g/" <> id = conn |> get("/dev/scenarios/card/p12?step=2") |> redirected_to()
    {:ok, script} = Scenarios.build(Scenarios.get("card", "p12"))
    {:ok, %{debug: %{at: at}}} = GameServer.get(id)
    assert at == Enum.at(script.steps, 1).at
  end

  test "a scenario table's bug report bundle names the scenario and the action", %{conn: conn} do
    conn = init_test_session(conn, player_token: "scenario-report")
    "/g/" <> id = conn |> get("/dev/scenarios/chip/blue/1") |> redirected_to()
    {:ok, bundle} = GameServer.bundle(id)
    {:ok, %{debug: %{at: at}}} = GameServer.get(id)
    assert bundle.scenario == %{key: "chip/blue/1", at: at}
  end

  for entry <- Scenarios.all() do
    @key Scenarios.key(entry)
    @tag scenario: @key
    test "scenario #{@key}", %{conn: conn} do
      [kind, id] = String.split(@key, "/", parts: 2)
      entry = Scenarios.get(kind, id)
      walk(conn, entry)
    end
  end

  defp walk(conn, entry) do
    script =
      case Scenarios.build(entry) do
        {:ok, script} ->
          script

        {:error, reason} ->
          fail(entry, "build", "no seed reaches the goal: #{inspect(reason)}")
      end

    for {step, message} <- Script.failures(script), do: fail(entry, step.label, message)

    conn = init_test_session(conn, player_token: "scenario-#{Scenarios.key(entry)}")
    "/g/" <> id = conn |> get(Scenarios.path(entry)) |> redirected_to()
    {:ok, view, _html} = live(conn, "/g/#{id}")

    script.steps
    |> Enum.with_index(1)
    |> Enum.each(fn {step, n} ->
      if n > 1, do: view |> element("#scenario-next") |> render_click()
      html = render(view)
      snapshot(entry, n, step.label, html)

      sees!(view, entry, n, step, ["#scenario-bar[data-step='#{step.label}']" | step.sees])

      for {tap, after_tap} <- step.taps do
        view |> element(tap) |> render_click()
        sees!(view, entry, n, step, after_tap)
      end
    end)

    Scenarios.record(entry, :pass)
  end

  defp sees!(view, entry, n, step, selectors) do
    for selector <- selectors, not has_element?(view, selector) do
      fail(entry, step.label, "step #{n} (#{step.label}): the page has no #{selector}")
    end
  end

  defp fail(entry, label, message) do
    Scenarios.record(entry, {:fail, label, message})
    flunk("#{Scenarios.key(entry)}, #{label}: #{message}")
  end

  defp snapshot(entry, n, label, html) do
    if System.get_env("SCENARIO_SNAPSHOTS") do
      dir =
        Path.join([Scenarios.dir(), "snapshots", String.replace(Scenarios.key(entry), "/", "-")])

      File.mkdir_p!(dir)
      name = "#{String.pad_leading("#{n}", 2, "0")}-#{String.replace(label, " ", "-")}.html"
      File.write!(Path.join(dir, name), html)
    end
  end
end
