defmodule QuacksWeb.Round26Test do
  @moduledoc """
  Round 26: the patient picker (spell book and waiting panel) and Start straight
  into the game (the waiting panel instead of the configure screen).
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias Quacks.Game.Essence

  doctest QuacksWeb.AlchemistsComponents

  @seed {1, 2, 3}

  defp browser(name),
    do: init_test_session(build_conn(), player_token: "#{name}-#{System.unique_integer()}")

  defp alchemists(view),
    do: view |> element("#books") |> render_change(%{"alchemists" => "true", "sets" => %{}})

  defp start(view) do
    {:error, {:live_redirect, %{to: "/g/" <> id = to}}} =
      view |> element("#new-game") |> render_click()

    {id, to}
  end

  describe "the spell book's patient picker" do
    test "shows with The Alchemists only: Random and the 3 the seed deals" do
      {:ok, view, _html} = live(browser("p1"), ~p"/?seed=1,2,3&step=patients")
      refute has_element?(view, "#lobby-patient")

      alchemists(view)
      assert has_element?(view, "#page-patients #lobby-patient")
      assert has_element?(view, "#lobby-patient [data-patient=random] input[checked]")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#lobby-patient [data-role=patient-option]")
        |> LazyHTML.attribute("data-patient")

      assert ids == ["random" | Enum.map(Essence.dealt(@seed), &Atom.to_string/1)]
    end

    test "a picked patient is yours at once; the game skips your choice" do
      [_a, b, _c] = Essence.dealt(@seed)
      {:ok, view, _html} = live(browser("p2"), ~p"/?seed=1,2,3&step=patients")
      alchemists(view)
      view |> element("#lobby-patient") |> render_change(%{"patient" => to_string(b)})
      assert has_element?(view, "#lobby-patient [data-patient=#{b}] input[checked]")

      # a crafted id that is not dealt is Random
      render_change(view, "patient", %{"patient" => "nope"})
      assert has_element?(view, "#lobby-patient [data-patient=random] input[checked]")
      view |> element("#lobby-patient") |> render_change(%{"patient" => to_string(b)})

      render_click(view, "players", %{"count" => "1"})
      {id, _to} = start(view)
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.player(game, 0).patient == b
      assert game.round == 1 and game.phase != :patient_choice
    end
  end

  describe "Start goes straight into the game" do
    test "every seat filled (host and bots): the game page, no waiting panel" do
      conn = browser("straight")
      {:ok, view, _html} = live(conn, ~p"/?seed=1,2,3")
      alchemists(view)

      view
      |> element(~s([data-role=seat-slot][data-seat="1"] [data-role=add-bot]))
      |> render_click()

      {id, to} = start(view)
      assert {:ok, %{status: :playing}} = GameServer.get(id)
      {:ok, game_view, _html} = live(conn, to)
      refute has_element?(game_view, "#waiting-panel")
      # Random by default: the host never waits on a patient dialog.
      refute has_element?(game_view, "[data-role=patient-choice]")
    end

    test "an open seat: the waiting panel; the joiner picks a colour and a patient" do
      [a, b, _c] = Essence.dealt(@seed)
      host_conn = browser("host")
      {:ok, view, _html} = live(host_conn, ~p"/?seed=1,2,3")
      alchemists(view)
      view |> element("#lobby-patient") |> render_change(%{"patient" => to_string(a)})
      {id, to} = start(view)

      {:ok, host, _html} = live(host_conn, to)
      assert has_element?(host, "#waiting-panel [data-role=waiting-for-players]", "1 of 2 seated")
      assert has_element?(host, "#waiting-panel [data-role=share-link]")
      assert has_element?(host, "#waiting-patient [data-patient=#{a}] input[checked]")
      refute has_element?(host, "#books")
      refute has_element?(host, "#options")

      {:ok, guest, _html} = live(browser("guest"), to)
      assert has_element?(guest, ~s([data-seat="1"] [data-role=colour-picker]))
      assert has_element?(guest, "#waiting-patient [data-patient=random] input[checked]")
      guest |> element("#waiting-patient") |> render_change(%{"patient" => to_string(b)})
      assert {:ok, %{patient_picks: %{0 => ^a, 1 => ^b}}} = GameServer.get(id)

      host |> element("[data-role=start-game]") |> render_click()
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.player(game, 0).patient == a
      assert Game.player(game, 1).patient == b
      assert has_element?(guest, "button[data-slot=draw]")
    end

    test "no Alchemists: no patient picker in the waiting panel" do
      {:ok, id} = GameServer.create(%{players: 2}, "host-np", @seed)

      {:ok, view, _html} =
        live(init_test_session(build_conn(), player_token: "host-np"), ~p"/g/#{id}")

      assert has_element?(view, "#waiting-panel")
      refute has_element?(view, "#waiting-patient")
    end
  end
end
