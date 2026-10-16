defmodule HeartsWeb.BoardTest do
  @moduledoc """
  `HeartsWeb.Board` without a room: the gallery's board states (a fixed seed)
  and the board's own timers.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias HeartsWeb.{Board, Gallery}

  defp board(state, players \\ 4),
    do: Gallery.board_story(%{"state" => state, "players" => players}).board

  defp html(assigns),
    do: assigns |> Board.page() |> rendered_to_string() |> LazyHTML.from_document()

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  test "the received cards are marked, and the mark ends after a time" do
    assigns = board("received")
    assert [_, _, _] = received = assigns.new_cards
    # Marked even when you may not play them now (they are disabled then).
    assert count(html(assigns), "#ht-hand-s [data-state=new]") == 3

    socket = %Phoenix.LiveView.Socket{assigns: assigns}

    {:noreply, kept} = Board.handle_info({:hearts_seen, [hd(received)]}, socket)
    assert kept.assigns.new_cards == received

    {:noreply, seen} = Board.handle_info({:hearts_seen, received}, socket)
    assert seen.assigns.new_cards == []
    assert count(html(seen.assigns), "#ht-hand-s [data-state=new]") == 0
  end

  test "the last trick of a hand stays on the table before the score table opens" do
    doc = html(board("ending"))
    assert count(doc, "#ht-trick .tb-card") == 4
    assert count(doc, "#ht-trick [data-state=won]") == 1
    assert count(doc, "#ht-deck") == 0
    assert count(doc, "#hearts-scores") == 0
    assert count(doc, "#ht-hand-s .tb-card") == 0

    # The seats show the hand that ends: 13 tricks in all.
    tricks = doc |> LazyHTML.query("[id^=ht-pile-]") |> LazyHTML.attribute("data-count")
    assert tricks |> Enum.map(&String.to_integer/1) |> Enum.sum() == 13
  end

  test "Last trick shows the cards of the newest trick and who played them" do
    assert count(html(board("pass")), "#last-trick-open") == 0

    doc = html(board("last-trick"))
    assert count(doc, "#last-trick-open") == 1
    assert count(doc, "#hearts-last-trick #last-trick-cards li") == 4
    assert count(doc, "#hearts-last-trick [data-winner=true] [data-state=won]") == 1
  end

  test "3 players: the trick has three slots" do
    doc = html(board("collect", 3))
    assert count(doc, "#ht-trick .tb-slot") == 3
  end
end
