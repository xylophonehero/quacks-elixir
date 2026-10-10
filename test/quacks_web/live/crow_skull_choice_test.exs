defmodule QuacksWeb.CrowSkullChoiceTest do
  @moduledoc """
  The crow skull's choice (blue Set 1). Phones: the choice row has the height of
  Stop and Draw, and the hint is in the info row over it, where the white track
  is. From 64rem: a panel in the context column, and the bar keeps Stop and Draw.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp solo do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false})

    conn = init_test_session(build_conn(), player_token: "crow-#{System.unique_integer()}")
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    {id, view}
  end

  defp blue(id, pending),
    do: replace_game(id, &H.put(&1, phase: :blue_choice, pending: pending))

  defp classes(view, selector) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("class")
    |> hd()
    |> String.split()
  end

  @four [{:orange, 1}, {:white, 3}, {:yellow, 1}, {:blue, 2}]
  @five @four ++ [{:red, 1}]

  test "the choice row has the same height class as the Draw/Stop row" do
    {id, view} = solo()
    assert "*:min-h-12" in classes(view, "[data-role=action-bar]")

    blue(id, @four)
    row = classes(view, "footer [data-role=bar-blue] [data-role=blue-row]")
    assert "h-12" in row
    assert "h-12" in classes(view, "[data-role=blue-row] [data-role=blue-tray]")
    assert "h-12" in classes(view, "[data-role=blue-row] [data-role=blue-skip]")
  end

  test "the hint and the crow skull chip are in the info row, not the chip row" do
    {id, view} = solo()
    blue(id, @four)

    info = "footer [data-role=bar-blue] [data-role=info-row]"
    assert has_element?(view, "#{info} [data-role=blue-hint]", "Add a chip to the pot")
    assert has_element?(view, "#{info} [data-role=blue-book] [data-chip-icon=blue]")
    refute has_element?(view, "[data-role=blue-row] [data-role=blue-hint]")
    # below 64rem the info row takes the white track's place
    assert "max-lg:hidden" in classes(view, "[data-role=fuse-row]")
  end

  test "4 and 5 chips and Skip stay in the row, chips 36 px in 44 px targets" do
    for pending <- [@four, @five] do
      {id, view} = solo()
      blue(id, pending)

      row = "[data-role=blue-row]"
      html = render(view)
      chips = html |> LazyHTML.from_document() |> LazyHTML.query("#{row} button[data-pool-chip]")
      assert Enum.count(chips) == length(pending)
      assert has_element?(view, "#{row} button.size-11[data-pool-chip] .chip-token.size-9")
      refute has_element?(view, "#{row} .chip-token.size-12")
      assert has_element?(view, "#{row} > [data-role=blue-skip]", "Skip")
    end
  end

  test "from 64rem the choice is a panel in the context column" do
    {id, view} = solo()
    blue(id, @five)

    panel = "aside[data-area=context] [data-role=crow-panel]"
    assert has_element?(view, "#{panel} [data-role=crow-hint]")

    assert view
           |> render()
           |> LazyHTML.from_document()
           |> LazyHTML.query("#{panel} button[data-pool-chip]")
           |> Enum.count() == 5

    assert has_element?(view, "#{panel} [data-role=crow-skip]", "Skip")
    assert "lg:flex" in classes(view, panel)
    assert "lg:hidden" in classes(view, "footer [data-role=bar-blue]")
    # the bar keeps Stop and Draw (disabled) from 64rem
    assert "max-lg:hidden" in classes(view, "footer [data-role=action-bar]")
    assert has_element?(view, "[data-role=action-bar] [data-slot=draw][disabled]")
  end

  test "a chip in the panel goes in the pot" do
    {id, view} = solo()
    blue(id, [{:red, 1}, {:white, 1}])

    view |> element("[data-role=crow-panel] button[aria-label*='red 1']") |> render_click()
    refute has_element?(view, "[data-role=crow-panel]")
    refute has_element?(view, "[data-role=bar-blue]")
  end

  test "the gallery has the crow skull with 1, 4 and 5 chips" do
    {:ok, view, _html} = live(build_conn(), "/dev/gallery/frame/bar/crow-5")
    assert has_element?(view, "[data-role=crow-panel]")
    assert has_element?(view, "[data-role=bar-blue] [data-role=blue-row].h-12")

    for n <- [1, 4] do
      {:ok, view, _html} = live(build_conn(), "/dev/gallery/frame/bar/crow-#{n}")
      assert has_element?(view, "[data-role=crow-panel]")
    end
  end
end
