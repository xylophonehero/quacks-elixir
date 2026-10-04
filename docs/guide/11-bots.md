# 11. The bots

[Back to the guide](../GUIDE.md)

A bot is a pure function. It reads the game, picks one action from
`legal_actions/2` and gives it back. The GameServer (chapter 4) calls it on a timer
and applies the action through `Session.apply/3`, as for a human click. This
chapter is about the function.

The design and the numbers are in two research docs:

- `docs/research/ai-opponents.md`: the heuristic bot, its profiles and its tuning.
- `docs/research/jev-plan.md`: the expected-value prototype, the static choice
  scorer, and why the bots need no language model.

## The contract: a behaviour

A *behaviour* is a TypeScript `interface` for a module. `Quacks.AI.Decider`
(`lib/quacks/ai/decider.ex:11-12`) declares one callback:

```elixir
@callback decide(Game.t(), Game.seat(), Profile.t(), :rand.state()) ::
            {Game.action(), :rand.state()} | :none
```

`Quacks.AI` says `@behaviour Quacks.AI.Decider` and marks its function with
`@impl true` (`lib/quacks/ai.ex:18` and `:34`). The compiler warns when a module
misses a callback or marks a function that is not one. Another bot, for example a
bot that asks a decision model, can implement the same callback and plug in.

## `decide/4`: one action per call

```elixir
def decide(game, seat, profile, rng) do
  phase = Game.phase(game, seat)

  case Game.legal_actions(game, seat) do
    [] ->
      :none

    _legal when phase == :stopped ->
      :none

    legal ->
      {action, rng} =
        choose(phase, %{game: game, seat: seat, profile: profile, legal: legal}, rng)

      # Last resort: an unknown book or card must never stall the game.
      {if(action in legal, do: action, else: hd(legal)), rng}
  end
end
```

(`lib/quacks/ai.ex:37-54`)

`choose/3` has one clause per phase (`lib/quacks/ai.ex:56-85`), the same dispatch as
the engine's `step/3`. A multi-step turn, such as the shop (`Quacks.AI.Shop`), asks
again after each action. The last line is a safety net: if a new rule adds an action
that `choose/3` does not know, the bot still plays a legal move.

## Profiles are data

How a bot plays is a struct, not code (`Quacks.AI.Profile`,
`lib/quacks/ai/profile.ex`). Three profiles, `:cautious`, `:balanced` and
`:reckless`, differ only in their numbers. For example, the highest explosion
chance at which the balanced bot still draws, per round
(`lib/quacks/ai/profile.ex:173`):

```elixir
max_bust: bust([0.60, 0.55, 0.50, 0.45, 0.30, 0.25, 0.15, 0.15, 0.10]),
```

Other fields set the shop taste (`colour_weight`, `value_weight`), the ruby plan
and the rules to use: `stop_rule` (`:threshold` or `:ev`), `flask_rule` and
`choice_rule` (`lib/quacks/ai/profile.ex:53-84`). This is chapter 7 again: tuning
changes a number, not a function.

`Profile.parse/1` reads a name with `+` modifiers, such as `"balanced+ev+scored"`
(`lib/quacks/ai/profile.ex:105-136`), for the simulator. Bots at a real table use
`@bot_profile :balanced` (`lib/quacks/game_server.ex:79`) with the threshold rule
(see "At the table" below).

## Exact odds: `Quacks.AI.Odds`

A draw takes a chip from the bag with equal chance for each chip, and the bag is
open information. So the bot does not guess the chance of an explosion. It counts
(`lib/quacks/ai/odds.ex:19-22`):

```elixir
def bust([], _sum, _limit), do: 0.0

def bust(bag, sum, limit),
  do: Enum.count(bag, &match?({:white, w} when sum + w > limit, &1)) / length(bag)
```

`match?/2` takes a guard (`when sum + w > limit`), so "the whites that push the sum
over the limit" is one expression. The doctest shows a case: 1 bad white in a bag
of 4 gives `0.25`. `next_draw/2` (lines 29-35) returns 0 when the draw cannot
explode, for example with card B3.

The threshold rule draws while that chance is at most `max_bust` for the round,
moved by `margin_shift` per VP behind the leader (`threshold/1`,
`lib/quacks/ai.ex:111-118`).

## Expected value: `Quacks.AI.Expectimax`

The threshold rule asks "how likely is a bust?". The EV rule asks "is one more draw
worth more than a stop?" (`stop_rule: :ev`). The moduledoc gives the value of a
pot (`lib/quacks/ai/expectimax.ex:8-10`):

    value(space, round) = coin_weight[round] * coins + vp + ruby_value * ruby

`coin_weight` falls from 1.5 in round 1 to 0.12 in round 8: coins buy chips early
and are worth little late.

**The state is small.** A pot is `{whites, coloured, index, sum}`: the chips in the
bag as `%{value => count}`, the space of the newest chip and the white sum
(`pot/3`, `lib/quacks/ai/expectimax.ex:90-94`). Colours and chip effects are left
out on purpose: a coloured chip is a safe move of its value. Two bags with the
same counts are the same state.

**The search** is two functions that call each other
(`lib/quacks/ai/expectimax.ex:101-133`):

```elixir
defp best(pot, 0, ctx, memo), do: {stop(pot, ctx), memo}

defp best(pot, depth, ctx, memo) do
  key = {pot, depth}

  case memo do
    %{^key => value} ->
      {value, memo}

    _ ->
      {draw, memo} = draw(pot, depth, ctx, memo)
      value = max(stop(pot, ctx), draw)
      {value, Map.put(memo, key, value)}
  end
end
```

- `best` is the *max* node: stop now, or draw, whichever is worth more.
- `draw` is the *chance* node: the mean of `best` over each chip value in the bag,
  weighted by its count, one level less deep. A white that busts the pot ends the
  branch with the explosion payout (`outcome/5`, lines 135-146).
- `depth` is `ev_depth` (default 3, `lib/quacks/ai/profile.ex:70`): how many draws
  ahead it looks. At depth 0 the bot stops.

**Memoisation without mutation.** `memo` is a plain map that each call takes and
gives back, so the same pot at the same depth is computed once. `%{^key => value}`
matches when the map has that key (the pin `^` uses the value of `key`, not a new
binding). In JS you would put the cache in a closure or a `Map` you mutate. Here it
is an accumulator, like the state in `Array.reduce`, and it is gone after the call.

The research measured a mean of 19 µs per decision at depth 3, and 55-56 % wins in
2-player games against the threshold bot (parity 50 %) (`docs/research/jev-plan.md`
§3.3). `test/quacks/ai/expectimax_test.exs:59-76` checks that depths 1 to 5 stay
fast.

## Choices: `Quacks.AI.Choice`

The fortune, chip, gold witch and essence choices use `choice_rule`. With
`:scored`, `Quacks.AI.Choice` gives each legal option a value in VP from one table
and takes the highest (`lib/quacks/ai/choice.ex:41-56`):

```elixir
def pick(game, seat, profile, legal),
  do: Enum.max_by(legal, &value(&1, game, seat, profile), fn -> hd(legal) end)

def value({:fortune, choice}, game, seat, profile), do: fortune(choice, game, seat, profile)
def value({:chip, choice}, game, seat, profile), do: chip(choice, game, seat, profile)
def value({:witch, :gold}, _game, _seat, _profile), do: 1.0
def value({:essence, {:space, n}}, _game, _seat, _profile), do: n
def value(_pass, _game, _seat, _profile), do: 0
```

A chip is worth its Set 1 price times the round's `coin_weight`; a ruby is
`ruby_value`; a pass is 0. No search, just a table. In the base game the choices
are worth little; with the expansions the table gains 1.2-1.6 VP over the default
rule (`docs/research/jev-plan.md` §4).

## A deterministic rng per bot

Some choices are random, for example a fortune choice under the default rule
(`random/2`, `lib/quacks/ai.ex:234-237`, with `:rand.uniform_s/2`). The rng for this
is the bot's own, made from the game seed and the seat
(`lib/quacks/ai.ex:32`):

```elixir
def new_rng({a, b, c}, seat), do: :rand.seed_s(:exsss, {a, b, c + 7919 * (seat + 1)})
```

What this buys:

- **The bots never change the chips.** A bot does not read or advance `game.rng`.
  Add a bot, or change its profile, and every human still draws the same chips
  from the same seed.
- **Replay stays exact.** The session log holds the bot's actions like any other
  action (chapter 3). Replay applies them again; it does not ask the bot.
- **A bot game repeats.** The same seed and the same profiles give the same game,
  move for move. A strange bot move in the simulator is a seed you can run again.
- **Seats do not disturb each other.** Each seat has its own stream, so the bot in
  seat 1 makes the same random choices whatever seat 2 does.

## At the table

The decider is the same function in the simulator and at a real table. What
differs is who calls it and when. Chapter 4 has the GameServer code; this is the
bot's view of it.

**The flags are for the simulator.** `stop_rule: :ev` and `choice_rule: :scored`
are fields of the profile, and `+ev` and `+scored` turn them on
(`@variants`, `lib/quacks/ai/profile.ex:105-114`). The GameServer stores the atom
`:balanced` per bot seat and calls `Profile.get/1`
(`lib/quacks/game_server.ex:760` and 866), so a table bot uses the defaults:
`stop_rule: :threshold`, `choice_rule: :default` (`lib/quacks/ai/profile.ex:67-69`).
The research measured the EV rule and the scored choices as a little stronger
(above). To use them at a table, the server would keep a parsed profile, for
example `Profile.parse("balanced+ev+scored")`, in place of the atom. No decider
code changes.

**Brewing in lockstep.** In the potions phase a bot gets one tick per action, 700 ms
apart. It may `:draw` only while it has drawn fewer chips this round than the human
who drew most (`capped?/3`, `lib/quacks/game_server.ex:915-926`). So a bot brews
draw for draw beside the humans and never runs ahead. The decider does not know
about the cap: the server just does not ask it. When every human has stopped, the
cap is off and the bot finishes at tick speed. Round 9 has no cap, because the
stir already makes all seats draw together.

**Choices in concurrent phases: plans.** In the fortune, chip, witch and shop
phases every seat decides at the same time. There the server calls `decide/4` in a
loop on a private copy of the game (`plan/2`, `lib/quacks/game_server.ex:863-885`)
and keeps the bot's actions until no human decides any more. The bot thus decides
from the state at the start of its part, the same as a human who cannot see the
other choices yet. Because the decider is pure and takes the rng as an argument,
"decide five times on a copy" needs no new bot code.

**The Mandrake.** The server answers the Mandrake question for humans (chapter 4).
A bot answers it itself: `choose(:yellow_choice, _ctx, rng)` gives `:return_white`
(`lib/quacks/ai.ex:57`).

**Names.** A bot at a table gets a name from `Quacks.AI.Names`
(`lib/quacks/ai/names.ex`): 20 alchemist names, and `pick/2` takes a free one with
the table's own rng (`:rand.uniform_s/2`). When all 20 are taken, the bot is
"Bot N". The profile also has a `bot_name` ("Steady Sam" for `:balanced`,
`lib/quacks/ai/profile.ex:86`), but the table does not use it: two balanced bots
must not have the same name.

## The simulator: `Quacks.AI.Sim` and `mix quacks.sim`

`Quacks.AI.Sim` plays whole games with no processes: `Game.new/1`, then
`AI.decide/4` and `Game.apply/3` for each seat in turn, until `Game.over?/1`
(`play/3` and `loop/5`, `lib/quacks/ai/sim.ex:58-85`). It gives each bot
`AI.new_rng/2`, as the GameServer does. `Sim.run/1` runs many games in parallel
with `Task.async_stream/3` and sums them up per profile (chapter 8).

The mix task prints a table (`lib/mix/tasks/quacks.sim.ex:1-14`):

```
mix quacks.sim --games 1000 --profiles balanced+ev,balanced --seed 1
```

The columns are mean VP, its spread, win rate, explosion rate overall and per
round, then mean coins per round and chips bought per game. To compare two
profiles, run the same seed with each and read the two rows. The research docs
show the tables that chose today's numbers.
