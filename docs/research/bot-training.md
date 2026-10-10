# Stronger bots: options, benchmark and training

Research date: 2026-10-10. Branch `bots-ai`. Earlier work: `docs/research/ai-opponents.md` (the heuristic bot), `docs/research/jev-plan.md` (the expected-value draw/stop rule and the choice scorer).
Tags: **[M]** = measured on this engine with `mix quacks.bench`. **[S]** = from a source. **[E]** = an estimate.

## 0. Short answer

- **Do not start with a neural network.** Quacks is a small game for a computer: the bag is open, the odds are exact, and one game takes about 1 ms to play. The cheap methods are not used up yet, and they give most of the strength.
- **Recommended path:** (1) a benchmark that measures every change (done: `mix quacks.bench`); (2) the best rules that we have together (done: `balanced+strong`); (3) tune the numbers of the bot by self-play (done: `mix quacks.tune`); (4) only when the gains stop: a small learned value function, trained from self-play data.
- **Results tonight** (§4, §5): `balanced+strong` wins **30.3 % ± 1.5** of 4-player games against three table bots (parity 25 %). The tuned bot wins **TUNED_VS_BALANCED** against the table bots and **TUNED_VS_STRONG** against three `balanced+strong` bots.
- **Cost:** the training ran for about 105 minutes on 4 of the 10 cores under `nice -n 10`. No new dependencies.

## 1. What makes Quacks hard (and easy) for a bot

- **Push your luck.** The main decision, many times per round, is "draw one more chip or stop". The bag is open information, so the chance of an explosion is exact (`Quacks.AI.Odds`). A search over the next 2–3 draws is cheap (`Quacks.AI.Expectimax`, 5 µs per decision).
- **Deck-building.** The shop decides the bag for the rest of the game. A bad buy costs a little in every later round, so the effect of one buy is hard to see in one game. This is where the current bot is weakest: its shop is a table of hand-set weights.
- **Hidden order, no hidden hands.** Nothing is secret except the order of the chips in the bags. So the game needs no bluffing and no opponent model. The other players only matter through the score (when you lead, you can stop safe) and, with a limited supply, through the chips they take.
- **2–8 players.** The rules are the same for every player count, but the value of risk changes: in a 4-player game only the first place counts, so a bot must take more risk than in a 2-player game. A good bot is tested at 2 and at 4 players.
- **Luck.** One game says almost nothing. The VP spread per seat is about 9 VP. To see a 1-point change in win rate you need thousands of games. So the first tool is a benchmark that plays many games fast and gives a confidence interval.

## 2. The options

| Option | What it is | Gain for Quacks | Cost | Risk |
|---|---|---|---|---|
| **A. Better hand rules with exact odds** | Rules written by a person: exact bust odds, EV of a stop against a draw, a value table for choices. | Large for draw/stop (done: EV rule +5 points of win rate in 4p). Small after that: a person cannot guess 30 weights well. | Hours per rule. | Low. Easy to read and to debug. |
| **B. Search at decision points (expectimax, Monte-Carlo rollouts)** | At a decision, play the options forward: exactly over the bag (expectimax) or by sampling many futures (rollouts with a simple bot). | Draw/stop: already exact to depth 3. Shop: rollouts could compare two buys by playing the rest of the game many times. | Expectimax: µs. A shop rollout: ~1 ms per future × 100s of futures × 10s of buys = 0.1–1 s per shop decision. OK for the table (the bot waits about 0.7 s anyway) but 1000× slower in training. | Medium. The rollout bot's own errors bias the result. |
| **C. Parameter search (CEM / CMA-ES) by self-play** | Keep the rules, but let the computer find the numbers: play many games with changed numbers, keep the changes that win. | **Large and cheap** (§5): the shop weights, coin weights per round, ruby value and explosion choice are all numbers. | Only CPU time. ~25 s per generation of 25 candidates on 4 cores. | Low. The result is a JSON file of numbers that a person can read. Can over-fit to one opponent: always check against other bots. |
| **D. A small neural network (policy and/or value) by self-play** | A network learns "how good is this position" (value) or "which action" (policy) from millions of self-play positions. | Possibly the strongest in the end, mainly for the shop. The Quackulator v2 bot learned a value function with a ridge regression on 45 features (no deep net) and got a large part of its strength from it [S]. | Days of work: features, a training loop, a way to use the net in the bot, and new dependencies. | High. Hard to debug, easy to make worse than the rules. |

### 2.1 A neural network in more detail

- **What to learn.** A **value function** is the best first target: given a position at the end of the shop step (own bag, round, VP, rubies, droplet position, the gap to the leader), predict the final VP margin or the chance to win. The bot then uses it for the hard decision: in the shop, try every legal buy and take the one with the best predicted value. Draw/stop stays with the exact expectimax. A **policy net** (pick the action directly) needs more data and is harder to keep legal; not worth it here.
- **Features (about 40–60 numbers):** round; own VP, rubies, droplet position, flask full; the gap to the best other player; for every chip type (colour × value, about 20) the count in the bag; the white total; the number of chips; the number of players.
- **Data volume.** One 4-player game gives 4 × 8 = 32 shop positions. The harness plays about 400–900 games per second on 4 cores, so 1 million games (32 million positions) take 20–40 minutes [M for the speed, E for the rest]. A small model (ridge regression, or 2 layers of 64 units) needs far less.
- **Library.**
  - *Elixir: Nx + Axon + EXLA.* All in one language, no sidecar, the trained model runs inside the GameServer. EXLA runs on the Apple Silicon CPU (no Metal GPU; the MLX backend `emlx` for Metal is still young). For a net this small, the CPU is enough: training takes minutes. One call of a small model through EXLA costs about 50–100 µs [E], well under the decision budget. Cost: 3 new dependencies, and EXLA downloads a large precompiled XLA library.
  - *Python sidecar (PyTorch or scikit-learn).* More examples and tools, Metal GPU through PyTorch `mps`. But the data must be exported (CSV or JSON from Elixir), and the model must be brought back: export the weights to JSON and write the forward pass in plain Elixir (fine for a linear model or a 2-layer net).
  - **Recommendation:** start with a linear or ridge model, fitted in plain Elixir or Nx without Axon. Go to Axon only if the linear model shows a gain and a bigger model is the next step.
- **Time.** Data generation 30 min, fitting minutes, then the same benchmark as for any other bot. The real cost is the work to build it: about 2–3 days.

## 3. The benchmark harness

`Quacks.AI.Bench` (`lib/quacks/ai/bench.ex`) and `mix quacks.bench` (`lib/mix/tasks/quacks.bench.ex`).

```
nice -n 10 mix quacks.bench --games 2000 --players 4 --bots balanced+strong,balanced,balanced,balanced --seed 1 --jobs 4
```

- **Bots** are profile texts: `balanced`, `cautious`, `reckless`, with `+` modifiers (`+ev`, `+scored`, `+strong`, …), or a weights file `file:priv/bots/tuned.json`. Name a bot more than once to give it more seats; seats with the same name are pooled.
- **Duplicate seating.** Every game seed is played once per rotation of the bots: with 4 bots, 4 games with the same chips, and each bot sits in each seat once. Luck cancels out much faster. Two copies of the same bot are always exactly at parity (a test checks this).
- **Output per bot:** seats, win rate (a tie is shared) and its 95 % confidence interval, mean VP and its interval, explosion rate, and the mean time per decision. `--stats` adds the decisions per phase (count, mean and max time). The intervals treat one seed (all its rotations) as one sample, because the games of one seed are not independent.
- **Deterministic:** the same `--seed` gives the same numbers, whatever `--jobs` is.
- **CPU limits:** at most `--jobs` games at the same time; the default is half the cores (`System.schedulers_online() |> div(2)`, 5 on a 10-core Mac). `--minutes` sets a time budget (no new batch after it). A progress line shows games/s and the time left (`--quiet` turns it off).
- **Speed** [M]: 400–900 games/s with 2–4 jobs (4 players, `balanced`); `balanced+strong` takes 5 µs per decision.

## 4. First improvement: `balanced+strong`

The research in `jev-plan.md` found two better rules, but the table bots still use neither. The benchmark shows where the current bot is weak: per game, a bot makes about 100 draw/stop decisions, 20 shop steps, and 2–3 choices (`--stats`). The draw/stop rule is a fixed bust threshold per round; it does not look at what a draw can win. The new modifier `+strong` turns on the exact rules:

- `stop_rule: :ev`: draw when the expected value of one more draw (exact over the bag, 3 draws deep) is more than a stop now.
- `choice_rule: :scored`: the fortune, chip, witch and essence choices by a value table.

| Seed | Players | `balanced+strong` win % (parity) | VP (strong vs balanced) | Explosion % |
|---|---|---|---|---|
| 1 | 4 (1 vs 3) | **30.3 ± 1.5** (25) | 53.6 ± 0.4 vs 51.9 | 37.1 vs 39.5 |
| 2 | 4 (1 vs 3) | **30.4 ± 1.5** (25) | 53.6 vs 51.9 | 37.1 vs 39.5 |
| 1 | 2 | **54.6 ± 2.1** (50) | 56.4 ± 0.5 vs 54.8 | 37.8 vs 34.6 |
| 2 | 2 | **54.8 ± 2.1** (50) | 56.4 vs 54.8 | 37.8 vs 34.6 |

4000 games (4-player) and 2000 games (2-player) per line, `--jobs 2`. Time per decision: 5 µs mean (table bot: 3 µs). The GameServer can use it with no code change in the decider: store `Profile.parse("balanced+strong")` in place of the atom `:balanced`.

## 5. Training by parameter search (`mix quacks.tune`)

### 5.1 What it does, in plain words

1. **Start** from the strong bot. Its play depends on 27 numbers (`Quacks.AI.Weights.spec/0`): the value of a coin in each round, the value of a ruby, the round from which an explosion takes VP, the shop's taste for each colour and chip size, how many black chips, when purple, when to buy droplets, when to use the flask.
2. **Make 24 variants.** Change all the numbers a little at random (around the current best guess, with a spread for each number).
3. **Let them play.** Each variant plays 400 four-player games (1 variant against 3 copies of the strong bot) and 200 two-player games, on the same chips for every variant. Its score is its win rate divided by the fair share (1.0 = as good as the opponent).
4. **Keep the best 6**, and move the best guess towards them. Numbers on which the best 6 agree get a smaller spread; numbers on which they disagree keep a wide spread.
5. **Repeat.** One round of this is a *generation* (about 20 s on 4 cores). After each generation the state is saved, so the run can stop and go on at any time.

This is the *cross-entropy method*, a simple evolution strategy. It needs no gradient, it copes with the luck in the results (because it keeps an average over many variants), and the result is a short list of numbers that a person can read. CMA-ES is the same idea with a full covariance matrix; for 27 numbers and noisy scores it gives little extra.

### 5.2 Tonight's run

```
nice -n 10 mix quacks.tune --minutes 105 --jobs 4
```

TRAINING_RESULTS

## 6. How to run the training

Everything runs on the laptop, on the CPU, with no new dependencies.

### 6.1 Keep the Mac cool

- **`nice -n 10`** in front of every command: macOS gives the training a low priority, so the desktop stays fast.
- **`--jobs 4`** (or less): 4 of the 10 cores. The default is half the cores (5). The fans stay quiet at 4.
- **Low Power Mode** (System Settings → Battery) makes the chips run slower and cooler; the training takes about 1.5× longer. Use it for a run overnight.
- **`caffeinate -i`** only when the Mac goes to sleep during a long run on battery or with the lid open and no activity (`caffeinate -i nice -n 10 mix quacks.tune ...`). It stops idle sleep, not the display sleep.
- Stop a run with Ctrl-C (twice) or by its PID (`kill <pid>`); never by name. A stopped run loses at most the current generation.

### 6.2 Commands

```sh
# 1. Train: about 20 s per generation; the gains came in the first 30-60 minutes.
nice -n 10 mix quacks.tune --minutes 60 --jobs 4

# Go on from where it stopped (the same command; it reads the checkpoint):
nice -n 10 mix quacks.tune --minutes 60 --jobs 4

# Start again from zero:
rm priv/bots/tune-checkpoint.json && nice -n 10 mix quacks.tune --minutes 60 --jobs 4

# Train against another bot, or start from another profile:
nice -n 10 mix quacks.tune --base balanced+strong --opponent balanced --checkpoint priv/bots/tune-vs-balanced.json --out priv/bots/tuned-vs-balanced.json

# 2. Check the result on seeds that the training never saw (2-5 minutes):
nice -n 10 mix quacks.bench --jobs 4 --games 4000 --players 4 --seed 101 --bots file:priv/bots/tuned.json,balanced+strong,balanced+strong,balanced+strong
nice -n 10 mix quacks.bench --jobs 4 --games 4000 --players 4 --seed 101 --bots file:priv/bots/tuned.json,balanced,balanced,balanced
nice -n 10 mix quacks.bench --jobs 4 --games 2000 --players 2 --seed 101 --bots file:priv/bots/tuned.json,balanced
```

### 6.3 Where the results go

- `priv/bots/tune-checkpoint.json`: the state of the search (generation, mean, spread, history). Not committed (`.gitignore`).
- `priv/bots/tuned.json`: the weights (27 numbers, readable), written after every generation. Committed only after review and a benchmark on new seeds.
- The progress lines (`gen 12: mean fitness 1.19, best 1.32, spread 0.022, 15 s`) go to the terminal. *Mean fitness* is the score of the current best guess (1.0 = as good as the opponent); it jumps up and down by about ±0.1 from luck, so look at the trend over 10 generations.

### 6.4 Using a trained bot at the table (later)

`Profile.parse("file:priv/bots/tuned.json")` gives the profile. The GameServer stores an atom per bot seat (`:balanced`, `Profile.get/1`). To offer the trained bot in the lobby: add a profile name (for example `:expert`) whose fields `Profile.get/1` reads from the committed weights file at compile time (`@external_resource`), and add it to the bot pick on the configure screen. That touches `lib/quacks_web/**` and is left for after the UI refactor.

## 7. Next steps

1. Use `balanced+strong` (or the tuned weights) for the table bots after Nick's review.
2. Tune against a mix of opponents (`--opponent` per run, or a future option for a mixed field) so the bot does not over-fit to one style; check at 3 and 5 players too.
3. Shop rollouts (option B) for the last 3 rounds, where few futures are left and the value of a buy is easy to simulate.
4. Only then a learned value function for the shop (option D, §2.1): self-play data from the tuned bot, a ridge model first.

## Sources

- Quackulator (Set 1 solver and self-play, ridge value function on 45 features): https://github.com/coreyduval/Quackulator
- Cross-entropy method: Rubinstein & Kroese, *The Cross-Entropy Method* (2004); Szita & Lőrincz, "Learning Tetris Using the Noisy Cross-Entropy Method", Neural Computation 18 (2006).
- CMA-ES: Hansen, "The CMA Evolution Strategy: A Tutorial", arXiv:1604.00772.
- Nx / Axon / EXLA: https://github.com/elixir-nx; EMLX (MLX backend): https://github.com/elixir-nx/emlx
- Engine and bots: `lib/quacks/ai.ex`, `lib/quacks/ai/*.ex`, `lib/mix/tasks/quacks.bench.ex`, `lib/mix/tasks/quacks.tune.ex`.
