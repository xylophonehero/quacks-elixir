defmodule QuacksWeb.Round22Test do
  @moduledoc """
  Round 22: the pot's corners (the kept Toadstool chips top right, the fortune card
  top left), the new card over the pot, the rat track in equal steps, the final
  scoring in one overlay flow, and the Toadstool rows.
  """
  use QuacksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]

  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.Rules.Fortune

  defp browser(name), do: init_test_session(build_conn(), player_token: name)

  defp solo(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, rules)
    {:ok, view, _html} = live(browser("r22-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  defp red_choice(id, pending) do
    replace_game(id, fn g ->
      %{g | sets: Map.put(g.sets, :red, 2)} |> H.put(0, phase: :red_choice, pending: pending)
    end)
  end

  describe "the Toadstool rows" do
    test "one row per chip, three buttons each, one line of help" do
      {id, view} = solo()
      red_choice(id, [{:red, 1}, {:red, 2}])

      rows = "dialog#decision-red_choice [data-role=red-rows]"
      assert has_element?(view, "#{rows} #red-row-0 [data-role=red-chip][aria-label='red 1']")
      assert has_element?(view, "#{rows} #red-row-1 [data-role=red-chip][aria-label='red 2']")

      for i <- 0..1, kind <- ~w(place keep return) do
        assert has_element?(view, "#{rows} #red-row-#{i} button[data-role=red-#{kind}]")
      end

      # Place is the primary button; the three share the row equally.
      assert has_element?(view, "#{rows} #red-row-0 .grid-cols-3 button[data-role=red-place]")

      assert has_element?(
               view,
               "#{rows} #red-row-0 button[data-role=red-keep][class~='min-h-12']"
             )

      refute has_element?(view, "#{rows} [data-role=chip-pick]")
    end

    test "Keep puts the chip beside the pot" do
      {id, view} = solo()
      red_choice(id, [{:red, 2}])

      view |> element("#red-row-0 button[data-role=red-keep]") |> render_click()

      assert has_element?(
               view,
               "[data-role=pot-area] [data-role=beside-pot] [data-role=aside-chip]"
             )
    end
  end

  describe "the corner card" do
    test "the round's card sits in the pot's top left corner with its icon and name" do
      {id, view} = solo(%{})
      {:ok, %{game: game}} = GameServer.get(id)
      card = Fortune.card(game.fortune_card)

      tile = "[data-role=pot-area] > [data-role=pot-corner] > #corner-card"
      assert has_element?(view, ~s(#{tile}[popovertarget="sheet-fortune"]), card.name)
      assert has_element?(view, "#{tile} [data-role=card-motif], #{tile} svg")
      refute has_element?(view, "header [data-role=fortune-tile]")
    end
  end

  describe "the rat track" do
    defp trio(vps) do
      {:ok, id} = GameServer.start(3, {1, 2, 3}, %{}, %{fortune: false})
      token = "r22-#{System.unique_integer()}"
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      {:ok, _} = GameServer.add_bot(id, token)
      {:ok, _} = GameServer.add_bot(id, token)
      {:ok, _} = GameServer.begin(id, token)

      replace_game(id, fn g ->
        vps |> Enum.with_index() |> Enum.reduce(g, fn {vp, s}, g -> H.put(g, s, vp: vp) end)
      end)

      view
    end

    # The `left` of each dot or rat, in DOM order, as its 0..1 factor.
    defp lefts(view, role) do
      view
      |> element("#rat-track")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=#{role}]")
      |> Enum.map(fn node ->
        [style] = LazyHTML.attribute(node, "style")
        [_, x] = Regex.run(~r/\* ([\d.]+)\)/, style)
        String.to_float(x)
      end)
    end

    test "equal steps, not to scale: the leader left, the tails between" do
      # 30 / 11 / 2: tails 28..12 (9), 10, 7, 4 between them: 12 rats, 13 steps.
      view = trio([2, 30, 11])
      assert has_element?(view, "#rat-track[data-steps='13']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='1'][data-step='0']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='2'][data-step='9']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='0'][data-step='12']")

      rats = lefts(view, "track-rat")

      gaps =
        rats
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> Float.round(b - a, 3) end)

      assert gaps |> Enum.uniq() |> length() == 1
      assert rats == Enum.sort(rats)
    end

    test "seats on the same step stack" do
      view = trio([8, 13, 9])
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='0'][data-step='2']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='2'][data-step='2']")

      html = view |> element("#rat-track") |> render()
      assert html =~ "+ 3.5px" and html =~ "+ -3.5px"
    end
  end

  describe "a new card over the pot" do
    test "the card hovers over the pot; the overlay is a bottom sheet with Continue" do
      {id, view} = solo(%{})
      {:ok, %{game: game}} = GameServer.get(id)
      name = Fortune.card(game.fortune_card).name

      assert has_element?(view, "dialog#reveal-card-1.reveal-card-sheet")

      assert has_element?(
               view,
               "[data-role=pot-area] > #pot-card-1.pot-card [data-role=card-flip]",
               name
             )

      refute has_element?(view, "#reveal-card-1 [data-role=fortune-card]")
      refute has_element?(view, "#reveal-card-1 [data-role=reveal-strip]")
      assert has_element?(view, "#reveal-card-1 #reveal-next", "Continue")

      # Continue: the card shrinks into the corner (a view transition of type card).
      view |> element("#reveal-next") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "#pot-card-1")
      assert has_element?(view, "[data-role=pot-area] #corner-card", name)
    end

    test "a card's choice: on phones the card hovers over the pot, not in the sheet" do
      {id, view} = solo(%{})

      replace_game(id, fn g ->
        g |> H.put(fortune_card: :p1, phase: :fortune_choice) |> Map.put(:phase, :fortune_choice)
      end)

      assert has_element?(view, "dialog#card-round-1")
      # From 64rem the choice is a panel with the card; the pot card is for phones.
      assert has_element?(view, "#pot-card-1.lg\\:hidden")
      assert has_element?(view, "#card-round-1 .max-lg\\:hidden [data-role=fortune-card]")
    end

    test "the CSS: a clear backdrop, the pot card absolute, reduced motion skips the shrink" do
      css = File.read!("assets/css/app.css")
      assert css =~ ".sheet.reveal-card-sheet[open]::backdrop {\n  background-color: transparent;"
      assert css =~ ".pot-card {\n  position: absolute;"
      js = File.read!("assets/js/app.js")
      assert js =~ "!reduced()" and js =~ "types"
    end
  end

  describe "the final scoring in one overlay flow" do
    defp over(g),
      do: %{
        g
        | phase: :over,
          round: 9,
          log: [{:round_end, 9}, {0, {:final_conversion, 7, 1, 2, 1}} | g.log]
      }

    test "final scoring, standings, podium; the last slide holds the actions and stays" do
      {id, view} = solo()
      replace_game(id, &over/1)

      assert has_element?(view, "#reveal-final-9 #reveal-slide-0[data-kind=final]")
      view |> element("#reveal-next") |> render_click()
      assert has_element?(view, "#reveal-final-9 #reveal-slide-1[data-kind=standings]")
      view |> element("#reveal-next") |> render_click()

      last = "#reveal-final-9 #reveal-slide-2[data-kind=podium]"
      assert has_element?(view, "#{last} [data-role=game-over]")

      for role <- ~w(play-again return-to-lobby share-result),
          do: assert(has_element?(view, "#{last} [data-role=#{role}]"))

      refute has_element?(view, "#reveal-final-9 [data-role=reveal-bar]")
      refute has_element?(view, "#reveal-stage[phx-click]")
      refute has_element?(view, "dialog#game-over")

      # Enter (Next) does not close it; × does; "Show the result" opens it again.
      render_hook(view, "reveal_next", %{})
      assert has_element?(view, last)
      render_hook(view, "reveal_close", %{})
      refute has_element?(view, "#reveal-final-9")
      view |> element("[data-role=show-result]") |> render_click()
      assert has_element?(view, "#{last} [data-role=play-again]")
    end

    test "a reload in the middle of the final slides shows the last one" do
      token = "r22-mid-#{System.unique_integer()}"
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      replace_game(id, &over/1)
      assert has_element?(view, "#reveal-final-9 #reveal-slide-0")

      {:ok, again, _html} = live(browser(token), ~p"/g/#{id}")
      assert has_element?(again, "#reveal-final-9 #reveal-slide-2 [data-role=play-again]")
    end

    test "a reload after the end shows the last slide" do
      token = "r22-reload-#{System.unique_integer()}"
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
      replace_game(id, &over/1)
      render_hook(view, "reveal_close", %{})
      assert {:ok, %{seen: %{0 => %{final: 9}}}} = GameServer.get(id)

      {:ok, again, _html} = live(browser(token), ~p"/g/#{id}")

      assert has_element?(
               again,
               "#reveal-final-9 #reveal-slide-2[data-kind=podium] [data-role=play-again]"
             )

      assert has_element?(
               again,
               "#reveal-final-9 #reveal-slide-2[data-kind=podium] [data-role=play-again]"
             )

      # A spectator gets the last slide too.
      {:ok, watcher, _html} = live(browser("r22-watch-#{System.unique_integer()}"), ~p"/g/#{id}")
      assert has_element?(watcher, "#reveal-final-9 [data-role=game-over]")
    end
  end
end
