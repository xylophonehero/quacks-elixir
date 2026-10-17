defmodule Codex.Bot.SearchTest do
  @moduledoc "The stage-2 Codex bot: the whole-turn search and the sampled game."
  use ExUnit.Case, async: true

  import Codex.TestHelpers, only: [assert_conserved: 1]

  alias Codex.AI.Determinize
  alias Codex.Bot.{Plan, Search}
  alias Codex.{Game, Rules, Zones}
  alias Table.Kit.Rng

  defp bot_game(seed, preset \\ "first"),
    do: elem(Game.new(%{bot: true, preset: preset}, seed), 1)

  defp fast, do: Search.new(n: 6, budget_ms: nil)

  defp play_out(game, max, bots) do
    Enum.reduce_while(1..max, {game, bots}, fn _, {game, bots} ->
      case Game.status(game) do
        {:over, _} ->
          {:halt, {game, bots}}

        {:playing, [s]} ->
          {action, bot} = Search.choose(Game.bot_view(game, s), bots[s])
          assert {:ok, game} = Game.apply(game, s, action), "#{inspect(action)} was refused"
          {:cont, {%{game | history: []}, Map.put(bots, s, bot)}}
      end
    end)
    |> elem(0)
  end

  test "search against search: legal actions, card conservation, the games end" do
    for seed <- 1..2 do
      game = play_out(bot_game({seed, 9, 9}), 3000, %{0 => fast(), 1 => fast()})
      assert_conserved(game)
      assert game.phase == :over
    end
  end

  test "Blue vs Black: search against search, legal actions, the game ends" do
    game = play_out(bot_game({3, 9, 9}, "blue_black"), 4000, %{0 => fast(), 1 => fast()})
    assert_conserved(game)
    assert game.phase == :over
  end

  test "with no clock the same view and state give the same action" do
    game = bot_game({4, 5, 6})
    view = Game.bot_view(game, 0)
    assert elem(Search.choose(view, fast()), 0) == elem(Search.choose(view, fast()), 0)
  end

  test "it plays its plan one action per call, then searches again on a surprise" do
    game = bot_game({1, 2, 3})
    {action, bot} = Search.choose(Game.bot_view(game, 0), fast())
    assert bot.queue != []
    # The plan ends the turn: no new search after its last action.
    assert {:end_turn, _} = List.last(bot.queue)
    {:ok, game} = Game.apply(game, 0, action)
    [{next, _fp} | _] = bot.queue
    assert {^next, _} = Search.choose(Game.bot_view(game, 0), bot)

    # Not the state it expected (2 more gold): it searches again, from this state.
    rich = put_in(game.sides[0].gold, game.sides[0].gold + 2)
    {again, _} = Search.choose(Game.bot_view(rich, 0), bot)
    assert again in Rules.legal(rich)
  end

  test "the tech step is the stage-1 bot's" do
    game = bot_game({1, 2, 3})
    {:ok, game} = Game.apply(game, 0, :end_turn)
    view = Game.bot_view(game, 0)
    assert elem(Search.choose(view, fast()), 0) == elem(Plan.choose(view, nil), 0)
  end

  test "River sidelines the squad leader, then a unit attacks the base for the win" do
    opts = %{preset: "custom", p1_starter: "Neutral", p1_spec: "Finesse"}

    {:ok, game} =
      Game.new(
        Map.merge(opts, %{p2_starter: "Neutral", p2_spec: "Bashing", bot: true}),
        {1, 2, 3}
      )

    [river] = game.sides[0].zones.command
    {game, [brother]} = Game.add_cards(game, 0, ["older-brother"])
    {game, [foot]} = Game.add_cards(game, 1, ["tenderfoot"])

    game =
      game
      |> Zones.move(river, {0, :in_play})
      |> Zones.update_card(river, &%{&1 | level: 3})
      |> Zones.move(brother, {0, :in_play})
      |> Zones.move(foot, {1, :patrol}, :squad_leader)

    game = put_in(game.sides[1].base_hp, 2)
    view = Game.bot_view(game, 0)
    sideline = Enum.find(view.legal, &match?({:ability, ^river, :sideline, [^foot]}, &1))
    assert sideline

    # The stage-1 bot does not see it.
    refute elem(Plan.choose(view, nil), 0) == sideline

    {action, bot} = Search.choose(view, Search.new(budget_ms: nil))
    assert action == sideline
    assert Enum.any?(bot.queue, &match?({{:attack, ^brother, {:building, 1, :base}}, _}, &1))
  end

  test "the table bot (level :search) answers with a legal action within the tick" do
    game = bot_game({1, 2, 3})
    {:ok, game} = Game.apply(game, 0, :end_turn)
    {:ok, game} = Game.apply(game, 0, elem(Plan.choose(Game.bot_view(game, 0), nil), 0))
    view = Codex.Table.view(game, 1)
    bot = Codex.Table.bot_new(:search, {1, 2, 3})
    {us, {action, _}} = :timer.tc(fn -> Codex.Table.bot_choose(:search, view, bot) end)
    assert action in Rules.legal(game)
    assert us < 650_000
  end

  describe "Determinize.sample/3" do
    setup do
      {game, _} =
        Enum.reduce(1..70, {bot_game({6, 6, 6}), nil}, fn _, {g, _} ->
          {a, _} = Plan.choose(Game.bot_view(g, g.active), nil)
          {:ok, g} = Game.apply(g, g.active, a)
          {%{g | history: []}, nil}
        end)

      %{game: game}
    end

    test "the zone sizes are the real ones; the bot's own cards stay", %{game: game} do
      me = game.active
      view = Game.bot_view(game, me)
      {g, _} = Determinize.sample(view, me, Rng.seed({1, 2, 3}))

      for s <- [0, 1], zone <- [:hand, :deck, :discard, :workers, :codex] do
        assert length(g.sides[s].zones[zone]) == length(game.sides[s].zones[zone]),
               "side #{s} #{zone}"
      end

      for zone <- [:hand, :discard, :workers, :codex, :in_play] do
        assert g.sides[me].zones[zone] == game.sides[me].zones[zone]
      end

      assert_conserved(g)
    end

    test "the hidden cards come from the real card pool", %{game: game} do
      me = game.active
      opp = 1 - me
      {g, _} = Determinize.sample(Game.bot_view(game, me), me, Rng.seed({7, 7, 7}))

      slugs = fn g, s, zones ->
        Enum.sort(for z <- zones, id <- g.sides[s].zones[z], do: g.cards[id].card)
      end

      hidden = [:hand, :deck, :discard, :workers, :codex]
      assert slugs.(g, opp, hidden) == slugs.(game, opp, hidden)
      assert slugs.(g, me, [:deck]) == slugs.(game, me, [:deck])
    end

    test "the same rng gives the same game", %{game: game} do
      view = Game.bot_view(game, game.active)
      rng = Rng.seed({3, 3, 3})

      assert Determinize.sample(view, game.active, rng) ==
               Determinize.sample(view, game.active, rng)
    end
  end
end
