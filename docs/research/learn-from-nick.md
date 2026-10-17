# Learn from Nick's games

Date: 2026-10-17. Branch `learn-nick`. Earlier work: `docs/research/bot-training.md` (bench, duplicate seating, CEM, the tuned bot).

Nick asked: "train them on games I've won where they didn't beat me. Look at my strategy and show them what they could have done better."

## 0. Short answer

- **No finished game was kept until now.** The server deleted each game file at the end. Now each finished game goes to an archive on the server (§1): Quacks and the other table games (Hearts, Codenames Duet, Codex, Crazy Eights). The rest of the pipeline is ready and waits for data. The review and the training are for Quacks only.
- **Pipeline:** `mix quacks.games.pull` → `mix quacks.review` → `mix quacks.tune --starts` → `mix quacks.bench` (§2).
- **First run** (§3): only 2 of Nick's games can be read, and both stop in round 4 or 5 (bug report bundles #74 and #89; #1 does not replay on today's engine). That is 95 decisions by Nick. This is too small for a conclusion. The numbers below show that the pipeline works, not what Nick's strategy is.
- **Training** (§4): not adopted. The bot trained from Nick's buys and positions wins 22.9 % ± 0.9 of 4-player games against 3 × `tuned` (parity 25 %) and 49.6 % ± 1.5 of 2-player games (parity 50 %). `priv/bots/tuned.json` stays. The training ran 45 minutes, 9 386 s CPU (2.6 CPU hours), `nice -n 10`, `--jobs 4`.
- **Data needed** (§5): about 30 finished games that Nick won for a first useful shop fit and start positions; about 90 played games to measure his win rate against the bots to ±10 points.

## 1. The archive of finished games

When a game ends, its server writes `<GAMES_DIR>/finished/<game key>/<id>.json` (`Quacks.GameStore.archive/4`). One layout for all games: Quacks in `finished/quacks/`, the `Table.Server` games in `finished/hearts/`, `finished/codenames_duet/`, `finished/codex/` and `finished/generic/`. Prod and staging run the same code (`GAMES_DIR=/data/games`).

### 1.1 Quacks (`finished/quacks/<id>.json`)

```json
{
  "format": 1,
  "game": "quacks",
  "id": "kqzfmw",
  "finished_at": "2026-10-17T19:00:00Z",
  "app_version": "0.1.0 (024c0d1)",
  "players": 4,
  "seats": [
    {"seat": 0, "name": "Nick", "human": true, "bot": null, "vp": 71, "rubies": 2},
    {"seat": 1, "name": "Hubert", "human": false, "bot": "expert", "vp": 64, "rubies": 0}
  ],
  "standings": [0, 2, 3, 1],
  "winners": [0],
  "bundle": {"version": 1, "seed": [1, 2, 3], "players": 4, "opts": {}, "log": [], "names": [], "bots": [1, 2, 3]}
}
```

- `bundle` is the replay bundle (`Quacks.Session.bundle/1`, the same as in a bug report). It replays to the same final game.
- `standings` uses the rule of the game (most VP, then fewer rubies). `winners` holds every seat with the same VP and rubies as the leader.
- **Retention (all games):** per game folder, the newest 1000 files and at most 50 MB in total (`GameStore.prune/3`, by file time). One Quacks file is about 10–40 KB, so the count limit applies first.
- The archive file is written one time, at the action that ends the game. A game that was over before a restart is not archived again. Debug tables are not archived. The normal game file goes later as before (1 hour after every human closed the final scoring).
- The archive does not change the game: the golden tests are green with no fixture change.

### 1.2 The other table games (`finished/<game key>/<room code>.json`)

`Table.Server` (Hearts, Codenames Duet, Codex, the generic games such as Crazy Eights) now keeps the seed and every applied `{seat, action}` of a room. When the adapter's status turns to `{:over, _}`, the room writes `Table.Archive.body/2`:

```json
{
  "format": 1, "game": "hearts", "id": "K7QPX",
  "finished_at": "2026-10-17T19:00:00Z", "app_version": "0.1.0 (f32768e)",
  "seed": [11, 12, 13],
  "opts": {"m": [["players", 4]]},
  "seats": [{"seat": 0, "name": "Nick", "human": true, "bot": null},
            {"seat": 1, "name": "Ada", "human": false, "bot": "heuristic"}],
  "status": ["over", {"m": [[0, 52], [1, 101]]}],
  "winners": [0],
  "log": [[0, ["pass", {"l": [[4, "clubs"], [6, "clubs"], [8, "clubs"]]}]], ...]
}
```

- `opts`, `status` and each action use one generic JSON form of terms (`Table.Archive.encode/1`: an atom is a string, a tuple an array, `{"l": ...}` a list, `{"m": ...}` a map, `{"s": ...}` a string, `{"t": module, "m": fields}` a struct). The read makes no new atoms (`String.to_existing_atom/1`).
- `Table.Archive.replay/1` plays the log through the game's adapter again. A test per game (a whole bot game of Hearts, Codenames Duet, Codex and Crazy Eights) shows that the replay gives the same final game and status.
- Optional adapter callbacks: `winners/1` (Hearts: the lowest total; Codenames Duet: both seats or nobody; Codex: the winner; generic: the highest score), and `encode_action/1` / `decode_action/1` for a game that needs its own form of an action. No game needs them now.
- A room's next games (play again) are `<code>-2.json`, `<code>-3.json`, ...

## 2. How to run it

```sh
# 1. Copy the finished games to the laptop (read-only on the server).
mix quacks.games.pull --app quacks --app quacks-staging --github
#    -> tmp/finished/<app>/<game>/*.json (every game; --game quacks for one),
#       tmp/finished/github/github-<issue>.json

# 2. Review the games that a human won. Writes tmp/review/review.md and review.json.
#    --fit writes a shop start point fitted to the humans' buys.
nice -n 10 mix quacks.review tmp/finished --human-won --jobs 4 --futures 32 \
  --fit tmp/review/nick-start.json

# 3. Train from the fitted start, against the tuned bot, with the positions of
#    Nick's won games as extra start states.
nice -n 10 mix quacks.tune --base file:tmp/review/nick-start.json \
  --opponent file:priv/bots/tuned.json --starts tmp/finished --starts-human-won \
  --checkpoint tmp/train/ck.json --out tmp/train/nick.json --minutes 45 --jobs 4

# 4. Bench on new seeds (2000 seeds per line). Adopt only when the 95 % interval
#    is clear of parity against tuned at 2 and 4 players.
nice -n 10 mix quacks.bench --jobs 4 --games 8000 --players 4 --seed 303 \
  --bots file:tmp/train/nick.json,file:priv/bots/tuned.json,file:priv/bots/tuned.json,file:priv/bots/tuned.json
nice -n 10 mix quacks.bench --jobs 4 --games 4000 --players 2 --seed 303 \
  --bots file:tmp/train/nick.json,file:priv/bots/tuned.json
```

- **Pull.** `--app` runs `fly ssh console` two times or more: `find` in the archive, then `tar | base64` of the new files (100 per call). `--game hearts` pulls one game only. It does not write on the server. It needs `fly auth login`. Files that are on the laptop already are not copied again. `--github` reads the bug report issues (label `bug-report`).
- **Review.** It reads Quacks archive files and bundles; it skips the files of the other games. A bug report bundle names the bot seats but not their profile; the review uses `expert` (`--bot-profile` changes it). For bot games without humans (the golden bundles), `--humans 0` makes seat 0 the "human".
- **What the review measures:**
  - *Nick's style:* per round, his stops (the bust chance and the white total at the stop) next to the bots' stops in the same games; how often the tuned bot's expectimax would draw where he stopped; his explosions and his choice (coins or VP); his buys per round, by colour and by value; his rubies (droplet, flask); his flask uses; his book, card, witch and essence choices.
  - *Nick against the tuned bot:* for each decision, what the tuned bot does in the same state. The agreement per kind. The biggest differences by loss: draw/stop by expectimax (the tuned bot's own value scale), buys, explosions, rubies and choices by rollouts.
  - *The bots' mistakes:* at each bot decision, every option (at most 10; for a buy the best by the shop score) is played to the end `--futures` times. All options use the same game seeds. The value of a future is the seat's VP minus the best other seat's VP. A loss counts as a mistake only when it is more than 2 standard errors. Note: the best of 10 noisy options looks better than it is, so some "mistakes" are noise. Use 32 futures or more, and look for patterns over many games, not single rows.
- **Train.** `--starts DIR` adds one more term to the CEM fitness: the candidate plays on from the start of each round (from round 2) of the games in `DIR`, in every seat, against the opponent. `--starts-human-won` uses only the games a human won.

## 3. First run on the data that exists

### 3.1 Nick's two partial games (bug reports #74 and #89)

Both games: Nick in seat 0, three bots, 4 players, The Alchemists. #74 stops in round 4 (Nick leads, 10 VP against 8, 6, 3). #89 stops in round 5 (Nick has 4 VP, a bot leads with 12). Command: `mix quacks.review tmp/finished --futures 32 --jobs 4 --fit tmp/review/nick-start.json` (35 s on 4 cores, 135 s CPU).

| Kind | Nick's decisions | Same as the tuned bot |
|---|---|---|
| Draw/stop | 63 | 90 % |
| Buy | 7 | 29 % |
| Choice (fortune, book, essence) | 17 | 82 % |
| Explosion (coins or VP) | 2 | 100 % |
| Rubies | 6 | 100 % (droplets, as the bot) |

- **Draw/stop.** Nick stops later than the bots in round 1 (bust chance 83 % at the stop, bots 75 %), and at the same risk in rounds 2–4. The tuned bot's expectimax says "draw" at both of his round-1 stops (0.8 VP of loss each, on the bot's value scale). In 58 draws the tuned bot would stop only once.
- **Shop.** Nick bought 1-chips (11 of 12 chips): black and blue, purple and red, orange, locoweed. The tuned bot likes 4-chips much more (value weight 5.1). The largest differences (rollouts, 32 futures): round 1 of #89, red 1 against blue 1 + orange 1 (4.4 VP ± 7.4); round 3 of #74, purple 1 + red 1 against red 4 (3.3 ± 4.7). **No difference is larger than its 2-se interval.** The sample says nothing yet about who buys better.
- **Agreement on buys is not a sign of a style yet.** A `balanced` bot in the golden games agrees with the tuned bot on 23 % of buys (§3.2); Nick's 29 % is in the same range.
- **Bot mistakes** (283 bot decisions): 5 decisions pass the 2-se rule (patient choice, one draw, one buy, one essence buy, one stop). With 283 tests, about 6 false alarms are expected at that rule, so these 5 are not evidence of a weak spot.
- **Shop fit.** On 7 buys, the fitted weights explain Nick's buys better (log-likelihood per buy −2.90 → −1.21; the best-scored buy is his buy in 71 % against 29 %). The fit lowers green, orange, blue and yellow, and raises purple and 1-chips. 7 buys for 11 numbers is an over-fit; the prior (`prior: 10`) keeps it only partly near the tuned bot.

### 3.2 The golden bot games (pipeline check)

The 5 golden bundles (`test/fixtures/bundles/`, `balanced` bots, 1–8 players) with `--humans 0 --bot-profile balanced --futures 16`: 585 "human" and 1712 bot decisions, 78 s on 4 cores (303 s CPU). Agreement of the `balanced` seat 0 with the tuned bot: draw/stop 93 %, buy 23 %, choice 92 %. Rollout standard error of one buy decision at 16 futures: 2–4 VP.

## 4. Training run

```
nice -n 10 mix quacks.tune --base file:tmp/review/nick-start.json \
  --opponent file:priv/bots/tuned.json --starts tmp/finished \
  --checkpoint tmp/train/ck.json --out tmp/train/nick.json --minutes 45 --jobs 4 --seeds 100 --seed 7
```

- **Start:** the tuned bot with the shop weights fitted to Nick's 7 buys (§3.1). **Start positions:** 7 (the start of rounds 2–4 of #74 and 2–5 of #89, all 4-player), each played in every seat 2 times per candidate. **Opponent:** `tuned` itself.
- **Run:** 147 generations, 45 minutes (2 713 s wall), **9 386 s CPU** (9 252 user + 134 sys) on 4 jobs under `nice -n 10`. About 17 s per generation.
- **Fitness** (1.0 = as good as `tuned`): 0.79 (mean of generations 1–20), then 0.92–0.98 per block of 20 generations. It did not pass 1.0.

**Bench on new seeds** (seed 303, 2000 seeds per line, duplicate seating, `--jobs 4`):

| Bot | Opponents | Players | Win % (parity) | VP |
|---|---|---|---|---|
| trained (`tmp/train/nick.json`) | 3 × `tuned` | 4 | **22.9 ± 0.9** (25) | 51.5 vs 52.2 |
| trained | `tuned` | 2 | **49.6 ± 1.5** (50) | 53.5 vs 53.7 |
| trained | 3 × `balanced` | 4 | 34.2 ± 1.0 (25) | 54.0 vs 51.6 |
| trained | `balanced` | 2 | 61.0 ± 1.4 (50) | 55.5 vs 52.2 |
| fitted start, before the search | 3 × `tuned` | 4 | 7.6 ± 0.6 (25) | 47.6 vs 52.6 |
| fitted start, before the search | `tuned` | 2 | 31.0 ± 1.4 (50) | 49.6 vs 54.8 |

The table bots play `expert`, which is `tuned`, so the first two lines are also the comparison with the table bots.

- **Decision: not adopted.** At 4 players the trained bot is worse than `tuned` (the interval is clear of parity, on the wrong side); at 2 players it is equal. `priv/bots/tuned.json` stays.
- **Why:** the shop weights fitted to 7 buys make a weak bot (7.6 % at 4 players): they put green, orange, blue and yellow near 0, so the bot often buys too little. The search then spent its time on a return to the tuned weights, and 7 positions are too few to teach anything new. This is a result of too little data, not a sign that Nick's style is bad.

## 5. How many of Nick's games are needed

Estimates from the variance in this run [E]:

- **Nick's win rate against the bots.** One 4-player game is one yes/no result (no duplicate seating for a human). With a win rate near 35 %, the standard deviation per game is 0.48. For ±10 points (95 %): (1.96 × 0.48 / 0.10)² ≈ **90 games**; for ±5 points about 350.
- **The shop fit.** A 4-player game gives about 8 of Nick's buys. The fit has 11 numbers (7 colours, 4 values). 7 buys gave an over-fit that loses badly (§4). With about 20 buys per number, about 220 buys: **about 30 games that Nick won** (about 70–90 played, if he wins 35–40 %).
- **Start positions.** A game gives 8 positions (rounds 2–9). The bench resolves ±0.9 points at 4 players with 2000 seeds (per-seed standard deviation about 0.2 of a win). For the start term of the fitness to have a standard error of about 1 point with 2 plays per position and seat, it needs about 130 positions: **about 17 won games**; more give more different positions.
- **The bots' mistakes.** A rollout of one buy decision has a standard error of 2–4 VP at 16 futures. To see a mean loss of 0.5 VP per decision of one kind: (1.96 × 3 / 0.5)² ≈ 140 decisions. The 3 bots make 24 buys per 4-player game: **about 6 games** for the buys, fewer for draw/stop.
- **Together:** run the pipeline again at **about 30 finished games that Nick won**. Before that, the review is useful to read single games, but do not train from it.

## 6. Limits

- A human seat in a rollout is played by the tuned bot. So a rollout says "what this choice is worth if the tuned bot plays on", not "if Nick plays on".
- Draw/stop for Nick is valued with the tuned bot's expectimax, on its own coin weights per round. A different plan (for example "save coins for a 6-chip next round") is not visible to it.
- Bug report bundles stop where Nick sent the report. Only the archive gives whole games.
- The archive keeps 1000 games per game key. Pull it from time to time.
- The fit prior (`prior: 10`) is a guess. With more buys, check the fit with a held-out part of the buys before training from it.
