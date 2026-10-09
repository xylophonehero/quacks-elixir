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
    # Round 33: in the bar, one chip at a time: the info row names it, then
    # Place, Keep and Return as three equal buttons.
    test "one chip at a time, three buttons, one line of help" do
      {id, view} = solo()
      red_choice(id, [{:red, 1}, {:red, 2}])

      bar = "#bar-pick-red_choice"
      refute has_element?(view, "dialog#decision-red_choice")
      assert has_element?(view, "#{bar} [data-role=info-row] [aria-label='red 1']")
      assert has_element?(view, "#{bar} [data-role=info-row]", "(2 waiting)")
      assert has_element?(view, "#{bar} [data-role=info-row]", "Place it now")
      assert has_element?(view, "#{bar} [data-role=choice-grid].grid-cols-3")

      for {kind, text} <- [place: "Place", keep: "Keep", return: "Return"] do
        action = QuacksWeb.GameLive.encode({:red, {kind, {:red, 1}}})
        assert has_element?(view, ~s(#{bar} button[phx-value-action="#{action}"]), text)
      end

      view
      |> element("#{bar} button[aria-label='Toadstool: return red 1 to the bag']")
      |> render_click()

      assert has_element?(view, "#{bar} [data-role=info-row] [aria-label='red 2']")
    end

    test "Keep puts the chip beside the pot" do
      {id, view} = solo()
      red_choice(id, [{:red, 2}])

      view
      |> element("#bar-pick-red_choice button[aria-label^='Toadstool: keep']")
      |> render_click()

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
      assert has_element?(view, ~s(#{tile}[phx-click="card_grow"]), card.name)
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
    test "the card hovers over the pot; a tap shrinks it into the corner" do
      {id, view} = solo(%{})
      {:ok, %{game: game}} = GameServer.get(id)
      name = Fortune.card(game.fortune_card).name

      assert has_element?(
               view,
               "[data-role=pot-area] > #pot-card-1.pot-card [data-role=card-flip]",
               name
             )

      # Round 24: no sheet for a card that did nothing by itself.
      refute has_element?(view, "dialog#reveal-card-1")

      # The tap: the card shrinks into the corner (a view transition of type card).
      view |> element("#card-tap") |> render_click()
      assert_push_event(view, "quacks:vt", %{type: "card"})
      refute has_element?(view, "#pot-card-1")
      assert has_element?(view, "[data-role=pot-area] #corner-card", name)
    end

    # Round 31: on every screen the card hovers over the pot while its choice waits
    # in the bar; there is no card dialog.
    test "a card's choice: the card hovers over the pot, no sheet" do
      {id, view} = solo(%{})

      replace_game(id, fn g ->
        g |> H.put(fortune_card: :p1, phase: :fortune_choice) |> Map.put(:phase, :fortune_choice)
      end)

      refute has_element?(view, "dialog#card-round-1")
      assert has_element?(view, "#pot-card-1.pot-card-reveal")
      refute has_element?(view, "#pot-card-1.lg\\:hidden")
    end

    test "the CSS: a clear backdrop, the pot card absolute, reduced motion skips the shrink" do
      css = File.read!("assets/css/app.css")
      assert css =~ ".sheet.reveal-card-sheet[open]::backdrop {\n  background-color: transparent;"
      assert css =~ ".pot-card {\n  position: absolute;"
      js = File.read!("assets/js/app.js")
      assert js =~ "!reduced()" and js =~ "types"
    end
  end

  # Round 31: no final slides any more: the score chart lies over the pot, Play
  # again / Lobby / Share are the bar's buttons, also after a reload.
  describe "the game's end in place" do
    defp over(g),
      do: %{
        g
        | phase: :over,
          round: 9,
          log: [{:round_end, 9}, {0, {:final_conversion, 7, 1, 2, 1}} | g.log]
      }

    defp in_place?(view) do
      has_element?(view, "[data-role=pot-area] #final-board [data-role=final-score]") and
        Enum.all?(
          ~w(play-again return-to-lobby share-result),
          &has_element?(view, "[data-role=game-over-actions] [data-role=#{&1}]")
        )
    end

    test "the chart over the pot and the bar's buttons, no overlay" do
      {id, view} = solo()
      replace_game(id, &over/1)

      assert in_place?(view)
      refute has_element?(view, "[data-role=reveal]")
      refute has_element?(view, "[data-role=show-result]")
      # Enter (Next) does nothing at the end.
      render_hook(view, "reveal_next", %{})
      assert in_place?(view)
    end

    test "a reload, and a spectator, show the same" do
      token = "r22-reload-#{System.unique_integer()}"
      {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
      {:ok, _view, _html} = live(browser(token), ~p"/g/#{id}")
      replace_game(id, &over/1)

      {:ok, again, _html} = live(browser(token), ~p"/g/#{id}")
      assert in_place?(again)

      {:ok, watcher, _html} = live(browser("r22-watch-#{System.unique_integer()}"), ~p"/g/#{id}")
      assert has_element?(watcher, "#final-board [data-role=final-score]")
    end
  end
end
