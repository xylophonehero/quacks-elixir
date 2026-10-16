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
  alias Quacks.Game.State
  alias Quacks.Rules.Chips
  alias Quacks.Scenarios.Script
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
      component("pot", "Pot board", 520, "PotComponents.pot/1", pot_variants()),
      component(
        "tiles",
        "Player tiles",
        150,
        "TileComponents.players_ledger/1 + player_chip/1 (the players row)",
        tile_variants()
      ),
      component(
        "bar",
        "Bottom context bar",
        520,
        "the bar: Draw/Stop, BarComponents.bar_choice/1, TipComponents.tip_card/1",
        bar_variants()
      ),
      component(
        "track",
        "Score / rat track",
        110,
        "TrackComponents.rat_track/1",
        track_variants()
      ),
      component(
        "chip",
        "Chip",
        1450,
        "ChipComponents.chip/1: every colour x size x value",
        chip_variants()
      ),
      component(
        "motion",
        "Chip motion",
        640,
        "app.js PotMotion + chip_morph.js: Play runs the change on the large pot",
        []
      ),
      component(
        "sounds",
        "Sounds",
        900,
        "QuacksWeb.Sounds + assets/js/sound.js: one button per sound, at its game gain",
        [{"all", "Every sound", fn -> %{view: :sounds} end}]
      ),
      # The card table (Hearts first): stories with args only (`Stories.arg_stories/1`).
      component(
        "hearts",
        "Hearts",
        780,
        "TableWeb.Components (Cards, HeartsTable, Theme) + assets/css/table.css + assets/js/table.js",
        []
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
    # Green II stops at the seats' chip choices: the steps so far (`TileReveal.live/2`).
    slides = TileReveal.live(g, Reveal.result_slides(g))
    stage(g, slides, kind, names)
  end

  defp stage(g, slides, kind, names) do
    i = Enum.find_index(slides, &step?(&1, kind)) || raise "no #{kind} step"
    slide = Enum.at(slides, i)
    choosing = if slide.kind == :book, do: TileReveal.choosing(g, slide.book), else: []

    %{
      view: :stage,
      game: g,
      names: names,
      seat: 0,
      slide: slide,
      rows: TileReveal.stage_rows(g, slide, choosing),
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
  defp take_a_chance(n \\ 5) do
    names = names(n, nil)
    g = brewed_round(n, fortune: true)
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
      {"flask-empty", "Flask used, white chip back", &flask_pot/0},
      {"bowl", "The overflow bowl (The Herb Witches)", &bowl_pot/0}
    ]
  end

  defp pot(g, seat \\ 0, rings \\ nil) do
    %{view: :pot, game: g, seat: seat, rings: rings, flask: flask(g, seat)}
  end

  # By hand: a chip on the last space and then four more draws need a long brew.
  defp bowl_pot do
    g = draws(new(1, expansions: [:herb_witches]), 0, mid_brew())
    pot(put(g, 0, bowl: [{:red, 1}, {:green, 2}, {:white, 2}, {:orange, 1}, {:blue, 2}]))
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

  # The rows' news as the game page gives it (`reveal`: a results step on the rows).
  defp tiles(g, opts \\ []) do
    peek = opts[:peek] && min(1, length(g.seats) - 1)

    %{
      view: :tiles,
      game: g,
      names: names(length(g.seats), opts[:names]),
      seat: 0,
      bots: opts[:bots] || [],
      news: Map.new(g.seats, &{&1, TileReveal.news(g, &1, opts[:reveal])}),
      rolls: Map.new(g.seats, &{&1, TileReveal.rolls(g, &1)}),
      peek: peek
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
      {"explosion-silver-witch", "Exploded with the silver witch (Herb Witches)",
       fn ->
         bar(draws(new(1, expansions: [:herb_witches], witches: %{silver: :s4}), 0, boom()))
       end},
      {"explosion-visit-witch", "Exploded with a visiting S4 (AB8 Visit from a witch)",
       fn ->
         g = new(1, expansions: [:herb_witches], witches: %{silver: :s1})
         bar(draws(%{g | fortune_card: :ab8, visitor: :s4}, 0, boom()))
       end},
      {"explosion-silver-witch-s1", "Exploded with the silver witch S1: flask (Herb Witches)",
       fn ->
         bar(draws(new(1, expansions: [:herb_witches], witches: %{silver: :s1}), 0, boom()))
       end},
      {"chip-choice", "Chip choice: green book II", &chip_choice/0},
      {"rubies-gold-witch", "Rubies with the gold witch (Herb Witches)", &rubies_g4/0},
      {"tip-brew", "Hint: first brew", fn -> tip(draws(new(1), 0, mid_brew()), "brew") end},
      {"tip-risk", "Hint: white 3 or more",
       fn -> tip(draws(new(1), 0, [{:white, 3}, {:orange, 1}]), "risk") end},
      {"tip-choice", "Hint: first choice (Mandrake)", fn -> tip(mandrake_game(), "choice") end}
    ]
  end

  # `choice`: the `BarComponents.bar_choice/1` the page shows for the seat's phase.
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

  # Blue I draws as many chips as its value (1, 2 or 4); the engine never offers 3
  # or 5, so for those the offer gives a chip back to the bag, or takes one more
  # from it, by hand.
  defp crow(n), do: bar(crow_game(new(1), n))

  defp crow_game(g, n) do
    value = Enum.find([1, 2, 4], 4, &(&1 >= n))
    g = draws(g, 0, [{:white, 1}, {:blue, value}])
    %{pending: pending, bag: bag} = g.players[0]

    cond do
      length(pending) > n ->
        {keep, back} = Enum.split(pending, n)
        put(g, 0, pending: keep, bag: back ++ bag)

      length(pending) < n ->
        {more, rest} = Enum.split(bag, n - length(pending))
        put(g, 0, pending: pending ++ more, bag: rest)

      true ->
        g
    end
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

  # -- 7. stories with args (`QuacksWeb.Gallery.Stories`) ------------------------------
  #
  # Each takes the story's args (a map, string keys) and gives the frame's assigns.

  @doc "Results step `kind` (`:die`, a book colour, `:space`). Args: players, long_names, exploded, vp_digits."
  @spec results_story(atom, map) :: map
  def results_story(kind, a), do: results(a["players"], kind, round_opts(a))

  @doc "The recap at round 2's start, step `kind` (`:shop`, `:standings`). Args as `results_story/2`."
  @spec recap_story(atom, map) :: map
  def recap_story(kind, a), do: recap(a["players"], kind, round_opts(a))

  @doc "Take a Chance for `players` players."
  @spec chance_story(map) :: map
  def chance_story(%{"players" => n}), do: take_a_chance(n)

  @doc "The pot mid-brew with the first `chips` chips of a brew drawn."
  @spec pot_story(map) :: map
  def pot_story(%{"chips" => k}), do: pot(draws(new(1), 0, Enum.take(mid_brew(), k)))

  @doc """
  The players row (the ledger, `TileComponents.players_ledger/1`). Args: players,
  state (`brewing`, `stopped`, `exploded`, `done`: every brew ended, `shop`: one
  seat bought a chip, `results`: the scoring space step on the rows), alchemists,
  witches, rats, long_names, vp_digits, bots (every seat but yours), peek (the
  sheet of seat 2 under the rows, as a tap opens it).
  """
  @spec tiles_story(map) :: map
  def tiles_story(%{"players" => n} = a) do
    {g, reveal} = tiles_state(n, a["state"], tile_opts(n, a))
    g = g |> vp_digits(a["vp_digits"]) |> tile_pieces(a)
    bots = if a["bots"], do: g.seats -- [0], else: []
    tiles(g, names: long(a), bots: bots, reveal: reveal, peek: a["peek"])
  end

  defp tile_opts(n, a) do
    expansions =
      if(a["alchemists"], do: [:alchemists], else: []) ++
        if a["witches"], do: [:herb_witches], else: []

    [rules: %{rats: a["rats"] == true}, expansions: expansions] ++
      if a["alchemists"], do: [patients: Map.new(0..(n - 1), &{&1, :random})], else: []
  end

  defp tiles_state(n, state, opts) when state in ~w(brewing stopped exploded) do
    g = Enum.reduce(0..(n - 1), new(n, opts), &draws(&2, &1, race_brew(&1)))

    g =
      case state do
        "brewing" -> g
        "stopped" -> apply!(g, min(1, n - 1), :stop)
        "exploded" -> tiles_boom(g, n)
      end

    {g, nil}
  end

  defp tiles_state(n, "done", opts) do
    plans = [mid_brew(), boom(), [{:orange, 1}], Enum.take(mid_brew(), 4)]
    {finish_round(new(n, opts), for(s <- 0..(n - 1), do: Enum.at(plans, rem(s, 4)))), nil}
  end

  defp tiles_state(n, state, opts) do
    plans = for s <- 0..(n - 1), do: if(s == 1, do: boom(), else: plan(s))
    g = n |> new(opts) |> finish_round(plans) |> settle_all()

    case state do
      "shop" ->
        seat = min(2, n - 1)
        {buy(g, seat, [{:orange, 1}]) || apply!(g, seat, {:buy, []}), nil}

      "results" ->
        slides = TileReveal.live(g, Reveal.result_slides(g))

        case Enum.find_index(slides, &(&1.kind == :space)) do
          nil -> {g, nil}
          i -> {g, %{slides: slides, index: i + 1, tiles: true}}
        end
    end
  end

  # Seat s draws 3..7 chips of a mix with white 7 at most (no explosion), from its
  # own place in the mix, so the pots differ in length and colour.
  @race_mix [
    {:orange, 1},
    {:white, 1},
    {:green, 1},
    {:white, 2},
    {:red, 1},
    {:white, 1},
    {:purple, 1},
    {:orange, 1},
    {:green, 2},
    {:white, 3},
    {:black, 1},
    {:orange, 1}
  ]

  defp race_brew(s) do
    {a, b} = Enum.split(@race_mix, rem(5 * s, length(@race_mix)))
    Enum.take(b ++ a, 3 + rem(2 * s, 5))
  end

  defp tiles_boom(g, n) do
    g = draws(g, min(1, n - 1), boom())
    if n > 2, do: apply!(g, 2, :stop), else: g
  end

  # Ends every open choice of the round (also the essence phase of The Alchemists),
  # so the game reaches the shop.
  defp settle_all(g) do
    Enum.reduce_while(1..200, g, fn _, g ->
      case g.phase not in [:shopping, :over] && Enum.find_value(g.seats, &auto_action(g, &1)) do
        {seat, action} -> {:cont, apply!(g, seat, action)}
        _none -> {:halt, g}
      end
    end)
  end

  defp auto_action(g, seat) do
    actions = Game.legal_actions(g, seat)

    action =
      Enum.find([:stop, {:explosion_choice, :vp}, :return_all, :keep], &(&1 in actions)) ||
        Enum.find(actions, &match?({:essence, :pass}, &1)) ||
        Enum.find(actions, &match?({:essence, {:space, _}}, &1)) ||
        if(:draw in actions and g.phase == :essence, do: :draw)

    action && {seat, action}
  end

  # By hand: essence comes from an essence phase, rat tails from a VP gap, a spent
  # penny from a witch; round 1 has none of them yet.
  defp tile_pieces(g, a) do
    Enum.reduce(g.seats, g, fn s, g ->
      g = if a["alchemists"], do: put(g, s, essence: rem(3 * s + 2, 9)), else: g
      g = if a["rats"] and rem(s, 2) == 1, do: put(g, s, rat_stone: s + 1), else: g

      if a["witches"] and s == 1,
        do: put(g, s, pennies: %{g.players[s].pennies | copper: false}),
        else: g
    end)
  end

  @doc "The crow skull's offer of `chips` chips (1..5) in the bar."
  @spec crow_story(map) :: map
  def crow_story(%{"chips" => n}), do: crow(n)

  @doc """
  Round 45, the chip motion story: the large pot before and after one change
  (`motion`: draw, to-bag, flask, swap, return). The frame's Play button
  patches the pot from `before` to `after`, so `PotMotion` plays as in the game.
  """
  @spec motion_story(map) :: map
  def motion_story(%{"motion" => kind}) do
    {before, aft, bagged} = motion(kind)
    %{view: :motion, before: before, after: aft, bagged: bagged, seat: 0, kind: kind}
  end

  defp motion_pot, do: draws(new(1), 0, [{:white, 1}, {:orange, 1}, {:green, 1}, {:white, 2}])

  defp motion("draw"), do: {motion_pot(), draw(motion_pot(), 0, {:red, 1}), false}
  defp motion("to-bag"), do: {motion_pot(), motion_pot(), true}

  defp motion("flask") do
    g = draws(new(1), 0, [{:orange, 1}, {:green, 1}, {:white, 3}])
    {g, apply!(g, 0, :use_flask), false}
  end

  # A pot chip becomes a bigger one on its space. Round 46: one story for Chicken
  # eyes, AB1, the copper witch and the purple book IV (they look the same). This is
  # the purple book IV, by hand with the engine's log entry: the green 1 leaves the
  # pot, a green 2 goes to the bag, and the pot holds the green 2 on the green 1's
  # space until the round's chips go back (`PotComponents.held/2`).
  defp motion("swap") do
    g = motion_pot()
    p = g.players[0]

    aft =
      g
      |> put(0, drawn: List.keydelete(p.drawn, {:green, 1}, 0), bag: [{:green, 2} | p.bag])
      |> State.effect(0, {:purple, 4}, {:upgrade, {:green, 1}, {:green, 2}})

    {g, aft, false}
  end

  # Several chips leave at once (the white chips go back, as a witch's S3): by hand.
  defp motion("return") do
    g = motion_pot()
    p = g.players[0]
    whites = for {{:white, _}, _} = d <- p.drawn, do: d
    {g, put(g, 0, drawn: p.drawn -- whites, bag: Enum.map(whites, &elem(&1, 0)) ++ p.bag), false}
  end

  @doc "The score track: players and a VP spread (`early`, `tied`, `above-50`, `big-gaps`)."
  @spec track_story(map) :: map
  def track_story(%{"players" => n, "spread" => spread}),
    do: track(for(s <- 0..(n - 1), do: spread_vp(spread, s)))

  defp spread_vp("early", s), do: rem(s * 3, 5)
  defp spread_vp("tied", s), do: Enum.at([6, 6, 3], rem(s, 3))
  defp spread_vp("above-50", s), do: 52 + rem(s * 9, 23)
  defp spread_vp("big-gaps", s), do: Enum.at([2, 30, 31, 70, 45, 12, 58, 20], s)

  # VP by hand: every seat's VP gets `digits` digits (1: as played).
  defp vp_digits(g, 2), do: Enum.reduce(g.seats, g, &put(&2, &1, vp: 20 + 7 * &1))
  defp vp_digits(g, 3), do: Enum.reduce(g.seats, g, &put(&2, &1, vp: 100 + 7 * &1))
  defp vp_digits(g, _digits), do: g

  defp round_opts(a) do
    vp = %{1 => nil, 2 => 20, 3 => 100}[a["vp_digits"] || 1]

    [names: long(a), vp: vp, many: a["many_chips"] == true, green_set: a["green_set"] || 1] ++
      if(a["exploded"], do: [exploded: a["exploded"]], else: [])
  end

  defp long(%{"long_names" => true}), do: :long
  defp long(_a), do: nil

  # -- 8. full screens (`QuacksWeb.GameLive.preview/3`) ---------------------------------
  #
  # The whole game page for a phase. The assigns are the game and the options of
  # `GameLive.preview/3`; `QuacksWeb.GalleryFrameLive` draws them with `GameLive.render/1`.

  @doc "Brewing: every seat mid-brew. Args: players, long_names."
  @spec brewing_screen(map) :: map
  def brewing_screen(%{"players" => n} = a), do: screen(brewing(n), a)

  @doc "A choice for you (seat 0) while the others brew: `crow`, `mandrake`, `mandrake_ruby`, `explosion`, `chip_choice`, `toadstool`."
  @spec choice_screen(map) :: map
  def choice_screen(%{"players" => n, "choice" => choice} = a),
    do: screen(choice_game(n, choice), a)

  defp choice_game(n, "crow"), do: n |> others_brew() |> crow_game(4)

  defp choice_game(n, "mandrake"),
    do: n |> others_brew() |> draws(0, [{:orange, 1}, {:white, 2}, {:yellow, 1}])

  # Bug #89: yellow Set 6 with a ruby in hand: pay it, the yellow moves 3 more.
  defp choice_game(n, "mandrake_ruby") do
    g = others_brew(n)

    %{g | sets: Map.put(g.sets, :yellow, 6)}
    |> put(0, rubies: 1)
    |> draws(0, [{:orange, 1}, {:white, 2}, {:yellow, 2}])
  end

  defp choice_game(n, "explosion"), do: n |> others_brew() |> draws(0, boom())

  # Bug #74: red Set 6. You drew two red chips, so two chips wait beside the pot
  # to be placed while you brew (the "Toadstool" row and the tappable pill).
  defp choice_game(n, "toadstool") do
    g = new(n, sets: %{red: 6})

    (g.seats -- [0])
    |> Enum.reduce(g, fn s, g -> draws(g, s, Enum.take(mid_brew(), 2 + rem(s, 3))) end)
    |> draws(0, [{:orange, 1}, {:red, 1}, {:green, 1}, {:red, 1}])
  end

  defp choice_game(n, "chip_choice") do
    g = new(n, sets: %{green: 2})

    finish_round(
      g,
      for(s <- g.seats, do: if(s == 0, do: [{:orange, 1}, {:green, 1}], else: [{:orange, 1}]))
    )
  end

  # Every seat but you drew a few chips.
  defp others_brew(n) do
    Enum.reduce(new(n).seats -- [0], new(n), fn s, g ->
      draws(g, s, Enum.take(mid_brew(), 2 + rem(s, 3)))
    end)
  end

  @doc "An evaluation step on the tiles (`die`, a book colour, `space`). Args: players, long_names, exploded."
  @spec evaluation_screen(map) :: map
  def evaluation_screen(%{"players" => n, "step" => "rubies"} = a) do
    # Round 47 (audit #3): this round's card "Give and take" (AP3) gave you 2
    # rubies (by hand: its log line and the rubies, as `Fortune` does), so the
    # rubies step opens (a droplet move costs 2). The counters must show them.
    g =
      n
      |> brewed_round(round_opts(a))
      |> State.update_player(0, &%{&1 | rubies: &1.rubies + 2})
      |> State.record(0, {:fortune, :ap3, :rubies})

    screen(g, a, seen: %{}, step: :rubies)
  end

  def evaluation_screen(%{"players" => n, "step" => step} = a) do
    g = brewed_round(n, round_opts(a))
    screen(g, a, seen: %{}, step: String.to_existing_atom(step))
  end

  @doc "Round 2's start: the last round's recap, step `shop` or `standings` (round scored)."
  @spec scored_screen(map) :: map
  def scored_screen(%{"players" => n, "step" => step} = a) do
    g = n |> brewed_round(round_opts(a)) |> shop_all()
    screen(g, a, seen: %{}, step: String.to_existing_atom(step))
  end

  @doc "The shop after round 1 (the results seen). Args: players, long_names."
  @spec shop_screen(map) :: map
  def shop_screen(%{"players" => n} = a), do: screen(brewed_round(n, round_opts(a)), a)

  @doc """
  AB8 Visit from a witch: witch `witch` visits (the own witches are S2, C1 and G2;
  the card and the visitor are set by hand) at her moment: silver S3 while brewing,
  S1 and S4 after an explosion, copper and G4 in the shop, G1 in the gold choice.
  """
  @spec visit_screen(map) :: map
  def visit_screen(%{"players" => n, "witch" => witch} = a) do
    id = String.to_existing_atom(witch)
    g = new(n, expansions: [:herb_witches], witches: %{silver: :s2, copper: :c1, gold: :g2})
    screen(visit_moment(%{g | fortune_card: :ab8, visitor: id}, id), a)
  end

  defp visit_moment(g, id) when id in [:s1, :s4], do: draws(g, 0, boom())
  defp visit_moment(g, :s3), do: draws(g, 0, [{:orange, 1}, {:white, 2}, {:white, 1}])

  defp visit_moment(g, _id) do
    mine = [{:orange, 1}, {:green, 1}, {:blue, 1}, {:white, 1}]
    g = finish_round(g, for(s <- g.seats, do: if(s == 0, do: mine, else: [{:orange, 1}])))
    # Round 45: the own copper witch C1 has her step first; pass it to reach the shop.
    if :skip_upgrade in Game.legal_actions(g, 0), do: apply!(g, 0, :skip_upgrade), else: g
  end

  @doc """
  Round 45: the copper witch C1's own step before the shop (seat 0; the other seats
  shop). `state`: `one` (only single chips go up: the last 2 are white and orange),
  `last_two` (the last 2 may go up together), `picked` (a tap on the newest chip
  asks: this chip or the last 2), `upgraded` (the moment the pot shows the bigger
  chips) or `visit` (AB8: C1 visits, the own copper witch is C3; Skip has no penny).
  """
  @spec upgrade_screen(map) :: map
  def upgrade_screen(%{"players" => n, "state" => state} = a) do
    copper = if state == "visit", do: :c3, else: :c1
    g = new(n, expansions: [:herb_witches], witches: %{silver: :s2, copper: copper, gold: :g2})
    g = if state == "visit", do: %{g | fortune_card: :ab8, visitor: :c1}, else: g

    mine =
      if state == "one",
        do: [{:green, 1}, {:red, 1}, {:orange, 1}, {:white, 1}],
        else: [{:orange, 1}, {:white, 1}, {:green, 1}, {:red, 1}]

    g = finish_round(g, for(s <- g.seats, do: if(s == 0, do: mine, else: [{:orange, 1}])))

    last_two =
      Enum.find(Game.legal_actions(g, 0), &match?({:witch, _, {:upgrade, [_, _]}}, &1))

    opts =
      case state do
        "picked" -> [pot_pick: {:red, 1}]
        "upgraded" -> [upgrade: last_two]
        _ -> []
      end

    screen(g, a, opts)
  end

  @doc "The waiting panel before the game begins (`GameLive.preview/3` with no game)."
  @spec waiting_screen(map) :: map
  def waiting_screen(%{"players" => n, "seated" => k} = a) do
    %{
      view: :screen,
      game: nil,
      preview: [
        players: n,
        seated: k,
        host: not a["guest"],
        bot: a["bot"],
        names: names(n, long(a))
      ]
    }
  end

  @doc "The game over: bots play every seat through round 9 (`Quacks.Scenarios.Script`)."
  @spec over_screen(map) :: map
  def over_screen(%{"players" => n} = a) do
    s = Script.new({20, 26, 10}, n, rules: %{fortune: false})
    screen(Script.game(Script.play(s, &Game.over?/1)), a)
  end

  defp screen(g, a, opts \\ []) do
    %{view: :screen, game: g, preview: [names: names(length(g.seats), long(a))] ++ opts}
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
  @settle [:stop, {:explosion_choice, :vp}, :return_all, :keep]

  defp finish_round(g, plans) do
    g = plans |> Enum.with_index() |> Enum.reduce(g, fn {chips, s}, g -> draws(g, s, chips) end)
    settle(g, @settle)
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

  # A seeded round 1 of `n` players to the shop. Seat 1 explodes (from 3 players;
  # `exploded:` sets how many seats explode, from seat 1); the others end at
  # different spaces, with black, green and purple chips so every book step has
  # rows. `vp:` adds that many VP to every seat first (by hand).
  defp brewed_round(n, opts) do
    g =
      new(n,
        rules: %{fortune: opts[:fortune] || false},
        sets: %{green: Keyword.get(opts, :green_set, 1)}
      )

    g =
      if vp = opts[:vp],
        do: Enum.reduce(g.seats, g, &put(&2, &1, vp: vp + 7 * &1)),
        else: g

    exploded = min(Keyword.get(opts, :exploded, if(n > 2, do: 1, else: 0)), n - 1)
    many = opts[:many] || false
    plans = for s <- g.seats, do: brew_plan(s, s in 1..exploded//1, many)
    finish_round(g, plans)
  end

  defp brew_plan(_s, true, _many), do: boom()
  defp brew_plan(s, false, true), do: many(s)
  defp brew_plan(s, false, false), do: plan(s)

  # Round 44: a brew with many black, purple and green chips, so a book step shows
  # stacks (seat by seat 1, 2, 3, 0 black, 1..3 purple; two greens of different
  # values last, for green II).
  defp many(s) do
    List.duplicate({:black, 1}, rem(s + 1, 4)) ++
      [{:white, 1}] ++
      List.duplicate({:purple, 1}, 1 + rem(s + 2, 3)) ++
      [Enum.at([{:green, 1}, {:green, 2}, {:green, 4}], rem(s, 3)), {:green, 2}]
  end

  defp plan(s) do
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
