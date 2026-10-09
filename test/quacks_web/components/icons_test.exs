defmodule QuacksWeb.IconsTest do
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameServer
  alias Quacks.Rules.{Alchemists, Chips}
  alias QuacksWeb.{GameComponents, Icons}

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "icons-#{System.unique_integer()}")}
  end

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  # An icon draws from the page's sprite: one `<use href="#icon-NAME">`, no paths.
  defp one_path?(html, name) do
    svg = query(html, ~s(svg[data-icon="#{name}"][viewBox="0 0 512 512"]))

    Enum.count(svg) == 1 and Enum.count(LazyHTML.query(svg, ~s(use[href="#icon-#{name}"]))) == 1 and
      Enum.empty?(LazyHTML.query(svg, "path"))
  end

  test "every chip colour has an ingredient icon" do
    colours = Chips.shop() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    assert Enum.sort([:white | colours]) -- Icons.ingredients() == []

    for colour <- Icons.ingredients() do
      assert one_path?(render_component(&Icons.ingredient_icon/1, colour: colour), colour)
    end
  end

  test "every piece has an icon" do
    for name <- ~w(flask droplet ruby rat die vp book tube bag cauldron penny witch)a do
      assert one_path?(render_component(&Icons.piece_icon/1, name: name), name)
    end
  end

  test "every patient has an icon" do
    assert Enum.sort(Alchemists.patients()) == Enum.sort(Icons.patients())

    for id <- Alchemists.patients() do
      assert one_path?(render_component(&Icons.patient_icon/1, id: id), id)
    end
  end

  test "the sprite holds one symbol per icon; inline puts the paths in place" do
    sprite = render_component(&Icons.sprite/1, %{})
    names = Icons.ingredients() ++ Icons.pieces() ++ Icons.patients()

    for name <- names do
      symbol = query(sprite, ~s(svg#icon-sprite symbol#icon-#{name}[viewBox="0 0 512 512"]))
      assert Enum.count(symbol) == 1
      refute Enum.empty?(LazyHTML.query(symbol, "path"))
    end

    assert sprite |> query("symbol") |> Enum.count() == length(names)

    inline = render_component(&Icons.piece_icon/1, name: :ruby, inline: true)
    refute inline |> query("svg[data-icon=ruby] path") |> Enum.empty?()
    assert inline |> query("use") |> Enum.empty?()
  end

  test "every page has the sprite once", %{conn: conn} do
    {:ok, id} = GameServer.start(1, {10, 11, 12})

    for path <- [~p"/", ~p"/g/#{id}"] do
      html = conn |> get(path) |> html_response(200)
      assert html |> query("svg#icon-sprite") |> Enum.count() == 1
      assert html |> query("symbol#icon-white") |> Enum.count() == 1
    end
  end

  test "a chip shows its icon and its value; :xs shows only the value" do
    html = render_component(&GameComponents.chip/1, chip: {:orange, 1})
    assert one_path?(html, :orange)
    assert html |> query("[data-role=chip-value]") |> LazyHTML.text() =~ "1"

    xs = render_component(&GameComponents.chip/1, chip: {:orange, 1}, size: :xs)
    assert xs |> query("svg") |> Enum.empty?()
  end

  test "every bonus die face draws" do
    for face <- [{:vp, 1}, {:vp, 2}, :ruby, :droplet, :orange] do
      html = render_component(&GameComponents.die/1, face: face)
      assert Enum.count(query(html, "[data-role=die] .die-strip > g")) == 7
    end
  end

  test "shop tiles show the ingredient icon", %{conn: conn} do
    {:ok, id} = GameServer.start(1, {10, 11, 12})
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
    view |> element("button", "Stop") |> render_click()

    tiles = view |> render() |> query("[data-role=shop-row] label")
    assert Enum.count(tiles) == length(Chips.shop())
    assert Enum.all?(tiles, &(not Enum.empty?(LazyHTML.query(&1, "svg[data-icon]"))))
    # placed chips in the pot carry their icon too
    assert has_element?(view, "[data-role=pot-chip] svg[data-icon]")
  end

  test "the lobby credits the icon authors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#credits", "game-icons.net")
    assert has_element?(view, "#credits", "CC BY 3.0")
    assert File.read!("docs/CREDITS.md") =~ "CC BY 3.0"
  end
end
