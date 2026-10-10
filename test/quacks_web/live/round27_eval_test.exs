defmodule QuacksWeb.Round27EvalTest do
  @moduledoc """
  Round 27, part 2 (experimental): the Results setting "On tiles" plays the
  evaluation on the player tiles instead of the overlay.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.{Game, GameServer}
  alias QuacksWeb.TileReveal

  defp browser(token), do: init_test_session(build_conn(), player_token: token)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  # Two seats brew to the shop: each stops (or answers what it must).
  defp to_shop(id) do
    Enum.find_value(1..120, fn _ ->
      {:ok, %{game: game}} = GameServer.get(id)

      if game.phase == :shopping do
        true
      else
        seat = Enum.find(game.seats, &(Game.legal_actions(game, &1) -- [:resume] != []))
        actions = Game.legal_actions(game, seat) -- [:resume]
        pick = [:stop, :chip_done, {:explosion_choice, :vp}, :draw]
        {:ok, _} = GameServer.apply(id, seat, Enum.find(pick, hd(actions), &(&1 in actions)))
        nil
      end
    end)
  end

  defp duo_results do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
    alice = open(browser("alice-#{id}"), id)
    _bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {:ok, _} = GameServer.apply(id, 0, :draw)
    {:ok, _} = GameServer.apply(id, 1, :draw)
    {:ok, _} = GameServer.apply(id, 1, :draw)
    to_shop(id)
    {id, alice}
  end

  # Round 39: no Results setting; once the browser's settings come, every screen
  # plays the steps on the tiles (an old saved "overlay" changes nothing).
  test "the browser's settings play the steps on the tiles, never in the overlay" do
    {_id, view} = duo_results()
    refute has_element?(view, "#reveal-settings [name=show]")

    render_hook(view, "reveal_settings", %{
      "mode" => "step",
      "speed" => "normal",
      "show" => "overlay"
    })

    refute has_element?(view, "[data-role=reveal]")
    assert has_element?(view, "#tile-stage[data-kind]")
    # The tiles show the running totals while the steps play.
    assert has_element?(view, "[data-role=player-chip] [data-role=player-vp] .tile-count")

    # Next steps through; the last step ends the reveal, the tiles keep the die.
    Enum.find(1..10, fn _ ->
      view |> element("[data-role=tile-next]") |> render_click()
      not has_element?(view, "#tile-stage")
    end)

    refute has_element?(view, "#tile-stage")
    assert has_element?(view, "[data-role=player-chip] [data-role=tile-die] [data-role=die-face]")
  end

  test "Skip ends the steps on the tiles" do
    {_id, view} = duo_results()

    render_hook(view, "reveal_settings", %{
      "mode" => "auto",
      "speed" => "normal",
      "show" => "tiles"
    })

    assert has_element?(view, "#tile-stage")
    refute has_element?(view, "[data-role=tile-next]")
    view |> element("[data-role=tile-skip]") |> render_click()
    refute has_element?(view, "#tile-stage")
  end

  test "badges: a book's ingredient and its rewards; the space's VP and ruby" do
    book = %{
      kind: :book,
      book: :black,
      rows: [
        %{seat: 0, scored: true, vp: 0, rubies: 1, droplet: 1},
        %{seat: 1, scored: false, vp: 0, rubies: 0, droplet: 0}
      ]
    }

    assert TileReveal.badges(book, 0) == [{:book, :black}, {:rubies, 1}, {:droplet, 1}]
    assert TileReveal.badges(book, 1) == []

    space = %{kind: :space, rows: [%{seat: 0, coins: 9, vp: 2, rubies: 1}]}
    assert TileReveal.badges(space, 0) == [{:vp, 2}, {:rubies, 1}]
    assert TileReveal.label(book) == "Black book"

    # Round 37: the standings ("Round scored") moved to the recap after the shop.
    assert TileReveal.slides([%{kind: :die}, %{kind: :results}, %{kind: :standings}]) == [
             %{kind: :die}
           ]
  end
end
