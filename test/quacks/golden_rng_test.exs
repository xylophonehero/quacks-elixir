defmodule Quacks.GoldenRngTest do
  @moduledoc """
  The same seed gives the same game. Bots play whole games for fixed seeds and
  settings; every random outcome (the chips drawn, the bonus die, the Fortune Teller
  deck, the witches and their visits, the patients, the bots' own picks) must match
  `test/fixtures/golden_rng.exs`, and so must a hash of the full log and the final
  game.

  This file guards refactors of the random code (#83: `Table.Kit`). If a change is
  meant to change the draws, record again with
  `GOLDEN_RECORD=1 mix test test/quacks/golden_rng_test.exs` and say so in the PR.
  """
  use ExUnit.Case, async: true

  alias Quacks.{AI, Game, Session}
  alias Quacks.AI.{Bench, Names, Profile}
  alias Quacks.Game.{Evaluation, Fortune, Potions}
  alias Quacks.Rules.Alchemists
  alias Quacks.Rules.Witches, as: WitchCards

  @fixture Path.expand("../fixtures/golden_rng.exs", __DIR__)

  @games [
    solo: {{1, 2, 3}, [:balanced], []},
    duo_no_cards: {{4, 5, 6}, [:balanced, :reckless], [rules: %{fortune: false}]},
    four_both_expansions:
      {{7, 8, 9}, [:balanced, :reckless, :cautious, :balanced],
       [expansions: [:herb_witches, :alchemists], sets: %{green: 2, locoweed: 1}]},
    three_house_rules:
      {{11, 12, 13}, [:reckless, :cautious, :balanced],
       [rules: %{die: :no_orange, supply: :limited, starting_rubies: 2}, sets: %{blue: 3}]},
    eight_herb_witches: {{21, 22, 23}, List.duplicate(:balanced, 8), [expansion: :herb_witches]},
    duo_alchemists_random_patients:
      {{31, 32, 33}, [:cautious, :reckless],
       [expansions: [:alchemists], patients: %{0 => :random, 1 => :random}]},
    solo_sets: {{41, 42, 43}, [:reckless], [sets: %{purple: 2, black: 2, orange: 2}]}
  ]

  test "every recorded game plays out the same" do
    actual = record()

    if System.get_env("GOLDEN_RECORD") do
      File.mkdir_p!(Path.dirname(@fixture))
      text = inspect(actual, limit: :infinity, printable_limit: :infinity)
      File.write!(@fixture, [Code.format_string!(text), "\n"])
    end

    expected = @fixture |> Code.eval_file() |> elem(0)

    for {name, want} <- expected do
      got = Map.fetch!(actual, name)

      for {key, value} <- want do
        assert {name, key, Map.fetch!(got, key)} == {name, key, value}
      end
    end

    assert Map.keys(actual) == Map.keys(expected)
  end

  defp record do
    games = Map.new(@games, fn {name, game} -> {name, game_outcome(game)} end)

    Map.merge(games, %{
      units: units(),
      session_replay: session_replay()
    })
  end

  defp game_outcome({seed, bots, opts}) do
    start = Game.new([seed: seed, players: length(bots)] ++ opts)
    {game, _stats} = Bench.play(Enum.map(bots, &Profile.get/1), seed, opts)
    log = Enum.reverse(game.log)

    %{
      deck: [start.fortune_card | start.fortune_deck],
      witches: start.witches,
      patients: start.patients,
      draws: for({seat, {:drew, chip, _}} <- log, do: {seat, chip}),
      card_draws: for({seat, {:fortune, id, {:drew, chips}}} <- log, do: {seat, id, chips}),
      die: for({seat, {:bonus_die, face}} <- log, do: {seat, face}),
      visitors: for({:visitor, id} <- log, do: id),
      score: Game.score(game),
      log_hash: hash(log),
      game_hash: hash(game)
    }
  end

  # The pure helpers that take an rng, called on their own.
  defp units do
    rngs = for s <- [{1, 2, 3}, {9, 9, 9}, {123, 456, 789}], do: :rand.seed_s(:exsss, s)
    g = Game.new(seed: {5, 5, 5}, players: 2)

    {rolls, _g} =
      Enum.map_reduce(1..30, g, fn _, g ->
        {face, g} = Evaluation.roll(g, 0)
        {face, g}
      end)

    {taken, g2} = Potions.take_random(g, 0, 5)
    {all, _g} = Potions.take_random(g2, 1, 99)

    %{
      decks: Enum.map(rngs, &Fortune.deck(&1, 4, [:herb_witches, :alchemists])),
      base_decks: Enum.map(rngs, &Fortune.deck(&1, 2, [], false)),
      witches: Enum.map(rngs, &WitchCards.deal/1),
      patients: Enum.map(rngs, &Alchemists.deal/1),
      names: Enum.map(rngs, &(&1 |> then(fn rng -> Names.pick([], rng) end) |> elem(0))),
      bot_rngs: for(seat <- 0..3, do: :rand.export_seed_s(AI.new_rng({1, 2, 3}, seat))),
      rolls: rolls,
      take_random: {taken, all, Game.player(g2, 0).bag, :rand.export_seed_s(g2.rng)}
    }
  end

  # A bundle through JSON replays to the same game.
  defp session_replay do
    session =
      Session.new({7, 8, 9}, 3,
        sets: %{green: 2, locoweed: 1},
        rules: %{pot_side: :back, explode_above: 8},
        expansions: [:herb_witches, :alchemists]
      )
      |> play()

    {:ok, rebuilt} =
      session |> Session.bundle() |> Jason.encode!() |> Jason.decode!() |> Session.from_bundle()

    %{
      actions: length(session.actions),
      score: Game.score(rebuilt.game),
      game_hash: hash(rebuilt.game)
    }
  end

  # Bots (`:balanced`) play every seat of `session` to the end.
  defp play(session) do
    profile = Profile.get(:balanced)
    rngs = Map.new(session.game.seats, &{&1, AI.new_rng(session.seed, &1)})

    Enum.reduce_while(1..5000, {session, rngs}, fn _, {s, rngs} ->
      next = Enum.find_value(s.game.seats, &decision(s.game, &1, profile, rngs[&1]))

      with {seat, action, rng} <- next,
           {:ok, s} <- Session.apply(s, seat, action) do
        {:cont, {s, Map.put(rngs, seat, rng)}}
      else
        _over -> {:halt, {s, rngs}}
      end
    end)
    |> elem(0)
  end

  defp decision(game, seat, profile, rng) do
    with [_ | _] <- Game.legal_actions(game, seat),
         {action, rng} <- AI.decide(game, seat, profile, rng),
         do: {seat, action, rng},
         else: (_none -> nil)
  end

  defp hash(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic]))
    |> Base.encode16(case: :lower)
  end
end
