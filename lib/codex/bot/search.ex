defmodule Codex.Bot.Search do
  @moduledoc """
  The stage-2 Codex bot: a search over the whole turn
  (`docs/research/codex-bot.md` §4.2.2).

  Once per turn, at its first main-phase action, it:

  1. Deals the hidden cards at random (`Codex.AI.Determinize.sample/3`), so it
     has a full game to play on. It sees only its fair view.
  2. Plays candidate turns on that game to the end of the main phase, with
     the engine (`Codex.Rules.act_legal/2`):
     - the stage-1 policy (`Codex.Bot.Plan.policy/2`) for the whole turn;
     - the same turn with an "enabler" put in at one point (River's sideline,
       "stop the music", Discord, Appel Stomp, Intimidate, any other activated
       ability), then the policy;
     - randomised turns: at each step, with chance `eps`, a random legal action
       in place of the policy's action.
  3. Scores each candidate after each of its actions with `Codex.AI.Eval`
     (so a turn may also stop early), and keeps the best: the policy wins a tie.
  4. Plays the best turn one action per call. Before each action it checks
     that the state is the one that it expected (`fingerprint/2`); if not (a
     card was drawn, a guess was wrong), it searches again.

  Limits: at most `n` candidates, and at most `budget_ms` milliseconds (nil:
  no clock). With no clock the bot is deterministic: the same view and seed give
  the same action (the bench and the tuner use this). The tech step is the
  stage-1 bot's.
  """

  alias Codex.AI.{Determinize, Eval, Weights}
  alias Codex.Bot.Plan
  alias Codex.{Rules, Zones}
  alias Table.Kit.Rng

  @max_steps 60
  @enabler_spells ~w(intimidate discord appel-stomp)

  @doc """
  A bot state. Options: `n:` candidates per turn (default 40), `budget_ms:`
  (default 400; nil for no clock), `eps:` (default 0.15), `seed:` (default 1),
  `prefix:` (default true: a turn may stop early when the score after an
  earlier action is the best), `weights:` (default
  `Codex.AI.Weights.defaults/0`), `rules:` the stage-1
  rule changes for the policy (default `[]`).
  """
  @spec new(keyword) :: map
  def new(opts \\ []) do
    weights = Keyword.get(opts, :weights, Weights.defaults())

    %{
      n: Keyword.get(opts, :n, 40),
      budget_ms: Keyword.get(opts, :budget_ms, 400),
      eps: Keyword.get(opts, :eps, 0.15),
      prefix: Keyword.get(opts, :prefix, true),
      seed: Keyword.get(opts, :seed, 1),
      plan: Plan.new(Keyword.get(opts, :rules, []), weights),
      queue: [],
      last: nil
    }
  end

  @doc "The bot's next action for `view`, and its new state."
  @spec choose(map, map | nil) :: {term, map}
  def choose(view, nil), do: choose(view, new())

  def choose(%{phase: :main, legal: [_ | _]} = v, st) do
    fp = fingerprint(v, v.active)

    case st.queue do
      [{action, ^fp} | rest] ->
        if action in v.legal, do: {action, %{st | queue: rest}}, else: search(v, st)

      _ ->
        search(v, st)
    end
  end

  def choose(v, st) do
    {action, _} = Plan.choose(v, st.plan)
    {action, %{st | queue: []}}
  end

  defp search(v, st) do
    me = v.active
    turn = v.sides[me].turn
    rng = Rng.seed({st.seed, turn, :erlang.phash2({v.sides[me].zones.hand, v.sides[me].gold})})
    {g, rng} = Determinize.sample(v, me, rng)
    deadline = st.budget_ms && System.monotonic_time(:millisecond) + st.budget_ms

    ctx = %{me: me, plan: st.plan, w: st.plan.weights, eps: st.eps, prefix: st.prefix}
    {score, line, base, memo} = rollout(g, [], 0.0, rng, ctx, %{})
    {best, left, memo} = enablers(base, {score, line}, st.n - 1, deadline, ctx, memo)
    {{_score, line}, _} = randomised(g, best, left, deadline, rng, ctx, memo)

    case line do
      [{action, _fp} | rest] ->
        if action in v.legal,
          do: {action, %{st | queue: rest}},
          else: {elem(Plan.choose(v, st.plan), 0), %{st | queue: []}}

      [] ->
        {:end_turn, %{st | queue: []}}
    end
  end

  # One candidate from `g`: `forced` actions first, then the policy (or, with
  # chance eps, a random action). Returns its best prefix `{score, line}`, the
  # states along it (`[{game, line so far}]`, for the enabler candidates) and
  # the memo of policy actions (`%{state key => action}`).
  defp rollout(g, forced, eps, rng, ctx, memo) do
    start = Eval.score(g, ctx.me, ctx.w)
    walk(g, forced, eps, rng, ctx, memo, {[], start}, [{g, []}], {start, []}, 0)
  end

  defp walk(g, forced, eps, rng, ctx, memo, {line, cur}, states, best, k) do
    if k >= @max_steps or g.phase != :main or g.active != ctx.me do
      finish(ctx, {line, cur}, states, best, memo)
    else
      {action, forced, rng, memo} = next(g, forced, eps, rng, ctx, memo)

      if action == :end_turn do
        finish(ctx, {line, cur}, states, best, memo)
      else
        g1 = Plan.sim(g, action)
        line = [{action, fingerprint(g, ctx.me)} | line]
        s = Eval.score(g1, ctx.me, ctx.w)
        best = if s >= elem(best, 0), do: {s, Enum.reverse(line)}, else: best
        walk(g1, forced, eps, rng, ctx, memo, {line, s}, [{g1, line} | states], best, k + 1)
      end
    end
  end

  # With `prefix` the best state along the line counts (the turn may stop
  # early); without it, the state at the end of the line.
  defp finish(%{prefix: true}, _now, states, {score, line}, memo),
    do: {score, line, Enum.reverse(states), memo}

  defp finish(_ctx, {line, cur}, states, _best, memo),
    do: {cur, Enum.reverse(line), Enum.reverse(states), memo}

  defp next(_g, [a | rest], _eps, rng, _ctx, memo), do: {a, rest, rng, memo}

  defp next(g, [], eps, rng, ctx, memo) when eps > 0 do
    {u, rng} = Rng.uniform(rng)

    case u < eps and wild(Rules.legal(g)) do
      [_ | _] = moves ->
        {a, rng} = Rng.pick(moves, rng)
        {a, [], rng, memo}

      _ ->
        {a, memo} = policy(g, ctx, memo)
        {a, [], rng, memo}
    end
  end

  defp next(g, [], _eps, rng, ctx, memo) do
    {a, memo} = policy(g, ctx, memo)
    {a, [], rng, memo}
  end

  # The policy's action, from the memo when the state was seen before.
  defp policy(g, ctx, memo) do
    key = :erlang.phash2({g.cards, g.sides})

    case memo do
      %{^key => a} ->
        {a, memo}

      _ ->
        a = Plan.policy(g, ctx.plan)
        {a, Map.put(memo, key, a)}
    end
  end

  # The actions for a random step: not the end of the turn, not a move off the patrol.
  defp wild(legal), do: Enum.reject(legal, &(&1 == :end_turn or match?({:sideline, _}, &1)))

  # The policy's turn with one enabler put in at one of its states.
  defp enablers(base, best, left, deadline, ctx, memo) do
    tries =
      for {g, line} <- base,
          a <- Rules.legal(g),
          enabler?(g, a),
          do: {g, Enum.reverse(line), a}

    Enum.reduce_while(tries, {best, left, memo}, fn {g, prefix, a}, {best, left, memo} ->
      if left <= 0 or late?(deadline) do
        {:halt, {best, left, memo}}
      else
        {s, line, _, memo} = rollout(g, [a], 0.0, nil, ctx, memo)
        {:cont, {better(best, {s, prefix ++ line}), left - 1, memo}}
      end
    end)
  end

  defp enabler?(_g, {:ability, _id, _name, _targets}), do: true
  defp enabler?(g, {:play, id, _targets}), do: g.cards[id].card in @enabler_spells
  defp enabler?(_g, _action), do: false

  defp randomised(g, best, left, deadline, rng, ctx, memo) do
    if left <= 0 or late?(deadline) do
      {best, left}
    else
      {x, rng} = Rng.uniform(1_000_000_000, rng)
      {s, line, _, memo} = rollout(g, [], ctx.eps, Rng.seed({x, left, 7}), ctx, memo)
      randomised(g, better(best, {s, line}), left - 1, deadline, rng, ctx, memo)
    end
  end

  # A new candidate must be strictly better: the earlier one (the policy) wins a tie.
  defp better({s0, _} = old, {s1, _} = new), do: if(s1 > s0 + 1.0e-9, do: new, else: old)

  defp late?(nil), do: false
  defp late?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  @doc """
  What the bot checks before each planned action: the side to act, its gold,
  hand and the cards in play (with damage and exhaustion) of both sides, the
  patrols and the base HP. Works on a game and on a view.
  """
  @spec fingerprint(map, 0 | 1) :: term
  def fingerprint(g, me) do
    forces =
      for s <- [0, 1], id <- Zones.in_play(g, s) do
        c = g.cards[id]
        {id, c.damage, c.exhausted}
      end

    {g.active, g.sides[me].gold, Enum.sort(g.sides[me].zones.hand), forces,
     g.sides[0].zones.patrol, g.sides[1].zones.patrol, g.sides[0].base_hp, g.sides[1].base_hp}
  end
end
