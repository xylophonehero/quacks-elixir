# Codex bot: diagnosis and a plan for a strong bot trained locally

Research date: 2026-10-17. Worktree `codex-game`. Scope: the first-game set-up (Neutral starter decks, Bashing/Troq Bashar as P1 against Finesse/River Montoya as P2, 1-hero mode). Red vs Green comes later.
Tags: **[M]** = measured on this engine (scripts in the session scratchpad, not committed). **[S]** = from a source. **[E]** = an estimate.
Related: `docs/research/codex.md` (rules), `docs/research/bot-training.md` and `docs/research/ai-opponents.md` (the Quacks bots: same method, same repo rules).

## 0. Short answer

- **The bot never builds a tech building.** `Codex.Bot.main/2` has no step for `{:build, _}`. So it can never play a tech I, II or III unit. It still techs 2 codex units every turn, and they stay in its hand as dead cards. This one gap is most of its weakness.
- **A 6-line fix wins 99.5–100 %** of games against the current bot, in both seats [M] (§1.3). After that, Bashing (P1) wins 95 % of the mirror games. The next work is to make the bot play well, not only legally.
- **Recommended path** (same as for Quacks, §5 of `bot-training.md`):
  1. Heuristic fixes: hire, build, a tech plan per spec, spend the gold, attack and patrol rules (§4.1).
  2. A state evaluator and a search over the **whole turn** (sampled action sequences, then one evaluator call at the end of the turn), within 500 ms per turn. ISMCTS with determinization only if the turn search stops to give gains (§4.2).
  3. Tune the evaluator and the plan numbers by self-play with the cross-entropy method, in a mix task, on the laptop (§4.3).
  4. A benchmark harness with duplicate seating, fixed seeds and 95 % confidence intervals for every change (§4.4).
- **No neural network now.** A linear evaluator with about 30 features, tuned by self-play, is the best cost/benefit. Revisit only when the tuned search stops to gain.

## 1. Diagnosis of the current bot

### 1.1 What `lib/codex/bot.ex` does

One action per call, from the `legal` list in the view. The priority order: hire (while fewer than 10 workers) → summon the hero → kill spells → attacks with a positive score → play the best card → abilities → level up the hero → fill patrol slots → end the turn. In the tech step: the pair of codex cards with the highest `tech_value` (units of the lowest tech first).

Gaps in the code:

- No `{:build, _}` case. Tech I, tech II, tech III, Tower and Surplus never happen.
- The hire rule puts the card with the **lowest cost** into the workers. Cost 1 cards are Timely Messenger, Tenderfoot and Spark. The community workers Helpful Turtle, Fruit Ninja and Spark first, and rates Timely Messenger "B" [S: card ratings].
- The tech step always takes 2 cards, also at 10 workers (`{:tech, []}` scores 0, so a pair always wins). The guide says: "Generally you should choose 0 at that point, to avoid bloating your deck" [S: teching guide].
- `tech_value` gives tech II units 4 + ATK when tech II is not built. The bot never builds it, so these cards are dead.
- No plan over a turn: each action is greedy. The order "level up before patrol" and "attack before play" is fixed.
- Level-up takes all the gold that is left. This is the only gold sink, so Troq goes to level 8 in every game.
- It reads the opponent's hand. `Codex.Game.view/2` hides only the decks (as counts); the hand, discard, codex and workers of the other side are in the map. The moduledoc says "no hidden information beyond what its view holds", but the view holds too much. A fair bot must use an information-set view (§4.2.3).

### 1.2 Bot against bot, 200 seeded games [M]

`Game.new(%{bot: true}, {seed, 7, 11})`, seeds 1–200, current bot in both seats.

| Metric | P1 Bashing | P2 Finesse |
|---|---|---|
| Wins | **164 (82 %)** | 36 (18 %) |
| Hires per game; turn it reaches 10 workers | 6.0; turn 6 | 5.0; turn 5 |
| Tech buildings built (all games) | **0** | **0** |
| End turns with a tech build legal but not taken | 78 % | 83 % |
| Codex cards teched per game | 24 (the whole codex) | 24 (the whole codex) |
| Codex units played (all games) | **0** | **0** |
| Mean hand at end of turn; of which dead units (tech too high) | 3.0; **2.35** | 2.85; **2.2** |
| Gold left at end of turn: mean; turns with ≥ 4 left | **9.9; 72 %** | **11.9; 80 %** |
| Hero: summons per game; level-ups per game; max level reached | 4.6; 23.5; 8.0 (max) | 4.2; 13.5; 5.0 (max) |
| Attacks per game: base / buildings / units | 4.1 / 0 / 12.4 | 4.2 / 0 / 10.9 |
| End turns with an attack still legal | 34 % | 39 % |
| Patrol moves per game | 19.1 | 22.5 |
| Abilities used (River's sideline, Maestro's wreck) | 0 | 0 |

Game length: 34.4 turns (both sides together; 17 each), median 33, range 16–63. 229 actions per game. All 200 games end. Decision time 2.6 µs.

What the bot plays: only the 10 starter cards and the codex **spells** (The Boot, Intimidate, Wrecking Ball, Discord, Harmony, Two Step, Appel Stomp, rarely Final Smash). Spells need no tech building, so they are the only codex cards that it can use.

### 1.3 The quick probe: what each fix is worth [M]

A wrapper around `Codex.Bot` (scratchpad `probe.exs`) with three switches:

- `build`: take `{:build, :tech_1}`, then `:tech_2`, then `:tech_3` when legal (after the hire).
- `tech`: tech by the guide's Bashing vs Finesse plan (§3.3); at 10 workers, tech 0 cards when the plan is done.
- `hire`: worker the cards in the community order (Turtle, Fruit Ninja, Spark, Flagbearer, ...).

| Probe (seat) | Opponent | Probe wins | Games |
|---|---|---|---|
| `build` (P1) | current bot | **200/200 (100 %)** | 200 |
| `build` (P2) | current bot | **199/200 (99.5 %)** | 200 |
| `build` (P1) | `build` | 95.0 % ± 2.1 | 400 |
| `build+tech` (P1) | `build` | 96.3 % ± 1.9 | 400 |
| `build+tech` (P2) | `build` | 11.5 % ± 3.1 (mirror: 5.0 %) | 400 |
| `hire+build+tech` (P1) | `build+tech` | 83.8 % ± 3.6 | 400 |
| `hire+build+tech` (P2) | `build+tech` | 2.5 % ± 1.5 | 400 |
| `hire` only (P1 / P2) | current bot | 93.0 % / 16.5 % (base 82 % / 18 %) | 200 each |

Findings:

- The build rule alone takes the game length from 34 to 16–18 turns, and wins almost every game.
- The guide's tech plan helps Finesse (+6.5 points) and Bashing a little.
- The community worker order **hurts** this bot (−11 and −2.5 points). The rest of the bot does not use the cards that the order keeps (it plays Fruit Ninja most of all). Lesson: expert rules do not transfer one by one. Measure every rule; let the tuning (§4.3) set the order.
- **Seat/spec balance:** with equal bots, Bashing wins 95 %. Sirlin says the first-game pairing is fair; so the bots play Finesse badly (Harmony, Two Step, Maestro, River's sideline need a plan), or the engine has a rules gap. Check the big Finesse cards against `docs/research/codex.md` before the tuning (§5, risk 1). Always measure in both seats.

### 1.4 Main weaknesses, in order

1. No tech buildings: 0 builds, 2.3 of 3 hand cards are dead, 0 codex units played.
2. Techs the whole codex (24 cards), also at 10 workers: the deck bloats.
3. Wastes gold: 10–12 gold left at the end of a turn (gold cap 20); level-up is the only sink.
4. No turn plan: 34–39 % of turns end with an attack still legal; no building attacks; no use of River's or Maestro's abilities.
5. Worker choice by cost: it workers the cheap good cards (Timely Messenger).
6. Reads the opponent's hand through the view (a fairness bug, not a strength bug).

## 2. Engine facts that decide the method [M]

- **Speed** (30 games, 6 806 actions, one core): `Rules.legal/1` 29 µs, `Game.view/2` 55 µs, `Game.apply/3` 91 µs (with `history: []`). So one step of a simulation costs about **120 µs**. One turn (about 7 actions) ≈ 1 ms. One full game (230 actions) ≈ 28 ms.
- In the 500 ms budget on one core: about **400 turn simulations** or about **17 full games**. Full-game rollouts are too slow for MCTS at the table; a search must stop at the end of the turn (or the next opponent turn) and call an evaluator.
- **History:** `Game.apply/3` pushes the state into `history` (50 states). A simulation must set `history: []` before each apply, or memory grows fast.
- **Throughput for training:** 200 bot games in 2.8 s on 4 jobs (≈ 70 games/s). A heuristic bot plays 1 000 games in about 15 s; a bot with a 50 ms turn search about 100× slower.
- **Bot state:** `Table.Server` keeps a bot state per seat (`bot_new/2` gets a seed, `bot_choose/3` returns the new state). Use it for the AI rng (`Table.Kit.Rng.fork/2`) and for a turn plan that is computed once and then played one action per tick (650 ms `bot_delay`).
- **Branching:** 11 legal actions at the start, often 30–80 in the mid game (plays × targets, attacks × targets, patrol × slots). A turn is a sequence of 5–15 actions, so the number of whole-turn sequences is very large. Most orders give the same end state (transpositions).

## 3. What good play looks like (sources)

### 3.1 Economy [S]

- "Hire a worker every turn until you get to 10." Do not skip a worker before 8 workers. Skip only for a big play: kill a tech building or a max-level hero. [S: workers guide]
- "Tech I at 6 workers, Tech II at 8 workers, Tech III at 10 workers." [S: workers guide] P1: tech I from turn 1, tech II from turn 3, tech III on turn 5. P2: tech I from turn 1, tech II on turn 2 or 3, tech III on turn 4. [S: teching guide]
- In this engine: tech I needs 6 workers and 1 gold, tech II 8 workers, tech I and 4 gold, tech III 10 workers, tech II and 5 gold (`Codex.Rules`, `@tech_needs`, `@build_gold`). Buildings finish at the end of the turn.
- Workers first: Helpful Turtle (D), Fruit Ninja (D+), Spark (D+). Keep Bloom (B), Timely Messenger (B), Wither (B−). [S: card ratings] (But see §1.3: measure it.)

### 3.2 Tech step [S]

- Tech 2 cards per turn while fewer than 10 workers (a rule). At 10 workers, usually tech 0 cards; a tech III or an ultimate is worth the bloat. [S: teching guide]
- Tech 1 copy of an answer card, unless it is versatile. [S: teching guide, reply]
- Tech a card about 2–3 turns before you can play it (a 4–5 card draw each turn brings it back after the reshuffle). Tech a spell while the hero is in the command zone, then summon. [S: teching guide]

### 3.3 Bashing vs Finesse tech plans (the guide's example) [S]

The turn is the turn that ends just before the tech step.

| Turn | Bashing | Finesse |
|---|---|---|
| 1 | Iron Man ×2 | Nimble Fencer, Discord |
| 2 | Revolver Ocelot, Intimidate | Nimble Fencer, Two Step |
| 3 | Rhinoceros, Hired Stomper | Maestro, Appel Stomp |
| 4 | Rhinoceros, Eggship | Grounded Guide, Cloud Sprite |
| 5 | Trojan Duck ×2 | Blademaster ×2 |

### 3.4 Card and hero notes [S]

- **Bashing:** Iron Man 3/4 for 3 is strong at tech I. Wrecking Ball (0 gold, 2 damage to a building) early on a tech building (5 HP): a destroyed tech building sets the opponent back a turn and deals 2 to the base; Brick Thief adds the last point. The Boot kills any early unit. Hired Stomper clears a unit when it arrives. Sneaky Pig gets past patrollers to a hero or a building. Trojan Duck is the closer (4 to a building on arrival and on attack, obliterate 2). [S: Sirlin, Bashing spec] One forum player puts Trojan Duck before Final Smash, because Troq rarely reaches max level in real games. [S: Red vs Green thread]
- **Troq:** rated F in the hero ratings ("not worth the gold" to level); Sirlin disagrees: "very much worth leveling up in Bashing vs Finesse". [S: hero ratings] Final Smash needs Troq at level 8 at the start of the turn: 2 + 7 gold, then 6 for the spell. [S: Bashing spec]
- **Finesse:** Virtuosos plan: Nimble Fencer gives Virtuosos haste (Tenderfoot is a Virtuoso); Maestro makes Virtuosos cost 0 and gives them "exhaust: 2 damage to a building" (no combat, no patrollers, also the base); Grounded Guide +2/+1 to Virtuosos. Harmony plan: each spell makes a Dancer (max 3); sacrifice Harmony → 3 Angry Dancers 2/1 unstoppable = 6 damage past the patrol. Appel Stomp ×2 chains. Against Bashing: River's level-3 sideline removes one big defender; swift strike (Blademaster) kills big units with no damage back. [S: Sirlin, Finesse spec]
- **River:** "fine filler"; her max band "doesn't provide significant payoff in most situations". [S: hero ratings]

### 3.5 Patrol and tempo (rules + general play) [S/E]

- The squad leader must be attacked first and has 1 armor; put the unit with the most HP there. The elite gets +1 ATK. Scavenger: 1 gold if it dies; technician: 1 card if it dies. Lookout: resist 1. [S: rulebook, `codex.md` §8]
- [E] Patrol only when the opponent can attack into it with a good trade; otherwise keep units ready to attack. An empty patrol lets every attacker hit the base or a tech building.
- [E] Tempo: a destroyed tech II building costs the opponent a turn of tech and 2 base HP. The bot should value enemy buildings and its own as part of the evaluator, not only the base.

## 4. Approaches and the recommended plan

### 4.0 The options

| Option | What it is | Fit for Codex | Cost | Risk |
|---|---|---|---|---|
| **A. Heuristic rules** | Hand-written rules per phase. | Large gain now (§1.3): build, tech plan, gold use. Limit: a person cannot weigh 30 board features well. | Hours per rule; µs per decision. | Low. |
| **B. Evaluator + turn search** | Score a state with a weighted sum of features. Generate many full-turn action sequences (greedy + random), simulate each, score the end state, play the best. | **Best fit.** The opponent acts only after `:end_turn`, so the whole turn is under the bot's control: a 1-turn search has no hidden-info problem inside the turn (only the own deck order, for draw effects). | 1–2 days. ≤ 500 ms per turn. | Medium: the evaluator is the weak point; fix by tuning (C). |
| **B2. 2-ply** | B, then the opponent's best reply turn with a cheap policy, then score. | Catches "my patrol dies to their attack" and the threat of a big unit. Needs a determinized opponent hand. | 10–50× B; fewer samples per turn. | Medium. |
| **C. Self-play tuning (CEM / CMA-ES / GA)** | The computer finds the weights of A and B by playing many games. | **Large and cheap**, proved on Quacks (+14 points of win rate at 4 players, `bot-training.md` §5). Hearthstone: an EA-tuned action-score agent was runner-up in the Hearthstone AI competition and held its own against MCTS agents [S: García-Sánchez et al.]. LOCM: evolved evaluators are the standard method [S: Miernik & Kowalski]. | Only CPU: hours on 4 cores. | Low. Over-fits to one opponent: tune against a mix. |
| **D. ISMCTS with determinization** | Sample the hidden cards, search a tree of action sequences over several turns, average over samples. | Strong in MTG and Hearthstone research [S: Cowling/Ward/Powley; Santos et al.; Zhang]. But here a full rollout costs 28 ms: at 500 ms only ~17 per move, too few. Works only with an evaluator at a cut-off depth, so it needs B's evaluator first. | 3–5 days. | High: slow, hard to debug; gain over B is small at this budget. |
| **E. Neural net (value or policy)** | Learn the evaluator from millions of self-play positions (Nx/Axon, or Python with weights exported to a data module). | Possible later step for the evaluator. A linear model already gets most of it (Quackulator v2: ridge on 45 features, `bot-training.md` §2.1). | Days; new deps (EXLA) or a Python sidecar. | High. |

### 4.1 Stage 1: heuristic fixes (rules)

Put them in `Codex.Bot` (or a new `Codex.AI.Plan` used by it). Each rule has a number that stage 3 can tune; the start values are below.

1. **Hire:** hire every turn while workers < 10 (`hire_until: 10`). Skip the hire only when the gold for the hire makes a lethal attack or a kill on a tech building impossible. Worker choice: a score per card = `worker_keep[slug]` + a penalty for tech too high for the next 2 turns; worker the lowest. Start `worker_keep` from the card ratings, but let the tuning set it (§1.3 shows the hand order hurts now).
2. **Build:** after the hire, build tech I when legal (6 workers); tech II when legal (8 workers, 4 gold), before any play; tech III when legal and a tech III card is in the deck or discard. Add-on: Tower when the opponent has stealth or invisible cards in its codex/discard (Sneaky Pig, Backstabber) and 3 gold are spare; else Surplus at 10 workers when 5 gold are spare.
3. **Tech plan:** a list per spec (§3.3) as the start; at 10 workers tech 0 cards when the list is done; exceptions: tech III and ultimate. Store it as data: `Codex.AI.TechPlan` (`%{"Bashing" => [...], "Finesse" => [...]}`), not in logic.
4. **Play units before levels:** units and buildings first, then spells with a target, then level-up. Level-up only while the hero is alive and: (a) the next band is 1–2 levels away, or (b) the gold has no other use this turn. Troq: aim for level 5 (base ping) early; level 8 only when Final Smash is in the deck. River: level 3 (sideline) when the enemy squad leader is a tech 0/I unit.
5. **Attacks:** order the attacks: kill the squad leader first (it guards the rest), then free kills, then buildings when the patrol is empty or dead. Use Wrecking Ball/Brick Thief/Maestro's wreck on a tech building with ≤ 2/≤ 3 HP left (destroys it: −2 base HP, opponent loses a turn of tech). Hit the base when no patroller is left.
6. **Patrol:** patrol only when the opponent has ready attackers that could hit the base or a tech building. Squad leader: the most HP + armor. Do not patrol a unit that dies to one enemy attacker for nothing; keep a 1-HP unit in the scavenger or technician slot (it gives gold or a card when it dies).
7. **Use the abilities:** River's sideline on the enemy squad leader before the attacks; Maestro's wreck on buildings; Harmony: play cheap spells to make Dancers, sacrifice Harmony when 3 Angry Dancers (6 unstoppable) kill a building or the base.
8. **Gold check:** at end of turn, if gold ≥ 3 and a legal play exists, play it. Target: mean gold left < 3.
9. **Fair view:** build the bot's view from public data only (§4.2.3).

Expected result [E]: against the current bot ≈ 100 % (already shown by the probe); the real target is the probe `build+tech` bot as the new baseline.

### 4.2 Stage 2: evaluator + whole-turn search (≤ 500 ms per turn)

#### 4.2.1 The evaluator `Codex.AI.Eval.score(game, seat) :: float`

A weighted sum of features of the side minus the same for the opponent (about 30 numbers). Weights in a data module (§4.3.4).

- Base HP (with a steep term near 0: `w * hp + w2 * min(hp, 6)`), tech buildings and add-on (built, pending, HP left), workers (up to 10), gold (small; it carries over, cap 20).
- Board: for each unit/hero in play: ATK, HP left, armor, keywords (flying, stealth, invisible, swift strike, overpower, haste, readiness, unstoppable), ready or exhausted; hero level and band; the patrol (squad leader HP + armor; empty patrol when the opponent has attackers).
- Threat: the damage that the opponent's ready forces can deal to my base next turn through my patrol (a cheap greedy count), and the same for me. The 2-ply effect without the 2-ply cost.
- Cards: hand size; "live" cards in hand (cost ≤ next-turn gold and tech ≤ built); deck + discard size (bloat penalty); key cards teched (tech III, ultimate).
- A win is +∞ (`base_hp ≤ 0`).

#### 4.2.2 The turn search `Codex.AI.TurnSearch`

1. At the start of the bot's main phase, take the state `g` (determinized, §4.2.3).
2. Make candidate turns: the stage-1 policy (one sequence); then N sequences from a **softmax over the policy scores** (temperature τ) with `Rng` from the bot state; also a few with fixed macro choices (hire yes/no, build yes/no, level-up stop at band k, patrol none/all).
3. Each candidate runs with `Game.apply/3` (history off) until `:end_turn`, then the tech step by the plan, then the cleanup (draw). Score with `Eval.score/2`.
4. Play the best sequence: store it in the bot state, give one action per `bot_choose/3` call. If an action is not legal any more (it should not happen in a deterministic turn; draw effects can change the hand), search again from the current state.
5. Budget: stop at 400 ms (`System.monotonic_time`) or at N_max = 300 sequences. In training, use a **fixed N** (not time) so the result is deterministic given the seed.

Why this first: the turn belongs to the bot, so no opponent model is needed inside it. It finds order effects (patrol after attacks, River's sideline before attacks, spells before the Harmony sacrifice), and uses all the gold. Card-game bots with a one-turn search and a hand-made evaluator, such as the LOCM competition winner (alpha-beta at fixed depth with an evaluator) [S: Coac/locm] show that this is strong in card games of this type.

**Stage 2b (2-ply), only if the threat feature is not enough:** for the top 5 candidates, simulate the opponent's next turn with the stage-1 policy on K = 4 determinized hands; score the mean. Cost ≈ 20 turn simulations per candidate: fits in 500 ms for 5 candidates.

#### 4.2.3 Hidden information and determinization

- Hidden from the bot in real play: the opponent's hand, deck order, face-down discard (tech picks), workers, codex picks; its own deck order.
- `Codex.AI.Infoset.view(game, seat)`: the view with these parts replaced by counts. Use it for the stage-1 bot too (fixes weakness 6).
- `Codex.AI.Determinize.sample(view, rng) :: %Codex.Game{}`: the opponent's unknown cards = its starter cards + the codex cards it can have teched (24 − codex left), minus the cards seen in play, discard face-up and trash; deal them at random into hand (known size), deck (known size) and discard. Own deck: shuffle the known contents. Use `Table.Kit.Rng` only.
- Ensemble determinization (sum the action values over several samples) beat an expert rule player in MTG [S: Cowling, Ward, Powley 2012]. ISMCTS (one tree over information sets) is the better form for deep search [S: Cowling, Powley, Whitehouse 2012]; with determinization take care of "strategy fusion" (the search assumes it knows the cards).

#### 4.2.4 ISMCTS (stage 4, optional)

Only when stage 3 stops to gain. Single-observer ISMCTS over **macro actions** (a whole own turn = one sampled candidate from §4.2.2; the opponent's turn = one policy sample), depth 2–3 turns, evaluator at the leaf, no full rollouts. At ≈ 1 ms per turn simulation: about 150 iterations of depth 3 in 500 ms. Gain over stage 2b is not sure [E]; measure it with §4.4.

### 4.3 Stage 3: self-play tuning (locally)

#### 4.3.1 Method

The cross-entropy method of `Quacks.AI.Tune` (`lib/quacks/ai/tune.ex`): 24 candidates around a mean, each plays a fixed seed set, keep the best 6, move the mean and the spread, save a checkpoint each generation. It copes with noise and gives a readable list of numbers. CMA-ES adds little for 30–60 noisy numbers (`bot-training.md` §5.1). TD learning of the evaluator weights (from self-play positions, target = the result) is a good second step for the evaluator alone, because it uses every position, not only the result [E].

What to tune (about 40–60 numbers): the evaluator weights (§4.2.1), `worker_keep` per starter card (10), level-up targets per hero, the softmax temperature, the tech plan as a score per codex card per turn band (not a fixed list).

#### 4.3.2 Cost on the laptop

| Bot in the games | Games/s (4 jobs) | 1 generation (24 × 400 games) | 100 generations |
|---|---|---|---|
| Stage 1 (µs per decision) | ≈ 70 [M] | ≈ 2.5 min | ≈ 4 h |
| Stage 2 with N = 30 sequences/turn (≈ 30 ms/turn) | ≈ 3–4 [E] | ≈ 50 min | not practical |

So: tune stage 1 and the **evaluator inside a cheap search** (N = 10–20, or a greedy 1-step look-ahead: try each legal action, score the state after it). Then benchmark the full stage-2 bot (N = 300) against it. The evaluator transfers; the N does not need tuning. Use the 2-player duplicate seating (each seed in both seats), 200 seeds per candidate (400 games), and check on new seeds.

Run as in `bot-training.md` §6: `nice -n 10`, `--jobs 4`, `--minutes`, resumable checkpoint, stop by PID only.

#### 4.3.3 Fitness

Win rate over both seats against a **field**: the current bot (10 %), the probe/stage-1 bot (40 %), the current best tuned bot (50 %). Score = mean win rate (P1 and P2 games equal). A tie (no winner after N actions) = 0.5; log the count of ties, it shows stalls.

#### 4.3.4 Where the weights live

- During a run: `priv/bots/codex-tune-checkpoint.json` (not committed) and `priv/bots/codex-tuned.json`.
- After a benchmark on new seeds: generate a data module `lib/codex/ai/weights_data.ex` (`def weights, do: %{...}`) with `mix codex.tune --export`, or read the JSON at compile time with `@external_resource` (the Quacks pattern, `bot-training.md` §6.4). The data module is the source of truth in git; a person reads the diff.

### 4.4 Benchmark harness `mix codex.bench`

- `Codex.AI.Bench.run(bots: [a, b], games: n, seed: s, jobs: j)`. Every seed is played twice: bot A as P1 and as P2 (duplicate seating). Report per bot: win % with 95 % CI (one seed = one sample, as in `Quacks.AI.Bench.ci/1`), win % per seat, mean turns, ties/stalls, mean decision and turn time (mean and max), gold left at end of turn, tech buildings per game.
- Fixed seeds: tuning seeds 1–1000; benchmark seeds from 10 001; never mix.
- Size: 1 000 games (500 seeds × 2 seats) gives a CI of about ± 3 points near 50 %; 4 000 games ± 1.5.
- Bot specs as text: `old`, `probe`, `rules`, `search:300`, `file:priv/bots/codex-tuned.json`.
- Determinism: the same seed gives the same numbers for any `--jobs` (each game has its own seed; the bot rng is forked from the game seed with `Table.Kit.Rng.fork/2`). The time budget is off in the bench (fixed N).
- A test: two copies of the same bot are at exact parity over duplicate seating.

## 5. Risks and checks

1. **Spec imbalance (95 % for Bashing in the mirror).** Before tuning, check that Finesse's key cards work as the rules say (Maestro's free Virtuosos and wreck, Harmony's Dancers and "stop the music", Two Step, Appel Stomp, Blademaster's swift strike, River's sideline) with targeted tests. A tuned bot against an engine bug learns the bug.
2. **Over-fit to one opponent.** Use a field of opponents (§4.3.3) and check against the old bot and the probe.
3. **Server time.** The search runs in the `Table.Server` process. Search once per turn (≤ 400 ms), then play the plan one action per tick. Or run the search in a `Task` under the room's supervisor and keep the tick; do not block longer than one tick.
4. **Fairness.** The search must use only `Infoset.view/2` + determinization, never the true `game` (decks, opponent hand). A test: the bot's choice is the same for two games that differ only in hidden cards.
5. **Card coverage.** The heuristics name cards by slug. Red vs Green adds 3 specs per side; keep card knowledge in data (`TechPlan`, `worker_keep`, evaluator keyword weights), so stage 3 can tune it for new decks.

## 6. What exists and what is new

**Reuse:**

- `Codex.Rules.legal/1`, `Codex.Game.apply/3`, `Codex.Game.view/2`, `Codex.Rules.all_stats/1` (ATK/HP now), `Codex.Combat` (attack targets), `Codex.Stats` (keywords).
- `Table.Kit.Rng` (`seed/1`, `uniform/2`, `shuffle/2`, `fork/2`): all AI randomness.
- `Table.Server` bot API: `bot_levels/0`, `bot_new/2` (seeded state), `bot_choose/3`, `bot_delay/1`. Add `:strong` next to `:basic` in `Codex.Table.bot_levels/0`.
- `Quacks.AI.Bench` (duplicate seating, `ci/1`, `--jobs`, `--minutes`, progress line) and `Quacks.AI.Tune` (CEM, checkpoint JSON): copy the pattern; or extract the game-free parts (`ci/1`, the job pool, the CEM update) to `Table.Kit.AI` and use them from both games.
- `mix quacks.bench` / `mix quacks.tune` option sets (same flags for the Codex tasks).
- `test/codex/bot_test.exs` (`play_out/2`, `assert_conserved/1`): keep it green for every bot level.

**New:**

- `lib/codex/ai/infoset.ex`, `determinize.ex`, `eval.ex`, `turn_search.ex`, `tech_plan.ex` (data), `weights_data.ex` (data), `bench.ex`, `tune.ex`.
- `lib/mix/tasks/codex.bench.ex`, `lib/mix/tasks/codex.tune.ex`.
- Changes in `lib/codex/bot.ex` (stage 1) and `lib/codex/table.ex` (`:strong` level, seeded bot state).

## 7. Plan and order of work

| Step | Work | Done when | Effort [E] |
|---|---|---|---|
| 1 | `Codex.AI.Bench` + `mix codex.bench` (duplicate seats, CI, fixed seeds) | Old bot vs old bot at exact parity; numbers of §1.2 come out again | 0.5 day |
| 2 | Finesse card checks (§5.1) | Tests for the 7 Finesse mechanics pass, or the bugs are fixed | 0.5 day |
| 3 | Stage 1 rules (§4.1) + `Infoset.view` | ≥ 99 % vs old; ≥ 60 % vs probe `build+tech` over both seats; gold left < 3 | 1–2 days |
| 4 | `mix codex.tune` on stage-1 numbers | Tuned ≥ 55 % vs untuned stage 1 on new seeds | 0.5 day + overnight run |
| 5 | `Eval` + `TurnSearch` (fixed N in bench, 400 ms at the table) | ≥ 65 % vs tuned stage 1; max turn time < 500 ms | 2 days |
| 6 | Tune `Eval` weights inside a cheap search (N = 10–20) | Search bot with tuned weights ≥ 55 % vs step 5 | 1 day + overnight runs |
| 7 | Optional: 2-ply (2b), then ISMCTS (§4.2.4) | Each ≥ 55 % vs the step before, or drop it | 2–5 days |

Keep the engine pure and the bot deterministic for a given seed (except the wall-clock stop at the table). No `Enum.random`, no `Enum.shuffle`, no `:rand.uniform/1` in `lib/codex/ai/*`.

## Sources

Codex strategy:
- Collected Codex Resources (index): https://forums.sirlingames.com/t/collected-codex-resources/860
- Beginner's Guide to Workers: https://forums.sirlingames.com/t/guide-beginners-guide-to-workers/1003
- Beginner's Guide to Teching (Bashing vs Finesse tech plan): https://forums.sirlingames.com/t/guide-beginners-guide-to-teching/1421
- Card ratings, starter decks: https://forums.sirlingames.com/t/card-ratings-the-starter-decks/171
- Card ratings, heroes (and Sirlin's reply on Troq): https://forums.sirlingames.com/t/card-ratings-the-heroes/172
- Sirlin, "Codex: Bashing spec": https://www.sirlin.net/posts/codex-bashing-spec
- Sirlin, "Codex: Finesse spec": https://www.sirlin.net/posts/codex-finesse-spec
- Strategy for Red vs Green (Trojan Duck over Final Smash): https://forums.sirlingames.com/t/strategy-for-red-vs-green/1010?page=2

Game AI:
- Cowling, Powley, Whitehouse, "Information Set Monte Carlo Tree Search", IEEE TCIAIG 4(2), 2012: https://eprints.whiterose.ac.uk/id/eprint/75048/
- Cowling, Ward, Powley, "Ensemble Determinization in MCTS for the Imperfect Information Card Game Magic: The Gathering", IEEE TCIAIG 2012: https://eprints.whiterose.ac.uk/75050/
- Ward, Cowling, "Monte Carlo search applied to card selection in Magic: The Gathering", CIG 2009: https://dblp1.uni-trier.de/rec/conf/cig/WardC09.html
- Browne et al., "A Survey of Monte Carlo Tree Search Methods", IEEE TCIAIG 2012: https://turing.iimas.unam.mx/~luis/cursos/IA2022-1/lecturas/SurveyMCTS.pdf
- Santos et al., "Monte Carlo Tree Search Experiments in Hearthstone", IEEE CIG 2017: https://research.ou.nl/en/publications/monte-carlo-tree-search-experiments-in-hearthstone/
- Zhang, determinized MCTS for Hearthstone with learned rollout policies, MSc thesis, U. Alberta 2017: https://era.library.ualberta.ca/files/cv979v349b
- García-Sánchez, Tonda, Fernández-Leiva, Cotta, "Optimizing Hearthstone agents using an evolutionary algorithm", Knowledge-Based Systems 2020: https://arxiv.org/abs/2410.19681
- Miernik, Kowalski, "Evolving Evaluation Functions for Collectible Card Game AI": https://arxiv.org/abs/2105.01115
- Kowalski, Miernik et al., "Summarizing Strategy Card Game AI Competition": https://arxiv.org/abs/2305.11814
- LOCM winner (alpha-beta at fixed depth + evaluator): https://github.com/Coac/locm
- Świechowski, Tajmajer, practical MCTS under hidden information (Annals of CSIS 25): https://annals-csis.org/Volume_25/pliks/3.pdf
- Forge (MTG) AI wiki and AI-vs-AI `sim` mode: https://github.com/Card-Forge/forge/wiki/ai
- CMA-ES tutorial (Hansen): https://arxiv.org/abs/1604.00772

Repo: `lib/codex/bot.ex`, `lib/codex/rules.ex`, `lib/codex/game.ex`, `lib/codex/table.ex`, `lib/table/server.ex`, `lib/table/kit/rng.ex`, `lib/quacks/ai/bench.ex`, `lib/quacks/ai/tune.ex`, `lib/mix/tasks/quacks.bench.ex`, `lib/mix/tasks/quacks.tune.ex`.
