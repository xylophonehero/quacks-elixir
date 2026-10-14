defmodule QuacksWeb.PotBoardTest do
  @moduledoc """
  The pot and the board around it: VP tags, the overflow bowl, the ruby badge, a spoiled brew, the Toadstool rows and the corner card, the rat track, sticky sheet headers, chips that move in the pot, test tubes, the burst and the draw flight, the scoring ring, the value badge and the Mandrake chip over the bag.
  """
  use QuacksWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Quacks.GameHelpers, only: [replace_game: 2]
  import QuacksWeb.LiveHelpers
  import QuacksWeb.LiveHelpers
  alias Quacks.Game
  alias Quacks.GameHelpers
  alias Quacks.GameHelpers, as: H
  alias Quacks.GameServer
  alias Quacks.Rules.Fortune
  alias Quacks.Rules.PotTrack
  alias QuacksWeb.ChipComponents
  alias QuacksWeb.Icons
  alias QuacksWeb.PotComponents

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
        action = QuacksWeb.ActionCode.encode({:red, {kind, {:red, 1}}})
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

  describe "the 💥 burst" do
    test "the explosion symbol is our layered burst, not explosion-rays" do
      sprite = render_component(&Icons.sprite/1, %{})
      [symbol] = Regex.run(~r{<symbol id="icon-explosion".*?</symbol>}s, sprite)

      for colour <- ~w(#d6322c #f28a1e #ffd94a), do: assert(symbol =~ colour)
      assert length(Regex.scan(~r/<path/, symbol)) == 3
    end
  end

  describe "round 45: chips that change" do
    defp pot_html(game, opts) do
      render_component(&QuacksWeb.PotComponents.pot/1, [game: game, seat: 0] ++ opts)
      |> LazyHTML.from_fragment()
    end

    defp drew(chips) do
      game = Game.new(seed: {1, 2, 3}, players: 1, rules: %{fortune: false})
      drawn = chips |> Enum.with_index(1) |> Enum.reverse()
      H.put(game, 0, drawn: drawn)
    end

    test "your pot's chips name their kind, for a swap in place" do
      html = pot_html(drew([{:white, 1}, {:green, 1}]), flask: :full)
      chips = LazyHTML.query(html, "[data-role=pot-chip]")
      assert Enum.sort(LazyHTML.attribute(chips, "data-chip")) == ["green-1", "white-1"]
    end

    test "a purple book IV upgrade leaves the bigger chip's face for the morph" do
      game =
        drew([{:white, 1}]) |> Game.effect(0, {:purple, 4}, {:upgrade, {:green, 1}, {:green, 2}})

      [to] =
        pot_html(game, flask: :full) |> LazyHTML.query("[data-role=morph-to]") |> Enum.to_list()

      assert LazyHTML.attribute(to, "data-from") == ["green-1"]
      assert LazyHTML.attribute(to, "visibility") == ["hidden"]
      assert LazyHTML.query(to, "[data-role=chip-value]") |> Enum.count() == 1

      assert pot_html(drew([{:white, 1}]), flask: :full)
             |> LazyHTML.query("[data-role=morph-to]")
             |> Enum.empty?()
    end

    test "the flask tips as a group, and the pot carries the shuffle and flask sounds" do
      html = pot_html(drew([{:white, 1}]), flask: :full)

      assert LazyHTML.query(
               html,
               "[data-role=flask] [data-role=flask-tilt] [data-role=flask-brew]"
             )
             |> Enum.count() == 1

      [svg] = LazyHTML.query(html, "svg[phx-hook=PotMotion]") |> Enum.to_list()
      assert LazyHTML.attribute(svg, "data-shuffle-sound") == [QuacksWeb.Sounds.shuffle_sound()]
      assert LazyHTML.attribute(svg, "data-flask-sound") == ["flask"]
    end

    test "a bag list with an id keys each kind and its count, so they pop" do
      html =
        render_component(&PotComponents.chip_counts/1, chips: [{:white, 1}, {:white, 1}], id: "b")
        |> LazyHTML.from_fragment()

      assert LazyHTML.query(html, "li#b-white-1.chip-in span#b-white-1-n2.count-in")
             |> Enum.count() == 1
    end

    test "the moves play once and honour reduced motion" do
      js = File.read!("assets/js/pot_moves.js") <> File.read!("assets/js/chip_morph.js")
      assert js =~ "reduced()"
      assert File.read!("assets/js/app.js") =~ "swapped.forEach(c => this.swap(c))"
    end
  end

  describe "the draw flight" do
    test "only your own large pot is marked for PotMotion's bag-to-pot flight" do
      game = Game.new(seed: {1, 2, 3})
      seat = game.players |> Map.keys() |> Enum.min()

      pot = fn opts ->
        render_component(&QuacksWeb.PotComponents.pot/1, [game: game, seat: seat] ++ opts)
      end

      assert pot.(flask: :full) =~ ~s(data-mine="true")
      refute pot.([]) =~ "data-mine"
      refute pot.(size: :sm, flask: :full) =~ "data-mine"
    end

    test "app.js flies one new chip from the bag, with no flight under reduced motion" do
      js = File.read!("assets/js/app.js")

      assert js =~
               "this.el.dataset.mine && this.bag()) this.fly(added[0]), potSound.draw(this.el, added[0])"

      assert js =~ ~r/fly\(chip[^{]*\{\n\s+if \(reduced\(\)\) return/
    end
  end

  defp trio_2(vps) do
    {:ok, id} = GameServer.start(3, {1, 2, 3}, %{}, %{fortune: false})
    token = "r34-#{System.unique_integer()}"
    {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
    {:ok, _} = GameServer.add_bot(id, token)
    {:ok, _} = GameServer.add_bot(id, token)
    {:ok, _} = GameServer.begin(id, token)

    replace_game(id, fn g ->
      vps |> Enum.with_index() |> Enum.reduce(g, fn {vp, s}, g -> H.put(g, s, vp: vp) end)
    end)

    view
  end

  describe "sticky sheet headers" do
    test "the game's sheets mark their title row as the sticky head" do
      view = trio_2([0, 0, 0])

      for sheet <- ~w(sheet-books sheet-bag sheet-log sheet-menu) do
        assert has_element?(view, "##{sheet} .sheet-head"), sheet
      end
    end

    test "the head and the × are sticky; so is a New-game book page's heading" do
      css = File.read!("assets/css/app.css")
      assert css =~ ~r/\.sheet \.sheet-head \{\s*position: sticky;/
      assert css =~ ~r/\.sheet \.sheet-close \{\s*position: sticky;/
      assert css =~ ~r/\.book-heading \{\s*position: sticky;/
    end
  end

  describe "rat tails after 50" do
    test "the rat track counts the tails on the second lap" do
      # Nick's round-scored screen: 51 / 39 / 68. 51..67: tails after 51, 54, 57,
      # 60, 62, 64, 66 (7); 39..50: 40..48 (5) more, 12 rats, 13 steps.
      view = trio_2([51, 39, 68])
      assert has_element?(view, "#rat-track[data-steps='13']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='2'][data-step='0']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='0'][data-step='7']")
      assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='1'][data-step='12']")
    end
  end

  describe "a chip that moves in the pot (green III)" do
    defp pot_chips(game) do
      render_component(&PotComponents.pot/1, game: game)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-role=pot-chip]")
      |> Enum.map(fn n ->
        {hd(LazyHTML.attribute(n, "id")), hd(LazyHTML.attribute(n, "data-order")),
         hd(LazyHTML.attribute(n, "data-index"))}
      end)
    end

    test "keeps its draw order on a new id at the new space: PotMotion flies it from there" do
      game = Game.new(seed: {1, 2, 3})
      drawn = [{{:green, 2}, 9}, {{:white, 3}, 7}, {{:white, 4}, 4}]
      before = put_in(game.players[0].drawn, drawn)
      moved = put_in(game.players[0].drawn, [{{:green, 2}, 11} | tl(drawn)])

      [{old_id, order, "9"}] = pot_chips(before) -- pot_chips(moved)
      [{new_id, ^order, "11"}] = pot_chips(moved) -- pot_chips(before)
      assert old_id != new_id

      js = File.read!("assets/js/app.js")
      assert js =~ "gone[0].dataset.order === added[0].dataset.order"
      assert js =~ "this.fly(added[0], this.pos(gone[0].dataset.index)"
    end
  end

  describe "rat track labels" do
    defp track(vps) do
      game = Game.new(seed: {1, 2, 3}, players: length(vps))

      game =
        vps
        |> Enum.with_index()
        |> Enum.reduce(game, fn {vp, s}, g -> put_in(g.players[s].vp, vp) end)

      render_component(&QuacksWeb.TrackComponents.rat_track/1, game: game, names: %{})
      |> LazyHTML.from_fragment()
    end

    defp texts(html, selector) do
      html |> LazyHTML.query(selector) |> Enum.map(&String.trim(LazyHTML.text(&1)))
    end

    test "every seat's VP shows at its dot" do
      html = track([30, 3, 12])
      assert texts(html, "[data-role=leader-vp]") == ["30"]
      assert Enum.sort(texts(html, "[data-role=track-vp]")) == ["12", "3"]
    end

    test "3 or more rats between neighbouring seats: no rat VPs in between" do
      # 30 vs 12: tails 12..28 = 9 rats; 12 vs 3: tails 4, 7, 10 = 3 rats.
      html = track([30, 3, 12])
      assert length(LazyHTML.query(html, "[data-role=track-rat]") |> Enum.to_list()) == 12
      assert Enum.all?(texts(html, "[data-role=track-rat]"), &(&1 == ""))
    end

    test "small gaps keep their rat VPs" do
      # 12 vs 8: tail 10 (1 rat); 8 vs 3: tails 7, 4 (2 rats).
      html = track([3, 12, 8])
      assert texts(html, "[data-role=track-rat]") == ~w(10 7 4)
    end

    test "mixed: the big gap is quiet, the small gap keeps its VPs" do
      # 20 vs 8: tails 18..10 = 5 rats (quiet); 8 vs 3: tails 7, 4 (shown).
      html = track([20, 8, 3])
      assert Enum.reject(texts(html, "[data-role=track-rat]"), &(&1 == "")) == ~w(7 4)
    end

    test "tails repeat after 50" do
      html = track([56, 50])
      assert texts(html, "[data-role=track-rat]") == ~w(54 51)
    end
  end

  describe "rats in the pot when the droplet moves" do
    alias Quacks.GameHelpers, as: H
    alias QuacksWeb.{PotComponents, TrackComponents}

    defp rat_game do
      Game.new(seed: {1, 2, 3}, players: 2) |> H.put(1, rat_stone: 3, pot_index: 3)
    end

    test "before the first draw the rats follow the droplet" do
      game = rat_game() |> Game.move_droplet(1, 1)
      assert TrackComponents.rat_spaces(game.players[1]) == [2, 3, 4]
      assert game.players[1].pot_index == 4
    end

    test "the first chip fixes the rat stone; a later move takes the first rat's space" do
      game = H.force_draws(rat_game(), 1, [{:white, 2}])
      assert game.players[1].mods.rat_end == 3
      assert TrackComponents.rat_spaces(game.players[1]) == [1, 2, 3]

      game = Game.move_droplet(game, 1, 1)
      assert TrackComponents.rat_spaces(game.players[1]) == [2, 3]
      # Locoweed 5 still reads the distance moved at round start.
      assert game.players[1].rat_stone == 3

      game = Game.move_droplet(game, 1, 3)
      assert TrackComponents.rat_spaces(game.players[1]) == []
    end

    test "the pot draws one pebble per rat space, keyed by its space" do
      game = H.force_draws(rat_game(), 1, [{:white, 2}]) |> Game.move_droplet(1, 1)

      html =
        render_component(&PotComponents.pot/1, game: game, seat: 1, size: :lg)
        |> LazyHTML.from_fragment()

      rats = LazyHTML.query(html, "[data-role=rat]")
      assert Enum.map(rats, &LazyHTML.attribute(&1, "data-index")) == [["2"], ["3"]]
    end
  end

  describe "chips back to the bag before the shop" do
    alias Quacks.GameServer

    test "the results keep the chips; closing them for the shop bags them" do
      {:ok, id} = GameServer.start(1, {10, 11, 12})

      {:ok, view, _html} =
        live(init_test_session(build_conn(), player_token: "r35-bag"), ~p"/g/#{id}")

      for _ <- 1..3, do: view |> element("button[data-slot=draw]") |> render_click()
      view |> element("button", "Stop") |> render_click()

      assert has_element?(view, "#pot-0-lg [data-role=pot-chip]")
      refute has_element?(view, "#pot-0-lg[data-bagged]")

      render_hook(view, "reveal_close", %{})
      assert has_element?(view, "#pot-0-lg[data-bagged]")
      refute has_element?(view, "#pot-0-lg [data-role=pot-chip]")
      assert has_element?(view, "#decision-shop")
    end

    test "the hook flies the chips to the bag and the shop waits for them" do
      js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
      assert js =~ "toBag(gone, true)"
      assert js =~ "bagUntil - performance.now()"
    end
  end

  describe "test tubes" do
    test "the ruby and the VP are icons, no VP text; the rack is shorter" do
      html =
        render_component(&QuacksWeb.PotComponents.test_tubes/1, id: "t", tube: 0)
        |> LazyHTML.from_fragment()

      assert html |> LazyHTML.query("[data-role=glass-ruby][data-icon=ruby]") |> Enum.count() > 0
      assert html |> LazyHTML.query("[data-role=glass-vp][data-icon=vp]") |> Enum.count() > 0
      texts = html |> LazyHTML.query("text") |> Enum.map(&String.trim(LazyHTML.text(&1)))
      refute "VP" in texts

      assert LazyHTML.attribute(LazyHTML.query(html, "svg[data-role=test-tubes]"), "viewBox") == [
               "0 -18 364 72"
             ]
    end
  end

  describe "the patient badge" do
    test "phones show the icon only; the name is in the tooltip" do
      game =
        Game.new(seed: {1, 2, 3}, players: 1) |> Quacks.GameHelpers.put(0, patient: :carrot_nose)

      html =
        render_component(&QuacksWeb.AlchemistsComponents.flask_strip/1, game: game, seat: 0)
        |> LazyHTML.from_fragment()

      badge = LazyHTML.query(html, "[data-role=patient-badge]")
      assert LazyHTML.attribute(badge, "title") == ["Carrot nose"]
      assert LazyHTML.attribute(badge, "aria-label") == ["Patient: Carrot nose"]
      assert badge |> LazyHTML.query("[data-icon=carrot_nose]") |> Enum.count() == 1
      [class] = badge |> LazyHTML.query("[data-role=patient-name]") |> LazyHTML.attribute("class")
      assert "hidden" in String.split(class) and "sm:inline" in String.split(class)
    end
  end

  defp solo_2 do
    {:ok, id} = GameServer.start(1, {10, 11, 12}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("r37-#{System.unique_integer()}"), ~p"/g/#{id}")
    {id, view}
  end

  defp blue(id, pending),
    do: replace_game(id, &H.put(&1, phase: :blue_choice, pending: pending))

  describe "the crow skull's choice" do
    # Round 40 moved the hint to the info row and made the chips one size
    # (`crow_skull_choice_test.exs`).
    test "the drawn chips lie on a cloth" do
      {id, view} = solo_2()
      blue(id, [{:orange, 1}, {:white, 3}, {:yellow, 1}, {:blue, 2}])

      row = "footer section[data-role=bar-blue]"
      assert has_element?(view, "#{row} [data-role=blue-tray] [data-role=blue-cloth]")
      assert view |> render() |> count("#{row} [data-role=blue-tray] button[data-pool-chip]") == 4
    end

    test "as the row leaves, the cloth and hint fade but the chips fly" do
      css = File.read!("assets/css/app.css")
      assert css =~ ".bar-to-bag [data-role=info-row],"
      assert css =~ ".bar-to-bag [data-role=blue-cloth] {"
      assert css =~ ".blue-cloth {"
    end
  end

  describe "the value badge at every chip size" do
    test "each size with a badge places and sizes it" do
      for {size, class} <- [sm: "size-4", md: "size-[18px]", lg: "size-5"] do
        html = render_component(&ChipComponents.chip/1, chip: {:white, 3}, size: size)

        [badge] =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("[data-role=chip-value]")
          |> Enum.to_list()

        classes = badge |> LazyHTML.attribute("class") |> hd() |> String.split()
        assert class in classes, "#{size}: #{inspect(classes)}"
        assert Enum.any?(classes, &String.contains?(&1, "-bottom-")), "#{size} is not placed"
      end
    end
  end

  describe "the scoring ring on a draw" do
    test "the old marks shrink and fade, the new ones grow and fade in after the landing" do
      js = File.read!("assets/js/app.js")

      # round 39: the flight sets the wait; `updated` moves the marks
      assert js =~ "this.wait = 460"
      refute js =~ "scoringPulse"
      assert js =~ "[{scale: 1, opacity: 1}, {scale: 0.85, opacity: 0}]"
      assert js =~ "[{scale: 0.85, opacity: 0}, {scale: 1, opacity: 1}]"
      assert js =~ "delay: after"
      # the old marks are copied before the patch (`snapshot` in beforeUpdate)
      assert js =~ "this.oldMarks = this.marks()"
    end
  end

  describe "the spoon is not a space" do
    defp pot(game), do: render_component(&PotComponents.pot/1, game: game)

    defp spoon(html),
      do: html |> LazyHTML.from_fragment() |> LazyHTML.query("g[data-space='53']")

    test "no disc on the spoon, but its coins and VP show" do
      game = Game.new(seed: {1, 2, 3}, rules: %{fortune: false})
      html = spoon(pot(game))

      assert LazyHTML.attribute(html, "data-spoon") == ["true"]
      assert html |> LazyHTML.query("circle[r='22']") |> Enum.empty?()
      assert html |> LazyHTML.text() =~ "35"
      assert html |> LazyHTML.query("[data-role=vp-tag]") |> LazyHTML.text() =~ "15"

      other =
        pot(game)
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("g[data-space='52'] circle[r='22']")

      refute Enum.empty?(other)
    end

    test "a chip on the last space (52) rings the spoon as the scoring space" do
      game = Game.new(seed: {1, 2, 3}, rules: %{fortune: false})
      game = H.put(game, drawn: [{{:orange, 1}, 52}], pot_index: 52)
      html = spoon(pot(game))

      assert html |> LazyHTML.query("[data-role=scoring-ring]") |> Enum.count() == 1
      assert html |> LazyHTML.query("[data-role=next-space]") |> Enum.count() == 1
      assert html |> LazyHTML.query("[data-role=pot-chip]") |> Enum.empty?()
    end
  end

  defp duo(rules \\ %{fortune: false}) do
    {:ok, id} = GameServer.start(2, {1, 2, 3}, %{}, rules)
    alice = open(browser("alice-#{id}"), id)
    bob = open(browser("bob-#{id}"), id)
    {:ok, _} = GameServer.begin(id, "alice-#{id}")
    {id, alice, bob}
  end

  describe "the Mandrake chip over the bag" do
    test "the white chip and the undo button show over the bag, with no text" do
      {id, alice, bob} = duo()
      refute has_element?(alice, "[data-role=mandrake-undo]")

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:yellow, 1}])
      end)

      alice |> element("button[data-slot=draw]") |> render_click()

      assert has_element?(alice, "[data-role=bag-button] ~ [data-role=mandrake-undo] #keep-white")
      assert has_element?(alice, "[data-role=mandrake-undo] .mandrake-bob [aria-label='white 1']")
      refute render(alice) =~ "went back in your bag.</span>"
      refute has_element?(alice, ".game-tray [data-role=mandrake-undo]")
      refute has_element?(bob, "[data-role=mandrake-undo]")

      alice |> element("#keep-white") |> render_click()
      refute has_element?(alice, "[data-role=mandrake-undo]")
      {:ok, %{game: game}} = GameServer.get(id)
      assert Game.pot_chips(game, 0) == [{:yellow, 1}, {:white, 1}]
    end

    test "no undo button without the Mandrake answer" do
      {id, alice, _bob} = duo()

      replace_game(id, fn g ->
        H.put(g, 0, drawn: [{{:white, 1}, 1}], pot_index: 1, bag: [{:green, 1}])
      end)

      alice |> element("button[data-slot=draw]") |> render_click()
      refute has_element?(alice, "#keep-white")
    end
  end

  describe "the droplet move marker" do
    test "rubies paid for the droplet mark it for PotMotion's hop" do
      {id, alice, _bob} = duo()
      replace_game(id, &H.put(&1, 0, phase: :rubies, rubies: 4))
      render_click(alice, "seen", %{"kind" => "results", "round" => 1})
      refute has_element?(alice, "#droplet-0-lg[data-hop]")

      alice |> element("#bar-rubies button[data-ruby=droplet]") |> render_click()
      assert has_element?(alice, "#droplet-0-lg[data-hop=rubies][data-index='1']")
    end

    test "the last ruby spend on the droplet still ends the round, with the marker" do
      {id, alice, _bob} = duo()
      replace_game(id, &H.put(&1, 0, phase: :rubies, rubies: 2))
      render_click(alice, "seen", %{"kind" => "results", "round" => 1})

      alice |> element("#bar-rubies button[data-ruby=droplet]") |> render_click()
      {:ok, %{game: game}} = GameServer.get(id)
      assert game.players[0].droplet == 1
      assert {0, :end_round} in game.log
    end

    test "the flask brew sits in a clip group, so the hook can raise it" do
      {id, alice, _bob} = duo()
      replace_game(id, &H.put(&1, 0, flask: true))
      assert has_element?(alice, "[data-role=flask] g[clip-path] > [data-role=flask-brew]")
    end
  end

  # A 3-player game, two seats bots, begun; `vps` per seat.
  defp trio_3(rules, vps) do
    {:ok, id} = GameServer.start(3, {1, 2, 3}, %{}, Map.merge(%{fortune: false}, rules))
    token = "r16-#{System.unique_integer()}"
    {:ok, view, _html} = live(browser(token), ~p"/g/#{id}")
    {:ok, _} = GameServer.add_bot(id, token)
    {:ok, _} = GameServer.add_bot(id, token)
    {:ok, _} = GameServer.begin(id, token)

    replace_game(id, fn g ->
      vps |> Enum.with_index() |> Enum.reduce(g, fn {vp, s}, g -> H.put(g, s, vp: vp) end)
    end)

    view
  end

  test "every seat's dot in its step, the rats between with their VP" do
    # Seat 0 (me) on 3, seat 1 on 12, seat 2 on 8: tails after 10, 7, 4 → 3 rats.
    view = trio_3(%{}, [3, 12, 8])
    assert has_element?(view, "#rat-track[data-steps='4']")
    assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='1'][data-step='0']")
    assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='2'][data-step='1']")
    assert has_element?(view, "#rat-track [data-role=track-dot][data-seat='0'][data-step='3']")

    html = view |> element("#rat-track") |> render()
    rats = html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-role=track-rat]")
    assert Enum.map(rats, &(&1 |> LazyHTML.text() |> String.trim())) == ~w(10 7 4)
    assert html =~ "Player 1 3 VP, 3 rats"
  end

  test "no track with the rats rule off" do
    view = trio_3(%{rats: false}, [3, 12, 8])
    refute has_element?(view, "#rat-track")
  end

  test "no track solo" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    {:ok, view, _html} = live(browser("r16-solo"), ~p"/g/#{id}")
    refute has_element?(view, "#rat-track")
  end

  defp solo_3(seed) do
    {:ok, id} = GameServer.start(1, seed)
    {:ok, view, _html} = live(browser("solo"), ~p"/g/#{id}")
    {id, view}
  end

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.

  describe "no stats strip, rubies by the pot" do
    test "the strip is gone; the ruby total is a badge in the pot's top right corner" do
      {_id, view} = solo_3({1, 2, 3})

      refute has_element?(view, "[data-role=stats]")
      badge = "[data-role=pot-area] [data-role=pot-corner-right] [data-role=ruby-badge]"
      assert has_element?(view, "#{badge} dt svg[data-icon=ruby]")
      assert has_element?(view, "#{badge} dt .sr-only", "Rubies")
      assert has_element?(view, "#{badge} dd#stat-rubies.font-hand.text-num.tabular-nums")
    end
  end

  # Play seat 0 of a solo game to the shop, with 30 coins to spend.

  test "an exploded pot's brew is spoiled" do
    game = Game.new(seed: {1, 2, 3})
    calm = render_component(&PotComponents.pot/1, game: game, seat: 0)
    assert count(calm, "[data-role=brew]:not([data-spoiled])") == 1

    game = GameHelpers.put(game, 0, exploded?: true)
    html = render_component(&PotComponents.pot/1, game: game, seat: 0)
    assert count(html, "[data-role=brew][data-spoiled]") == 1
    assert html |> query("[data-role=groove]") |> LazyHTML.attribute("stroke-opacity") == ["0.7"]
  end

  # A player detail sheet renders its body once its chip in the players row is tapped.

  # Seed 10,11,12 draws white 2, 3, 1: stop there for a shop with 7 coins.

  # The rest of `to_shop_2/1` after one draw, then "Done" (round over).

  test "every space with VP shows its VP tag, at every screen width" do
    html = render_component(&PotComponents.pot/1, game: Game.new(seed: {1, 2, 3}))
    with_vp = Enum.count(0..PotTrack.last(), &(PotTrack.at(&1).vp > 0))

    assert count(html, "[data-role=vp-tag]") == with_vp
    refute html =~ "hidden sm:inline"
  end

  # A 2-player game without fortune cards, started by alice.

  test "the overflow bowl shows under the pot in a base game once it has chips" do
    {:ok, id} = GameServer.start(1, {1, 2, 3}, %{}, %{fortune: false})
    view = open(browser("bowl"), id)
    refute has_element?(view, "[data-role=bowl]")

    replace_game(id, &H.put(&1, 0, bowl: [{:white, 1}]))
    assert has_element?(view, "[data-role=bowl] [data-role=bowl-chip]")
  end
end
