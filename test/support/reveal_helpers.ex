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
end
