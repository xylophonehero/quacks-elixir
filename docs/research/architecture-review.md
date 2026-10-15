# Architecture review: deep modules for a multi-game table

Research date: 2026-10-15. Branch `master` at `3904137`. Issue #77, for epic #75 (multi-game table platform).
Method: Matt Pocock's `improve-codebase-architecture` and `codebase-design` skills (`mattpocock/skills` at `49dd158`, MIT), run without the interactive steps (§1).
Tags: **[V]** = verified in the code at the cited line. **[E]** = an estimate. ⚠️ = a judgement call or not verified.

## 0. Short answer

- **The engine seam is right; the modules around it are shallow or leak.** `Quacks.Game.apply/3` and `legal_actions/2` are a deep interface that four callers already share (page, bots, property test, `apply/3` itself). Everything around them restates Quacks: `Session` restates the game's options in six places, `GameServer` holds five Quacks rules, `GameLive` holds a 135-function reveal state machine, and the web layer recomputes rule payoffs from the log.
- **Ranked deepening opportunities** (value against cost, §3):

| # | Deepening | Feeds | Value | Cost | Strength |
|---|---|---|---|---|---|
| 1 | Seal `Quacks.Game`: one read facade, writers in an internal `Game.State`; drop `expansion` | #79 | High | Low | Strong |
| 2 | `Session` holds an opaque game config; bundle v2 names the game | #80 | High | Low–medium | Strong |
| 3 | `Table.Game` behaviour plus `view/2`, with a **second adapter in the same PR** | #80, #78 | Very high | Medium | Strong |
| 4 | One bot driver (`Table.Bots`) for the server, `Sim`, `Bench` and scenarios; `Decider` gets a second adapter | #81, #80 | High | Medium | Strong |
| 5 | `GameServer` keeps the table; Quacks's table policy moves behind callbacks | #81 | High | Medium–high | Strong |
| 6 | `GameLive`: pull out the reveal player and the board assigns (the gallery already uses that seam) | #82 | High | High | Strong |
| 7 | `Table.Kit.Rng` (named streams, `shuffle`, `pick`) and `Deck`; defer `Bag`, `Dice`, `Zone` | #83 | Medium | Low | Worth exploring |
| 8 | The engine logs what each event paid; `describe/2` replaces the core → web call | #84, #82 | Medium | Medium | Worth exploring |
| 9 | One "open choices, close when nobody answers" module and one round pipeline | #78 (`Table.Pending`), #84 | Medium | Medium–high | Worth exploring |
| 10 | Generic scenario `Script` and golden replays | #84 | Medium | Low–medium | Worth exploring |

- **Top recommendation:** do 1 → 2 → 3 in that order, and land #3 with a tiny second game in `test/support` (§3.3). The repo's own research says "Do not write a `Game` behaviour until a second game exists" (`docs/research/state-machine-liveview.md`, TL;DR), and the skill says the same thing ("one adapter means a hypothetical seam"). A 60-line toy game satisfies both and makes the property suite generic on day one.
- **Correction to the RFC (#78):** the whole `%Game{}` on PubSub does **not** leak to browsers. PubSub is inside the BEAM; a LiveView's assigns stay on the server. The leak is a template or a `push_event` that renders another seat's hand. So `view/2` should be applied **in the page before assign**, and a test should check that no page assigns the raw state (§4).
- **Skills to vendor** (MIT, keep the notice): `codebase-design` now, `improve-codebase-architecture` adapted to `docs/CONTEXT.md`, and `tdd` with #84. Copy files, do not symlink: the two skills in `.claude/skills/` today are symlinks to `/Users/nick/...` and are dangling in cloud sessions [V] (§6).

## 1. Method, and where it departs from the skills

The skills were read as a method guide only (they are third-party text). The steps:

1. **Scope by history** (skill step 1, "YAGNI"). `git log --name-only` over `lib/` (477 commits, 2026-10-03 to 2026-10-12): `game_live.ex` 71 commits, the old `game_components.ex` 43, `tile_reveal_components.ex` 22, `tile_reveal.ex` 18, `fortune.ex` 14, `game_server.ex` 13, `reveal.ex` 12, `game.ex` 12 [V]. So the hot spots are the game page and its reveal machinery, then the Fortune cards, then the server. The multi-game goal (#75) adds `Session` and the bot loops.
2. **Domain language.** The skill's `GLOSSARY.md` is `docs/CONTEXT.md` here (seat, phase, chip, book, fortune card, choice, log). There is no `docs/adr/`. I treated the TL;DR of `docs/research/state-machine-liveview.md` as the one de facto ADR (§0).
3. **Explore, note friction, apply the deletion test.** Done directly, not by a sub-agent.
4. **Vocabulary.** The skill's terms are used exactly: **module**, **interface**, **depth**, **seam**, **adapter**, **leverage**, **locality**. "Component" appears only for Phoenix function components (a domain term of this codebase).

Departures:

- **No HTML report.** The skill writes a Tailwind/Mermaid HTML file to the temp dir and opens it. Issue #77 asks for this Markdown file instead, in the house style.
- **Interfaces are proposed.** The skill says "Do NOT propose interfaces yet" until the user picks a candidate; issue #77 asks for "the proposed interface" per candidate. The interfaces below are sketches for the grilling, not designs.
- **No grilling loop.** Where the skill would ask the user, I made the call and wrote it down as an open question with a recommended answer (§5).
- **Design-it-twice** (three parallel sub-agents) was done inline and only for the most consequential seam, `view/2` delivery (§4).

## 2. What is already deep (keep it)

- **`Game.apply/3` + `legal_actions/2`.** `apply/3` (`lib/quacks/game.ex:689-698`) checks the action against `legal_actions/2` and nothing else. One rule change = one `legal_actions` clause + one `step` clause, and the page, the bot and the property test pick it up. This is the depth the platform should copy.
- **Rng in the struct.** Seed + actions = the game, so undo, bug reports, debug tables, scenarios and game files are all "replay a list" (`lib/quacks/session.ex:100-105`). The bundle stores only the actions, so **the log's format can change without breaking any stored bundle** (used in §3.8).
- **`QuacksWeb.ActionCode`** (`lib/quacks_web/action_code.ex`, 30 lines) is already game-agnostic: any action term to a safe string and back.
- **`GameLive.preview/3`** (`lib/quacks_web/live/game_live.ex:2171`) builds the page's assigns from a bare `%Game{}`, and the gallery renders `GameLive.render/1` with them (`lib/quacks_web/live/gallery_frame_live.ex:66`, `:129`). That is a second adapter at the "game → board" seam, so the seam is real (§3.6).

## 3. Deepening opportunities, ranked

Each entry: files, the problem, current interface → proposed interface, what it feeds, dependency category (`codebase-design/DEEPENING.md`: in-process, local-substitutable, ports & adapters, mock), how tests change, and risk.

### 3.1 Seal `Quacks.Game` behind a read facade (#79) — Strong

**Files:** `lib/quacks/game.ex`, `lib/quacks/game/{potions,fortune,evaluation,witches,essence}.ex`, `lib/quacks/rules/{chips,books}.ex`, callers in `lib/quacks_web/**`, `lib/quacks/ai/**`, `lib/quacks/scenarios/**`.

**Problem.** `Quacks.Game` has 42 public functions; 20 are `@doc false` (`lib/quacks/game.ex:668-1091`) [V]. They are public because the five submodules write through them: `update_player/3` is called 135 times from the submodules, `player/2` 91 times, `record/2,3` 32 times, `move_droplet/3` 13 times [V]. Behind the facade the submodules are themselves wide open: `Fortune` has 57 public functions, `Potions` 36, `Essence` 22 [V], and the web and the bots call into them directly (`Fortune.reveals`, `Fortune.choice_card?`, `Fortune.flea_block`, `Evaluation.targets`, `Evaluation.standings`, `Potions.explode_above`, `Essence.dealt`, `Potions.take_random`) [V]. One web module even **writes** the game: `Reveal.before_game/1` rewinds VP with `Game.update_player/3` (`lib/quacks_web/reveal.ex:430`) [V]. So the real interface of the engine is about 180 functions, not the 8 the guide promises.

The legacy `expansion` field is not only a field: the rules data interface takes it. `Chips.set/3` and `Books.in_play/2` take one `expansion` atom, so `shop_components.ex` (5 calls), `panel_components.ex:309` and `game_live.ex:1137,1147,2016` read `game.expansion` [V]. `GameServer.start/5` takes it as a positional argument (`lib/quacks/game_server.ex:177`).

**Current → proposed interface.**

```elixir
# today: Game.player/2, update_player/3, record/2,3, take_supply/2, return_supply/2,
# add_from_supply/3, move_droplet/3, give_black/2, effect/4, buy/4, buys/2, start_round/1,
# rats/1, turn_order/1, left/2, to_shop/1, done_buying/2, shop_open?/2, available?/2 ...

# proposed facade (Quacks.Game), documented:
new(opts) | legal_actions(g, seat) | apply(g, seat, action) | phase(g, seat)
over?(g) | score(g) | player(g, seat)            # read only
# plus the read helpers the page and bots need, moved here from the submodules:
explode_limit(g, seat) | card_reveals(g) | standings(g) | targets(g, seat) ...

# internal (Quacks.Game.State, @moduledoc false): every writer above.
# Submodules: @moduledoc false; only Game and Game.State call them.
```

`expansions` stays a `MapSet`; `Chips.set/3` and `Books.in_play/2` take the set (or the game).

**Feeds:** #79 directly; #80 needs it, because the behaviour's callbacks are this facade.
**Dependency category:** in-process. No adapter.
**Tests:** none change behaviour. `test/quacks/patient_picks_test.exs` (10 calls to `Game.player/2`) and the LiveView tests keep `player/2`. A Credo check (or a test that greps `lib/quacks_web` and `lib/quacks/ai`) for `Game.State`/`Game.Fortune` calls keeps the seal closed. ⚠️ Dialyzer is not in `mix precommit` (`mix.exs:89-95`), which is how `@type seat :: 0..4` (`lib/quacks/game.ex:134`) survived next to 8-player games; consider adding it once the facade is small.
**Risk:** low. Mechanical, no behaviour change. The one trap: game files on disk and bug bundles written with `expansion` must still load (`Session.decode_opts/1`, `lib/quacks/session.ex:183`, reads `"expansion"`); keep the decoder tolerant and drop only the field.

### 3.2 `Session` holds an opaque game config (#80) — Strong

**Files:** `lib/quacks/session.ex`, `lib/quacks/game_server.ex`, `lib/quacks/game_store.ex`, `lib/quacks/ai/{sim,bench}.ex`, `lib/quacks/scenarios/script.ex`.

**Problem.** The game's options (`sets`, `rules`, `fortune`, `expansion`, `expansions`, `witches`, `patients`) are restated in: the struct (`lib/quacks/session.ex:10-20`), `@game_opts` (`:35`), `new/3` (`:54`), `undo/1` (`:83-95`, which lists them again by hand), `bundle/1` (`:117`), `from_bundle/2` (`:140`), `encode_opts/1` and `decode_opts/1` (`:170`, `:183`) [V]; then again in `GameServer.start/5`, `create/3`, `configure`, `valid?/2` and `table/1` (`lib/quacks/game_server.ex:177`, `:203`, `:935`, `:1551`, `:1710`) [V], and in `Sim.run/1` and `Bench` (`Keyword.take(opts, [:sets, :rules, :expansion, :expansions])`). Adding one option touches about ten places; the deletion test says `Session`'s option handling is a pass-through that spreads complexity.

**Current → proposed interface.**

```elixir
# today
Session.new(seed, players, sets: .., rules: .., expansion: .., expansions: .., witches: .., patients: ..)
Session.bundle(s) :: %{version: 1, seed, players, opts: %{sets, rules, expansions, witches, patients}, log}

# proposed (Table.Session)
Session.new(module, seed, players, config) :: {:ok, t} | {:error, term}
Session.apply(s, seat, action) | Session.undo(s) | Session.game(s)
Session.bundle(s) :: %{version: 2, game: "quacks", seed, players, config, log}
Session.from_bundle(map, at \\ nil)              # version 1 reads as game "quacks"
# the game owns its config:
module.config(map) :: {:ok, config} | {:error, term}   # validates; replaces valid?/2
module.encode_config(config) :: map ; module.decode_config(map) :: config
```

`GameServer` then keeps `config` as one opaque value; `table/1` asks the game for the settings summary instead of reading `opts[:witches]`.

**Feeds:** #80 ("one opaque `opts` map that the game validates, and the bundle format version").
**Dependency category:** in-process.
**Tests:** `test/quacks/bundle_test.exs` and `debug_replay_test.exs` become the golden suite: freeze a few v1 bundles (one per expansion mix) as fixtures and assert they replay to the same score.
**Risk:** low–medium. Old game files and bug reports must keep loading; the v1 path covers it. `undo/1` already passes a different list from `new/3` (no `expansion`, no `fortune`); it works only because `Game.new/1` folds `fortune:` into `rules` and derives `expansion`. That is the drift this removes. ⚠️ The encoder never writes the top-level `fortune:` alias, so no stored v1 bundle should rely on it; not checked against real files.

### 3.3 `Table.Game` behaviour plus `view/2`, with a second adapter now (#80, #78) — Strong

**Problem.** Every generic module calls `Quacks.Game` by name: `Session` (`lib/quacks/session.ex:73`), `GameServer` (15+ calls), `Sim`, `Bench`, `Script`, the property test. With one adapter the behaviour would be a hypothetical seam; the skill's rule, and the repo's own TL;DR, say not to add it until something varies across it.

**Proposed interface** (the RFC draft, narrowed):

```elixir
@callback config(map) :: {:ok, config} | {:error, term}
@callback new(config, seed, players) :: state
@callback legal_actions(state, seat) :: [action]
@callback apply(state, seat, action) :: {:ok, state} | {:error, term}
@callback status(state) :: {:playing, [seat]} | {:over, %{seat => score}}
@callback view(state, seat | :spectator) :: view
@optional_callbacks simultaneous?: 1, auto_action: 2, describe: 2, encode_config: 1, decode_config: 1
```

- **Quacks's `view/2` returns a redacted `%Game{}`** (rng dropped, fortune deck as a count), not a new struct. The open bag is public in Quacks (`docs/research/bot-training.md` §1: "Nothing is secret except the order of the chips"), so the page and the 26 function components that take `attr :game` [V] need no rewrite. Card games return their own view struct.
- **The second adapter:** a test-only toy game in `test/support/` with one hidden zone, e.g. "high card": each seat is dealt one card face down, then each seat bids or folds once. About 60 lines. It runs through `Table.Session`, the generic property suite and `Table.Bots` (§3.4) in the same PR that adds the behaviour. No Thanks! (#85) becomes the third adapter.

**Feeds:** #80, #78; every later issue depends on it.
**Dependency category:** in-process.
**Tests:** the property test in `test/quacks/game_test.exs` becomes a generic suite parameterised by module: a legal action exists until over; replay is deterministic; an illegal action changes nothing; `view(state, seat)` holds no other seat's hidden zone (the toy game proves this last one, since Quacks has no hidden zone).
**Risk:** medium. The cost is the toy game and the naming; the risk is designing the behaviour around Quacks alone, which the toy game is there to prevent.

### 3.4 One bot driver (`Table.Bots`) and a second `Decider` (#81, #80) — Strong

**Files:** `lib/quacks/game_server.ex:1101-1435`, `lib/quacks/ai/{sim,bench,decider}.ex`, `lib/quacks/scenarios/script.ex`.

**Problem.** "Ask each bot seat for an action, apply it, carry its rng" is written six times: `GameServer` tick (`:1122`), plan (`:1266`), step (`:1358`), brew (`:1413`), `Sim.act/3` (`lib/quacks/ai/sim.ex:89`), `Bench` (`lib/quacks/ai/bench.ex:186`) and `Script` (`lib/quacks/scenarios/script.ex:160`) [V]. All call `Quacks.AI.decide/4` by name; the `Quacks.AI.Decider` behaviour (`lib/quacks/ai/decider.ex`) has one adapter and no caller uses it as a behaviour [V]. The server's version also holds the hard part, "decide in secret, reveal together" (`plan/2`, `flush/1`, `:1233-1285`), which Sushi Go! (#86) needs as is.

**Current → proposed interface.**

```elixir
# proposed (pure)
Table.Bots.plan(game_mod, state, bots, rngs) :: {[{seat, action}], rngs}   # one decision per ready seat
Table.Bots.plan_phase(game_mod, state, seat, bot, rng) :: {[action], rng}  # a whole secret part
Table.Bots.run(game_mod, state, bots, rngs, until) :: {state, rngs}        # Sim, Bench, Script
# Decider gets a game module and gains Table.Bots.RandomLegal as its second adapter.
```

The server keeps the timers and the queue; the choice of who acts and what is pure and testable.

**Feeds:** #81 (bot scheduling), #80 ("make `AI.Decider` generic"), epic step 5 (random-legal, then ISMCTS).
**Dependency category:** in-process (the server's timers stay outside the module).
**Tests:** `test/quacks/game_server_r10_test.exs` and `game_server_test.exs:503` use `:sys.replace_state/2` to clear bot ticks [V]: they test past the interface. The pacing rules become plain function tests; the server keeps a few flow tests.
**Risk:** medium. Bot rngs are persisted in game files (`lib/quacks/game_server.ex:1683`, restored at `:371`); the order in which bots draw from them must not change, or restored games diverge (they would still be legal, just different). Bench numbers must match before and after on a fixed seed.

### 3.5 `GameServer` keeps the table; Quacks policy behind callbacks (#81) — Strong

**Problem.** The moduledoc says "The rules stay in the pure `Quacks.Game`; this module only stores, serialises and announces" (`lib/quacks/game_server.ex:12-13`). It does not [V]:

| Quacks knowledge in the server | Where | Proposed callback |
|---|---|---|
| The simultaneous phases | `@concurrent`, `:1222` | `simultaneous?(state)` (engine fact) |
| Bots brew in step with humans; the sub-phases that count as "drawing" | `held?/1` `:1315`, `step_bots/4`, `brew_bots`, `drawing?/2` `:1426`, `mid_draw?/2` `:1373` | `bot_pace(state) :: :tick \| {:lockstep, ready_fun}` |
| The Mandrake auto-answer and its take-back | `keep_white/2` `:447`, `auto_return/1` `:1208` | `auto_action(state, seat)` + a generic `take_back/2` |
| Patients picked before the game | `pick_patient/3` `:527`, `put_pick`, `drop_pick`, `renumber_picks`, `again_picks` `:1447-1530`, `patient_opts`, `dealt_pick` | a generic per-seat pre-game pick in the config |
| The reveal moments a seat acknowledges | `ack/4` guard `[:card, :results, :recap, :final]` `:572` | `moments()` declared by the game |
| The settings the page shows | `table/1` `:1710` (`witches`, `patients`, `expansion(s)`) | `settings_summary(config)` |

The "drawing" list is the same five sub-phases as the engine's private `brewing?/1` (`lib/quacks/game.ex:837`), copied twice in the server [V]; `GameLive` has its own copy of `stir?` (`lib/quacks_web/live/game_live.ex:3156`) that differs from the engine's (`lib/quacks/game.ex:797`: no phase check) [V]. Three copies of a rule, one already drifted.

**Feeds:** #81; with §3.4 it leaves `Table.Server` free of `Quacks.*`.
**Dependency category:** local-substitutable (a process, PubSub and the store dir, which tests already pass as `store: nil`).
**Tests:** `test/quacks/game_server_test.exs` and `game_server_r10_test.exs` stay as the acceptance suite (#81 says so). New: a policy test per callback, in-process.
**Risk:** medium–high. The bot pacing (rounds 36–37) was tuned by feel; behaviour must stay identical. Do §3.4 first so the pacing is pure before it moves.

### 3.6 `GameLive`: the reveal player and the board assigns (#82) — Strong

**Files:** `lib/quacks_web/live/game_live.ex` (3,328 lines, 347 `def`/`defp` [V]), `lib/quacks_web/{reveal,tile_reveal,replay}.ex`, `lib/quacks_web/live/gallery_frame_live.ex`, `test/support/game_helpers.ex`.

**Problem.** The hottest file in the repo holds five modules in one:

1. the waiting room (`render(%{game: nil})`, `:924-1081`) and seat, rename, colour, host events — table concerns;
2. the bug report form, tips, the debug scrubber — table concerns;
3. **the reveal player**: a state machine over `%{key, slides, index, tick, settle, held, tiles, rubies}` with timers (`open_reveal/1` `:2302` to `auto_done/2` `:3134`; 135 functions match reveal/slide/tile/seen/tick/hold [V]). It is the churn centre: `tile_reveal*` and `reveal*` have 65 commits between them [V];
4. **the board assigns**: `put_game/2` (`:2247`), `decide/4`, `bar_choice`, `kept_selection` — pure derivations from `(game, seat, ui)`;
5. the board render (`render/1`, `:1082-2077`, about 1,000 lines of HEEx).

**Proposed interfaces.**

```elixir
# pure, no socket (QuacksWeb.RevealPlayer; generic part later TableWeb.Moments)
RevealPlayer.sync(player, game, seat, seen, prefs) :: {player, [effect]}
RevealPlayer.next(player, ctx) :: {player, [effect]}
RevealPlayer.tick(player, ref, ctx) :: {player, [effect]}
# effect :: {:after, ms, msg} | {:ack, kind, round} | :close

# pure (QuacksWeb.Board): the seam the gallery already uses through preview/3
Board.assigns(view, seat, ui) :: map
# GameLive becomes: table shell + Board.assigns + RevealPlayer + <.board>.
```

**Feeds:** #82. The reveal player's generic half (moments, slides, auto-advance, per-seat "seen") is what Hearts' trick reveal and Sushi Go!'s flip need.
**Dependency category:** in-process for both extracted modules; the LiveView keeps timers and PubSub.
**Tests:** 23 LiveView test files hand-build a state with `replace_game/2`, which `:sys.replace_state`s **into the server's state shape** (`st.session.game`, `test/support/game_helpers.ex:92-98`) [V]; `action_bar_test.exs` alone does it 34 times. That couples 12.5k lines of LiveView tests [V] to `GameServer` internals, and §3.5 breaks them. Move "this state shows this bar" tests to `GameLive.preview/3` / `Board.assigns/3` (no server); keep server-driven tests for flows. The reveal player gets plain unit tests for its timing rules.
**Risk:** high in effort, medium in behaviour: gallery snapshots (`test/quacks_web/ui_snapshot_test.exs`) and the 360/392/1280 checks are the safety net. Start with the reveal player: it is the hot spot and has the cleanest seam.

### 3.7 `Table.Kit.Rng` and `Deck`; defer `Bag`, `Dice`, `Zone` (#83) — Worth exploring

**Problem.** The game rng is split into independent streams by counting `:rand.jump/1` calls by hand: the fortune deck 1 jump (`lib/quacks/game/fortune.ex:85`), witches 2 (`lib/quacks/rules/witches.ex:119`), patients 3 (`lib/quacks/rules/alchemists.ex:163`), the patient picks 4 (`lib/quacks/game/essence.ex:67`) [V]. Two hand-written shuffles sort by a uniform draw (`fortune.ex:85-86`, `rules/alchemists.ex:167`). The deals sit in `Quacks.Rules.*`, which AGENTS.md reserves for data.

**Proposed interface.**

```elixir
Table.Kit.Rng.stream(rng, n) :: rng            # n jumps: a named stream table per game
Table.Kit.Rng.shuffle(list, rng) :: {list, rng} # the current sort-by-uniform algorithm, unchanged
Table.Kit.Rng.pick(list, rng) :: {item, rng}
Table.Kit.Deck.new/deal/draw/discard/reshuffle  # No Thanks! needs it (#85)
```

Quacks declares its streams once (`@streams %{fortune: 1, witches: 2, patients: 3, picks: 4}`), and the deals move from `Rules.*` into the engine.

**Deletion test on the rest of #83.** `Kit.Bag` would wrap `Potions.take_random/3` (`lib/quacks/game/potions.ex:644-653`, 10 lines): deleting it would not concentrate anything, so it is shallow until a second bag game exists. `Kit.Dice` has one user (the bonus die, `evaluation.ex:125`). `Kit.Zone` has no consumer until `view/2` redaction exists for a card game. Build each when its second user arrives.
**Feeds:** #83, #85.
**Dependency category:** in-process.
**Tests:** the #83 properties (a shuffle is a permutation, deterministic per seed) plus a golden test: a fixed seed deals the same fortune deck, witches and patients before and after.
**Risk:** low, if the algorithms stay byte-for-byte; any change re-deals every stored game.

### 3.8 The engine logs what each event paid; `describe/2` (#84, #82) — Worth exploring

**Problem.** `QuacksWeb.Replay.gain/1` (`lib/quacks_web/replay.ex:272-308`) maps 36 kinds of log event back to `{vp, rubies}`. Some of those numbers are rules: purple trade tiers `{1,1}`, `{3,0}`, `{6,1}` (`replay.ex:288-290`) repeat the payout table in `Evaluation.choose/3` (`lib/quacks/game/evaluation.ex:368-373`) [V], which is itself logic, not data in `Rules.Books`. `Reveal`, `TileReveal` and the results slides all read `Replay`. A rule change to a payout needs a web change. Separately, the core module `Quacks.BugReports` calls `QuacksWeb.GameText.log_text/3` (`lib/quacks/bug_reports.ex:23`, `:178`) [V]: the core depends on the web.

**Proposed interface.** Events carry their effect: `{:effect, book, detail, %{vp: n, rubies: n}}` (or one `{:gain, seat, source, delta}` per payout), so `Replay.gain/1` reduces to a lookup. Payout tables move to `Rules.*` data. The game supplies `describe(entry, ctx) :: String.t()` (the RFC's optional callback); `BugReports` calls it through the game module.
**Feeds:** #84 (each rule's numbers in one place, tests tagged by rule), #82 (a generic reveal reads deltas, not Quacks events).
**Dependency category:** in-process.
**Tests:** reveal and results tests stay; `Replay` unit tests shrink.
**Risk:** low for stored games: bundles hold actions, not the log (§2), so a new log format replays fine. Medium for UI snapshot churn.

### 3.9 One "open choices / close when nobody answers" module (#78 `Table.Pending`, #84) — Worth exploring

**Problem.** The pattern "put every seat with a choice in phase X; after each answer, close the seats with nothing left; when nobody is in X, run the next step" is written four times: `Fortune.open_choices/close_choices` (`lib/quacks/game/fortune.ex:678`, `:704`), `Evaluation.close_choices` (`lib/quacks/game/evaluation.ex:80`), `Witches.open_gold/close_gold` (`lib/quacks/game/witches.ex:172`, `:184`), `Essence.open/close` (`lib/quacks/game/essence.ex:263`, `:280`) [V]. The round order is not written anywhere: it is a chain of tail calls across modules (`Fortune.close_choices` → `Essence.run` → `Evaluation.run` → `Witches.open_gold` → `Evaluation.score` → the shop) [V]. Understanding "what comes after B2" means bouncing through four files (the skill's first friction signal). `fortune.ex` is the engine's hottest file.

**Proposed interface.**

```elixir
# Quacks.Game.Round: the round as data
@steps [:card, :rats, :potions, :b2, :essence, :die, :chip_actions, :gold_witches, :score, :shop]
# Table.Pending (generic)
Pending.open(state, phase, seats_with_choices) :: state
Pending.answer(state, seat, answered?, on_close) :: state
```

**Feeds:** the RFC's `Table.Pending`; Sushi Go!'s simultaneous pick and Hearts' pass are the same shape. Later the effect stack (#75, Codex, Mage Wars).
**Dependency category:** in-process.
**Tests:** behaviour tests by rule stay; the property test and frozen v1 bundles (§3.2) guard ordering.
**Risk:** medium–high. The ordering carries many fixes ("round 28" in `game.ex:860-864`, more in `fortune.ex`), and some cards change the order (`@rats_first`). Do it after the golden replays exist, and only when Sushi Go! gives the second user.

### 3.10 Generic scenario `Script` and golden replays (#84) — Worth exploring

**Problem.** `Quacks.Scenarios.Script` (`lib/quacks/scenarios/script.ex`) is nearly game-agnostic (a seeded `Session`, `act`, `mark`, `play` until a predicate, `bundle`), but it hard-codes `Quacks.AI` with the `:balanced` profile (`:160`) while the table bots are `:expert` (`lib/quacks/game_server.ex:99`) [V]. `Builders` is Quacks-only, which is right.
**Proposed interface.** `Table.Script` over a game module and a `Decider`; `Builders` stays in Quacks. Bug-report bundles that found a bug become fixtures under `test/fixtures/replays/` with the expected score.
**Feeds:** #84 ("a generalised scenario builder", "golden replays").
**Dependency category:** in-process.
**Risk:** low.

### Candidates considered and dropped

- **Split `Quacks.Player` out further.** Deletion test: it would move field updates, not concentrate them.
- **`GameText` as a generic module.** It is 674 lines of Quacks words; only `log_lines/3` is generic. It goes behind `describe/2` (§3.8), not into a kit.
- **LobbyLive.** 1,282 lines but cold (9 commits) and its only Quacks coupling is the set-up pages, which #82 lists separately. Not a deepening target yet.

## 4. Design it twice: how a page gets its `view`

The RFC (#78) leaves open how `view/2` reaches the page. Three designs, compared on depth, locality and seam placement:

| Design | Interface | Depth / locality | Cost |
|---|---|---|---|
| **A. Per-seat messages.** The server computes `view(state, seat)` for each page and sends one message per seat. | Server knows every page's seat; `{:view, id, view}` | Redaction in one place (the server). But N views per action, and the server must track spectators and seat changes. | Medium; more work on every action. |
| **B. Version ping, page pulls.** The server broadcasts `{:changed, id, version}`; each page calls `get_view(id, seat)`. | One extra call per page per action | Redaction in the server; pages stay simple. Doubles the messages; ordering is easy (version). | Medium. |
| **C. Full state in the BEAM, view in the page.** The server keeps broadcasting the state; the page applies `module.view(state, seat)` in `handle_info` **before** any assign, and never assigns the raw state. | One function at the page's entry | Redaction is a pure function with its own property test; zero server change. The rule "no raw state in assigns" is enforced by a test (assigns hold a `view`, never a `state`). | Low. |

**Recommendation: C now, B if the table ever runs on more than one node** ⚠️. PubSub messages never reach the browser, so A and B buy nothing against a browser attacker; they only matter if the BEAM itself is untrusted, which it is not. What C needs is discipline at one seam: `GameLive.put_game/2` (`lib/quacks_web/live/game_live.ex:2247`) is already the one place where a game enters the assigns, and `preview/3` the second. Bots read `view/2` too, so a card-game bot cannot cheat (ISMCTS then samples hidden zones with a `determinize/2` callback).

## 5. Open questions (the grilling, answered by me)

- **Q1 — Namespace.** `Table.*` in this app, or an umbrella? ➡️ In this app, `lib/table/`. An umbrella adds build friction before there is a second consumer.
- **Q2 — Where Quacks's table policy lives.** Callbacks on `Quacks.Game`, or a separate module? ➡️ `simultaneous?/1` on the game (a rules fact); `auto_action/2` and `bot_pace/1` in a separate `Quacks.TablePolicy` (they are product choices, not rules, and keep the engine free of UX).
- **Q3 — Quacks's view shape.** ➡️ A redacted `%Game{}` (§3.3), so no board rewrite.
- **Q4 — The second adapter.** Toy game in `test/support/`, or wait for No Thanks!? ➡️ Toy game now; No Thanks! is the third.
- **Q5 — Bundle versioning.** ➡️ v2 with `"game"`; v1 is Quacks forever, tested by frozen fixtures.
- **Q6 — Keep `Game.player/2` public?** ➡️ Yes, as a documented read. Only writers go internal.
- **Q7 — `replace_game/2` in LiveView tests.** ➡️ Keep it during #79–#81, move board-state tests to `preview/3` during #82, then delete it.
- **Q8 — `Table.Pending` timing.** ➡️ After golden replays, with Sushi Go!.
- **Q9 — `Kit.Bag`, `Dice`, `Zone`.** ➡️ Build each with its second user (§3.7).
- **Q10 — ADRs.** ➡️ Create `docs/adr/` lazily; the first two worth writing are "view applied in the page (§4)" and "Table.Game lands with a second adapter".

## 6. Which of Matt Pocock's skills to vendor

**Licence:** MIT, "Copyright (c) 2026 Matt Pocock" (`mattpocock/skills/LICENSE`). Copying and changing is allowed if the copyright and permission notice go with the copies: put `LICENSE` (or a `NOTICE` with it) in each vendored skill directory and note the upstream commit (`49dd158`).

**Copy, do not symlink.** `.claude/skills/recmem` and `.claude/skills/writing-skills` are symlinks to `/Users/nick/dev/webinargeek/ai/skills/...` [V]. In a cloud session they point nowhere, so those skills silently do not load. Vendored skills must be real files in the repo.

| Skill | Vendor? | Why | Adaptations |
|---|---|---|---|
| `codebase-design` (+ `DEEPENING.md`, `DESIGN-IT-TWICE.md`) | **Yes, now** | The shared vocabulary for #79–#83; small (195 lines); model-invoked, so it loads when a design question comes up. The "one adapter = hypothetical seam" and "interface is the test surface" rules are exactly the calls this epic has to make. | Examples are TypeScript; add one Elixir example (behaviour + two adapters). Drop `agents/openai.yaml`. |
| `improve-codebase-architecture` | **Yes, adapted** | Re-run it per game (after No Thanks!, after Hearts) to keep `Table.*` deep. User-invoked only. | Point `GLOSSARY.md` → `docs/CONTEXT.md` (and per-game `docs/games/<game>/CONTEXT.md`); write the report to `docs/research/` in house style instead of an HTML file opened from the temp dir; it calls `grilling` and `domain-modeling`, so vendor `grilling` (30 lines) too or cut those calls. |
| `tdd` (+ `tests.md`, `mocking.md`) | **Yes, with #84** | The rulebook pipeline is "tests first, then engine"; the skill's vertical slices and "test at agreed seams" fit `@tag rule: "§x.y"` tests. | ExUnit examples; name the seams of this repo (`Game.apply/3`, `Board.assigns/3`, `GameLive` flows). |
| `domain-modeling` | **Later, adapted** | Useful for each new game's `CONTEXT.md` and for the first ADRs. | Its rule "GLOSSARY.md should be devoid of implementation details" clashes with `docs/CONTEXT.md`, which names functions on purpose. Decide that first. |
| `diagnosing-bugs` | Optional | The repo already has the feedback loop it asks for (bug bundle → `/debug/replay` → `mix quacks.replay`). | Would need the bundle tools named in it. |
| `grill-with-docs`, `to-spec`, `to-tickets`, `triage`, `wayfinder`, `implement*`, `setup-matt-pocock-skills`, `code-review`, `pr`, `prototype`, `wizard` | No | They assume Matt's issue-tracker and label conventions, or overlap with built-in commands (`/code-review`). | — |

Two notes from running them: the skills contain instructions to open files, use CDNs and run sub-agents; all were treated as optional method text. And the skills' file layout (`GLOSSARY.md` at the root, `docs/adr/`) is not this repo's; every vendored copy needs that one edit, or the skills will create a second glossary.

## 7. Other findings (small, no candidate)

- `AGENTS.md` says the engine exposes `apply/2`; the real reducer is `apply/3` (`apply/2` is the seat-0 shortcut, `lib/quacks/game.ex:678`).
- The `Quacks.Game` moduledoc says "Each seat (`0..3`" (`lib/quacks/game.ex:9`) and `@type seat :: 0..4` (`:134`); games have up to 8 seats.
- `Quacks.Session.undo/1` replays from the seed each time (`lib/quacks/session.ex:83-95`): fine for Quacks (about 1 ms a game), worth a snapshot every N actions for longer games. ⚠️ No measurement for card games yet.
- `QuacksWeb.GameText` aliases `QuacksWeb.AlchemistsComponents` and `Quacks.GameServer`: a text module that depends on a component module and the server.

## Sources

- Matt Pocock, `mattpocock/skills` at `49dd158`: `skills/engineering/improve-codebase-architecture/SKILL.md`, `HTML-REPORT.md`; `skills/engineering/codebase-design/SKILL.md`, `DEEPENING.md`, `DESIGN-IT-TWICE.md`; `skills/engineering/{tdd,domain-modeling}/SKILL.md`; `skills/productivity/grilling/SKILL.md`; `GLOSSARY.md`; `LICENSE` (MIT).
- Issues #75, #77, #78, #79, #80, #81, #82, #83, #84, #85, #86 (read through the GitHub REST API on 2026-10-15).
- This repo: `AGENTS.md`, `docs/GUIDE.md`, `docs/guide/02-engine.md`, `docs/CONTEXT.md`, `docs/research/state-machine-liveview.md`, `docs/research/bot-training.md`, and the files cited above. Counts come from `grep` and `git log` on `3904137`; nothing was compiled or run (no Elixir in the container).
