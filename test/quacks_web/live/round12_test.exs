defmodule QuacksWeb.Round12Test do
  @moduledoc """
  Round 12 playtest fixes: the reward line above the draw strip (with the chance
  that the next draw explodes), a shop bar that fits its sheet, name cards without
  update chips, the b key for the bag, and the ruby marker on a space's lower left.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("solo-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  defp key(view, key, meta \\ %{}),
    do: view |> element("#game") |> render_keydown(Map.put(meta, "key", key))

  describe "the reward line" do
    test "sits beside the white meter and always names the VP" do
      {_id, view} = solo()

      # Round 29: one row, the meter then the reward.
      assert has_element?(view, "[data-role=fuse-row] > #fuse-meter + [data-role=reward-line]")
      assert has_element?(view, "[data-role=reward-line].h-7 [data-role=next-reward]", "Reward:")
      assert has_element?(view, "[data-role=next-reward]", "0 VP")
    end

    test "shows the chance that the next draw explodes, 0% when it cannot" do
      {id, view} = solo()
      assert has_element?(view, "[data-role=explode-chance][data-percent=\"0\"]", "Explode: 0%")

      # 6 white in the pot, limit 7: the 3-white of two chips explodes (50%).
      replace_game(id, fn g ->
        H.put(g, 0,
          drawn: [{{:white, 3}, 3}, {{:white, 3}, 1}],
          bag: [{:white, 3}, {:orange, 1}],
          starters: []
        )
      end)

      assert has_element?(view, "[data-role=explode-chance][data-percent=\"50\"]", "Explode: 50%")

      replace_game(id, &H.put(&1, 0, phase: :stopped))
      assert has_element?(view, "[data-role=explode-chance][data-percent=\"0\"]")
    end
  end

  describe "the b key" do
    test "toggles the bag sheet; not while typing or with a modal open" do
      {_id, view} = solo()
      key(view, "b")
      assert_push_event(view, "quacks:toggle", %{id: "sheet-bag"})
      key(view, "B")
      assert_push_event(view, "quacks:toggle", %{id: "sheet-bag"})

      key(view, "b", %{"typing" => true})
      key(view, "b", %{"modal" => true})
      refute_push_event(view, "quacks:toggle", _, 50)
    end

    test "app.js toggles the popover the server names" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ ~s{window.addEventListener("phx:quacks:toggle"}
      assert js =~ "togglePopover()"
    end

    test "the key hints are lowercase; the bag button names its key" do
      {_id, view} = solo()
      assert has_element?(view, "[data-slot=draw] kbd", "d")
      assert has_element?(view, "[data-role=bag-button][aria-keyshortcuts=b]")
    end
  end

  describe "the shop bar" do
    test "fits its sheet: its parts may shrink, Buy's Enter hint needs the room" do
      {id, view} = solo()
      replace_game(id, &H.put(&1, 0, phase: :shop, coins: 20))
      assert has_element?(view, "[data-role=shop-footer].min-w-0")
      assert has_element?(view, "[data-role=shop-buy].min-w-0")

      view
      |> element("#shop")
      |> render_change(%{"chips" => [QuacksWeb.ActionCode.encode({:orange, 1})]})

      assert has_element?(view, "[data-role=shop-buy].min-w-0 span.truncate", "Buy")

      # Round 35: nothing ticked, Buy stays (disabled); there is no Skip.
      view |> element("#shop") |> render_change(%{"chips" => []})
      assert has_element?(view, "[data-role=shop-buy]:disabled")
    end
  end

  describe "the pot" do
    test "a ruby space has its gem on the lower left, mirroring the VP tag" do
      {_id, view} = solo()
      html = render(view)
      assert html =~ ~s(x="-21.5")
      refute html =~ ~s(y="-27")
    end
  end
end
