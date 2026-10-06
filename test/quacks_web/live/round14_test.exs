defmodule QuacksWeb.Round14Test do
  @moduledoc """
  Round 14 playtest fixes: the witches sheet has a title row and the order copper,
  silver, gold; the menu's "App" line; name cards on one line.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp herb_solo do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
    {:ok, view, _html} = live(browser("r14-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  describe "the witches sheet" do
    test "has a title row and shows copper, silver, gold" do
      {_id, view} = herb_solo()
      assert has_element?(view, "#sheet-witches > [data-role=witches-title]", "Herb witches")

      html = render(view)

      ids =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#sheet-witches [data-role=witch-card]")
        |> LazyHTML.attribute("data-witch")

      assert Enum.map(ids, &String.first/1) == ["c", "s", "g"]
    end
  end

  describe "the menu" do
    test "has the App line that app.js fills" do
      {_id, view} = herb_solo()
      assert has_element?(view, "#sheet-menu #app-status[phx-hook=AppStatus]", "App:")

      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ "navigator.serviceWorker?.getRegistration()"
      assert js =~ "install prompt: ${prompt}"
    end
  end

  describe "name cards" do
    test "keep the name on one line, cut with an ellipsis" do
      {_id, view} = herb_solo()
      assert has_element?(view, "[data-role=player-name] > [data-role=player-name-text].truncate")
      refute render(view) =~ "wrap-anywhere"
    end
  end
end
