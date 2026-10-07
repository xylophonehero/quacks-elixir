defmodule QuacksWeb.SeatsColoursTest do
  @moduledoc """
  Seats: up to 8 players in every game, one unique palette colour per seat (picked
  in your seat row) and the name edited right in the seat row.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  describe "GameServer" do
    test "8 players start a game; a 9th browser watches" do
      {:ok, id} = GameServer.start(8, {1, 2, 3})
      for n <- 0..7, do: assert({:ok, ^n} = GameServer.claim_seat(id, "t#{n}"))
      assert GameServer.claim_seat(id, "t8") == {:error, :full}

      assert {:ok, %Game{seats: seats}} = GameServer.begin(id, "t0")
      assert seats == Enum.to_list(0..7)
      assert {:ok, %{colours: colours}} = GameServer.get(id)
      assert colours == Map.new(0..7, &{&1, &1})
    end

    test "a limited supply with 8 players runs dry at 0" do
      game = Game.new(seed: {1, 2, 3}, players: 8, rules: %{supply: :limited})
      assert game.supply[{:white, 3}] == 0
      assert Enum.all?(game.supply, fn {_chip, count} -> count >= 0 end)
    end

    test "a colour is unique at the table; a newcomer gets a free one" do
      {:ok, id} = GameServer.start(3, {1, 2, 3})
      {:ok, 0} = GameServer.claim_seat(id, "a")
      assert :ok = GameServer.set_colour(id, 0, 1)
      {:ok, 1} = GameServer.claim_seat(id, "b")

      # seat 1's own colour (1) is taken, so it gets the lowest free one
      assert {:ok, %{colours: %{0 => 1, 1 => 0}}} = GameServer.get(id)
      assert GameServer.set_colour(id, 1, 1) == {:error, :taken}
      assert GameServer.set_colour(id, 1, 8) == {:error, :invalid}
      assert GameServer.set_colour(id, 2, 5) == {:error, :invalid}
      assert :ok = GameServer.set_colour(id, 1, 7)

      # the colours follow the renumbered seats into the game
      :ok = GameServer.leave_seat(id, "a")
      {:ok, _game} = GameServer.begin(id, "b")
      assert {:ok, %{colours: %{0 => 7}}} = GameServer.get(id)
    end
  end

  describe "the waiting panel" do
    test "your name is edited in your seat row; other names are text" do
      {:ok, id} = GameServer.start(2)
      alice = open(browser("alice"), id)
      bob = open(browser("bob"), id)

      refute has_element?(alice, "label", "Your name")
      assert has_element?(alice, ~s([data-seat="0"] input#seat-name[placeholder="Player 1"]))
      refute has_element?(alice, ~s([data-seat="1"] input))

      alice |> form("#rename-form", name: "Alice") |> render_change()
      assert {:ok, %{names: %{0 => "Alice"}}} = GameServer.get(id)
      assert has_element?(bob, ~s([data-seat="0"]), "Alice")
      assert has_element?(alice, ~s(#seat-name[value="Alice"]))

      # a blank name is the default again, shown as the placeholder
      alice |> form("#rename-form", name: "  ") |> render_change()
      assert {:ok, %{names: %{0 => "Player 1"}}} = GameServer.get(id)
      refute has_element?(alice, "#seat-name[value]")
    end

    test "your seat row picks a colour; taken ones cannot be picked" do
      {:ok, id} = GameServer.start(2)
      alice = open(browser("alice"), id)
      bob = open(browser("bob"), id)

      picker = ~s([data-seat="0"] [data-role=colour-picker])
      assert has_element?(alice, picker <> ~s( button[data-colour="0"][aria-pressed="true"]))
      assert has_element?(alice, picker <> ~s( button[data-colour="1"][disabled]))
      refute has_element?(alice, ~s([data-seat="1"] [data-role=colour-picker]))

      alice |> element(picker <> ~s( button[data-colour="5"])) |> render_click()
      assert {:ok, %{colours: %{0 => 5, 1 => 1}}} = GameServer.get(id)
      assert has_element?(alice, ~s{main[style*="--color-player-0: var(--color-seat-5)"]})
      assert has_element?(bob, ~s{main[style*="--color-player-0: var(--color-seat-5)"]})
      assert has_element?(bob, ~s([data-seat="1"] button[data-colour="5"][disabled]))

      # the chosen colour stays on in the game
      alice |> element("button", "Start game") |> render_click()
      assert has_element?(bob, ~s{main[style*="--color-player-0: var(--color-seat-5)"]})
      assert has_element?(bob, ~s{main[style*="--color-player-1: var(--color-seat-1)"]})
    end
  end
end
