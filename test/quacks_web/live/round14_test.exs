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

  describe "the herb witch pickers" do
    test "show with the expansion; a pick goes into the game and the browser's memory" do
      {:ok, id} = GameServer.start(2)
      {:ok, host, _html} = live(browser("r14-host-#{System.unique_integer()}"), ~p"/g/#{id}")
      refute has_element?(host, "[data-role=witch-pickers]")

      host |> form("#books", expansion: "true") |> render_change()
      assert has_element?(host, "[data-role=witch-tile][data-colour=copper]", "Random")

      tiles =
        host
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("[data-role=witch-tile]")
        |> LazyHTML.attribute("data-colour")

      assert tiles == ~w(copper silver gold)
      assert has_element?(host, "#witch-picker-silver [data-witch=s3]", "Two whites back")

      host
      |> form("#books", expansion: "true", witches: %{copper: "c3", silver: "", gold: ""})
      |> render_change()

      assert {:ok, %{witches: %{copper: :c3, silver: nil, gold: nil}}} = GameServer.get(id)
      assert has_element?(host, "[data-role=witch-tile][data-witch=c3]", "One free copy")

      assert_push_event(host, "save_config", %{
        expansion: true,
        witches: %{copper: "c3", silver: "", gold: ""}
      })

      host |> element("button", "Start game") |> render_click()
      {:ok, %{game: game}} = GameServer.get(id)
      assert game.witches.copper == :c3
    end

    test "parse_witches: an unknown id or a missing colour is Random" do
      assert QuacksWeb.SetupComponents.parse_witches(%{"copper" => "c3", "gold" => "g9"}) ==
               %{copper: :c3, silver: nil, gold: nil}

      assert QuacksWeb.SetupComponents.parse_witches(nil) == %{
               copper: nil,
               silver: nil,
               gold: nil
             }
    end

    test "a fresh screen takes the saved picks back" do
      {:ok, id} = GameServer.start(2)
      {:ok, host, _html} = live(browser("r14-fresh-#{System.unique_integer()}"), ~p"/g/#{id}")

      render_hook(host, "load_config", %{
        "players" => 2,
        "expansion" => true,
        "witches" => %{"gold" => "g2", "copper" => "nope"}
      })

      assert {:ok, %{witches: %{gold: :g2, copper: nil}}} = GameServer.get(id)
      assert has_element?(host, "[data-role=witch-tile][data-witch=g2]", "Count the bag")
    end

    test "a debug table from a bundle keeps the picks" do
      session =
        Quacks.Session.new({1, 2, 3}, 1, expansions: [:herb_witches], witches: %{silver: :s4})

      bundle = Quacks.Session.bundle(session)
      {:ok, id} = GameServer.start_from_bundle(bundle)

      assert {:ok, %{game: %{witches: %{silver: :s4}}, witches: %{silver: :s4}}} =
               GameServer.get(id)
    end
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
