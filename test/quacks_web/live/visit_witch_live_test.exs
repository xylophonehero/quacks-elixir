defmodule QuacksWeb.VisitWitchLiveTest do
  @moduledoc "AB8 Visit from a witch on the game page."
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Quacks.GameHelpers
  alias Quacks.GameServer
  alias QuacksWeb.GameText

  setup %{conn: conn} do
    %{conn: init_test_session(conn, player_token: "visit-#{System.unique_integer()}")}
  end

  # A solo Herb Witches game (seed 1,2,3 deals S2, C4 and G4) with `visitor` this
  # round's visiting witch under AB8.
  defp live_visit(conn, visitor, fields \\ []) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false}, :herb_witches)
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")

    GameHelpers.replace_game(id, fn g ->
      %{g | fortune_card: :ab8, visitor: visitor} |> GameHelpers.put(0, fields)
    end)

    {id, view}
  end

  test "the visiting witch: on the card, on the witches sheet, free; a call uses the visit",
       %{conn: conn} do
    {_id, view} = live_visit(conn, :s3)
    view |> element("button[data-slot=draw]") |> render_click()

    assert has_element?(view, "#sheet-fortune [data-role=card-visitor][data-witch=s3]")
    assert has_element?(view, "#sheet-fortune [data-role=witch-card][data-visit]")

    card = "#sheet-witches [data-role=witch-card][data-witch=s3][data-visit]"
    assert has_element?(view, card, "visit · free this round")
    assert has_element?(view, "#sheet-witches [data-witch=s2]:not([data-visit])", "1 penny")
  end

  test "a visiting silver S3 is called from her card; her penny-free state shows", %{conn: conn} do
    {id, view} = live_visit(conn, :s3)
    GameHelpers.replace_game(id, &GameHelpers.force_draws(&1, [{:white, 1}]))
    card = "#sheet-witches [data-witch=s3][data-visit]"
    view |> element("#{card} button", "Call: the last white back") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    assert 0 in game.visited and game.players[0].pennies.silver
    assert has_element?(view, card, "visit used")
    refute has_element?(view, "#{card} button")
  end

  test "a visiting silver S4 is in the explosion bar", %{conn: conn} do
    {id, view} = live_visit(conn, :s4)

    GameHelpers.replace_game(
      id,
      &GameHelpers.force_draws(&1, [{:white, 3}, {:white, 3}, {:white, 2}])
    )

    assert has_element?(view, "footer [data-role=explosion-witch]")
    view |> element("footer [data-role=explosion-witch]") |> render_click()

    {:ok, %{game: game}} = GameServer.get(id)
    assert game.players[0].explosion_choice == :witch and game.players[0].pennies.silver
  end

  test "a visiting copper witch has her own card in the shop", %{conn: conn} do
    {id, view} = live_visit(conn, :c2)

    GameHelpers.replace_game(id, &GameHelpers.put(&1, 0, phase: :buy, coins: 6))
    assert has_element?(view, "[data-role=witch-card][data-witch=c2][data-visit] button")
  end

  test "log labels for the visit" do
    assert GameText.label({:visitor, :c3}) =~ "One free copy"
    assert GameText.label({:visitor_left, :c3}) =~ "left"
    assert GameText.label({:witch, :visit}) == "Call the visiting witch (free)"
    assert GameText.label({:witch, :visit, 2}) =~ "2 white chips"
    assert GameText.label({:witch, :visit, {:upgrade, [{:green, 1}]}}) =~ "upgrade"

    assert GameText.label({:witch, :visit, {:buy, [{:orange, 1}], {:orange, 1}}}) =~
             "free"
  end
end
