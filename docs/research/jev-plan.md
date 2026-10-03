# Jev in the bot logic, or algorithmic decisions?

Research date: 2026-10-04. Prototype: branch `ai-ev` (worktree `.claude/worktrees/ai-ev`), not merged.
Tags: **[M]** = measured with `Quacks.AI.Sim` on this engine. **[D]** = from the Jev or TypeSafe docs. **[E]** = from this engine.

## 0. Short answer

- **Jev is not a chat LLM.** It is a "decision model": you send a state and typed questions (choice, score, yes/no), and you get back labels with calibrated probabilities. It never writes text. It is weak at numbers and counting (§1.4).
- **Most bot decisions are arithmetic.** Of 27 decision points, 8 are obvious, 10 are computable from the open bag, 5 are weighted heuristics and 4 are judgement-like (§2).
- **The exact draw/stop rule wins.** A depth-3 expected-value search beats the tuned threshold bot: 55–56 % wins in 2-player games (parity 50 %) and 29 % in 4-player games (parity 25 %), +1.3 to +2.1 VP. It takes 19 µs per decision on average (§3).
- **A static table is enough for the judgement-like choices.** A value table beats the current random fortune choices by +0.3 to +0.6 VP in the base game and by +1.2 to +1.6 VP with the expansions. Random choices lose 4–5 VP with the expansions. So the choices matter, but a 60-line table gets most of the gain (§4).
- **Recommendation:** Phase 0 now: EV draw/stop and the static scorer. Jev is not needed for strength. Use it only if Nick wants bots that "feel" different, behind `Quacks.AI.Decider` with `Quacks.AI` as the fallback (§5).

## 1. Jev

### 1.1 What it is

- **[D]** "Jev for Elixir" (https://www.jev.store/projects/jev-elixir) is the Hex package `jev` by Danila Poyarkov (https://github.com/dannote/jev), MIT licence, version 0.2.3 (2026-09-27), 34 stars. It is a client for **TypeSafe Jev** (https://docs.typesafe.ai) and for other servers that speak the same `/v1/systemone` wire format (Laya, kev, decider, jeff; `jev_nx` runs open models in-process on Nx).
- **[D]** TypeSafe calls Jev a "System One" model: "fast, structured decisions for software". It "evaluates typed questions against a state and returns structured results directly". It does not generate text: "Jev does none of that" (stream text, call tools).
- **[D]** It is **not an agent framework** and **not a general LLM client**. It is a decision primitive.

### 1.2 API shape

Three question types, written as shorthand in a keyword list:

```elixir
security: "Is this a vulnerability?"                                         # Noul   -> probability of yes
kind:     {"What kind of issue?", %{bug: "Broken", feature: nil, other: nil}} # Choice -> label atom
severity: {"How severe?", ["Cosmetic", "Workaround", "Blocks", "Data loss"]}  # Score  -> expected level (float)
```

The reply is a plain map:

```elixir
%{kind: :bug, severity: 2.4, security: 0.03,
  confidence: %{kind: 0.91, severity: 0.62},
  probabilities: %{kind: %{bug: 0.93, feature: 0.04, other: 0.03}, ...},
  usage: %{input_tokens: 812, output_tokens: 0, cost: 3.4e-5},
  model: "jev-1.13.0"}
```

- **[D]** Labels come back as atoms, but only the criteria keys can become atoms (safe).
- **[D]** Two ways to call it:
  - `Jev.HTTP.post(state, questions, opts)` → `{:ok, reply} | {:error, %Jev.Error{}}`. Synchronous, Req-based, retries 429/529/502/503/504 with backoff.
  - `use Jev.Server`: a GenServer. A callback returns `{:reply, {tag, state, questions}, s}`; the answer arrives later in `handle_answer(reply | {:error, reason}, tag, state)`. Requests run under a `Task.Supervisor`, so a crash becomes `{:error, reason}`. The server never blocks.
- **[D]** `Jev.Backend` (one callback, `post/3`) swaps the transport, e.g. for a fake or an in-process model.

### 1.3 Providers, cost, latency, limits

| Item | Value | Source |
|---|---|---|
| Provider | TypeSafe (`https://api.typesafe.ai`, key `TYPESAFE_API_KEY`), or any `/v1/systemone` server as a named endpoint | README |
| Model | `jev-latest` → `jev-1.13.0` | docs/models |
| Price | $0.042 per million input tokens; output tokens free | docs/models |
| Rate limits | 100k tokens/s, 80 requests/s ("adjusting dynamically") | docs/models |
| Context | 64k tokens per request; 32k for state + longest question | docs/models |
| Latency | 0.27 s for one call with 13 questions on a ~12k-token article; 0.21 s per single-question call (2.71 s / 13) | cookbook "Parallel questions" |
| Structured output | Always: every answer is typed (label, level, probability) with confidence | docs |
| Determinism | No seed or temperature parameter documented. `jev-latest` moves on new releases; pin `jev-1.13.0` for stable answers | docs/models |

### 1.4 Known weak spots (from TypeSafe's own "jaggedness" page)

- **[D]** "It struggles with tasks that require numeric precision." "`jev-1.13` does not count reliably." "Keep the arithmetic in code."
- **[D]** It is better on semantic text than on numbers: score levels are "weak in numerical calibration".

For Quacks this is decisive: draw/stop, flask and explosion choices are pure arithmetic over the bag. Jev must not do them.

### 1.5 Inside a GenServer tick

- **[D]** `config :jev, receive_timeout: 30_000, max_retries: 3` are the defaults; both can be set per endpoint. For a bot tick, set `receive_timeout: 600` and `max_retries: 0`.
- The bot tick in `Quacks.GameServer` is ~0.7 s. A Jev call is 0.2–0.3 s. It fits, but only with a cap and a fallback (§5).

### 1.6 Testing without the network

- **[D]** `handle_answer/3` is a plain function: tests call it with a literal map.
- **[D]** Transport tests: `config :jev, req_options: [plug: {Req.Test, Jev.HTTP}, retry_delay: 0]`, then `Req.Test.stub(Jev.HTTP, &Jev.Test.respond(&1, kind: :bug))`. `Jev.Test.request/1` reads the request, so a stub can answer by state. `Jev.Test.error/3` sends failures.
- **[D]** A `Jev.Server` posts from a task, so tests need `Req.Test` shared mode and `async: false`.
- For replay: record `{state_hash, questions, reply}` per decision in the game log, and replay from the log (never ask again).

### 1.7 Dependency weight

- **[D]** Runtime deps: `req ~> 0.7.4` (we have 0.7.4), `json_codec ~> 0.2.6` (new), `telemetry ~> 1.4` (we have it), `plug` optional (we have it). One new small package.
- **[D]** Needs Elixir 1.18 and OTP 27 (built-in `JSON`). We run 1.18.3 / OTP 27, but `mix.exs` says `elixir: "~> 1.17"`; raise it to `~> 1.18` when we add Jev.

## 2. Decision inventory

Every bot decision point in `lib/quacks/ai.ex`, `lib/quacks/ai/shop.ex` and `docs/research/ai-opponents.md` §2.

| # | Decision (phase / action) | Class | Today | Note |
|---|---|---|---|---|
| 1 | `:yellow_choice` return the white | a | always return | strictly better |
| 2 | `:red_choice` (R2) place | a | place | a free move |
| 3 | Red Set 6 chips set aside: place first | a | place | a free move |
| 4 | `:ear_worm` draw | a | only action | one legal action |
| 5 | `:essence_offer` hump/carrot | a | take hump | free gain |
| 6 | `:droplet_choice` tube vs pot | a | tube to glass 12 | fixed rule |
| 7 | Round 9 shop: `{:rubies, :vp}` | a | always | nothing else to buy |
| 8 | `:stopped` → `:resume` | a | never | v1 policy |
| 9 | Draw or stop (`:potions`, also round-9 stir) | b | threshold | **EV prototype, §3** |
| 10 | Flask on the newest white | b | `flask_min_white` + threshold | **EV prototype, §3** |
| 11 | Card B10 return the white | b | threshold | EV prototype |
| 12 | Card B3 restart after 5 chips | b | never | EV of a new start vs the pot |
| 13 | `:blue_choice` which chip | b | furthest safe | exact with the white room |
| 14 | `:explosion_choice` VP or coins | b | round rule | `value()` from §3 |
| 15 | B7 Safety Procedure place | b | random (undominated) | move vs explosion, exact |
| 16 | Silver witch S1 (flask after explosion) | b | never | same as the flask EV |
| 17 | Y6 `{:chip, :yellow_ruby}` | b | first (take) | 3 spaces vs 1 ruby |
| 18 | Locoweed 5 `{:chip, {:return, c}}` | b | first | chip back in the bag vs its space |
| 19 | Shop buy | c | `Shop.score` weights | tuned |
| 20 | Rubies: flask or droplet | c | `ruby_plan` | tuned |
| 21 | Patient choice (The Alchemists) | c | fixed order | needs a value per patient |
| 22 | Essence bonus (swap / buy) | c | first swap / best buy | shop weights |
| 23 | Copper witches C1–C4 in the shop | c | never called | timing + shop weights |
| 24 | Fortune choices (P1, P3, P6, P9, P10, P11, P13, B2) | d | random, not dominated | **static scorer, §4** |
| 25 | Chip choices across books (G2, G4, P2, P4, G5, P5) | d | first | **static scorer, §4** |
| 26 | Witch calls: gold now or later, silver S2/S3/S4 | d | gold: take; silver: never | timing over the game |
| 27 | Essence: a lower space | d | furthest | **static scorer, §4** |

Counts: **(a) 8, (b) 10, (c) 5, (d) 4.**

### 2.1 The (d) decisions: what an LLM would need, and can a table do as well?

| Decision | Prompt needs | Static function? |
|---|---|---|
| Fortune choices | the card text, round, own VP/rubies/coins, own bag summary (whites, counts per colour), score gap, the legal options as an enum | Yes. Each option is a VP-equivalent: chip = price × coin weight, ruby, VP, droplet = spaces × rounds left. Measured in §4. |
| Chip choices | the book text, round, own bag, the options | Yes, the same table (chip worth, trade value). |
| Witch calls | the witch text, round, rounds left, own pot and bag, the score gap, "one use per game" | Mostly. Gold G1–G3 are only offered when they pay; "now vs later" is a threshold on round and gain. Silver S2/S3/S4 are EV questions (b) in disguise. |
| Essence lower space | the essence track, what each space gives, own patient | Yes; the furthest space was the best in the measurement. |

Jev would get a JSON state (round, VP, gap, bag counts, card text) and one `Choice` question over the legal options. But Jev itself says to keep arithmetic in code, and every option here is an arithmetic trade (VP vs rubies vs chips). A static scorer does as well or better, and it is free, instant and deterministic.

## 3. Prototype: exact draw/stop by expected value

### 3.1 Code (branch `ai-ev`)

- `Quacks.AI.Expectimax` (`lib/quacks/ai/expectimax.ex`): `ev/3` returns `%{stop: v, draw: v}`; `draw?/3`; `after_return/4` for the flask and B10; `space_value/3`.
  - The bag is a multiset: `%{value => count}` for whites and for coloured chips. Whites are exact; a coloured chip is a safe move of its value (no effects), as in Quackulator.
  - `value(space, round) = coin_weight[round] * coins + vp + ruby_value * ruby`. An explosion pays the coins or the VP (the profile's explosion rule: coins before round `explode_vp_from`) plus the ruby. The exploding chip is placed (the engine does this too).
  - `best(pot, d) = max(stop, mean over the bag of best(pot after the chip, d - 1))`, memoised on `{whites, coloured, index, white_sum, depth}`. Default depth 3.
- `Quacks.AI.Profile` new fields: `stop_rule: :threshold | :ev`, `flask_rule: :heuristic | :ev`, `choice_rule: :default | :random | :scored`, `ev_depth`, `coin_weight`, `ruby_value`, `flask_cost`. Defaults keep today's behaviour (`:threshold`, `:heuristic`, `:default`).
- `Quacks.AI.Profile.parse/1` and `mix quacks.sim --profiles balanced,balanced+ev`: modifiers `ev`, `flaskev`, `random`, `scored`, `d1`–`d5`.
- Flask rules: `:heuristic` = white ≥ `flask_min_white` (any in round 9) and the stop rule would draw again after the return. `:ev` = the best play after the return beats a stop now by more than `flask_cost` (2.0 VP = 2 rubies; 0 in round 9).
- Tests: `test/quacks/ai/expectimax_test.exs` (12 tests, 3 doctests, 1 property over the new variants with Sets 2–6 and both expansions).

### 3.2 Tuning (seed 3, so seeds 1 and 2 stay clean)

4000 games per line, the variant in each seat in turn, against `balanced` (threshold).

| Weights | 2p win % | 4p win % | Explosion % |
|---|---|---|---|
| `coin_weight` 0.5 → 0.15, ruby 0.5 (first guess) | 51.4 | 24.6 | 18.6 |
| same, depth 1 | 48.1 | 19.9 | 15.0 |
| same, depth 2 / 5 | 51.3 / 51.5 | 24.5 / 24.5 | 18.4 / 18.6 |
| ×1.5 early, ruby 1.0 | 54.1 | 28.6 | 32.8 |
| ×3 early, ruby 1.0 | 50.7 | 25.2 | 41.3 |
| **1.5, 1.4, 1.2, 1.0, 0.8, 0.5, 0.25, 0.12, 0.2; ruby 1.0** | **56.0** | **29.8** | **34.4** |

- Depth 2 and deeper are equal; depth 1 loses (agrees with Quackulator: two draws of look-ahead are enough).
- The first guess was too careful (19 % explosions). Coins early are worth more than 1 VP: higher early coin weights take more risk and win more, up to a point.

### 3.3 Head-to-head (seeds 1 and 2, the handoff's runs)

1000 games per line; the variant sits in each seat in turn (500 or 250 games per seat), the other seats are `balanced` with the threshold rule. Command: `mix run h2h.exs 1000 <seed>` (session scratchpad, not committed; it calls `Sim.run/1` with rotated `profiles:`). The mix task gives the same picture without rotation: `mix quacks.sim --games 1000 --profiles balanced+ev,balanced --seed 1` → ev 60.6 VP, 55.1 % wins.

| Variant | Seed | Players | VP (variant vs others) | Win % (parity) | Explosion % (variant vs others) |
|---|---|---|---|---|---|
| control (threshold vs threshold) | 1 | 2 | 59.0 vs 59.0 | 49.9 (50) | 34.6 vs 34.6 |
| control | 1 | 4 | 51.6 vs 51.6 | 24.8 (25) | 38.4 vs 38.5 |
| **ev** | 1 | 2 | **61.1 vs 59.0** | **55.8** (50) | 34.2 vs 35.1 |
| **ev** | 1 | 4 | **52.9 vs 51.5** | **29.2** (25) | 37.1 vs 38.8 |
| **ev** | 2 | 2 | **60.9 vs 59.0** | **55.1** (50) | 34.3 vs 35.1 |
| **ev** | 2 | 4 | **52.9 vs 51.6** | **29.0** (25) | 37.2 vs 38.8 |
| ev + flask EV | 1 | 2 | 60.4 vs 58.8 | 54.2 | 33.9 vs 34.7 |
| ev + flask EV | 1 | 4 | 52.8 vs 51.4 | 29.5 | 35.9 vs 39.0 |
| ev + flask EV | 2 | 2 | 60.3 vs 58.9 | 53.4 | 33.9 vs 34.7 |
| ev + flask EV | 2 | 4 | 52.9 vs 51.4 | 29.4 | 35.9 vs 39.0 |
| threshold + flask EV | 1 | 2 | 59.7 vs 58.9 | 52.9 | 33.5 vs 34.6 |
| threshold + flask EV | 1 | 4 | 51.8 vs 51.4 | 26.0 | 37.1 vs 39.0 |
| threshold + flask EV | 2 | 2 | 59.8 vs 59.0 | 53.4 | 33.3 vs 34.7 |
| threshold + flask EV | 2 | 4 | 51.8 vs 51.5 | 25.8 | 37.2 vs 39.0 |

- **[M]** EV draw/stop wins clearly: +5 to +6 points of win rate in 2p, +4 in 4p (about 20 % more wins than parity), on both seeds.
- **[M]** The total explosion rate stays near 34 %, but the shape changes: the EV bot explodes in 91 % of round-1 brews and 69 % of round-2 brews (an early explosion keeps the coins), then only 12–20 % in rounds 5–9 (threshold: 35/46/47/53 % in rounds 1–4, 20–24 % late). This is the Quackulator pattern (S1 maxim 3).
- **[M]** The flask rule hardly matters. The EV flask rule uses the flask 0.32 times per game (heuristic: 1.06), and `flask_cost` 1–4 VP gives the same results. With the EV stop rule it costs 1.6–1.7 points in 2p and adds 0.3–0.4 in 4p; with the threshold rule it adds 1 to 3 points. Keep the heuristic flask.
- **[M]** Runtime per draw/stop decision (100 four-player games, 39,345 decisions, `:timer.tc`): depth 3 mean 19 µs, median 17 µs, p99 59 µs, max 5.3 ms (one GC spike). Depth 5: mean 79 µs, p99 244 µs. Far under the 5 ms budget.

### 3.4 Not in the model (open)

- Score margin: the threshold rule draws harder when behind (`margin_shift`); the EV rule does not. A "win probability" value (Quackulator v3) is the next step.
- Chip effects (orange, red, blue extra draws, yellow) and the bonus die are ignored. Rat tails, bowl and the round-9 stir are handled only through the bag.
- Cautious/reckless: the EV rule has no risk dial. Scale `coin_weight` early (×1 = careful, ×2 = bold) to keep three characters.

## 4. Do the fortune and other choices matter?

`choice_rule` decides four phases: `:fortune_choice`, `:chip_choice`, `:witch_choice`, `:essence_choice`.

- `:default` (today): fortune random but never dominated; chips and witches: the first offer; essence: the furthest space.
- `:random`: any legal action, also the dominated ones.
- `:scored`: `Quacks.AI.Choice` (`lib/quacks/ai/choice.ex`), one value table in VP: 1 VP = 1; a chip = Set 1 price × `coin_weight[round]`; a ruby = `ruby_value`; a droplet step = one space in every round left; a white 1 out = 0.5 VP per round left; a pass = 0. It takes the highest.

2000 games per line, seed 1, variant in each seat in turn, against `balanced` with `:default`:

| Game | Variant | 2p VP (vs others) | 2p win % | 4p VP (vs others) | 4p win % |
|---|---|---|---|---|---|
| Base game (fortune cards) | random | 58.8 vs 58.9 | 49.5 | 51.2 vs 51.4 | 24.4 |
| | scored | 59.3 vs 59.0 | 50.6 | 52.1 vs 51.5 | 26.4 |
| Herb Witches + Alchemists | random | 77.7 vs 82.1 | 38.8 | 72.9 vs 76.2 | 16.6 |
| | scored | 83.6 vs 82.3 | 53.0 | 78.1 vs 76.6 | 27.3 |
| + green 2, purple 2 | random | 74.0 vs 78.4 | 37.3 | 68.4 vs 73.5 | 12.2 |
| | scored | 79.5 vs 78.5 | 52.3 | 74.4 vs 73.2 | 27.7 |
| + green 4, purple 4, yellow 6 | random | 73.1 vs 77.7 | 38.6 | 67.4 vs 72.3 | 14.9 |
| | scored | 80.2 vs 78.6 | 53.5 | 74.2 vs 72.8 | 28.4 |

- **[M]** Base game: the fortune choices are worth little. Random (with dominated options) loses 0.1–0.2 VP; the scorer gains 0.3–0.6 VP.
- **[M]** With the expansions the choices matter: random loses 4–5 VP (win rate 12–17 % at parity 25). The scorer gains 1.2–1.6 VP over today's rules (+2 to +3 points of win rate).
- **[M]** Both together, `balanced+ev+scored` vs `balanced` (seed 2, 2000 games): base game 2p 58.3 % wins (+2.6 VP), 4p 29.7 % (+1.8 VP); expansions + green/purple 2: 2p 58.3 % (+3.8 VP), 4p 31.0 % (+2.9 VP).
- Conclusion: a better Jev choice could gain at most the gap between the scorer and a perfect choice. With 0.3–1.6 VP on the table for all four phases together, and Jev's own advice to keep trade-off arithmetic in code, Jev is **not needed** for strength.

## 5. Plan

### Phase 0 (now, no new deps)

1. Merge `ai-ev` after review.
2. Switch `balanced` to `stop_rule: :ev` and `choice_rule: :scored` (one line each in `Profile.fields/1`). Keep the heuristic flask.
3. Give cautious and reckless their own `coin_weight` scale (×0.8 / ×2.0 early) instead of the threshold, then retune with `mix quacks.sim --profiles balanced,cautious+ev,...`.
4. Next strength steps, all code: margin-aware value (win probability, as Quackulator v3); B3/B7/S1 by the same EV; per-category ablation of the choices (which of fortune/chip/witch/essence is worth what).

### Phase 1 (optional): `Quacks.AI.Jev` for the (d) decisions only

Only if Nick wants bots that choose "in character" (e.g. a bot that loves rubies), not for strength.

- **Shape:** `Quacks.AI.Jev` implements `Quacks.AI.Decider`. For phases `:fortune_choice`, `:chip_choice`, `:witch_choice`, `:essence_choice` it asks Jev; for everything else, and on any failure, it calls `Quacks.AI.decide/4`.
- **Prompt (state):** JSON with round, own VP, score gap to the leader, rubies, coins, flask, bag counts per chip, rounds left, the card or book text, and the profile's personality line. Trim with `@derive {JSON.Encoder, only: [...]}`.
- **Question:** one `Jev.Choice` whose labels are the legal actions, e.g. `%{opt_0: "Take a black chip", opt_1: "Take 3 rubies"}`. Map the label back by index; check it is in `legal_actions`. Add the static scorer's values to the option text (Jev must not do the arithmetic).
- **Confidence gate:** take Jev's label only when `confidence > 0.6`; else the static scorer.
- **Tick:** `GameServer` starts the request with `Task.Supervisor.async_nolink` when the bot tick fires, and arms a cap timer (e.g. 600 ms). Reply in time and legal → apply. Timeout, `{:error, _}` or an illegal label → `Quacks.AI.decide/4`. The tick waits for the reply or the cap, so the bot pace stays ~0.7 s. `Jev.HTTP` with `receive_timeout: 600, max_retries: 0`.
- **Replay and undo:** the chosen action goes in the session log as today. Replay never asks Jev again. Log `{model, confidence}` next to it for tuning.
- **Caching:** key on `{phase, card, legal, bucketed state}`; the same situation in one game gives the same answer.
- **Cost:** a state of ~800 tokens plus ~200 for the question is ~1k input tokens = **$0.00004 per call**. About 10–20 (d) decisions per bot per game with the expansions (fewer in the base game) → **≤ $0.001 per bot per game**. Latency 0.2–0.3 s per call.
- **Config:** `config :jev, api_key: System.get_env("TYPESAFE_API_KEY")` in `runtime.exs`; `config :quacks, :jev, enabled: false` by default; bots fall back to `Quacks.AI` when it is off or the key is missing.
- **Tests / offline:** `config :jev, req_options: [plug: {Req.Test, Jev.HTTP}]` in `test.exs`; stubs with `Jev.Test.respond/2`; a fake `Jev.Backend` for the simulator, so `mix quacks.sim` never calls the network. A sim run with the stub answering "the scorer's choice" must equal the `:scored` numbers.

### Phase 2 (optional): personality and table talk

- Jev **cannot** write table talk: it never generates text. Table talk needs a chat model (e.g. Claude via Req), which is a different dependency, cost and latency. Canned lines per profile and event ("Bold Bruno pushes his luck!") cost nothing and may be enough.
- Jev could pick *which* canned line fits (a `Choice` over 10 lines), for ~$0.00004 per line.

### Risks

| Risk | Mitigation |
|---|---|
| Latency in the 0.7 s tick | Cap at 600 ms, fall back to `Quacks.AI`, no retries in a tick |
| Non-determinism vs replay | Log the action; replay never asks again; pin `jev-1.13.0`, not `jev-latest` |
| Cost | ≤ $0.001 per bot per game; off by default; per-game call cap |
| Wrong or illegal answers | Labels are only the legal actions; confidence gate; static scorer fallback |
| Rate limits ("adjusting dynamically") | 429 → fallback in a tick; it never blocks the game |
| Weaker play than the scorer | Measure with the sim first (fake backend vs the live model on a small batch) |
| New dep, Elixir 1.18 | One package (`json_codec`); raise `elixir:` in `mix.exs` to `~> 1.18` |

## Sources

- Jev for Elixir: https://www.jev.store/projects/jev-elixir; https://github.com/dannote/jev (README, `mix.exs`, CHANGELOG, `guides/usage/testing.md`, `guides/introduction/why-jev.md`, `guides/introduction/getting-started.md`)
- TypeSafe docs: https://docs.typesafe.ai/llms.txt, https://docs.typesafe.ai/models.md, https://docs.typesafe.ai/model-jaggedness/jev-1.13.md, https://docs.typesafe.ai/cookbooks/parallel_questions.md, https://docs.typesafe.ai/concepts/system-one.md
- Quackulator (S1 in `ai-opponents.md`): https://github.com/coreyduval/Quackulator
- Engine: `lib/quacks/ai.ex`, `lib/quacks/ai/*.ex`, `lib/quacks/game/potions.ex`, `lib/quacks/game/fortune.ex`, `lib/quacks/game/evaluation.ex`, `lib/quacks/game/witches.ex`, `lib/quacks/game/essence.ex`, `lib/quacks/rules/pot_track.ex`
