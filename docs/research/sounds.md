# Sounds for Quacks

Research note, 2026-10-11. Research and plan only: no app code is changed (a UI
refactor is in progress). Nick: "Something simple for drawing a chip since we do it a
lot and more fun for exploding."

Audition files: `scratchpad/sounds/` of session `03974705` (see §3.4), and the demo
page `scratchpad/sounds/demo/index.html` (all candidates, plus synthesised variants).
⚠️ = not verified first-hand.

## TL;DR

- Use the **Web Audio API**: one `AudioContext`, small decoded buffers, play with
  `AudioBufferSourceNode`. Do not use `<audio>` elements for effects (latency and
  overlap problems on iOS).
- **Unlock** the context in the first tap (`ctx.resume()` in a `click`/`touchend`
  handler). Keep the default iOS "ambient" audio session, so the **silent switch
  mutes the game**. That is correct for a game that people play in public.
- **Format:** one file per sound, **AAC-LC in `.m4a`, mono, 44.1 kHz, 64 kbps**
  (Ogg Opus is smaller, but Safari decodes Ogg only from iOS 18.4). Size budget for
  the MVP: **under 30 KB**; for the full list: under 150 KB.
- **MVP = 2 sounds:** the chip **draw/land** (soft wooden or casino-chip tick,
  3 samples round-robin, ±4 % pitch) and the **explosion** (cartoon pop + low thump +
  bubbles, about 1 s).
- **Sources:** all CC0. Kenney.nl packs (Casino Audio, Impact Sounds, Sci-fi Sounds,
  Interface Sounds, RPG Audio, Music Jingles), OpenGameArt CC0 packs, freesound.org
  CC0 sounds. Do not use the Sonniss GDC bundles (§3.1).
- **Synthesis:** a Web Audio synthesised tick is a good second choice for the draw
  (0 bytes, unlimited variation), but a recorded sample sounds more "real". Nick
  picks on the demo page.
- **Settings:** a Sound row in the game menu (On/Off + volume), kept in
  `localStorage["quacks:sound"]`, client only.

---

## 1. Best practices for game sound on mobile web

### 1.1 Web Audio API, not `HTMLAudioElement`

| | Web Audio (`AudioBufferSourceNode`) | `<audio>` / `new Audio()` |
|---|---|---|
| Latency | Low: the buffer is decoded in memory; `start(when)` is sample-accurate. | High and variable on iOS (tens to hundreds of ms). |
| Overlap | Unlimited: each play is a new, cheap source node. | One element plays one sound; overlap needs a pool of elements. |
| Pitch / gain per play | `playbackRate`, `GainNode`, per play. | `playbackRate` only; `volume` is read-only on iOS. |
| Scheduling | `start(ctx.currentTime + 0.37)`: sync to an animation offset. | `setTimeout` only. |
| Unlock | One `resume()` in a gesture unlocks the whole context. | Each element must play once in a gesture. |

Decision: **Web Audio for all effects.** No library is needed (Howler.js is 10 KB and
wraps the same API; our needs are ~60 lines).

### 1.2 Unlock, autoplay and the iOS silent switch

- All browsers start an `AudioContext` in the state `"suspended"` when no user
  gesture came first (Chrome autoplay policy, Safari, Firefox). Call `ctx.resume()`
  **inside** a user gesture handler. Use `pointerup`, `touchend`, `click` and
  `keydown` (iOS does not count `touchstart` in all versions ⚠️). After the first
  `resume()` succeeds, remove the listeners.
- In the same gesture, play a 1-sample silent buffer. This is the old iOS unlock
  trick and costs nothing.
- Create the context lazily (on the first gesture), not at page load. Then no
  console warning shows and no audio hardware wakes up for people who never play.
- iOS can put the context in the state `"interrupted"` (phone call, Siri, another
  app takes audio). On the next gesture, call `resume()` again. Check
  `ctx.state !== "running"` before each play and try to resume.
- **Silent switch:** iOS Safari puts a page with an `AudioContext` in the
  **"ambient"** audio session. The ring/silent switch mutes it, and it mixes with
  the user's music (it does not stop a podcast). From iOS 17 (Safari 17),
  `navigator.audioSession.type = "playback"` ignores the switch and stops other
  audio. **Recommendation: keep "ambient"** (set `navigator.audioSession.type =
  "ambient"` when the API exists, so the choice is explicit). A board game must not
  stop the user's music or sound in a meeting when the phone is on silent.
- Android has no silent switch: the media volume controls the sound. Our own Sound
  Off setting is the mute there.

### 1.3 Preloading and decoding

- Fetch and decode all buffers once, on the first gesture (after `resume()`), with
  `fetch(url) → arrayBuffer() → ctx.decodeAudioData()`. Keep a `Map` name → array of
  `AudioBuffer` (one array entry per round-robin sample).
- Files are tiny (2–10 KB each), so preload all. Do not lazy-load per event: the
  first explosion must not wait for the network.
- Decoded memory: 1 s mono at 44.1 kHz = 176 KB of float32. The full list is under
  6 s of audio, so under 1 MB of memory.
- If a play request comes before its buffer is ready, **drop it** (do not queue).
  A late sound is worse than no sound.
- Phoenix serves `priv/static/sounds/` with `Plug.Static` and digests the files with
  `mix phx.digest` (add `sounds` to `static_paths/0` in `quacks_web.ex`). Use the
  digested path (`~p"/sounds/draw-1.m4a"`) in a `data-sounds` attribute on `<body>`
  or the layout, or set long cache headers. The service worker (`/sw.js`) is
  pass-through, so it does not interfere.

### 1.4 File format

| Format | Chrome / Android | Firefox | Safari macOS / iOS | Size (1 s mono) |
|---|---|---|---|---|
| **AAC-LC `.m4a`** | Yes | Yes | Yes (all versions) | ~8 KB @ 64 kbps |
| MP3 | Yes | Yes | Yes | ~8 KB @ 64 kbps, but ~25 ms encoder padding at the start |
| Ogg Opus | Yes | Yes | Only from 18.4 ([source](https://github.com/bricedupuy/Songverse/issues/185)) | ~6 KB @ 48 kbps |
| WebM Opus | Yes | Yes | `decodeAudioData` fails on some Safari versions ⚠️ | ~6 KB |
| WAV | Yes | Yes | Yes | 88 KB (16-bit) |

Decision: **one format, AAC-LC `.m4a`.** No fallback list is needed. Encode with
`ffmpeg -i in.wav -ac 1 -ar 44100 -c:a aac -b:a 64k out.m4a`. Trim the silence at the
start of each file (`silenceremove`), or the tick lags. Measured sizes of the MVP
candidates as `.m4a`: 2.5–3.5 KB per draw sample, 2.5–9.4 KB per explosion layer.

Size budget: MVP under 30 KB, full list under 150 KB. For comparison, one pot SVG
patch is larger than all the draw samples.

### 1.5 Mixing and fatigue

A player draws about 90 chips per game (polish-ideas.md §18). A sound that plays
100+ times must be **short, soft and varied**:

- **Duration:** draw tick 60–200 ms. No tail, no reverb.
- **Level:** use a fixed gain table. Draw 0.35–0.5, land 0.4, explosion 1.0
  (the loudest sound in the game), UI ticks 0.25. A master `GainNode` applies the
  user's volume on top.
- **Variation (anti machine-gun):** 3 samples, round-robin (never the same sample
  twice in a row), plus random `playbackRate` 0.96–1.04 (±4 %, about ±0.7
  semitone), plus random gain ±10 %. This is the standard approach in game audio.
- **Frequency:** keep the draw sound in the mid and high range (1–4 kHz click). Phone
  speakers do not play under ~300 Hz, so the explosion's low thump must also have a
  mid "crack" or pop that a phone speaker plays.
- **Ducking:** when the explosion plays, stop any draw sound that plays (fade out in
  30 ms). One rare, loud sound must not mix with ten small ones. A simple rule: at
  most 4 voices at a time; a new voice over the limit drops.
- **Rate limit:** a bot's draws come every ~700 ms; your own draws can be faster.
  Do not play the same sound twice in 50 ms.
- **No music** in the MVP. Background music causes the most "turn off sound"
  reactions on mobile.

### 1.6 User settings

- **Sound On/Off** and **Volume** (3 steps: Low, Medium, High are enough on a
  phone; or a range input). Keep them in `localStorage["quacks:sound"]` as
  `{v: 1, on: true, volume: 0.7}`, in the same way as `quacks:reveal` and
  `quacks:risk`.
- **Default:** On at Medium is the recommendation (with the ambient session, the iOS
  silent switch is a natural mute). Decision for Nick (§6).
- `prefers-reduced-motion` is **not** a sound preference. Do not mute sounds with it.
  (There is no `prefers-reduced-sound` media query today.)
- **Hidden tab:** on `visibilitychange` with `document.hidden`, call
  `ctx.suspend()`; on visible, `ctx.resume()`. A bot's draws in a background tab must
  not make noise. Also do not play when `document.hidden` is true.
- **Haptics:** sound and haptics are separate channels. The explosion buzz (`Boom`)
  stays as it is. Sound Off must not turn off haptics.

### 1.7 Accessibility

- Sound only **adds** to the visual feedback. Each sound event already has a visual
  sign (chip animation, BOOM, ruby flight, fuse meter). Never put information only in
  sound.
- The explosion sound must not be a startle: peak at -1 dBFS, a soft attack (5–10 ms),
  under 1.2 s.
- Sound On/Off must be easy to find (game menu) and work with a keyboard and a screen
  reader (a real `<input type="radio">` segmented control, like the Tips row).
- Screen reader users hear VoiceOver over the game sound. Keep effects short so they
  do not mask speech.

### 1.8 Battery and performance

- An `AudioContext` that runs keeps the audio hardware awake. Suspend the context
  after ~30 s with no sound, and on hidden tab. Resume it on the next play (resume
  takes a few ms; the next sound plays at once if the context still runs).
- Source nodes are one-shot and garbage-collected after they end. Do not keep them.
- Do not use `OscillatorNode` loops or a running `ScriptProcessorNode`.
- Synthesised sounds cost a little CPU per play (a few nodes, < 200 ms). This is not
  a problem.

---

## 2. Sound list mapped to events

Priority: **MVP** = first build. **P2** = second batch. **P3** = later, if wanted.

| # | Event | Character | Length | Gain | Where it fires (app.js) | Priority |
|---|---|---|---|---|---|---|
| 1 | **Chip draw / lands in pot** (your own) | Soft wooden tick or casino-chip clack, 3 samples, ±4 % pitch | 60–200 ms | 0.45 | `PotMotion.fly()` at landing (offset 0.8 of 460 ms ≈ 370 ms) | **MVP** |
| 2 | **Explosion** (your own) | Cartoon pop + low thump + bubbles | 0.8–1.2 s | 1.0 | `Boom.mounted()` (same moment as the BOOM stamp and the buzz) | **MVP** |
| 3 | Chip lands, other pots (bot draw shown on the large pot) | Same as 1, quieter, or none | 60–200 ms | 0.2 | `PotMotion.land()` at offset 0.55 of 350 ms ≈ 190 ms | P2 (decision §6) |
| 4 | White chip near the limit | A low "fizz" or a short tense hum on the white draw when the next white can explode | 200 ms | 0.3 | `fly()` when the new chip is white and the risk is high (needs `data-colour` and the risk on the pot) | P2 |
| 5 | Stop | A cork "plop" | 150 ms | 0.4 | Stop button click (or the pot's `data-stopped` change) | P3 |
| 6 | Ruby gain | A small glass "ting" | 150–300 ms | 0.35 | `PotMotion.flights()`: at each ruby flight's end (`delay + 550 ms`) | P2 |
| 7 | Scoring / VP count-up tick | Very soft tick, pitch rises per step | 30–60 ms | 0.2 | Reveal beats (results overlay, `--beat-ms`) | P3 |
| 8 | Shop buy | Coins + chip drop in the bag | 300 ms | 0.4 | Shop submit (Buy) | P2 |
| 9 | Rat tails | Small squeak or patter | 200 ms | 0.3 | `PotMotion.ratsIn()` | P3 |
| 10 | Fortune card flip | Card place/slide | 300–600 ms | 0.35 | `phx:quacks:vt` with type `card` | P2 |
| 11 | Round end (chips to the bag) | A short rattle (chips into a bag) | 400 ms | 0.35 | `PotMotion.toBag()` | P3 |
| 12 | Game over | Short jingle, ~1.5 s | 1.5 s | 0.6 | Game-over sheet opens (`phx:quacks:open` to the game-over dialog) | P2 |

Notes:

- **Play at the landing, not at the click.** The tap sends an event to the server;
  the patch arrives after a network round trip; the chip then flies for 460 ms. A
  sound on the click is "early" and plays also when the server rejects the draw. In
  `fly()`, schedule the sound with `start(ctx.currentTime + 0.368)` (the land
  keyframe is at offset 0.8 of 460 ms). With reduced motion there is no flight: play
  at once.
- **Explosion timing today:** the BOOM stamp (`.boom`, 700 ms) shows on the same
  patch that adds the white chip, so BOOM starts while the chip still flies. For
  sound: play the explosion in `Boom.mounted()` (in sync with BOOM and the buzz) and
  **do not** play the draw tick for that chip (the explosion covers it). Later, if
  the BOOM waits for the chip to land, the sound waits with it (one `delay` value).
- `Boom` uses a `sessionStorage` key per game and round, so a reload does not buzz
  again. The explosion sound uses the same guard (put the play inside the same
  `if`).
- A move in the pot (green III, `moved` in `updated()`) and the chips that fly to the
  flask (`ghost`) need no MVP sound.

---

## 3. Sourcing

### 3.1 Licences

| Source | Licence | Public web game? | Notes |
|---|---|---|---|
| **Kenney.nl** audio packs | **CC0** (public domain) | Yes, no credit needed | Best fit. Consistent quality, game-ready, short, trimmed. Credit "Kenney.nl" is nice, not required. |
| **OpenGameArt.org** | Per item: CC0, CC-BY, CC-BY-SA, GPL | Yes, if CC0 (or CC-BY with credit) | Filter for CC0. Check each page's licence line. |
| **freesound.org** | Per sound: CC0, CC-BY, CC-BY-NC | CC0: yes. CC-BY: yes with credit. CC-BY-NC: no (not safe) | Use the licence filter "Creative Commons 0". Downloads need a free account; previews (`cdn.freesound.org/previews/…-hq.mp3`) are lossy 128 kbps. |
| **Sonniss #GameAudioGDC bundles** | Royalty-free licence, commercial use, no credit ([licence](https://sonniss.com/gdc-bundle-license/)) | Yes, in the game | Prohibits distribution "as sound effects" and AI training. Our files are plain downloadable files in `priv/static`, and the repo may be public. **Do not use** (risk: raw files in a public repo count as redistribution). |
| Pixabay sound effects | Pixabay Content Licence | Yes ⚠️ | Not CC0. Its own licence prohibits standalone redistribution. Avoid for the same reason. |

Rule for the builder: **CC0 only**, and record each file's source URL and licence in
`priv/static/sounds/LICENSES.md` (or a comment block in the sound module).

### 3.2 MVP candidates

**Chip draw / land** (pick one set of 3 samples):

| Id | Candidate | URL | Licence | Why |
|---|---|---|---|---|
| D1 | Kenney Casino Audio `chip-lay-1..3.ogg` (0.17–0.24 s) | https://kenney.nl/assets/casino-audio | CC0 | Real chip on a table: the closest match to a chip into a pot. 3 natural variants. ~2–3 KB each as `.m4a`. |
| D2 | Kenney Impact Sounds `impactWood_light_000..004.ogg` (0.27 s) | https://kenney.nl/assets/impact-sounds | CC0 | Warm wooden "tock": fits the wood/parchment look. 5 variants. A little longer and louder than D1. |
| D3 | Kenney Casino Audio `chips-collide-1..4.ogg` (0.22–0.26 s) | https://kenney.nl/assets/casino-audio | CC0 | Chip hits other chips: "into a full pot". Busier, so it can tire faster. |
| — | freesound "Basic Click Wooden" by GameAudio (0.5 s) | https://freesound.org/people/GameAudio/sounds/220200/ | CC0 | Clean UI-style wooden click. Backup only (more "button" than "chip"). |
| D4/D5 | **Synthesised** wooden tick / "plop" (Web Audio, no file) | demo page | n/a | 0 bytes, unlimited variation, tunable. See §3.3. |

**Explosion** (pick one):

| Id | Candidate | URL | Licence | Why |
|---|---|---|---|---|
| X1 | **Layered mix** (built here): unfa "Cartoon Pop (Clean)" + Kenney `lowFrequency_explosion_001` (+40 ms) + OGA `bubble_01` (+150 ms) | https://freesound.org/people/unfa/sounds/245645/, https://kenney.nl/assets/sci-fi-sounds, https://opengameart.org/content/40-cc0-water-splash-slime-sfx | all CC0 | "Fun, bigger": a comic pop, a thump, then the pot bubbles. Exactly Nick's brief. ~9 KB. |
| X2 | Kenney Sci-fi Sounds `lowFrequency_explosion_001.ogg` (1.0 s) | https://kenney.nl/assets/sci-fi-sounds | CC0 | Soft boom, not violent. Weak on phone speakers (mostly low end) alone. |
| X3 | OpenGameArt "25 CC0 bang / firework SFX" `bang_08.ogg` (0.87 s) | https://opengameart.org/content/25-cc0-bang-firework-sfx | CC0 | A real bang. More "firework" than "cauldron". |
| — | freesound "Crispy Nuclear Bomb Sound Cartoon CC0" by modusmogulus | https://freesound.org/people/modusmogulus/sounds/745138/ | CC0 | Cartoon explosion, but 12 s long: would need a cut. Backup. |
| — | OpenGameArt "bubbles 'pop'" / "3 Pop Sounds" / "Pop sounds" (EZduzziteh) | https://opengameart.org/content/bubbles-pop, https://opengameart.org/content/3-pop-sounds, https://opengameart.org/content/pop-sounds-0 | CC0 | Alternative pop layers for X1. |
| X4/X5 | **Synthesised** boom (noise burst + falling sine + random bubbles), or the unfa pop + synthesised bubbles | demo page | n/a | Tunable; no file. Can sound "cheap" if overdone. |

### 3.3 Synthesis vs a sample for the draw

A synthesised tick: a 4 ms noise burst through a band-pass filter at ~2.5 kHz, plus
a short sine "body" at ~700 Hz that decays in 60 ms; random pitch and filter
frequency per play. A "plop": a sine that glides from 300 to 900 Hz in 80 ms with a
fast decay (the classic water-drop sound).

| | Sample (D1/D2) | Synthesis (D4/D5) |
|---|---|---|
| Realism | Better: a real chip. | Clean but "electronic". |
| Variation | 3 samples × pitch jitter. | Unlimited (every parameter can vary). |
| Size | ~8 KB for 3 samples. | 0 bytes, ~20 lines of JS. |
| Latency | Same (both in memory). | Same. |
| Licence | CC0 record needed. | None. |

Recommendation: **a sample (D1 or D2) for the draw**; keep synthesis for the small
UI ticks (scoring count-up), where realism does not matter. If Nick likes D4/D5 on
the demo page, synthesis is a valid, simpler MVP (no asset pipeline). Nick decides
on the demo page.

### 3.4 Downloaded files (scratchpad, not in the repo)

Folder: `/private/tmp/claude-501/-Users-nick-dev-quacks-elixir/03974705-894b-485e-b686-7ae950bddfcf/scratchpad/sounds/`

| Path | Source | Licence |
|---|---|---|
| `kenney_casino-audio/` | https://kenney.nl/assets/casino-audio | CC0 (`License.txt` in the pack) |
| `kenney_impact-sounds/` | https://kenney.nl/assets/impact-sounds | CC0 |
| `kenney_interface-sounds/` | https://kenney.nl/assets/interface-sounds | CC0 |
| `kenney_rpg-audio/` | https://kenney.nl/assets/rpg-audio | CC0 |
| `kenney_sci-fi-sounds/` | https://kenney.nl/assets/sci-fi-sounds | CC0 |
| `kenney_music-jingles/` | https://kenney.nl/assets/music-jingles | CC0 |
| `kenney_digital-audio/` | https://kenney.nl/assets/digital-audio | CC0 |
| `oga/pop.ogg` | https://opengameart.org/content/bubbles-pop | CC0 |
| `oga/3pops/` | https://opengameart.org/content/3-pop-sounds | CC0 |
| `oga/pop1..9.wav` | https://opengameart.org/content/pop-sounds-0 | CC0 |
| `oga/bubbles-single1..3.wav` | https://opengameart.org/content/bubble-sound-effects | CC0 |
| `oga/water-splash-slime-sfx/` | https://opengameart.org/content/40-cc0-water-splash-slime-sfx | CC0 |
| `oga/25-CC0-bang-sfx/` | https://opengameart.org/content/25-cc0-bang-firework-sfx | CC0 |
| `freesound-previews/*.mp3` | unfa 245645/245646, modusmogulus 745138, GameAudio 220200, BenjaminNelan 321083, qubodup 182429 (freesound.org) | CC0 (each page checked). These are the lossy previews; download the originals with a free account before shipping. |
| `mvp/*.m4a`, `mvp/*.ogg` | D1–D3 and the explosion candidates, encoded mono AAC 64 kbps and Opus 48 kbps | as their source |
| `demo/` | The demo page and its MP3s | as their source |

(`oga/Bubble_Explo.zip` is a sprite animation, not a sound. Ignore it.)

---

## 4. Implementation plan (for a later builder)

### 4.1 `Sound` module in `assets/js/app.js` (or `assets/js/sound.js`, imported)

About 70 lines. Sketch:

```js
// Game sounds (docs/research/sounds.md). One AudioContext, made and unlocked on
// the first gesture; buffers decoded once; settings in localStorage["quacks:sound"].
const Sound = (() => {
  const files = JSON.parse(document.body.dataset.sounds || "{}") // {draw: [url, url, url], boom: [url]}
  const gains = {draw: 0.45, land: 0.2, boom: 1.0, ruby: 0.35, buy: 0.4, card: 0.35, gameover: 0.6}
  const buffers = new Map(), last = new Map()
  let ctx = null, master = null, voices = 0, idle = null
  const settings = () => { try { return {on: true, volume: 0.7, ...JSON.parse(localStorage.getItem("quacks:sound"))} } catch (_e) { return {on: true, volume: 0.7} } }
  const unlock = () => {
    if (!ctx) {
      if (navigator.audioSession) navigator.audioSession.type = "ambient"
      ctx = new AudioContext()
      master = ctx.createGain(); master.connect(ctx.destination)
      Object.entries(files).forEach(([name, urls]) => Promise.all(urls.map(u =>
        fetch(u).then(r => r.arrayBuffer()).then(b => ctx.decodeAudioData(b))))
        .then(bs => buffers.set(name, bs)).catch(() => {}))
    }
    if (ctx.state !== "running") ctx.resume().catch(() => {})
  }
  ;["pointerup", "touchend", "keydown"].forEach(t => addEventListener(t, unlock, {capture: true, passive: true}))
  document.addEventListener("visibilitychange", () => ctx && (document.hidden ? ctx.suspend() : ctx.resume()))
  // play("draw", {delay: 0.368, pitch: 0.04})
  const play = (name, {delay = 0, pitch = 0.04, gain = 1} = {}) => {
    const s = settings(), list = buffers.get(name)
    if (!s.on || !ctx || ctx.state !== "running" || document.hidden || !list || voices >= 4) return
    const i = list.length > 1 ? (((last.get(name) ?? -1) + 1 + Math.floor(Math.random() * (list.length - 1))) % list.length) : 0
    last.set(name, i)
    const src = ctx.createBufferSource(), g = ctx.createGain()
    src.buffer = list[i]
    src.playbackRate.value = 1 + (Math.random() * 2 - 1) * pitch
    g.gain.value = (gains[name] ?? 0.5) * gain * (0.9 + Math.random() * 0.2)
    master.gain.value = s.volume
    src.connect(g).connect(master)
    voices++; src.onended = () => voices--
    src.start(ctx.currentTime + delay)
    clearTimeout(idle); idle = setTimeout(() => ctx.suspend(), 30000)
  }
  return {play, unlock}
})()
```

Notes for the builder:

- Round-robin: the index rule above never picks the same sample twice in a row.
- The idle timer suspends the context after 30 s; `unlock` resumes it on the next
  gesture (a draw is always after a tap). A bot-only stretch longer than 30 s stays
  silent until the next tap. That is acceptable.
- `data-sounds` on `<body>` (in `root.html.heex`) holds the digested URLs, made with
  `~p"/sounds/…"` (verified routes digest them in prod).

### 4.2 Hooks into existing events

| Event | Change |
|---|---|
| Your own draw lands | In `PotMotion.fly()` (only for a draw, not a move: `s0 !== 1`): `Sound.play("draw", {delay: 0.368})`. In the reduced-motion early return: `Sound.play("draw")`. Skip it when the pot is exploded (`this.el.dataset.exploded === "true"`), because the explosion plays. |
| Explosion | In `Boom.mounted()`, after the `sessionStorage` guard, next to `navigator.vibrate`: `Sound.play("boom", {pitch: 0.02})`. |
| Bot draw on the large pot (P2) | In `PotMotion.land()`: `Sound.play("land", {delay: 0.19})` only if Nick wants it (§6). |
| Ruby (P2) | In `flights()`: `Sound.play("ruby", {delay: (delay + 550) / 1000})`. |
| Card flip (P2) | In the `phx:quacks:vt` listener when `e.detail?.type === "card"`. |
| Game over (P2) | In the `phx:quacks:open` listener when the target is the game-over dialog (or a `data-sound="gameover"` attribute on it). |
| Shop buy (P2) | A `data-sound="buy"` attribute on the Buy button; one delegated `click` listener plays `data-sound` names. Play only on a real buy (button enabled). |

### 4.3 Settings row

- In the game menu, next to `<.tips_settings>` (`game_live.ex`, the menu block near
  `<.reveal_settings>`): a new `sound_settings/1` component, same look as the Tips
  row (segmented On/Off) plus a `range` input for volume (0–1, step 0.1) or a
  3-step segmented Low/Med/High.
- The state is client only (the server does not need it). Give the form
  `phx-hook="SoundSettings"` and `phx-update="ignore"`, so a patch does not reset
  the checked state. The hook reads `localStorage["quacks:sound"]` on mount, sets the
  inputs, and writes on `change`. When the volume changes, it plays one draw tick as
  a preview.
- Do not add a lobby setting. (Optional later: a speaker icon in the header for a
  one-tap mute.)

### 4.4 Assets

`priv/static/sounds/` (add `sounds` to `static_paths/0`):

| File | Source | Size (m4a) |
|---|---|---|
| `draw-1.m4a`, `draw-2.m4a`, `draw-3.m4a` | D1 or D2 (Nick's pick) | ~3 KB each |
| `boom.m4a` | X1 layered mix (or Nick's pick) | ~9 KB |
| `LICENSES.md` | source URL + licence per file | — |
| P2: `ruby.m4a`, `buy.m4a`, `card.m4a`, `gameover.m4a`, `land-*.m4a` | Kenney Interface / RPG / Casino / Music Jingles | ~3–13 KB each |

**Size estimate:** MVP ≈ 18 KB. MVP + P2 ≈ 60 KB. Full list ≈ 90 KB.

### 4.5 Tests

- **ExUnit / LiveView:** the settings row renders (`#sound-settings`), and
  `<body data-sounds>` lists existing files (`File.exists?` on each digested path in
  a test). No audio test in Elixir.
- **Gallery / scenario:** use the existing scenarios (`/scenarios`) for an explosion
  and a draw. Optional: a gallery story "Sounds" with one button per sound name (a
  `phx-click` that dispatches `quacks:sound` with the name), so a designer can hear
  each sound at its gain.
- **Manual phone checklist (Nick):**
  1. iPhone Safari, silent switch **off**: first tap unlocks; draw ticks at the
     landing; explosion plays with the buzz.
  2. iPhone, silent switch **on**: no sound (ambient session).
  3. iPhone with music in another app: the music keeps playing under the game.
  4. iPhone: a phone call or Siri, then back: the next tap restores sound.
  5. Android Chrome: sound follows the media volume; Sound Off mutes all.
  6. Installed PWA (iOS and Android): same results as 1–5.
  7. 10 fast draws: no "machine gun" (round-robin and pitch audible), no clipping.
  8. Switch tab during a bot's turn: no sound from the hidden tab.
  9. Reload after an explosion: no second boom (sessionStorage guard).
  10. Reduced motion on: sounds still play (draw at once, no flight delay).
  11. Volume Low/High; Sound Off survives a reload.

---

## 5. Effort

- MVP (module + 2 hooks + settings row + 4 files): **S–M**, about half a day.
- P2 sounds: **S** each (one line per hook plus a file).

## 6. Decisions for Nick

1. **Draw sound:** D1 (casino chip), D2 (wooden tock), D3 (chips collide), or a
   synthesised D4/D5? (Demo page.) Recommendation: D1 or D2.
2. **Explosion:** X1 (layered pop + thump + bubbles), X2, X3, or synthesised X4/X5?
   Recommendation: X1.
3. **Default:** Sound On (recommended, with the iOS silent switch as a mute) or Off
   until the player turns it on?
4. **Silent switch:** respect it ("ambient", recommended) or play through it
   ("playback": louder, but stops the user's music)?
5. **Bot draws:** silent (recommended for the MVP), or a quieter tick?
6. **Explosion sync:** BOOM shows while the chip still flies. Keep the sound in sync
   with BOOM (recommended now), or later delay both until the chip lands?

## Sources

- Kenney.nl assets (CC0): https://kenney.nl/assets/casino-audio,
  https://kenney.nl/assets/impact-sounds, https://kenney.nl/assets/sci-fi-sounds,
  https://kenney.nl/assets/interface-sounds, https://kenney.nl/assets/rpg-audio,
  https://kenney.nl/assets/music-jingles
- OpenGameArt (CC0): https://opengameart.org/content/25-cc0-bang-firework-sfx,
  https://opengameart.org/content/40-cc0-water-splash-slime-sfx,
  https://opengameart.org/content/bubbles-pop, https://opengameart.org/content/3-pop-sounds,
  https://opengameart.org/content/pop-sounds-0, https://opengameart.org/content/bubble-sound-effects
- freesound.org (CC0): https://freesound.org/people/unfa/sounds/245645/,
  https://freesound.org/people/modusmogulus/sounds/745138/,
  https://freesound.org/people/GameAudio/sounds/220200/,
  https://freesound.org/people/BenjaminNelan/sounds/321083/
- Sonniss GDC bundle licence: https://sonniss.com/gdc-bundle-license/
- Safari Ogg Opus from 18.4: https://github.com/bricedupuy/Songverse/issues/185
- iOS ambient session and `navigator.audioSession` (several implementation PRs found
  by search; WebKit explainer ⚠️ not read first-hand):
  https://github.com/smolkaj/jolito/pull/226
- MDN Web Audio API best practices (⚠️ from memory):
  https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Best_practices
- Chrome autoplay policy (⚠️ from memory): https://developer.chrome.com/blog/autoplay
