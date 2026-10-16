defmodule QuacksWeb.RevealHelpers do
  @moduledoc """
  Test helpers for the round results, which play on the player tiles and their
  stage (`QuacksWeb.TileReveal`).
  """
  import Phoenix.LiveViewTest

  @doc """
  End the results that play on the tiles, if they play: Skip to the last step,
  then its button ("To the shop", "Spend rubies", ...). Returns the view.
  """
  def skip_results(view, left \\ 5)

  def skip_results(view, 0), do: view

  def skip_results(view, left) do
    cond do
      has_element?(view, "[data-role=tile-skip]") ->
        view |> element("[data-role=tile-skip]") |> render_click()
        skip_results(view, left - 1)

      has_element?(view, "[data-role=tile-next]") ->
        view |> element("[data-role=tile-next]") |> render_click()
        skip_results(view, left - 1)

      true ->
        view
    end
  end

  @doc """
  Play the results on the tiles step by step (Next) until `selector` shows, e.g.
  a book's choice that waits for its step. Returns the view.
  """
  def play_until(view, selector, left \\ 8)

  def play_until(view, _selector, 0), do: view

  def play_until(view, selector, left) do
    if not has_element?(view, selector) and has_element?(view, "[data-role=tile-next]") do
      view |> element("[data-role=tile-next]") |> render_click()
      play_until(view, selector, left - 1)
    else
      view
    end
  end

  @doc """
  The reveal on show, read from the page (`#reveal-state`, architecture review G8):
  `%{index, tiles, kind, book, tick}`; nil when no reveal plays. `kind` and `book`
  are the step on the tiles; `tick` is the Auto timer's reference, or nil.
  """
  def reveal_state(view) do
    if has_element?(view, "#reveal-state") do
      node = view |> element("#reveal-state") |> render() |> LazyHTML.from_fragment()
      attr = fn name -> node |> LazyHTML.attribute(name) |> List.first() end

      %{
        index: String.to_integer(attr.("data-index")),
        tiles: attr.("data-tiles") == "true",
        kind: atom(attr.("data-kind")),
        book: atom(attr.("data-book")),
        tick: attr.("data-tick") && :erlang.list_to_ref(String.to_charlist(attr.("data-tick")))
      }
    end
  end

  defp atom(nil), do: nil
  defp atom(name), do: String.to_existing_atom(name)

  @doc "Fire the reveal's Auto timer now, as its own timer would (`tick`: the step's)."
  def tick_reveal(view, tick \\ nil) do
    state = reveal_state(view)
    send(view.pid, {:reveal_tick, tick || (state && state.tick)})
    view
  end
end
