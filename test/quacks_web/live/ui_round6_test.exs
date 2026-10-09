defmodule QuacksWeb.UiRound6Test do
  @moduledoc """
  Nick's fifth game: no shop after exploding (or with nothing to buy), and the
  chips of a choice are the controls.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.{Game, GameServer}
  alias Quacks.GameHelpers, as: H
  alias QuacksWeb.GameLive

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("solo-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  defp pick(action),
    do: ~s(button[data-role=chip-pick][phx-value-action="#{GameLive.encode(action)}"])

  test "a seat that exploded and took the VP gets OK, then the rubies; no shop" do
    {id, view} = solo()

    replace_game(
      id,
      &H.put(&1, 0, phase: :shop, exploded?: true, explosion_choice: :vp, rubies: 2)
    )

    refute has_element?(view, "dialog#decision-shop")
    # Round 29: the rubies are in the bar, no dialog to open.
    assert has_element?(view, "#bar-rubies")
    render_hook(view, "reveal_close", %{})
    refute_push_event(view, "quacks:open", %{to: "#decision-rubies"})
  end

  test "a seat with no coins to spend skips the shop too; with coins it shops" do
    {id, view} = solo()
    replace_game(id, &H.put(&1, 0, phase: :shop, coins: 0, rubies: 2))
    refute has_element?(view, "dialog#decision-shop")
    assert has_element?(view, "#bar-rubies")

    replace_game(id, &H.put(&1, 0, coins: 10))
    assert has_element?(view, "dialog#decision-shop #shop")
    render_hook(view, "reveal_close", %{})
    assert_push_event(view, "quacks:open", %{to: "#decision-shop"})
  end

  test "the crow skull offer: the chips are the buttons; Return all stays text" do
    {id, view} = solo()
    replace_game(id, &H.put(&1, 0, phase: :blue_choice, pending: [{:red, 1}, {:white, 1}]))

    # Round 33: in the bar, the chips are buttons, then Return all.
    bar = "#bar-pick-blue_choice"
    refute has_element?(view, "dialog#decision-blue_choice")
    place = &~s(#{bar} button[phx-value-action="#{GameLive.encode({:place, &1})}"])
    assert has_element?(view, "#{place.({:red, 1})} .chip-token")
    assert has_element?(view, place.({:white, 1}))
    assert has_element?(view, "#{bar} button[aria-label^='Crow skull: return all']", "Return all")

    view |> element(place.({:red, 1})) |> render_click()
    {:ok, %{game: game}} = GameServer.get(id)
    assert {:red, 1} in Game.pot_chips(game, 0)
  end

  test "any 2-value chip: one chip per colour, in shop row order" do
    game =
      Game.new(seed: {1, 2, 3}, fortune: false)
      |> H.put(fortune_card: :p1, phase: :fortune_choice)

    game = %{game | phase: :fortune_choice}
    actions = Game.legal_actions(game, 0)

    html =
      render_component(&GameLive.chip_picks/1, actions: actions, game: game, me: game.players[0])

    chips =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("button[data-role=chip-pick] [aria-label]")
      |> LazyHTML.attribute("aria-label")

    assert chips == ["blue 2", "red 2", "green 2", "black 1"]
    assert count(html, pick({:fortune, {:take, {:green, 2}}})) == 1
    # "Take 3 rubies" has no chip: a text button outside the picks
    assert count(html, "button[data-role=chip-pick]") == 4
  end

  test "toadstool Set 2: one row per chip with Place, Keep and Return" do
    {id, view} = solo()

    replace_game(id, fn g ->
      %{g | sets: Map.put(g.sets, :red, 2)} |> H.put(0, phase: :red_choice, pending: [{:red, 2}])
    end)

    bar = "#bar-pick-red_choice"
    assert has_element?(view, "#{bar} [data-role=info-row] [aria-label='red 2']")

    for {kind, text} <- [place: "Place", keep: "Keep", return: "Return"] do
      action = GameLive.encode({:red, {kind, {:red, 2}}})
      assert has_element?(view, ~s(#{bar} button[phx-value-action="#{action}"]), text)
    end

    refute has_element?(view, "dialog#decision-red_choice")
  end
end
