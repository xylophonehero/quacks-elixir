defmodule QuacksWeb.LiveHelpers do
  @moduledoc """
  Shared helpers for the LiveView tests: a browser session, a game page, a unique
  token and LazyHTML queries.
  """
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint QuacksWeb.Endpoint

  @doc "A browser: a conn with the player token `name` in its session."
  def browser(name), do: init_test_session(build_conn(), player_token: name)

  @doc "Open the game page of game `id` in `conn`. Returns the view."
  def open(conn, id) do
    {:ok, view, _html} = live(conn, "/g/#{id}")
    view
  end

  @doc "A unique player token that starts with `name`."
  def token(name), do: "#{name}-#{System.unique_integer()}"

  @doc "The nodes of `html` that match `selector`."
  def query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  @doc "How many nodes of `html` match `selector`."
  def count(html, selector), do: html |> query(selector) |> Enum.count()

  @doc "The trimmed text of the nodes of `html` that match `selector`."
  def text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()

  @doc "Press `key` on the game page."
  def key(view, key, meta \\ %{}),
    do: view |> element("#game") |> render_keydown(Map.put(meta, "key", key))
end
