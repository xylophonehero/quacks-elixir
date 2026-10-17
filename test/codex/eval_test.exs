defmodule Codex.AI.EvalTest do
  @moduledoc "The Codex evaluator: features, the threat term, the stage-1 score."
  use ExUnit.Case, async: true

  alias Codex.AI.{Eval, Weights}
  alias Codex.Bot.Plan
  alias Codex.{Game, Stats, Zones}

  doctest Codex.AI.Weights

  defp bot_game(seed), do: elem(Game.new(%{bot: true}, seed), 1)

  defp play_out(game, n) do
    Enum.reduce_while(1..n, game, fn _, game ->
      case Game.status(game) do
        {:over, _} ->
          {:halt, game}

        {:playing, [seat]} ->
          {a, _} = Plan.choose(Game.bot_view(game, seat), nil)
          {:ok, game} = Game.apply(game, seat, a)
          {:cont, %{game | history: []}}
      end
    end)
  end

  # The stage-1 formula of `Codex.Bot.Plan.eval/2`, written out.
  defp stage1(g, me), do: side(g, me) - side(g, 1 - me)

  defp side(g, s) do
    sd = g.sides[s]

    forces =
      for id <- Zones.in_play(g, s), Stats.force?(g, id) do
        c = g.cards[id]
        base = max(Stats.atk(g, id), 0) + max(Stats.hp(g, id) - c.damage, 0)
        kws = Enum.count([:flying, :unstoppable, :swift], &Stats.kw?(g, id, &1))
        base + kws + if(c.level, do: 2 + c.level, else: 0)
      end

    buildings =
      for b <- sd.tech_buildings ++ sd.pending,
          do: if(b in [:tech_1, :tech_2, :tech_3], do: 4, else: 2)

    damage = sd.building_damage |> Map.values() |> Enum.sum()
    ongoing = Enum.count(sd.zones.in_play, &(g.cards[&1].card in ["two-step", "harmony"]))

    sd.base_hp * 1.5 + 0.5 * max(10 - sd.base_hp, 0) + Enum.sum(forces) + Enum.sum(buildings) -
      0.5 * damage + 0.3 * sd.gold + ongoing
  end

  test "the stage-1 weights give the stage-1 score" do
    for seed <- 1..3, n <- [10, 60, 120, 180] do
      g = play_out(bot_game({seed, 7, 7}), n)
      g = Eval.lasting(g)

      for me <- [0, 1], g.phase != :over do
        assert_in_delta Eval.score(g, me, Weights.stage1()), stage1(g, me), 1.0e-9
      end
    end
  end

  test "a win and a loss" do
    g = bot_game({1, 2, 3})
    over = %{g | phase: :over, winner: 1}
    assert Eval.score(over, 1, Weights.defaults()) == 1000.0
    assert Eval.score(over, 0, Weights.defaults()) == -1000.0
  end

  test "the score is zero-sum without the threat term" do
    g = play_out(bot_game({2, 7, 7}), 80)
    w = %{Weights.defaults() | workers: 0.4, hand: 0.3, tech_cards: 0.2, patrol_hp: 0.5}
    assert_in_delta Eval.score(g, 0, w), -Eval.score(g, 1, w), 1.0e-9
  end

  test "features count hidden zones by their size in the fair view" do
    g = play_out(bot_game({3, 7, 7}), 40)
    view = Game.bot_view(g, 0)
    real = Eval.features(g, 1)
    seen = Eval.features(Plan.game_of(view) |> with_counts(view, 1), 1)
    assert seen.hand == real.hand
    assert seen.workers == real.workers
    assert seen.tech_cards == real.tech_cards
  end

  # `game_of/1` empties the hidden zones; the view's counts go back in for the test.
  defp with_counts(g, view, s) do
    zones = Map.merge(g.sides[s].zones, Map.take(view.sides[s].zones, [:hand, :workers, :codex]))
    put_in(g.sides[s].zones, zones)
  end

  describe "threat/2" do
    setup do
      g = bot_game({1, 2, 3})
      {g, [a, b, c]} = Game.add_cards(g, 1, ["older-brother", "iron-man", "fruit-ninja"])
      {g, [p]} = Game.add_cards(g, 0, ["tenderfoot"])
      %{g: g, a: a, b: b, c: c, p: p}
    end

    test "with no patrol, all the ATK hits the base", %{g: g, a: a, b: b} do
      g = put_in(g.sides[1].zones.in_play, [a, b])
      t = Eval.threat(g, 0)
      assert t.base == Stats.atk(g, a) + Stats.atk(g, b)
      assert t.patrol == 0
    end

    test "the squad leader takes the attacks until it dies", %{g: g, a: a, b: b, p: p} do
      g = put_in(g.sides[1].zones.in_play, [a, b])
      g = put_in(g.sides[0].zones.patrol.squad_leader, p)
      # Tenderfoot: 1/2, with the squad leader's armor 1 it takes 3 to kill.
      assert Stats.atk(g, a) < 3
      assert Stats.atk(g, a) + Stats.atk(g, b) >= 3
      assert Eval.threat(g, 0) == %{base: 0, patrol: 3}
      # One attacker more: the weakest clear the patrol, the strongest hits the base.
      {g, [d]} = Game.add_cards(g, 1, ["older-brother"])
      g = put_in(g.sides[1].zones.in_play, [a, b, d])
      assert Eval.threat(g, 0) == %{base: Stats.atk(g, b), patrol: 3}
    end

    test "a high threat costs score; lethal costs more", %{g: g, a: a, b: b, c: c} do
      g = put_in(g.sides[1].zones.in_play, [a, b, c])
      w = %{Weights.defaults() | threat_base: 1.0}
      assert Eval.score(g, 0, w) < Eval.score(g, 0, Weights.defaults())
      low = put_in(g.sides[0].base_hp, 3)
      wl = %{w | lethal: 10.0}
      assert Eval.score(low, 0, w) - Eval.score(low, 0, wl) == 10.0
    end
  end
end
