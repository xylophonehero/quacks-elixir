# Speed check, 2026-10-11

Scope: the live Fly apps `quacks-staging` and `quacks`, plus one local measurement.
Read-only: no code, config, secret or machine was changed.

## Summary

1. **The server is fast.** In about 43 hours of staging play with the timing log
   (2026-10-09 00:00 to 2026-10-10 22:09 UTC), no action and no LiveView event took
   50 ms or more. Locally, `handle_event("action")` is p50 0.2 ms, p99 1-4 ms, and a
   render is p50 0.6-0.8 ms. The engine, the bots and the game file do not cause the slowness.
2. **Staging runs out of memory.** The 256 MB machine has about 207 MB for the OS
   and the BEAM. At rest the machine uses about 190 MB (p50), so only 20-30 MB is free.
   The kernel killed the BEAM **9 times** in 4 days (5 times in 4 minutes on
   2026-10-07 00:23-00:28). Each kill drops every socket. The player sees
   "reconnecting", then a full page re-render. Prod has the same size and the same
   headroom (p50 188 MB used, minimum 16 MB free). Prod had no kill only because it gets little use.
3. **Half of the staging sockets use long-polling, not WebSocket.** 207 of 405
   staging connections (51 %) came on `:longpoll`. Prod: 11 of 61 (18 %). With
   long-polling, each tap is one HTTP POST, and each server push (a bot move)
   needs a new poll request. This adds at least one network round trip to each
   update. When LiveView falls back to long-polling, the browser tab stays on it.
   The restarts (from item 2 and from 51 deploys) are a probable cause.
4. **Each update is big.** A draw sends about 15-17 KB of uncompressed JSON. A shop
   or results step sends 30-96 KB. The WebSocket does not compress. A bot move in a
   4-seat game re-sends all 4 player sheets, not only the sheet that changed. On a
   phone, the download and the DOM patch of a big diff cost more time than the
   server work.

## Data sources and time span

| Source | What | Span |
|---|---|---|
| Fly logs API (`/api/v1/apps/<app>/logs`, paged with `next_token`) | all retained log lines: staging 4,286, prod 581 | staging 2026-10-06 20:41 to 2026-10-10 22:09 UTC; prod 2026-10-04 09:58 to 2026-10-10 21:22 UTC |
| `fly logs --no-tail` | the last 100 lines only (not enough) | last ~40 minutes |
| Fly Prometheus (`api.fly.io/prometheus/personal`) | memory, CPU, throttle, OOM exit, proxy HTTP times, status codes | 5-minute steps, 2026-10-03 to 2026-10-10 |
| `fly status`, `fly scale show`, `fly machine status` | machine size and region | now |
| Local run (`MIX_ENV=test`, LiveViewTest, no HTTP server) | one full game, solo and 4 seats (1 human + 3 bots): telemetry times, size of each payload to the client, process memory | 2026-10-10 |

Files are in the scratchpad `speed/` directory: `fetch_logs.py` (log pager),
`parse_logs.py` (parser), `prom.sh` (Prometheus range query), `measure.exs` (local
game run), `diffsize.py` (payload break-down), the raw logs (`*_all.jsonl`) and the
results (`measure1.txt`, `measure4.txt`, `prom_*.json`).

Limits of the data:

- The timing lines log at `:info` only from 50 ms (`@slow_ms`). Prod logs at
  `:info`. Thus the logs show only slow lines, and there were none. There is no
  distribution of normal times from the live apps.
- Prod (`master`) does not have the timing code yet. Staging got it on 2026-10-09 (PR #21 merge).
- Fly keeps about 4 days of logs for staging. Older lines are gone.
- The local render time runs with `enable_expensive_runtime_checks`, so it is an upper limit.

## Machines

| App | Region | Size | Memory | Machines | Used memory p50 / max | Free memory min |
|---|---|---|---|---|---|---|
| quacks-staging | ams | shared-cpu-1x | 256 MB (207 MB usable) | 1 | 191 MB / 213 MB | 4 MB |
| quacks | ams | shared-cpu-1x | 256 MB (207 MB usable) | 1 | 188 MB / 201 MB | 16 MB |

- CPU: p50 0.15 %, p90 0.9 % (staging). It reached 87-100 % only at boots (09-09 16:00, 10-10 07:50, 10-10 21:30). No throttle. The CPU balance never ran out.
- Shared memory (`fly_instance_memory_shmem`) is a constant 37-39 MB. The OOM lines show `shmem-rss` 61 MB in `beam.smp`. A probable cause is the JIT's dual-mapped code area (memfd). This is not confirmed.
- At each kill, `beam.smp` had about 122 MB anonymous + 61 MB shared RSS.
- Network from Nick's Mac to staging: TCP connect 21 ms, TLS done 50 ms, first byte of `/` 90-180 ms.

## Timing lines from the logs

| Line | Staging (since 2026-10-09) | Prod |
|---|---|---|
| `action game=... total_ms>=50` | 0 | not deployed |
| `live_event ... ms>=50` | 0 | not deployed |

In the same span there were about 180 LiveView connects and many full games on
staging. Thus every action and every event was faster than 50 ms on the server.

HTTP dead renders (Phoenix `Sent 200 in`):

| Route | n | p50 | p90 | p99 | max |
|---|---|---|---|---|---|
| staging `/` | 118 | 4 ms | 8 ms | 17 ms | 51 ms |
| staging `/g/:id` | 46 | 4 ms | 8 ms | 13 ms | 13 ms |
| prod `/` | 34 | 3 ms | 6 ms | 9 ms | 9 ms |
| prod `/g/:id` | 9 | 3 ms | 7 ms | 7 ms | 7 ms |

Fly proxy response times (all HTTP, 14 days): staging 6,320 responses. 1,409 took
5-15 s. These are long-poll GETs that the server holds open on purpose, not slow
pages. They show how much long-polling there is: staging had 6,104 HTTP 200s but only
about 400 page loads.

## Local measurement (one full game)

Seat 0 plays with the bot AI through real `"action"` events. The other seats are bots.

| | Solo | 4 seats (1 human, 3 bots) |
|---|---|---|
| actions by seat 0 | about 140 | about 130 |
| `handle_event("action")` | p50 0.13 ms, p90 0.22 ms, p99 3.1 ms | p50 0.21 ms, p90 0.42 ms, p99 1.0 ms, max 4.2 ms |
| render | p50 0.61 ms, p90 0.93 ms, max 5.1 ms | p50 0.78 ms, p90 1.2 ms, max 16 ms |
| reply to own action (JSON) | p50 14.6 KB, p90 22 KB, max 55 KB | p50 17.5 KB, p90 30 KB, max 96 KB |
| push for a bot move (JSON) | none | 64 pushes, p50 12.5 KB, p90 15.9 KB, max 18.5 KB |
| total sent to one page in one game | 2.3 MB | 3.6 MB |
| gzip of the same payloads | about 4-6x smaller (15.2 KB to 2.5 KB; 96 KB to 17.6 KB) | |
| HTML of the game page (dead render) | 78 KB waiting, 126 KB in game | |
| LiveView process memory at game end | 2.9 MB | 2.9-4.7 MB |
| GameServer process memory | 0.1 MB | 0.4 MB (log of 1,172 entries) |

The bot batch work (the bots brew with the human's draw, and their plans for a
concurrent phase flush in one go) is inside the GameServer call. It is included
in the `handle_event` times above. It is not a cost.

The JSON of a draw is about 40 % strings and 60 % diff structure. One 15 KB bot-move
push has 793 strings and only 155 different ones. It holds the `close_player` hook
of all 4 seats, the ingredient book texts, and 18 copies of the same SVG chip
attributes. Thus each move re-renders the whole board, not only the changed part.

## Problems, by what the player feels

### 1. "Reconnecting" and lost moments: memory kills and restarts (high)

- Staging: 9 OOM kills, 58 boots and 51 deploys in 4 days. Each boot closes all
  sockets. The pages reconnect (often on long-poll, see item 2), mount again,
  get the full page (about 126 KB of HTML), and the GameServer restores from the
  game file. During the boot, Fly returned "instance refused connection" 114 times.
- Five kills came 13-71 s after a boot (2026-10-07 00:23-00:28 and 2026-10-10 19:00).
  Thus the boot itself (restore of all game files, reconnect of all pages) pushes
  memory over the limit when the base is already about 190 MB.
- Prod has the same base and the same limit. It will have the same kills when more people play.

Causes: 256 MB is too small for this release. The base use is about 190 MB before
any game. Each open game page adds 3-5 MB (the LiveView process), and each mount
renders 78-126 KB of HTML.

### 2. Each tap is slower on long-poll (high, mostly on phones)

- 51 % of staging connections and 18 % of prod connections use long-polling.
- On long-poll, a tap is one POST and the reply. A bot move needs the open GET to
  return and a new GET to start. That is at least one more round trip per update
  (about 50-150 ms on mobile networks), and a new HTTP request through the Fly proxy for each update.
- LiveView falls back after `longPollFallbackMs: 2500` when the WebSocket does not
  open in time. The tab then stays on long-poll. A restart, a slow phone network,
  or a deploy can cause this. Item 1 makes it happen more often.

### 3. Big payloads for each move (medium; it adds time on each draw)

- A draw is about 15-17 KB of JSON. A shop or results step is 30-96 KB. Without
  compression, on a 4G phone this is about 20-100 ms of transfer per update. The
  browser must also parse it and patch a large DOM.
- Cause: the board templates take the whole `@game` (and other big assigns) as
  their input. When `@game` changes, LiveView cannot know which part changed, so it
  renders all of it again: all player sheets, the books, the track, the log.
- The WebSocket has no `compress: true`. The long-poll responses are not gzipped either.

### 4. Things that are not a problem

- Engine time, bot planning, the GameServer mailbox, and the game file write (debounced, 500 ms, not in the reply path).
- CPU: no throttle, and use stays under 1 % except at boot.
- Dead render time: p99 under 20 ms.
- Planned waits are on purpose: a bot tick waits 700 ms (`:bot_delay`), and the
  droplet or flask move shows for 800 ms (`@show_move_ms`). If play with bots
  feels slow, check these first. They are design choices, not server cost.

## Fixes

| # | Fix | Where (module, behaviour) | Expected gain | Size |
|---|---|---|---|---|
| 1 | Set both apps to 512 MB | `fly.toml`, `fly.staging.toml` `[[vm]] memory`, or `fly scale memory 512` | stops the OOM kills and the restart loops after them. Fewer restarts also means fewer long-poll fallbacks | XS (config; about +2 USD per month per app) |
| 2 | Turn on WebSocket compression | `QuacksWeb.Endpoint` `socket "/live"`: `websocket: [compress: true, ...]` | about 4-6x fewer bytes per update (15 KB to about 2.5-3.5 KB). Small CPU cost | XS |
| 3 | Get pages back to WebSocket | `assets/js/app.js` LiveSocket: raise `longPollFallbackMs` (for example 2500 to 6000-8000), and clear the stored fallback after a successful WebSocket connect on a later page load. Also log the transport for each game page (see logging) | fewer tabs stuck on long-poll. Saves at least one round trip per bot move | S |
| 4 | Make diffs small: render only what changed | `GameLive` and `GameComponents`: give each board part only its own data (one player's sheet gets that player, not `@game`); for the player sheets and the log, use a keyed comprehension or LiveComponents, or streams; keep big static texts (book descriptions, tips) out of the parts that change | a bot move to about 1-3 KB, a draw to about 2-5 KB (before compression), and less DOM patching on the phone | M-L (fits the UI refactor that is in progress) |
| 5 | Make the boot lighter | `Quacks.GameStore.restore/1`: start the restored games one at a time or lazily (on the first `get`), and do not start bot ticks before a page connects | lower memory and CPU peak at boot, which is when 5 of the 9 kills came | S |
| 6 | Smaller dead render | `GameLive` mount: render a light shell on the dead render (no full board until `connected?`) | about 126 KB less HTML on each page load and reconnect | S-M |
| 7 | Find the base memory | `fly ssh console`, then `:erlang.memory()` and `/proc/<pid>/status` in the release | explains the 190 MB base and the 61 MB shared memory (JIT?) | XS (investigation) |

Recommended order: 1 and 2 now (configuration only), then 3, then 4 in the UI refactor.

## Logging and metrics for the next check

- **Log the normal times too, not only the slow ones.** Every 60 s, write one
  summary line for each action and event with count, p50, p90 and max (for example
  `timing_summary action=draw n=120 p50_ms=0.3 p90_ms=0.8 max_ms=4`). Without this
  the logs show nothing when everything is fast.
- **Log the payload size.** Add the size of each diff that goes to the client (from
  a `[:phoenix, :live_view, :render, :stop]` handler, or in the socket serializer) and the render time.
- **Log the transport for each game page** (`websocket` or `longpoll`) with the
  game id, so a slow player can be matched to long-poll.
- **Measure in the browser.** A small hook can time "tap to DOM patched" with
  `pushEvent` and its reply, and send p50 and p90 for each page to the server at
  intervals. This is the number the player feels. The server cannot see it.
- **Log memory.** Every 60 s, log `:erlang.memory(:total)`, process count and
  the number of LiveView processes (telemetry_poller already runs every 10 s). Set a
  Fly alert or check `fly_instance_exit_oom` after each play session.
- **Keep the logs longer.** Fly keeps only about 4 days. Ship the logs to a log
  service (Fly log shipper), or copy them with `fetch_logs.py` after each test session.
