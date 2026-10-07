defmodule QuacksWeb.TidyTest do
  @moduledoc """
  QA pass 2 leftovers: the log in one tense (past) with one line per event, the
  shop status line for a seat that cannot buy, a decision that waits for the new
  card (G5), the small card tile on phones (G6) and the toast above the bottom bar
  on phones (G7).
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias QuacksWeb.GameComponents

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp open(conn, id) do
    {:ok, view, _html} = live(conn, ~p"/g/#{id}")
    view
  end

  defp token(name), do: "#{name}-#{System.unique_integer()}"

  defp log_html(log),
    do: render_component(&GameComponents.action_log/1, log: log, names: %{0 => "A", 1 => "B"})

  describe "the log" do
    test "actions read in the past tense" do
      html =
        log_html([
          {0, {:buy, []}},
          {1, {:explosion_choice, :vp}},
          {1, {:exploded, 9}},
          {0, :stop},
          {0, :keep},
          {1, :witch_done}
        ])

      assert html =~ "A: Bought nothing"
      assert html =~ "B: Exploded: took the VP"
      assert html =~ "B: Exploded (white 9)"
      assert html =~ "A: Stopped<"
      assert html =~ "A: Mandrake: kept the white chip"
      assert html =~ "B: Kept the gold penny"
      refute html =~ "Buy nothing"
      refute html =~ "take the victory points"
    end

    test "an action that its event narrates is one line" do
      html = log_html([{0, {:returned, {:white, 1}}}, {0, :use_flask}])

      assert html =~ "A: Returned white 1 to the bag"
      refute html =~ "flask"
    end

    test "buttons keep the imperative" do
      assert GameComponents.label({:buy, []}) == "Buy nothing"
      assert GameComponents.label(:use_flask) == "Use flask"
    end
  end

  describe "the shop status line" do
    setup do
      {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, %{fortune: false})
      alice = open(browser(token("alice")), id)
      bob = open(browser(token("bob")), id)
      alice |> element("button", "Start game") |> render_click()

      # Alice exploded and took the VP: she keeps her rubies to spend, but no buy.
      replace_game(id, fn g ->
        g
        |> H.put(0, explosion_choice: :vp, coins: 0, rubies: 3)
        |> H.put(1, coins: 20)
        |> Quacks.Game.to_shop()
      end)

      %{alice: alice, bob: bob}
    end

    test "a seat with no buy waits for the others", %{alice: alice, bob: bob} do
      refute has_element?(alice, "[data-role=turn]")
      refute has_element?(bob, "[data-role=turn]")
    end
  end

  test "G5: a decision waits for the round's new card, which opens it on close (round 14: the overlay)" do
    {:ok, id} = GameServer.start(2, {1, 2, 3})
    alice = open(browser(token("alice")), id)
    _bob = open(browser(token("bob")), id)
    alice |> element("button", "Start game") |> render_click()
    replace_game(id, &H.put(&1, 0, droplet_moves: 1))

    assert has_element?(alice, "dialog#decision-droplet_choice")
    refute has_element?(alice, "dialog#decision-droplet_choice[phx-mounted*='quacks:modal']")
    assert has_element?(alice, "#pot-card-1 [data-role=card-caption]")
    alice |> element("#card-tap") |> render_click()
    assert_push_event(alice, "quacks:open", %{to: "#decision-droplet_choice"})
  end

  test "G6: the card tile is small on phones" do
    html = render_component(&GameComponents.fortune_tile/1, id: :b3)
    assert html =~ "w-12"
    assert html =~ "lg:w-20"
  end

  test "G7: the toast sits above the bottom bar on phones" do
    html =
      render_component(&QuacksWeb.CoreComponents.flash/1,
        kind: :info,
        flash: %{"info" => "You are now the host."}
      )

    assert html =~ "bottom-28"
    assert html =~ "sm:top-20"
  end
end
