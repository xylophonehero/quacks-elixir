defmodule Codex.Bot.PlanTest do
  @moduledoc "The stage-1 Codex bot: legal actions, whole games, its rules."
  use ExUnit.Case, async: true

  import Codex.TestHelpers, only: [assert_conserved: 1]

  alias Codex.Bot.{Plan, TechPlan}
  alias Codex.{Game, Rules, Table}

  defp bot_game(seed, preset \\ "first"),
    do: elem(Game.new(%{bot: true, preset: preset}, seed), 1)

  defp choose(game, bot \\ Plan.new()),
    do: elem(Plan.choose(Game.bot_view(game, game.active), bot), 0)

  defp play_out(game, max) do
    Enum.reduce_while(1..max, game, fn _, game ->
      case Game.status(game) do
        {:over, _} ->
          {:halt, game}

        {:playing, [seat]} ->
          action = choose(game)
          assert {:ok, game} = Game.apply(game, seat, action), "#{inspect(action)} was refused"
          {:cont, %{game | history: []}}
      end
    end)
  end

  test "bot against bot: legal actions, card conservation, every game ends" do
    games = for seed <- 1..4, do: play_out(bot_game({seed, 2, 3}), 3000)
    Enum.each(games, &assert_conserved/1)
    assert Enum.all?(games, &(Game.status(&1) |> elem(0) == :over))
  end

  test "Red vs Green: legal actions, card conservation, every game ends" do
    games = for seed <- 1..2, do: play_out(bot_game({seed, 2, 3}, "red_green"), 4000)
    Enum.each(games, &assert_conserved/1)
    assert Enum.all?(games, &(Game.status(&1) |> elem(0) == :over))
  end

  test "the same view gives the same action" do
    game = bot_game({5, 2, 3})
    assert choose(game) == choose(game)
  end

  test "it hires first, by the worker order" do
    game = bot_game({1, 2, 3})
    assert {:hire, id} = choose(game)
    hand = for c <- game.sides[0].zones.hand, do: game.cards[c].card
    order = TechPlan.worker_order()
    best = Enum.min_by(hand, &(Enum.find_index(order, fn s -> s == &1 end) || 99))
    assert game.cards[id].card == best
  end

  test "it builds tech I as soon as it is legal" do
    {game, _} = add_workers(bot_game({1, 2, 3}), 0, 2)
    game = put_in(game.sides[0].gold, 9)
    assert {:hire, _} = choose(game)
    {:ok, game} = Game.apply(game, 0, choose(game))
    assert {:build, :tech_1} in Rules.legal(game)
    assert choose(game) == {:build, :tech_1}
  end

  defp add_workers(game, seat, n) do
    {game, ids} = Game.add_cards(game, seat, List.duplicate("worker", n))
    {update_in(game.sides[seat].zones.workers, &(&1 ++ ids)), ids}
  end

  test "the tech step follows the plan: Iron Man twice for Bashing first" do
    game = bot_game({1, 2, 3})
    {:ok, game} = Game.apply(game, 0, :end_turn)
    assert game.phase == :tech
    {:tech, ids} = choose(game)
    assert Enum.map(ids, &game.cards[&1].card) == ["iron-man", "iron-man"]
  end

  test "at 10 workers with the plan done it techs no card" do
    game = bot_game({1, 2, 3})
    {game, _} = add_workers(game, 0, 6)
    plan = TechPlan.plan("Bashing")

    codex =
      Enum.reject(game.sides[0].zones.codex, &(game.cards[&1].card in plan))

    game = put_in(game.sides[0].zones.codex, codex)
    {:ok, game} = Game.apply(game, 0, :end_turn)
    assert choose(game) == {:tech, []}
  end

  test "it never moves a patroller from slot to slot: at most 5 patrol moves a turn" do
    game = play_out(bot_game({3, 2, 3}), 300)

    turns =
      game.log
      |> Enum.reverse()
      |> Enum.chunk_by(&match?({:action, _, :end_turn}, &1))

    assert Enum.all?(turns, fn t ->
             Enum.count(t, &match?({:action, _, {:patrol, _, _}}, &1)) <= 5
           end)
  end

  test "new/1 refuses an unknown rule" do
    assert Plan.new(tower: false).rules.tower == false
    assert_raise ArgumentError, fn -> Plan.new(nope: true) end
  end

  test "eval/2: a win is the best score; more base HP is better" do
    game = bot_game({1, 2, 3})
    assert Plan.eval(%{game | phase: :over, winner: 0}, 0) == 1000.0
    hurt = put_in(game.sides[1].base_hp, 15)
    assert Plan.eval(hurt, 0) > Plan.eval(game, 0)
  end

  test "the table's bot levels: :search (the default), :plan, :basic" do
    assert Table.bot_levels() == [:search, :plan, :basic]
    game = bot_game({1, 2, 3})
    {:ok, game} = Game.apply(game, 0, :end_turn)
    {:ok, game} = Game.apply(game, 0, choose(game))
    view = Table.view(game, 1)
    {action, _} = Table.bot_choose(:plan, view, Table.bot_new(:plan, {1, 2, 3}))
    assert action in Rules.legal(game)
  end

  test "the hidden cards of the other side do not change its choice" do
    game = play_out(bot_game({4, 5, 6}), 55)
    opp = 1 - game.active
    zones = game.sides[opp].zones
    n = min(length(zones.hand), length(zones.deck))
    assert n > 0
    {top, rest} = Enum.split(zones.deck, n)
    {out, keep} = Enum.split(zones.hand, n)
    other = put_in(game.sides[opp].zones, %{zones | hand: top ++ keep, deck: out ++ rest})
    assert choose(game) == choose(other)
  end

  test "Rules.act_legal/2 does what act/2 does for a legal action" do
    game = bot_game({2, 2, 3})

    for action <- Rules.legal(game) do
      assert {:ok, Rules.act_legal(game, action)} == Rules.act(game, action)
    end
  end
end
