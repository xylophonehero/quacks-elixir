# Animations for Quacks in Phoenix LiveView

Research note, 2026-10-04. Stack: Phoenix 1.8.15, LiveView 1.2.12, Tailwind v4, no
daisyUI, one `app.js` bundle with colocated hooks. Research only: no code changed.
⚠️ = not verified first-hand.

Skills used as the bar: `find-animation-opportunities`, `animate`, `improve-animations`,
`animation-vocabulary`, `apple-design`, `emil-design-eng`. Words in *italics* are terms
from the animation vocabulary.

## TL;DR

- **Default to CSS that runs when LiveView inserts a node.** A `@keyframes` animation
  starts when an element enters the DOM or when a selector starts to match. LiveView
  inserts a new node when its `id` is new. So "give the thing a stable `id` (or an `id`
  that contains its value) and attach a keyframe" covers most of the list with **zero
  JS**: chip landing, explosion, card flip, ruby/VP pulse, the whole evaluation replay.
- **Stage the evaluation (step B) in the browser with CSS `animation-delay`.** The server
  stays instant and gives each result line a beat number (`style="--beat: 3"`). The
  round-results dialog mounts once per round, so the beats play once. A "Skip" button
  adds one class. No timer process, no `push_event`, no engine change, bots never wait.
- **One small colocated hook (`.PotMotion`, about 80 lines, WAAPI) only for the chip
  flight** from the bag along the spiral, the flask return and the rat-stone hop. These
  need a start point outside the SVG, so CSS alone cannot do them.
- **View Transitions: opt-in per patch only.** LiveView 1.2 has a `dom.onDocumentPatch`
  callback made for `document.startViewTransition`. Wrap only the patches the server
  marks with `push_event(..., dispatch: :before)`. Do not wrap every patch: bots
  broadcast every 700 ms, only one transition runs at a time, and the page ignores
  clicks while one runs. View transitions also do not help inside the SVG pot.
- No library needed. If a later need appears (springs on many elements), Motion's
  `animate` mini (2.3 kB, WAAPI only) is the ceiling.

---

## 1. Techniques, lightest first

Existing motion tokens in `assets/css/app.css` (extend these, do not fork them):
`--ease-out: cubic-bezier(0.23, 1, 0.32, 1)`, `--ease-drawer: cubic-bezier(0.32, 0.72, 0, 1)`.
Sheets already use `@starting-style` + `transition-behavior: allow-discrete`; the flask
glow and book cards already have `prefers-reduced-motion` blocks. Add one token:
`--ease-in-out: cubic-bezier(0.77, 0, 0.175, 1)` (on-screen movement, from the skill).

| # | Technique | JS | Survives LiveView patches? | Use in Quacks |
|---|---|---|---|---|
| 1 | **CSS transition on a changed attribute/style** (`style="translate: …"`, `data-state`) | none | Yes. morphdom changes the attribute; the browser transitions from the current value. Interruptible (retargets). | Droplet slide, flask fill, VP ticker via `@property` |
| 2 | **CSS `@keyframes` on insert** (new `id`, or `:if` element) | none | Yes, plays once per new node. Unchanged nodes are not re-inserted, so it does not replay on later patches. | Chip landing pop, explosion puff, card flip, rat stone pop-in, result beats |
| 3 | **"Key by value"**: `id={"stat-rubies-#{@me.rubies}"}` | none | A new value = a new node = the keyframe plays again. | Ruby / VP pulse on change |
| 4 | **`@starting-style`** entry transition | none | Yes, but ⚠️ Safari 17.x applies it only at page load, not to nodes added later ([mdn/bcd #25643](https://github.com/mdn/browser-compat-data/issues/25643)). Keep it for `<dialog>`/popover (already works here); prefer #2 for patched-in nodes. | Sheets (exists) |
| 5 | **`phx-remove` + `JS.transition`** / `JS.hide(transition: …)` | LV built-in | LiveView keeps the node until the transition `time` ends, then removes it. | Chip leaves pot (flask), pot clears at round end |
| 6 | **`phx-mounted` + `JS.transition`** | LV built-in | Runs once when the element is added. Same effect as #2, but uses Tailwind classes; #2 is shorter. | Not needed |
| 7 | **WAAPI in a colocated hook** (`el.animate(keyframes, opts)`) | ~80 lines | Yes. WAAPI does not write attributes, so morphdom does not fight it; no `phx-update="ignore"` needed. Interrupt with `getAnimations().forEach(a => a.finish())`. | Chip flight bag → spiral, flask return, rat hop |
| 8 | **Hand-rolled FLIP** (measure First, patch, measure Last, Invert, Play) in `beforeUpdate`/`updated` | ~40 lines on top of #7 | Yes with stable ids. | Only if a layout move appears that #1 cannot express (none today) |
| 9 | **View Transitions (same-document)** via `dom.onDocumentPatch` | ~15 lines | Yes; snapshots old/new DOM. | Opt-in: essence marker, round change |
| 10 | **Motion `animate` mini** (2.3 kB) / hybrid (18 kB) | npm dep | Same as #7. | Not now |

### 1.1 CSS keyframes on insert (the workhorse)

LiveView patches with morphdom. Nodes with the same `id` are kept and moved; a new `id`
is a new node. A `@keyframes` animation starts when the node is inserted. Without ids,
morphdom matches siblings by position and tag; in the pot each space `<g>` holds
optional children (`pot_chip`, `scoring_ring`, droplet, rat) that are all `<g>`/`<path>`,
so a new chip can *morph* the old ring node instead of inserting a new one, and the
wrong element animates. **Prerequisite for everything below: stable ids on
`pot_chip`, the droplet and the rat stone.**

```css
@keyframes chip-land {
  from { opacity: 0; scale: 0.9; }   /* never scale(0) */
}
.pot-lg [data-role="pot-chip"] {
  transform-box: fill-box; transform-origin: center;
  animation: chip-land 220ms var(--ease-out);
}
```

Initial mount and reconnect also insert nodes, so all chips pop once on page load.
That is acceptable for a pop. For louder effects (shake, flip) gate them:
`.PotMotion` (or a one-line hook on the layout) sets `data-motion="on"` on the game root
in `mounted()` after one `requestAnimationFrame`; CSS scopes loud keyframes under
`[data-motion="on"]`. A LiveView rejoin keeps keyed nodes, so they do not replay.

### 1.2 `phx-remove` and `JS.transition`

`JS.transition({"transition-opacity duration-200", "opacity-100", "opacity-0"}, time: 200)`
or `phx-remove={JS.hide(transition: …, time: 200)}`. LiveView waits `time` ms before it
removes the node. Fine for SVG `<g>` (Tailwind `opacity-*`/`scale-*` classes work on SVG
with `transform-box: fill-box`). Source: [LiveView JS interop](https://phoenix-live-view.hexdocs.pm/js-interop.html),
`Phoenix.LiveView.JS.transition/3` docs (`deps/phoenix_live_view/lib/phoenix_live_view/js.ex`).

### 1.3 WAAPI hook

Colocated hook (`<script :type={Phoenix.LiveView.ColocatedHook} name=".PotMotion">`) on
the pot `<svg id="pot-…">`. `beforeUpdate()` records the set of chip ids; `updated()`
finds the new ones and animates them. WAAPI runs on the compositor for `transform` and
`opacity` and is interruptible ([emil-design-eng], "Use WAAPI for programmatic CSS
animations"). FLIP background: Paul Lewis, [FLIP your animations](https://aerotwist.com/blog/flip-your-animations/).

Coordinates: the bag is HTML outside the SVG. Convert its centre to SVG user units:
`new DOMPoint(cx, cy).matrixTransform(svg.getScreenCTM().inverse())`. The space
positions are already in the markup (`<g data-space=i transform="translate(x y)">`);
add `data-x`/`data-y` so the hook does not parse the attribute.

### 1.4 View Transitions API

LiveView 1.2 `LiveSocket` option (source comment, `assets/js/phoenix_live_view/live_socket.ts`):

```js
dom: { onDocumentPatch(start) { document.startViewTransition(start) } }
```

`start` must always be called, or the page is stuck. And `push_event(socket, ev, payload,
dispatch: :before)` dispatches an event **before** the patch (LV docs for `push_event/4`,
"Specifying the dispatch phase"). Together they give an opt-in, server-marked transition:

```js
let vtNext = false
window.addEventListener("phx:quacks:vt", () => { vtNext = true })
const reduce = matchMedia("(prefers-reduced-motion: reduce)")
dom: {
  onDocumentPatch(start) {
    const go = vtNext && document.startViewTransition && !reduce.matches
    vtNext = false
    go ? document.startViewTransition(start) : start()
  }
}
```

Support: Chrome/Edge 111+, Safari 18+ (iOS 18+), Firefox 144+ (Oct 2025), so Baseline
newly available ([caniuse](https://caniuse.com/view-transitions),
[Chrome: VT in 2025](https://developer.chrome.com/blog/view-transitions-in-2025)).
Limits that matter here:

- Only one transition runs at a time; a new one skips the old one
  ([Chrome docs](https://developer.chrome.com/docs/web-platform/view-transitions/same-document)).
  Bot broadcasts arrive every 700 ms (`:bot_delay`), so a global wrap would cut
  transitions off all the time.
- Every `view-transition-name` must be unique at the same time, or the transition is
  skipped (same source). Per-chip names = 54 names per pot × pots in sheets.
- While the DOM update is pending, hit testing goes to the document element
  ([spec](https://drafts.csswg.org/css-view-transitions-1/)); ⚠️ in practice the
  `::view-transition` overlay also catches clicks while it animates. A fast "Draw" tap
  can be lost. This alone rules out wrapping the draw patch.
- ⚠️ Inner SVG elements (`<g>`, `<circle>`) are not usable as separate transition
  groups in current engines (not found in the spec either way; the spec only excludes
  non-rendered/fragmented boxes). The pot is one SVG, so chips cannot get
  `view-transition-name`. **Conclusion: no FLIP-by-View-Transition for chips.** Use #7.

Good fits: HTML layout moves that happen rarely and are not tapped through: the essence
marker bead in `flask_strip` (`view-transition-name: essence-marker`), the round
counter in the header at round change.

### 1.5 Reduced motion

`prefers-reduced-motion: reduce` = fewer and gentler, not zero (skills; Chrome docs).
Rule for this project: keep opacity and colour, drop translate/scale/rotate/shake. In
the hook, read `matchMedia("(prefers-reduced-motion: reduce)")` each time (the user
can change it) and fall back to a 150 ms opacity fade at the destination.

### 1.6 Easing with a bounce

Nick wants "a small bounce" on the landing chip. A CSS `linear()` easing can encode a
spring (Baseline since late 2023). Generate it, do not hand-write it: Jake Archibald's
[linear() generator](https://linear-easing-generator.netlify.app/) with a spring of
bounce ≈ 0.2 (skill range 0.1–0.3), and store it as `--ease-spring` next to `--ease-out`.
The same string works in WAAPI's `easing` option.

### 1.7 Testing

CSS and WAAPI motion is invisible to `Phoenix.LiveViewTest`. Test only the data the
server renders: ids, `data-beat`, `--beat` styles, `data-face` on the die. Feel-check in
the browser at 0.25× speed (DevTools Animations panel) on Chrome and iOS Safari.

---

## 2. Opportunities (gated)

Personality: a playful board game at a table, but players repeat the same action
~90 times per game (draw). So: delight only at rare moments (round start, results,
explosion); the draw stays fast and never blocks input.

Trigger column: the assign or log entry that changes. Log entries are
`{seat, entry}`, newest first (`Game.record/3`).

### 2.1 Top 8 (ordered by leverage)

| # | Moment | Trigger | Purpose · Frequency | Technique | Motion (exact) | Reduced motion | Cost |
|---|---|---|---|---|---|---|---|
| 1 | **Chip from bag into the pot, counted along the spiral** | new `pot_chip` id; log `{:drew, chip, index}` | Spatial consistency + explanation (shows *how far* it moved = the value) · ~90/game | Hook `.PotMotion`, WAAPI keyframes | Flight bag → previous position (last chip, or the droplet start): 240 ms `--ease-out`, scale 0.9 → 1. Hops through each space to `index`: 80 ms each `--ease-in-out`, max 4 hops shown (more: one slide). Land: `scale` 1.08 → 1, 160 ms `--ease-spring`. Total ≤ 720 ms, **never blocks Draw**: the next draw calls `finish()` on running animations. | 150 ms opacity fade at the space | M |
| 2 | **Evaluation replay (step B) in the round results** | `#round-results` dialog mounts (phase `:shopping`) | Explanation / preventing a jarring change · 1/round | CSS `animation-delay: calc(var(--beat) * 350ms + 300ms)` per line; server sets `--beat` | Each line: fade + `translate: 0 6px` → 0, 220 ms `--ease-out`, `both` fill. Pot chips that pay light up on the same beat (ring 2px gold, `opacity` 0 → 1 → 0.6, 600 ms). Total line ticks up last (#6). Skip button. | Lines appear with 120 ms opacity stagger, no translate; highlights static | M |
| 3 | **Bonus die roll** | log `{seat, {:bonus_die, face}}` (line at beat 0) | Delight + explanation · 1/round | CSS *stepped animation*: a strip of 7 face frames, `translate` with `steps(6, jump-none)` 600 ms, then settle `scale` 1.15 → 1, 200 ms `--ease-out` | as left; real face is the last frame | Show final face, 200 ms fade | S |
| 4 | **Fortune card flip** | `#card-round-N` dialog mounts (id names the round) | Delight · 1/round | CSS 3D *flip*: inner card `rotateY(180deg)` → `0`, 520 ms `--ease-in-out`, delay 250 ms (after the 300 ms sheet slide). `perspective: 900px`, `backface-visibility: hidden` on both faces. | *Crossfade* back → front, 200 ms | S |
| 5 | **Explosion shake + puff** | `data-exploded` → `"true"` on the pot `<svg>`; `cracked-rim` `<g>` inserted; log `{:exploded, sum}` | State indication · a few/game | CSS: *shake* `translate` ±6 → ±3 → 0 px, 5 steps, 380 ms `--ease-out`, gated by `[data-motion=on]`; rim `<g>` fade-in 300 ms; one puff circle `scale` 0.7 → 1.3, `opacity` 0.5 → 0, 500 ms | Rim colour fade only | S |
| 6 | **VP / ruby ticker** | `@me.vp`, `@me.rubies` change (status bar); round total | Feedback · ~2/round | CSS *number ticker*: `@property --n { syntax: "<integer>"; inherits: false; initial-value: 0 }`, `transition: --n 600ms var(--ease-out)`, shown with `counter-reset: n var(--n); content: counter(n)`. Plus "key by value" pop: `scale` 1.15 → 1, 200 ms. `tabular-nums` already set. | Instant number, colour flash 200 ms | S |
| 7 | **Droplet moves along the track** | `@me.droplet` changes (black, purple 3, die, card, rubies) | Spatial consistency · ~2/round | Move the droplet out of the space groups into one top-level `<g id="droplet-…" style="translate: Xpx Ypx">`; CSS `transition: translate 360ms var(--ease-in-out)`. Straight line between neighbour spaces is fine (moves are 1–2 spaces). Same for the rat stone at round start, plus `chip-land` pop-in. | Instant | S |
| 8 | **Flask pours the white chip back** | `pot_chip` removed with `{:returned, chip}`; flask `full` → empty | Spatial consistency · ≤1/round | `phx-remove` on the chip: 200 ms fade + `scale: 0.9`, then hook flies a ghost chip to the bag (reverse of #1, 260 ms `--ease-out`); flask body fill transitions colour 300 ms `ease` | Fade only | S (+M with ghost) |

### 2.2 Also proposed, lower leverage (B3)

- **Round transition**: at round start, pot chips leave (`phx-remove`, 180 ms fade,
  20 ms *stagger* newest first), round number in the header crossfades via the opt-in
  view transition. The fortune card dialog (#4) covers most of this moment anyway.
- **Essence marker slide** (Alchemists `flask_strip`): opt-in view transition with
  `view-transition-name: essence-marker`, 300 ms `--ease-in-out`. Marked by
  `push_event(socket, "quacks:vt", %{}, dispatch: :before)` when `essence` changes.
- **Test-tube droplet** (reverse pot side): same as #7 inside `test_tubes`.

### 2.3 Rejected

- **Global view transition on every patch.** Blocks taps for its duration, one at a
  time, cut off by bot broadcasts every 700 ms. *Function* and *frequency* gates.
- **Bot "thinking" pulse.** A bot acts 700 ms after its turn starts; a pulse would
  flash for less than one cycle, ~tens of times per round. A static "thinking…" label
  on the `player_chip` is enough. *Frequency* gate. (Revisit if `:bot_delay` grows
  above ~1.5 s.)
- **Action log lines sliding in.** Text the user reads, tens per round. *Function* gate.
- **Small pots in player sheets / other seats' draws.** Information-dense, read-only;
  animate only your own large pot. *Function* gate.
- **Hover motion on pot spaces.** Spaces carry data (coins/VP); 54 targets, frequent.
  *Frequency* + *function* gates.

---

## 3. Implementation plan (`polish` branch, 3 batches)

Every batch: `mix precommit`, feel-check at 0.25× in Chrome DevTools and on iOS Safari,
reduced motion checked with DevTools rendering emulation (Chrome, not Vivaldi; see
memory note).

### B1 — CSS only, highest value per line (no JS)

1. `assets/css/app.css`: add `--ease-in-out` and `--ease-spring` (generated) next to
   `--ease-out`; one "Motion" section with all keyframes below and one
   `@media (prefers-reduced-motion: reduce)` block at its end.
2. `game_components.ex` `pot/1`: add `class="pot-#{@size}"` on the `<svg>`;
   `pot_chip/1` gets `id={"pot-#{seat}-#{size}-chip-#{index}"}` (pass `seat`/`index`
   in), `data-order` (position in `player.drawn`) for B3. Rat stone gets
   `id="rat-#{seat}-#{size}"`.
3. Chip landing pop (`chip-land`, §1.1) on `.pot-lg [data-role=pot-chip]`. This is the
   cheap half of #1 and stays as the reduced-motion fallback later.
4. Droplet (#7): render it once after the spaces loop as
   `<g id={"droplet-#{@seat}-#{@size}"} data-role="droplet" style={"translate: #{x}px #{y}px"}>`
   (positions from `@positions`); CSS transition on `translate`. Same for the rat stone.
5. Explosion (#5): `[data-motion=on] .pot-lg[data-exploded=true] { animation: pot-shake … }`,
   `[data-role=cracked-rim]` fade-in, a `<circle data-role="puff">` inside it. The
   `data-motion` flag: one tiny colocated hook `.MotionReady` on the game root, or put
   it in `.PotMotion` later (B3). Until then, scope the shake by insertion of the rim
   `<g>` instead (it inserts once), which needs no flag.
6. Fortune card flip (#4): in `fortune_card/1` wrap the card in
   `<div class="card-flip">` with a back face (`paper` + seal) and the front; keyframe
   on insert. Only inside the `card-round-N` dialog (add an attr `flip`), not in the
   info sheet.
7. Ticker + pop (#6): `status/1` `stat` for VP and Rubies: `style={"--n: #{value}"}`,
   number shown via `::after { content: counter(n) }`, real value in a `sr-only` span
   for screen readers; wrap in `<span id={"stat-#{label}-#{value}"}>` for the pop.
8. Tests: assert ids/`data-role` exist (`has_element?(view, "#droplet-0-lg")`).

### B2 — The evaluation stage (CSS beats, still no JS)

1. Pure helper `QuacksWeb.Replay.beats(game, seat)` (or extend `round_gains/1` in
   `game_components.ex`): this round's log entries for the seat, in engine order
   (die → chip actions → scoring space → ruby), each as
   `%{beat: n, text: …, kind: :die | :green | :black | :purple | :space | :ruby | :card, chips: [index]}`.
   `chips` comes from the pot: green → green chips among the last two drawn
   (the rule of the private `Evaluation.last_two/2`; make it public rather than copy it), purple/black → chips of that colour, space → the scoring
   index (ring pulses). Unit-test it (pure function).
2. `round_results/1`: each `<li data-role="result-line" data-beat={n} style={"--beat: #{n}"}>`.
   Own seat: one beat per line. Other seats (multiplayer): their block fades in as one
   beat after yours. The total line takes `beat = last + 1` and uses the ticker.
3. Die (#3): new `<.die face={face} />` component: a 7-frame strip; frames 1–6 are the
   die faces in a fixed rotated order (no RNG: rotate `@die` by the face's index), frame
   7 the real face. `data-face` for tests. The die line is beat 0; later beats add the
   die's 900 ms (`--beat-offset`).
4. Pot highlights: while `results?(@game)`, `pot_chip` gets `data-beat`/`--beat` for
   the chips in the beats; keyframe `chip-score` with the same delay formula. The pot
   is visible above the see-through bottom sheet on phones and beside it on desktop.
5. Skip: a "Skip" text button in the dialog header with
   `phx-click={JS.add_class("replay-done", to: "#round-results")}`. JS-added classes
   stick across patches. CSS: `.replay-done [data-beat] { animation-delay: 0s !important; animation-duration: 1ms !important; }`.
   The existing "To the shop" button stays usable all the time (never lock input).
6. Budget: dialog slide 300 ms + die 900 ms + ~350 ms per line. A typical round has
   3–6 lines: about 2.5–3.5 s, skippable.

**B2 as built (2026-10-04).** No ticker process and no hook: pot highlights are
CSS too. `QuacksWeb.Replay` (pure) numbers your seat's result lines (`beats/3`; a die
line takes two beats, 450 ms each, after a 300 ms lead) and maps each pot mark (chip
index, `:droplet`, `:ring`, `:essence`) to a beat (`highlights/1`). While the game is in
`:shopping`, the large pot renders a gold `beat-ring` inside each marked node; the ring
and the dialog's lines enter the page on the same patch, so one delay formula keeps
them in step. Skip (`JS.add_class("replay-done")`) and closing the dialog
(`dialog_sheet on_close`, run by app.js's existing `close` listener through
`liveSocket.execJS`) finish the replay; `:has(#round-results.replay-done)` hides the
rings. The JS-added class sticks across patches and reconnects; a full page reload
plays the replay again. Engine untouched (green "last two" is re-derived from
`drawn`, not via a public `Evaluation.last_two/2`). On phones the results sheet is
capped at 45dvh so the upper pot stays in sight; on large screens it sits at the right.

### B3 — The chip flight hook + opt-in view transitions

1. `.PotMotion` colocated hook on the large pot `<svg id="pot-#{seat}-lg">`
   (no `phx-update="ignore"`: it only uses WAAPI):
   - `mounted()`: set `data-motion="on"` on the game root after one rAF; store ids.
   - `beforeUpdate()`: `this.before = new Set(chip ids)`.
   - `updated()`: new ids = after − before. If 1–2 new (one draw, or a draw plus an
     on-draw effect), animate each per §2.1 #1; if more (reconnect, undo/replay), skip.
     Path points: bag centre (§1.3) → the space of the chip with `data-order` − 1 (or
     the droplet) → each space up to the new index (`data-x`/`data-y`). One
     `el.animate([...], {duration, easing: "linear", composite: "replace"})` with
     per-keyframe `easing` and `offset`, on the inner chip `<g>` (`transform-box: fill-box`).
   - Start of each `updated()`: `finish()` any running chip animation (interruption).
   - Reduced motion: opacity fade only.
2. Flask return (#8): `phx-remove` fade on the chip; in `beforeUpdate()` the hook sees
   the removed id, clones the chip into an overlay `<g>` and flies it to the bag.
3. Rat stone hop at round start: from the droplet to the rat space (2+ players).
4. Opt-in view transitions (§1.4) in `app.js`'s `LiveSocket` options; server marks
   patches with `push_event(socket, "quacks:vt", %{}, dispatch: :before)` in
   `put_game/2` when the round number or `essence` changed. CSS:
   `::view-transition-group(*) { animation-duration: 300ms; animation-timing-function: var(--ease-in-out) }`.
5. Round transition (§2.2) with `phx-remove` on pot chips.

**B3 as built (2026-10-04).** One external hook, `PotMotion` in `assets/js/app.js`
(about 95 lines, WAAPI only, no `phx-update="ignore"` on the pot), on the large pot
`<svg phx-hook="PotMotion" data-round>`. `beforeUpdate` finishes its running
animations and records the chips, the rat index, the flask and the round; `updated`
compares. A new chip (1–2 per patch) flies from the bag button's centre (converted
with `getScreenCTM().inverse()`) to the previous chip's space (or the rat stone, or
the droplet), hops through at most 3 sampled spaces (`data-x`/`data-y` on each space
of the large pot) and lands with a `--ease-spring` pop: 240 ms + 80 ms per hop + 160
ms, at most 720 ms. Its CSS `chip-land` is cancelled first so the pop plays once. A
single chip that leaves (no new chip) is a ghost: the detached node, re-parented
into `<g id="pot-fx-N" phx-update="ignore">`, flies to the flask when the flask just
emptied, else to the bag (mandrake, crow skull), 260 ms. At a new round
(`data-round` changed) the old chips fade as ghosts, 180 ms, 20 ms stagger newest
first. The rat stone hops from the droplet to its space, one 14-unit arc per counted
space (at most 5), 120 ms each; its CSS `translate` transition is cancelled first.
Reduced motion: no flight, ghost or hop; the CSS fade (chips) and ghost fades stay.
**Chip ids** now carry the placement count of that space this game
(`pot-chip-0-5-2`, from the log's `{:drew, chip, 5}` events), so a chip on a space a
returned chip left is a new node and lands again (the B1 gap); `data-index` too.
**View transitions**: only the round counter (`.round-counter`,
`view-transition-name: round-counter`). `put_game/2` pushes `quacks:vt` with
`dispatch: :before` when the round goes up; `dom.onDocumentPatch` wraps that one
patch in `document.startViewTransition` (feature-detected, skipped under reduced
motion). The root snapshot does not animate, the group does not slide (the phase
pill beside it changes width), the old number rolls up and out (200 ms), the new one
in (300 ms), `--ease-out`; `::view-transition { pointer-events: none }`. Patches that
arrive while the transition waits for its snapshot queue behind it (a promise chain),
so LiveView diffs stay in order. **Not done**: the essence marker keeps its B1 CSS
`translate` transition; a view transition there would double the motion and block
taps for nothing. Found while testing: at a round change the page sometimes shows
round N+1, then N, then N+1 within ~20 ms (an older broadcast arrives after the
LiveView's own reply; `handle_info({:game, …})` only skips an identical copy). Only
round increases mark a transition, and the queue keeps it to one.

Data attributes added overall: `id` on pot chips / droplet / rat stone, `data-order`,
`data-x`/`data-y` on spaces, `data-beat` + `--beat`, `data-face`, `data-motion` (root),
`view-transition-name` only on the essence marker and the round counter.

---

## 4. The sequencing problem

Today one action = one patch with the final state. That is right for the engine and
must stay so. The question is only how each browser *shows* the in-between.

| Option | How | For | Against |
|---|---|---|---|
| A. **Server ticker** | `handle_info(:reveal)` + `Process.send_after` per beat, assign `revealed: n`, "Skip" event | Testable in LiveViewTest; one source of truth | A round trip and a full patch per beat; state per LiveView; latency stretches beats; incoming broadcasts (bots, other seats) re-render mid-replay and must not reset it; more code in `game_live.ex` (already 1919 lines) |
| B. **Client queue from `push_event`** | Server pushes `{beats: [...]}`; a hook plays them | Precise control, can drive the pot too | The DOM already shows the end state, so the hook must hide/restore it; duplicate data path; reconnect edge cases |
| C. **CSS beats on server-rendered data (recommended)** | Server renders the final state *plus* a beat number per element; CSS `animation-delay` reveals in order; the dialog mounts once per round so it plays once | No JS, no timers, no extra events; patches during the replay do not restart it (nodes keep their ids and styles); Skip = one class; reduced motion = one media query | Beats are fixed-time (not "wait for the user" steps); fine for a replay |

Use **C** for step B and the die, and the hook (§3 B3) only for the chip flight, which
needs live coordinates.

Multiplayer: each LiveView renders its own seat's view, so each browser replays its own
results; other seats' blocks appear as one beat. The engine and `GameServer` never
wait: bots keep their 700 ms cadence, and nothing in the replay is game state. A
browser that joins or reconnects mid-replay gets the dialog with the same beats and
simply sees them play again (cheap, harmless) or, after it is closed, nothing.

Undo: undo re-renders an earlier state; the hook's "more than 2 new chips → no
animation" rule and `phx-remove` fades keep it calm.

The die "pause": no `:rolling` assign and no engine change. The engine logs the roll at
once; the die line is beat 0 with a 900 ms stepped animation, and every later beat is
offset by it. The status bar VP/rubies change at once behind the dialog; the ticker in
the results total is what the player watches. (If that spoils it in playtests: delay the
status ticker with the same `--beat` offset while `results?/1` is true.)

## Sources

- LiveView JS interop and `JS.transition`: https://phoenix-live-view.hexdocs.pm/js-interop.html
- LiveView 1.2.12 source: `dom.onDocumentPatch`, `onBeforeElUpdated`
  (`deps/phoenix_live_view/assets/js/phoenix_live_view/live_socket.ts`),
  `push_event/4` `dispatch: :before` (`lib/phoenix_live_view.ex`), CHANGELOG 1.2.0
- View Transitions, same-document: https://developer.chrome.com/docs/web-platform/view-transitions/same-document
- View Transitions in 2025 / Firefox 144: https://developer.chrome.com/blog/view-transitions-in-2025
- Browser support: https://caniuse.com/view-transitions
- CSS View Transitions spec: https://drafts.csswg.org/css-view-transitions-1/
- `@starting-style` support: https://caniuse.com/mdn-css_at-rules_starting-style ;
  Safari dynamic-insert bug: https://github.com/mdn/browser-compat-data/issues/25643
- FLIP: https://aerotwist.com/blog/flip-your-animations/
- Motion `animate` (mini 2.3 kB / hybrid 18 kB): https://motion.dev/docs/animate
- `linear()` easing generator: https://linear-easing-generator.netlify.app/
- Skills: `~/.claude/skills/{find-animation-opportunities,animate,improve-animations,animation-vocabulary,apple-design,emil-design-eng}/SKILL.md`
