defmodule QuacksWeb.Round23Test do
  @moduledoc """
  Round 23: the app is locked to the viewport (the page never scrolls sideways or
  down on a phone), the landscape grid needs a wide screen, and the New game flow
  has Back and Start on every page.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp css, do: File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

  describe "the viewport lock" do
    test "the game root and the lobby root carry the locked classes" do
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, game, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/g/#{id}")
      assert has_element?(game, "main[data-layout=full] > .game-grid")

      {:ok, lobby, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/")
      assert has_element?(lobby, "main[data-layout=full] > .lobby-root .lobby-screen #spell-book")
    end

    test "the roots are the screen: 100dvh, width 100%, overflow clip" do
      css = css()

      assert css =~
               ".game-grid,\n.lobby-root {\n  width: 100%;\n  height: 100dvh;\n  overflow: clip;"

      assert css =~ "body {\n  overscroll-behavior: none;"
      # The pages scroll, not the document.
      assert css =~ ".book-page {\n  min-height: 0;\n  overflow-y: auto;"
      refute css =~ ~r/\d+vw\b/
      refute css =~ ~r/\d+vh\b/
      refute css =~ "calc(100dvh - 2rem - 20px)"
    end

    test "the landscape layouts need a wide screen, not only a short one" do
      css = css()
      landscape = ~r/\(orientation: landscape\) and \(max-height: 30rem\)(.{0,30})/

      for [_, rest] <- Regex.scan(landscape, css) do
        assert rest =~ "and (min-width: 35rem)"
      end

      refute css =~ "@media (width < 64rem) and (height < 32rem) {"
    end

    test "the keyboard resizes only the visual viewport" do
      {:ok, _lobby, html} = live(browser("r23-#{System.unique_integer()}"), ~p"/")
      assert html =~ "interactive-widget=resizes-visual"
    end

    test "the Games page: the list, the install button and the credits scroll together" do
      {:ok, view, _html} = live(browser("r23-#{System.unique_integer()}"), ~p"/")
      assert has_element?(view, "#page-home #games-scroll > ul#games")
      assert has_element?(view, "#page-home #games-scroll > #install-app")
      assert has_element?(view, "#page-home #games-scroll > footer#credits")
      assert has_element?(view, "#page-home #games-scroll + .page-foot #new-game-flow")
    end
  end
end
