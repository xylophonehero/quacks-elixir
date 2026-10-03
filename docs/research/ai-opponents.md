# Heuristic AI opponents (no Jev)

Research date: 2026-10-03. Scope: bots that play a seat in `Quacks.Game`, with Set 1 books first.
Tags: **[M]** = measured or simulated by someone. **[O]** = community opinion. **[E]** = from this engine.

## 1. Strategy findings

### 1.1 When to stop drawing

- **[M]** The best Set 1 bot that we found (Quackulator, S1) uses no fixed threshold. It draws when the expected value of one more draw is more than the value of a stop. It always draws when no chip in the bag can explode the pot. After 2 draws of look-ahead, only the whites matter: it solves the whites exactly and treats every coloured chip as a safe mover. This agrees with a full exact solve to within 0.12 VP. (S1 maxims 1, 2, 7)
- **[M]** Early explosions cost little. Quackulator v3 explodes in 62 % of round-1 brews and 54 % of round-2 brews. Over a full game its explosion rate is 41.7 %, and it still beats a more careful bot (34.2 %). (S1 maxim 3, results table)
- **[M]** Risk follows the score margin. When the bot trails, it takes risky draws. When it leads, it stops safe. In round 9, when it trails by 4 VP, it draws at odds that a careful bot refuses. (S1 maxims 14, 16)
- **[O]** Count the white total. When the white 3 is already in the pot, some draws cannot explode you. (S5)
- **[O]** In early rounds, stop a little early on a ruby space so that you can refill the flask. (S6, S7) **[M]** Counterpoint: "the ruby space is one ruby, nothing more". (S1 maxim 13)
- **[E]** The engine stores the bag, so the bot knows the exact odds. With the limit `L` (`Potions.explode_above/2`, default 7) and white sum `s` (`Player.white_sum/1`, includes the bowl):
  `p_bust = count(white w in bag where s + w > L) / length(bag)`.
  Example, round 1: pot W1 W2 W2 orange (s = 5), bag 3×W1, W3, green. Only W3 explodes: p = 1/5 = 20 %.

### 1.2 Flask, rubies and rat tails

- **[M]** Use the flask when the position it saves is worth more than the 2 rubies for a refill. Yes for a white 3 in mid-round with many coloured chips left; no for a white 1 at the start. (S1 maxim 4) **[O]** "Do not play the whole game without using your flask." (S3)
- **[O]** In rounds 1–3, refill the flask each round; droplet moves are also good early. Droplet moves give more coins and VP each round but leave the flask empty. (S6, S7)
- **[M]** Rubies become VP (2 → 1) only at the end. (S1 maxim 10)
- **[M]** Rat tails help the player who trails. The aggressive v3 bot got 12.1 tails per game against 8.4 for v2 and won more. Falling behind early is not a disaster. (S1 maxim 14)

### 1.3 Explosion choice: VP or coins

- **[M]** Take coins (buy) on every explosion through round 5. Take VP from round 7 on. Round 6 is a toss-up: compare the VP lost with the value of the buy. (S1 maxim 3)

### 1.4 Chips in Set 1

- **[M]** Mean buys per game of the winning bot: red 3.2, orange 2.3, purple 2.3, blue 2.2, black 1.4, green 1.3. An older heuristic bot bought 0 red and 2.9 green and lost. Every learned policy buys 1 black in round 1. (S1 maxims 9, 13, 19)
- **[M]** Rate a buy by its value for the rest of the game, not by its face value. (S1 maxim 9)
- **[O]** Buy two chips when you can, one of them a 4 when you can. Two 1-chips are good early; 4-chips are better late. Many chips dilute the whites. Be careful with yellow 1 and purple 1. More than 3 black chips give less and less. (S3) Prefer 2- and 4-chips to 1-chips. (S4)
- **[O]** Orange + red works only with about 4 or more of each in the bag. (S3)
- **[O]** Meeple Like Us: the start bag is 22 % good chips; after the round-1 buys 36 %, after round 2 46 %. (S5)

### 1.5 Endgame

- **[M]** Coins do not carry over. With more than 3 coins, "buy nothing" is almost never right, also in round 8. (S1 maxim 8)
- **[M]** Round 9: 5 coins = 1 VP, 2 rubies = 1 VP. Players gain about 12.4 VP in round 9 against about 7.1 in round 8. (S1 table 2) **[E]** The engine converts coins and rubies at `:end_round`, and offers `{:rubies, :vp}` before.
- **[O]** "An explosion late in the game is the worst thing." (S3)

### 1.6 Existing bots

- **Quackulator** (S1, Python + Rust v3): expectimax over the bag; enumerates every buy; v2 learned a value function by self-play (ridge regression on 45 features); v3 maximises the chance of first place with a sigmoid per round. **[M]** v3 against three v2: 43.5 VP mean, 34.3 % wins (25 % = parity).
- **Rival Quack** (S2): a card-driven solo automa, no bag. Each round, cards give the rival a rat stone value (level 1: 6–9, 2: 7–11, 3: 8–12), 0–2 black chips and 1–5 droplet steps. Always spends 2 rubies. No measured results. A model for a cheap "ghost" opponent, not for a seat bot.

## 2. Engine fit

The bot uses only `Game.legal_actions(game, seat)` and `Game.apply(game, seat, action)`. The struct is fully open: every bag, pot, droplet, ruby count and VP total, plus `round`, `rules`, `sets`, `fortune_card`. A bot must not read `game.rng` to see the future (the next draw is computable from it). That is cheating; the AI rng is separate (§3).

A seat must act when `legal_actions(game, seat) != []`. The decision is from `Game.phase(game, seat)`:

| Phase (`Game.phase/2`) | Legal actions | Data the bot uses | Rule (§3.3) |
|---|---|---|---|
| `:potions` | `:draw`, `:stop`, `:use_flask`; `{:fortune, :restart_round \| :return_white}` (B3, B10); R6 `{:red, {:place, c}}`; silver witch | `bag`, `white_sum`, `pot_index`, `flask`, `drawn`, limit, `round`, other VP | draw/stop, flask |
| `:stopped` | `:resume` (only while another seat brews, never round 9) | other pots | never resume (v1) |
| `:yellow_choice` | `:return_white`, `:keep` | white sum | always `:return_white` |
| `:blue_choice` | `{:place, chip}`, `:return_all` | `pending`, `white_sum`, `pot_index` | best safe chip |
| `:explosion_choice` | `{:explosion_choice, :vp \| :buy}`; silver S1/S4 | round, scoring space | §1.3 |
| `:red_choice` (R2/R6) | `{:red, {:place \| :keep \| :return, c}}` | `pending` | place |
| `:chip_choice` | `{:chip, choice}`, `:chip_done` (G2/G4/G5/P2/P4/P5, Y6) | `chip_choices` | first good, else done |
| `:fortune_choice` | `{:fortune, choice}` (P-cards, B7) | `fortune_card` | random, unless dominated |
| `:witch_choice` | `{:witch, :gold}`, `:witch_done` | `witches` | take it (v1: G-witch offered only when it pays) |
| `:shop` | `{:buy, chips}` (from `Game.buys/2`, once), `{:rubies, :droplet \| :flask}`, round 9 `{:rubies, :vp}`, copper/G4 witch, `:end_round` | `coins`, `rubies`, `flask`, `round`, bag | shop scoring |
| `:waiting_stir`, `:done`, `:ready` | none | | |
| round 9 stir (2+ players) | `:draw` / `:stop` in `:potions` | as `:potions` | VP-only draw/stop |

Notes:
- **[E]** Draws are uniform over the bag multiset (`:rand.uniform_s(length(bag), rng)`), so the odds in §1.1 are exact. Exceptions: G5 starter chips are drawn first, in order (`Player.starters`); B3/B7 card draws cannot explode (`Fortune.safe_draw?/2`); B2 `mods.protect`.
- **[E]** `{:buy, chips}` is matched after sort; pass the list from `legal_actions`.
- **[E]** Multi-step turns: the shop needs several actions (buy, rubies, `:end_round`). The bot does one action per call and is asked again.
- **[E]** Concurrent phases (`:fortune_choice`, `:chip_choice`, `:witch_choice`, `:shopping`, potions) let every bot act in any order. With `supply: :limited` the first seat gets the chip.

## 3. Design proposal

### 3.1 Module shape

```elixir
defmodule Quacks.AI do
  @spec decide(Game.t(), Game.seat(), Profile.t(), :rand.state()) ::
          {Game.action(), :rand.state()} | :none
end
```

- Pure, no processes. The result is always a member of `legal_actions(game, seat)` (`:none` when that list is empty). A last-resort fallback picks the first legal action, so an unknown book or card never stalls the game.
- Deep module: one public function. Internals in private modules: `Quacks.AI.Odds` (bust probability, expected move, value of a space), `Quacks.AI.Shop` (scored buys), `Quacks.AI.Profile` (data).
- Own rng (`:rand.seed_s/1` from the game seed + seat), kept by the caller. The engine `rng` is never read.
- Behaviour `Quacks.AI.Decider` with `decide/4`. `Quacks.AI` is the first implementation; a Jev decider (recmem `rm-jev-ai`) plugs in later behind the same contract, e.g. with `Quacks.AI` as the fallback on timeout or illegal output.

### 3.2 Profiles (data)

```elixir
%Profile{
  name: :balanced,
  max_bust: %{1 => 0.35, 2 => 0.30, 3 => 0.25, 4 => 0.25, 5 => 0.20, 6 => 0.20, 7 => 0.15, 8 => 0.15, 9 => 0.20},
  margin_shift: 0.01,          # + per VP behind the leader, - per VP ahead (cap ±0.10)
  explode_vp_from: 6,          # explosion: :buy before this round, :vp from it
  flask_min_white: 2,          # use the flask only on a white of this value or more
  colour_weight: %{red: 1.2, orange: 1.0, blue: 1.1, purple: 1.0, black: 1.0, green: 0.8, yellow: 0.8},
  black_max: 2, purple_from: 3,
  ruby_plan: [:flask, :droplet], droplet_until: 6,
  fortune: :random
}
```

| Profile | `max_bust` round 1 → 8 | explode `:vp` from | Shop bias | Rubies |
|---|---|---|---|---|
| `:cautious` | 0.20 → 0.10 | round 5 | blue, orange, many cheap chips | flask first |
| `:balanced` | 0.35 → 0.15 | round 6 | red/orange, 1 black early, 4-chips late | flask, then droplet to round 6 |
| `:reckless` | 0.50 → 0.25 | round 7 | 4-chips, purple, red | droplet first |

Thresholds are starting points from §1.1 (early pushes are cheap; late explosions hurt). Tune them with the harness (§3.5).

### 3.3 Decision rules

- **Draw/stop.** `p = p_bust(bag, s, L)`. Draw when `p == 0`. Else draw when `p <= max_bust[round] + margin_shift * (leader_vp - my_vp)` (capped). Optional v2: one-step EV, `E[value(next space)] * (1 - p) + p * value(explode)` against `value(scoring space)`, with `value = coin_weight(round) * coins + vp_weight(round) * vp + ruby_value` (coin weight high early, 0 in round 9). The threshold rule is enough for v1.
- **Flask.** When legal, the last chip is a white of value `>= flask_min_white`, and the bot would draw again after the return (the new p is under the threshold): use it. Else stop.
- **Round 9 stir.** Same rule with VP-only value and a higher margin shift (draw harder when behind).
- **Yellow:** `:return_white`. **Blue:** place the non-white chip that moves furthest; a white only when it cannot explode; else `:return_all`. **Red R2:** place. **Explosion:** `:buy` before `explode_vp_from`, then `:vp`; in round 9 always `:vp`.
- **Shop.** Score every `{:buy, chips}` from `legal_actions`: `sum(colour_weight * value_weight(value, round))` with penalties (black over `black_max`, purple before `purple_from`, yellow 1 and purple 1 late) and a bonus for two chips. `{:buy, []}` only when nothing scores above 0. Order: buy, then rubies (flask refill if empty, droplet while `round <= droplet_until`), then `:end_round`. Round 9: `{:rubies, :vp}` while legal, then `:end_round`.
- **Fortune, chip and witch choices.** Random among the legal actions (Nick's wish), except dominated ones: never `:skip` when a free gain exists, never return to the supply what is free. Chip choices (Sets 2–6): first non-done choice, then `:chip_done`. Witches: v1 never calls silver/copper (needs timing rules); gold `:witch_choice` always takes it.
- **Never `:resume`** in v1.

### 3.4 GameServer wiring

- Table gains `bots: %{seat => profile_name}` (set on the configure screen) and state gains `bot_rngs`.
- After every state change (`begin`, `apply`), if a bot seat has legal actions, `Process.send_after(self(), {:bot, seat, version}, delay)` with `delay` ~600–900 ms (feel). On `{:bot, ...}`: drop stale versions, call `Quacks.AI.decide/4`, apply through `Session.apply/3` (so replay and undo still work), broadcast, schedule again. Return `@idle_timeout` from `handle_info` as the other callbacks do.
- One bot action per tick, so humans see each draw. Concurrent phases: one tick per bot seat.
- A human soft stop waits for bots to finish; bots never resume, so the round ends.

### 3.5 Evaluation harness

- Headless: a test-support module or `mix quacks.sim` loops `Game.new(seed:, players: n)` → for every seat with legal actions, `Quacks.AI.decide/4` → `Game.apply/3`, until `Game.over?/1`. No GenServer.
- Run N = 1,000 games per profile mix (e.g. 4 × `:balanced`, `:reckless` vs 3 × `:cautious`). Measure mean and spread of VP, win rate, explosion rate per round, mean coins per round, buys per colour, stalls (any action outside `legal_actions` or a game that does not end = bug).
- Tune `max_bust` with a grid search per round band. Check against S1: an explosion rate near 40 % and a win rate above parity for the tuned profile.
- Also a property test: random profiles and seeds always reach `:over`.

## 4. Open questions for Nick

1. **Bots in the lobby:** does the host add bots on the configure screen ("+ Bot" per empty seat, with a profile pick)? Can humans and bots mix at one table, and is there a bot limit (up to 7)?
2. **Names and colours:** fixed names per profile ("Careful Clara", "Bold Bruno") or "Bot N"? Do bots take the next free seat colour?
3. **Speed:** a fixed delay per action (about 0.7 s), a speed option, or "skip to my turn"? Do bots act in the shop while the human is still in the results dialog?
4. **Solo:** do bots replace solo mode, or does solo also get a "beat the ghost" variant (Rival Quack style, no seat bot)?
5. **Scope of books and cards:** v1 plays Set 1 well and the other books/witches with simple defaults. Is that enough, or must bots play every book well before launch? Fortune choices random: confirmed?

## 5. Tuning results

Date: 2026-10-03. Code: `Quacks.AI`, profiles in `Quacks.AI.Profile`. Command, 1,000 games per mix, Set 1 books, default rules:

```
mix quacks.sim --games 1000 --profiles <mix> --seed 1
```

| Mix | Profile | VP mean (sd) | Win % | Explosion % |
|---|---|---|---|---|
| 4 × balanced | balanced | 51.2 (8.6) | 25.0 | 39.3 |
| balanced, reckless, cautious, balanced | balanced | 53.4 (8.8) | 38.3 | 38.4 |
| | cautious | 47.2 (8.0) | 9.5 | 16.4 |
| | reckless | 46.2 (9.7) | 13.9 | 64.2 |
| balanced + 3 × cautious | balanced | 54.8 (9.6) | 60.9 | 38.7 |
| | cautious | 46.9 (7.9) | 13.0 | 16.7 |
| reckless + 3 × cautious | reckless | 45.6 (9.9) | 27.7 | 63.7 |
| | cautious | 46.3 (8.0) | 24.1 | 16.5 |
| balanced vs cautious | balanced | 55.8 (10.4) | 79.5 | 34.9 |
| balanced vs reckless | balanced | 54.6 (9.5) | 74.1 | 32.0 |

- Balanced beats cautious and reckless; reckless explodes most; balanced lands at 39 % explosions (S1: 41.7 %). Per round, balanced explodes 39/45/56/57 % in rounds 1–4 and 24–28 % in rounds 7–9 (S1: about 60 % early).
- Buys per game in the 4-player mix: balanced red 4.6, purple 3.0, orange 2.2, green 2.1, blue 1.4, black 1.0 (S1 winner: red 3.2, orange 2.3, purple 2.3, blue 2.2, black 1.4, green 1.3). Cautious: orange 6.8, blue 4.7. Reckless: red 6.6.
- No stalls in any run, also with The Herb Witches, Sets 2–6 and a limited supply (500 games each, 5 bots).
- What the tuning changed (balanced against 3 copies of itself, win % with parity 25): purple and black weight 1.0 → 3.0 with `black_max` 1 (+16), `max_bust` rounds 1–4 +0.25 and rounds 5–6 +0.05/+0.10 (+5), round 9 0.20 → 0.10, droplet before flask (+4), `flask_min_white` 3 (+3, the flask on a white 1 or 2 lost 6), `explode_vp_from` 7, value weight of a 4-chip 2.6 → 3.2 (+6). The margin shift and `droplet_until` hardly mattered.
- Tuning helper (not committed): a `mix run` script that plays a `%Profile{name: :test}` variant against 3 balanced with `Sim.run(profiles: [variant, :balanced, :balanced, :balanced])`; `Sim` accepts profile structs for this.

## Sources

- S1 Quackulator (Set 1 solver and self-play simulator): https://github.com/coreyduval/Quackulator, maxims https://raw.githubusercontent.com/coreyduval/Quackulator/main/MAXIMS.md
- S2 Rival Quack (solo automa): https://github.com/waschinski/rivalquack
- S3 What's Eric Playing: https://whatsericplaying.com/2019/09/16/the-quacks-of-quedlinburg/
- S4 Dice n Board guide: https://dicenboard.com/game-guides/quacks-of-quedlinburg-guide/
- S5 Meeple Like Us: https://www.meeplelikeus.co.uk/the-quacks-of-quedlinburg-2018/
- S6 BGG blog review: https://boardgamegeek.com/blog/8626/blogpost/158161/the-quacks-of-quedlinburg-review
- S7 Hiew and board games: http://hiewandboardgames.blogspot.com/2019/03/the-quacks-of-quedlinburg.html
- Engine: `lib/quacks/game.ex`, `lib/quacks/game/potions.ex`, `lib/quacks/player.ex`, `lib/quacks/session.ex`, `lib/quacks/game_server.ex`, `docs/CONTEXT.md`.
- Not found: a published stop-probability table, Herb Witches strategy. BGG forum threads return 403 to the fetcher.
