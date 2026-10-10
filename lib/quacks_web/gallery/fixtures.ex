defmodule QuacksWeb.Gallery.Fixtures do
  @moduledoc """
  The component gallery's variants (dev only, `/dev/gallery`, `QuacksWeb.GalleryLive`).

  `catalog/0` lists each component with its variants. A variant's `build` function
  gives the assigns of its frame (`QuacksWeb.GalleryFrameLive`). Where the engine can
  reach the state, the builder plays a seeded `Quacks.Game` with `Game.apply/3`, so
  the fixtures follow engine changes. The draws are rigged (`draw/3` puts the wanted
  chip where the game's own random number takes it), the rest is the engine.
  Builders set fields by hand (`put/3`) only for what the engine does not reach
  easily, e.g. 3-digit VP or a droplet far up the track; each such place says so.

  To add a variant: add `{id, title, fn -> assigns end}` to the component's list in
  `catalog/0`. To add a component: add an entry here and a `frame/1` clause in
  `QuacksWeb.GalleryFrameLive`.
  """

  alias Quacks.Game
  alias Quacks.Rules.Chips
  alias QuacksWeb.{Reveal, TileReveal, Tips}

  @short ~w(Ada Bram Cleo Dirk Edda Finn Gwen Hugo)
  @long [
    "Bartholomew Quackenbush",
    "Maximiliana von Krötenstein",
    "Cornelius Featherstonehaugh",
    "Wilhelmina Pottersfield-Brown",
    "Archibald Mandrake the Third",
    "Philippa Ravensworth",
    "Theodosius Bubblecauldron",
    "Henrietta Toadstool-Smythe"
  ]

  @typedoc "One variant: its id (in the URL), its title and its assigns builder."
  @type variant :: %{id: String.t(), title: String.t(), build: (-> map)}
  @typedoc "One component: its id (in the URL), title, frame height (px) and variants."
  @type component :: %{
          id: String.t(),
          title: String.t(),
          height: pos_integer,
          note: String.t(),
          variants: [variant]
        }

  @doc "Every component in the gallery, in menu order."
  @spec catalog() :: [component]
  def catalog do
    [
      component(
        "results",
        "Results panel",
        560,
        "TileRevealComponents.results_stage/1 + stage_list/1 over the bar's step line",
        results_variants()
      ),
      component("pot", "Pot board", 520, "GameComponents.pot/1", pot_variants()),
      component(
        "tiles",
        "Player tiles",
        150,
        "GameComponents.player_chip/1 in the players row",
        tile_variants()
      ),
      component(
        "bar",
        "Bottom context bar",
        420,
        "the bar: Draw/Stop, GameLive.bar_choice/1, TipComponents.tip_card/1",
        bar_variants()
      ),
      component(
        "track",
        "Score / rat track",
        110,
        "GameComponents.rat_track/1",
        track_variants()
      ),
      component(
        "chip",
        "Chip",
        1450,
        "GameComponents.chip/1: every colour x size x value",
        chip_variants()
      )
    ]
  end

  @doc "The component with `id`, or nil."
  @spec component(String.t()) :: component | nil
  def component(id), do: Enum.find(catalog(), &(&1.id == id))

  @doc "The assigns of `component`'s variant `variant`: `{:ok, assigns}` or `:error`."
  @spec fixture(String.t(), String.t()) :: {:ok, map} | :error
  def fixture(component, variant) do
    with %{variants: variants} <- component(component),
         %{build: build} <- Enum.find(variants, &(&1.id == variant)) do
      {:ok, build.()}
    else
      _ -> :error
    end
  end

  defp component(id, title, height, note, variants) do
    %{
      id: id,
      title: title,
      height: height,
      note: note,
      variants: for({vid, vtitle, build} <- variants, do: %{id: vid, title: vtitle, build: build})
    }
  end

  # -- 1. results panel ------------------------------------------------------------

  defp results_variants do
    steps =
      for {kind, label} <- [
            die: "die",
            black: "black book",
            green: "green book",
            purple: "purple book",
            space: "scoring space"
          ] do
        {"5p-#{kind}", "5 players: #{label}", fn -> results(5, kind) end}
      end

    steps ++
      [
        {"2p-space", "2 players: scoring space", fn -> results(2, :space) end},
        {"8p-space", "8 players, long names: scoring space (exploded rows)",
         fn -> results(8, :space, names: :long) end},
        {"8p-die", "8 players: die", fn -> results(8, :die, names: :long) end},
        {"recap-shop", "Recap: the shop (5 players)", fn -> recap(5, :shop) end},
        {"recap-standings", "Recap: round scored (5 players, places change)",
         fn -> recap(5, :standings) end},
        {"recap-2p", "Recap: round scored (2 players)", fn -> recap(2, :standings) end},
        {"recap-8p", "Recap: round scored (8 players, long names, 3-digit VP)",
         fn -> recap(8, :standings, names: :long, vp: 100) end},
        {"chance", "Take a Chance (5 players)", &take_a_chance/0},
        {"collapsed", "Collapsed: a choice waits (5 players)", fn -> collapsed() end}
      ]
  end

  # The round's results step `kind` (a book colour or `:die`, `:space`, `:standings`)
  # after a seeded round 1 of `n` players.
  defp results(n, kind, opts \\ []) do
    names = names(n, opts[:names])
    g = brewed_round(n, opts)
    slides = TileReveal.slides(Reveal.result_slides(g))
    stage(g, slides, kind, names)
  end

  defp stage(g, slides, kind, names) do
    i = Enum.find_index(slides, &step?(&1, kind)) || raise "no #{kind} step"
    slide = Enum.at(slides, i)

    %{
      view: :stage,
      game: g,
      names: names,
      seat: 0,
      slide: slide,
      rows: TileReveal.stage_rows(g, slide),
      index: i + 1,
      reveal: %{slides: slides, index: i + 1, tiles: true},
      collapsed: false,
      note: nil
    }
  end

  defp step?(%{kind: :book, book: colour}, colour), do: true
  defp step?(%{kind: kind}, kind), do: true
  defp step?(_slide, _kind), do: false

  # Round 37's recap at the start of round 2: what everyone bought, then the last
  # round's totals with the places that changed.
  defp recap(n, kind, opts \\ []) do
    names = names(n, opts[:names])
    g = n |> brewed_round(opts) |> shop_all()
    stage(g, Reveal.recap_slides(g), kind, names)
  end

  # Take a Chance (P12): round 2's card; everyone rolls the bonus die.
  defp take_a_chance do
    names = names(5, nil)
    g = brewed_round(5, fortune: true)
    g = g |> Map.put(:fortune_deck, [:p12 | g.fortune_deck -- [:p12]]) |> shop_all()

    %{
      view: :card,
      game: g,
      names: names,
      seat: 0,
      card: g.fortune_card,
      reveals: Reveal.card_reveals(g),
      order: Game.turn_order(g)
    }
  end

  defp collapsed do
    fx = results(5, :green)
    %{fx | collapsed: true, note: {"Green book", "choose a chip"}}
  end

  # -- 2. pot board --------------------------------------------------------------

  defp pot_variants do
    [
      {"empty", "Empty (round 1, nothing drawn)", fn -> pot(new(1)) end},
      {"mid-brew", "Mid-brew: the scoring ring", fn -> pot(draws(new(1), 0, mid_brew())) end},
      {"rats", "Rats in the pot (2 players, behind on VP)", &rats_pot/0},
      {"last-space", "A chip on the last space: the spoon scores", &last_space_pot/0},
      {"exploded", "Exploded", fn -> pot(draws(new(1), 0, boom())) end},
      {"rings", "Other players' rings (4 players)", &rings_pot/0},
      {"flask-empty", "Flask used, white chip back", &flask_pot/0}
    ]
  end

  defp pot(g, seat \\ 0, rings \\ nil) do
    %{view: :pot, game: g, seat: seat, rings: rings, flask: flask(g, seat)}
  end

  defp flask(g, seat), do: if(g.players[seat].flask, do: :full, else: :empty)

  defp mid_brew,
    do: [{:white, 1}, {:orange, 1}, {:white, 2}, {:green, 1}, {:white, 1}, {:orange, 1}]

  defp boom, do: [{:white, 3}, {:orange, 1}, {:white, 2}, {:white, 2}, {:white, 1}]

  # Round 2 for seat 0, 15 VP behind (VP set by hand: the engine needs a whole
  # round of scoring for that gap). The rat stone comes from the engine.
  defp rats_pot do
    g = new(2, rules: %{rats: true})
    g = g |> put(1, vp: 15) |> finish_round([[{:orange, 1}], [{:orange, 1}]]) |> shop_all()
    pot(draws(g, 0, [{:white, 1}, {:orange, 1}]))
  end

  # The droplet starts at 49 (by hand: far beyond what a few rounds reach), so the
  # third chip lands on the last space (52) and the spoon (53) is the scoring space.
  defp last_space_pot do
    g = new(1) |> put(0, droplet: 49, pot_index: 49)
    pot(draws(g, 0, [{:orange, 1}, {:white, 1}, {:orange, 1}]))
  end

  defp rings_pot do
    g =
      new(4)
      |> draws(0, [{:white, 1}, {:orange, 1}, {:white, 2}])
      |> draws(1, [{:orange, 1}, {:white, 1}])
      |> draws(2, [{:white, 2}, {:white, 1}, {:orange, 1}, {:white, 1}, {:orange, 1}])
      |> draws(3, [{:white, 3}, {:white, 2}, {:orange, 1}])

    pot(g, 0, Map.new(g.seats, &{&1, Game.scoring_index(g, &1)}))
  end

  defp flask_pot do
    g = draws(new(1), 0, [{:orange, 1}, {:white, 3}, {:white, 2}])
    pot(apply!(g, 0, :use_flask))
  end

  # -- 3. player tiles ------------------------------------------------------------

  defp tile_variants do
    [
      {"1p", "1 player, mid-brew", fn -> tiles(draws(new(1), 0, mid_brew())) end},
      {"2p", "2 players, mid-brew", fn -> tiles(brewing(2)) end},
      {"5p", "5 players, mid-brew", fn -> tiles(brewing(5)) end},
      {"8p", "8 players, mid-brew, long names", fn -> tiles(brewing(8), names: :long) end},
      {"exploded", "4 players: one exploded, one stopped", &tiles_states/0},
      {"crown", "4 players: everyone done, the crown on the leader", &tiles_crown/0},
      {"shop", "5 players: the shop (one ready)", &tiles_shop/0},
      {"bots", "3 players with bots, 3-digit VP", &tiles_bots/0}
    ]
  end

  defp tiles(g, opts \\ []) do
    %{
      view: :tiles,
      game: g,
      names: names(length(g.seats), opts[:names]),
      seat: 0,
      bots: opts[:bots] || []
    }
  end

  # Every seat drew 2..4 chips; nobody stopped.
  defp brewing(n) do
    Enum.reduce(new(n).seats, new(n), fn s, g ->
      draws(g, s, Enum.take(mid_brew(), 2 + rem(s, 3)))
    end)
  end

  defp tiles_states do
    g = brewing(4) |> draws(1, boom()) |> apply!(2, :stop)
    tiles(g)
  end

  defp tiles_crown do
    g = finish_round(new(4), [mid_brew(), boom(), [{:orange, 1}], Enum.take(mid_brew(), 4)])
    tiles(g)
  end

  defp tiles_shop do
    g = brewed_round(5, [])
    tiles(apply!(g, 2, {:buy, []}))
  end

  # VP by hand (3 digits needs most of a game).
  defp tiles_bots do
    g = brewing(3) |> put(0, vp: 104) |> put(1, vp: 99) |> put(2, vp: 117)
    tiles(g, bots: [1, 2])
  end

  # -- 4. bottom context bar ------------------------------------------------------

  defp bar_variants do
    [
      {"draw-stop", "Draw / Stop, mid-brew", fn -> bar(draws(new(1), 0, mid_brew())) end},
      {"draw-stop-risk", "Draw / Stop, white 6: the risk",
       fn -> bar(draws(new(1), 0, [{:white, 3}, {:white, 2}, {:white, 1}])) end},
      {"stopped", "Stopped (2 players): Resume", &bar_stopped/0},
      {"crow-1", "Crow skull: 1 chip", fn -> crow(1) end},
      {"crow-4", "Crow skull: 4 chips", fn -> crow(4) end},
      {"crow-5", "Crow skull: 5 chips (the 5th by hand)", fn -> crow(5) end},
      {"mandrake", "Mandrake: put the white chip back?", &mandrake/0},
      {"explosion", "Exploded: VP or coins", fn -> bar(draws(new(1), 0, boom())) end},
      {"chip-choice", "Chip choice: green book II", &chip_choice/0},
      {"rubies-gold-witch", "Rubies with the gold witch (Herb Witches)", &rubies_g4/0},
      {"tip-brew", "Hint: first brew", fn -> tip(draws(new(1), 0, mid_brew()), "brew") end},
      {"tip-risk", "Hint: white 3 or more",
       fn -> tip(draws(new(1), 0, [{:white, 3}, {:orange, 1}]), "risk") end},
      {"tip-choice", "Hint: first choice (Mandrake)", fn -> tip(mandrake_game(), "choice") end}
    ]
  end

  # `choice`: the `GameLive.bar_choice/1` the page shows for the seat's phase.
  defp bar(g, opts \\ []) do
    me = g.players[0]
    actions = Game.legal_actions(g, 0)

    %{
      view: :bar,
      game: g,
      me: me,
      seat: 0,
      actions: actions,
      choice: Keyword.get(opts, :choice, bar_choice(me.phase)),
      stop_slot: if(me.phase == :stopped, do: :resume, else: :stop),
      tip: nil
    }
  end

  @bar_choices [
    :explosion_choice,
    :blue_choice,
    :yellow_choice,
    :red_choice,
    :chip_choice,
    :essence_offer,
    :essence_bonus,
    :droplet_choice
  ]
  defp bar_choice(phase) when phase in @bar_choices, do: phase
  defp bar_choice(_phase), do: nil

  defp bar_stopped do
    g = new(2) |> draws(0, mid_brew()) |> apply!(0, :stop) |> draws(1, [{:orange, 1}])
    bar(g)
  end

  # Blue I draws as many chips as its value (1, 2 or 4); the engine never offers 5,
  # so the 5th chip moves from the bag to the offer by hand.
  defp crow(n) do
    g = draws(new(1), 0, [{:white, 1}, {:blue, min(n, 4)}])

    g =
      if n > 4 do
        [chip | bag] = g.players[0].bag
        put(g, 0, bag: bag, pending: g.players[0].pending ++ [chip])
      else
        g
      end

    bar(g)
  end

  defp mandrake_game, do: draws(new(1), 0, [{:orange, 1}, {:white, 2}, {:yellow, 1}])
  defp mandrake, do: bar(mandrake_game())

  defp chip_choice do
    g = new(2, sets: %{green: 2})
    g = finish_round(g, [[{:orange, 1}, {:green, 1}], [{:orange, 1}]])
    bar(g)
  end

  # The rubies step: rubies 4 by hand (a round gives 1 or 2).
  defp rubies_g4 do
    g =
      new(1, expansions: [:herb_witches], witches: %{gold: :g4})
      |> finish_round([[{:orange, 1}]])
      |> put(0, rubies: 4)
      |> apply!(0, {:buy, []})

    bar(g, choice: :rubies)
  end

  defp tip(g, key) do
    fx = bar(g)
    %{fx | tip: Tips.tip(key)}
  end

  # -- 5. score / rat track ---------------------------------------------------------

  # VP by hand: these spreads need many rounds of play.
  defp track_variants do
    [
      {"early", "Early game (4 players, 0-4 VP)", fn -> track([0, 2, 4, 1]) end},
      {"tied", "Ties (5 players)", fn -> track([6, 6, 3, 6, 3]) end},
      {"above-50", "Tails above 50 (4 players)", fn -> track([52, 61, 74, 58]) end},
      {"big-gaps", "Big gaps (5 players)", fn -> track([2, 30, 31, 70, 45]) end},
      {"8p", "8 players, spread", fn -> track([3, 11, 19, 24, 28, 40, 41, 55]) end}
    ]
  end

  defp track(vps) do
    g = new(length(vps), rules: %{rats: true})

    g =
      vps |> Enum.with_index() |> Enum.reduce(g, fn {vp, s}, g -> put(g, s, vp: vp) end)

    %{view: :track, game: g, names: names(length(vps), nil), seat: 0}
  end

  # -- 6. chip -------------------------------------------------------------------------

  defp chip_variants do
    [
      {"all", "Every colour x size x value 1/2/4/6",
       fn -> %{view: :chips, colours: Chips.order(), values: [1, 2, 4, 6]} end},
      {"no-value", "No value (book chips, value nil)",
       fn -> %{view: :chips, colours: Chips.order(), values: [nil]} end}
    ]
  end

  # -- engine helpers -------------------------------------------------------------------

  @seed {20, 26, 10}

  defp new(n, opts \\ []) do
    rules = Map.merge(%{fortune: false}, Keyword.get(opts, :rules, %{}))
    Game.new([seed: @seed, players: n, rules: rules] ++ Keyword.drop(opts, [:rules]))
  end

  defp apply!(g, seat, action) do
    case Game.apply(g, seat, action) do
      {:ok, g} -> g
      {:error, reason} -> raise "gallery fixture: #{inspect(action)} for #{seat}: #{reason}"
    end
  end

  @doc """
  Draw `chip` for `seat` with the engine: the chip goes (from elsewhere in the bag,
  or new) to the place the game's random number takes next (`Potions.take_random/3`),
  then `:draw` runs.
  """
  @spec draw(Game.t(), Game.seat(), Chips.chip()) :: Game.t()
  def draw(g, seat, chip) do
    bag = List.delete(g.players[seat].bag, chip)
    {i, _rng} = :rand.uniform_s(length(bag) + 1, g.rng)
    g = put(g, seat, bag: List.insert_at(bag, i - 1, chip))
    apply!(g, seat, :draw)
  end

  # Draw `chips` in order, while the seat may draw.
  defp draws(g, seat, chips) do
    Enum.reduce(chips, g, fn chip, g ->
      if :draw in Game.legal_actions(g, seat), do: draw(g, seat, chip), else: g
    end)
  end

  # Set player fields by hand (see the moduledoc: only where the engine cannot reach).
  defp put(g, seat, fields), do: update_in(g.players[seat], &struct!(&1, fields))

  # Each seat draws its chips, then every seat ends its brew (stop, take the VP of an
  # explosion); the engine scores the round. Stops at a choice (`:chip_choice`) or
  # the shop.
  defp finish_round(g, plans) do
    g = plans |> Enum.with_index() |> Enum.reduce(g, fn {chips, s}, g -> draws(g, s, chips) end)
    settle(g, [:stop, {:explosion_choice, :vp}, :return_all, :keep])
  end

  defp settle(g, picks) do
    Enum.reduce_while(1..100, g, fn _, g ->
      with false <- g.phase in [:shopping, :chip_choice, :over],
           seat when seat != nil <- Enum.find(g.seats, &(pick(g, &1, picks) != nil)) do
        {:cont, apply!(g, seat, pick(g, seat, picks))}
      else
        _ -> {:halt, g}
      end
    end)
  end

  defp pick(g, seat, picks) do
    actions = Game.legal_actions(g, seat)
    Enum.find(picks, &(&1 in actions))
  end

  # A seeded round 1 of `n` players to the shop. Seat 1 explodes (from 3 players);
  # the others end at different spaces, with black, green and purple chips so every
  # book step has rows. `vp:` adds that many VP to every seat first (by hand).
  defp brewed_round(n, opts) do
    g = new(n, rules: %{fortune: opts[:fortune] || false})

    g =
      if vp = opts[:vp],
        do: Enum.reduce(g.seats, g, &put(&2, &1, vp: vp + 7 * &1)),
        else: g

    plans = for s <- g.seats, do: plan(s, n)
    finish_round(g, plans)
  end

  defp plan(1, n) when n > 2, do: boom()

  defp plan(s, _n) do
    base = [
      [{:orange, 1}, {:black, 1}, {:white, 1}, {:green, 1}],
      [{:purple, 1}, {:white, 2}, {:black, 1}, {:green, 1}, {:orange, 1}],
      [{:white, 1}, {:orange, 1}, {:black, 1}, {:white, 2}, {:purple, 1}, {:green, 1}],
      [{:orange, 1}, {:white, 1}],
      [{:black, 1}, {:orange, 1}, {:white, 3}, {:purple, 1}],
      [{:green, 1}, {:white, 1}, {:orange, 1}, {:white, 2}, {:black, 1}, {:white, 1}]
    ]

    Enum.at(base, rem(s, length(base)))
  end

  # Every seat ends the shop (buys the first of `@buys` it can afford), so the next
  # round starts.
  @buys [
    [{:blue, 1}, {:orange, 1}],
    [{:green, 1}, {:orange, 1}],
    [{:blue, 1}],
    [{:green, 1}],
    [{:orange, 1}],
    []
  ]
  defp shop_all(g) do
    Enum.reduce(g.seats, g, fn s, g ->
      g = Enum.find_value(@buys, g, &buy(g, s, &1))
      if :end_round in Game.legal_actions(g, s), do: apply!(g, s, :end_round), else: g
    end)
  end

  defp buy(g, seat, chips) do
    case Game.apply(g, seat, {:buy, chips}) do
      {:ok, g} -> g
      {:error, _} -> nil
    end
  end

  defp names(n, :long), do: Map.new(0..(n - 1), &{&1, Enum.at(@long, &1)})
  defp names(n, _short), do: Map.new(0..(n - 1), &{&1, Enum.at(@short, &1)})
end
