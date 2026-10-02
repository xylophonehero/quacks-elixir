# Components and mobile layout for the game page

Research date: 2026-10-03. Stack: Phoenix 1.8.15, LiveView 1.2.12, Tailwind v4, no daisyUI.
⚠️ = not verified against a primary source.

## TL;DR

- **Do not add a component library.** Hand-write 2 components (`<.sheet>` and `<.sheet_button>`) on top of
  the native **Popover API** and `<dialog>`. Total: about 60 lines HEEx + 3 lines JS.
- The page fits one phone screen with a `100dvh` grid: header, status strip, pot (takes the free
  space), action bar. Log, bag, shop, other players, card text and choices go into bottom sheets.
- Remove `py-20` and `max-w-2xl` from `Layouts.app` for the game page. They use about 160px of height.

## 1. Component libraries

Versions and dates come from the hex.pm API (`/api/packages/<name>`), 2026-10-03.

| Library | Latest (date) | Licence | Install model | JS needed | TW v4 | Modal / sheet / popover / tabs | Notes |
|---|---|---|---|---|---|---|---|
| Phoenix 1.8 `core_components` | 1.8.15 | MIT | generated | `JS.show/hide` only | yes | **no modal** | 1.8 removed `<.modal>`; local file has `flash, button, input, header, table, list, icon, show, hide` only |
| [SaladUI](https://salad-ui.hexdocs.pm/readme.html) | 1.0.0 (2026-08-11) | MIT | dep or copy (`mix salad.install`) | **yes**, own JS hooks/components | ⚠️ not stated | dialog, sheet, popover, tabs; no drawer | shadcn look; brings its own JS runtime |
| [Mishka Chelekom](https://mishka.tools/chelekom/docs) | 0.0.10-alpha.8 (2026-09-12) | Apache-2.0 | generator copies files | some JS hooks ⚠️ | yes (since 0.0.8) | modal, drawer, popover, tabs | ~100 components; still alpha; colour CSS files generated |
| [Petal Components](https://github.com/petalframework/petal_components) | 4.17.0 (2026-10-02) | MIT | hex dep | `LiveView.JS` for overlays (no Alpine since v4); hooks only for some inputs/chat | yes (v3+) | modal, slide_over, popover, tabs | 200+ components; heavy dep for 3 overlays |
| [Fluxon UI](https://fluxonui.com/pricing) | private repo | **paid**, $249 one-time (individual) | private hex | ⚠️ some hooks | yes | sheet, modal, popover, tabs | best polish; not open source |
| [Doggo](https://github.com/woylie/doggo/releases/tag/0.18.0) | 0.18.0 (2026-10-02) | MIT | macros build unstyled components | hooks; `Doggo.JS.show_modal/2` | n/a (headless) | modal (uses `showModal()`), alert_dialog, tabs | good a11y; you style it all anyway |
| [Surface](https://hex.pm/packages/surface) | 0.12.3 (2026-03-25) | MIT | framework | n/a | n/a | none built-in | a component *framework*, not a kit; not useful here |
| [PrimerLive](https://hex.pm/packages/primer_live) | 0.11.0 (2025-04-04) | MIT | dep | yes, own JS/CSS | no (Primer CSS) | dialog, drawer, tabs | GitHub look; no release for 18 months |
| [phoenix_ui](https://hex.pm/packages/phoenix_ui) | 0.1.9 (2023-10-17) | MIT | dep | ⚠️ | no | some | **abandoned** |
| [Backpex](https://hex.pm/packages/backpex) | 0.21.0 (2026-09-29) | MIT | dep | yes | daisyUI-based | admin panels | admin CRUD only; not relevant |
| [daisy_ui_components](https://hexdocs.pm/daisy_ui_components/DaisyUIComponents.html) | 0.9.9 (2026-09-02) | Apache-2.0 | dep | `showModal` hook | needs daisyUI | modal, drawer, tabs | we removed daisyUI; skip |
| LiveView Native | - | - | - | - | - | - | native apps, not relevant |

### Recommendation: none. Hand-write the sheet.

Reasons:
1. We need 1 primitive (bottom sheet / dialog). Every library above brings 50-200 components we will not use.
2. The cauldron theme (`paper` utility, wood, Kalam font) is custom. A library look (shadcn, Primer)
   must be overridden everywhere. A headless lib (Doggo) still needs all the styling.
3. The browser now does the hard parts: focus trap, Esc, backdrop, top layer, light dismiss.
   See section 2. LiveView 1.1+ added `JS.ignore_attributes/1` exactly for `<dialog open>`.
4. Ponytail: zero new deps, nothing to upgrade.

If a library is required later: **Petal Components** (MIT, active, TW v4, no Alpine).

## 2. Native patterns in LiveView 1.2

### A. Info sheets (log, bag, players, card text): Popover API, zero JS

```heex
<button popovertarget="sheet-log" class="min-h-11 ...">Log</button>
<div id="sheet-log" popover class="sheet">  <%!-- light dismiss + Esc are native --%>
  <.action_log log={@game.log} />
</div>
```
- Popover API is Baseline since 2024 (Chrome 114, Safari 17, Firefox 125) ⚠️ check MDN for your min iOS.
- The open state is not an HTML attribute (`:popover-open`), so a LiveView patch does not close it ⚠️ test it.
- Not modal: the page behind stays interactive. Good for read-only info.

### B. Choices that need an answer (shop, crow skull, fortune choice, explosion): `<dialog>`

```heex
<dialog id="sheet-shop" class="sheet"
  phx-mounted={JS.ignore_attributes("open") |> JS.dispatch("quacks:modal")}>
  ...
  <form method="dialog"><button>Close</button></form>
</dialog>
```
```js
// app.js — the only custom JS
window.addEventListener("quacks:modal", e => e.target.open || e.target.showModal())
```
- Render it with `:if={phase == :buy_chips}`: it opens itself when the phase starts and leaves
  the DOM when the phase ends. No server "show" state needed.
- `JS.ignore_attributes("open")` comes from the installed LV docs: "useful in combination with
  `phx-mounted` ... `<dialog phx-mounted={JS.ignore_attributes("open")}>`". Without it, a patch
  removes `open` and the dialog closes.
- `JS.dispatch` from `phx-mounted` with no `to:` fires on the dialog itself; the event bubbles to window.
- `closedby="any"` gives backdrop-click close ⚠️ (Chrome 134+; Safari support unverified). Fallback:
  a full-size backdrop button, or `phx-click-away`.
- Alternative: a colocated hook (`<script :type={Phoenix.LiveView.ColocatedHook} name=".Modal">`)
  with `mounted() { this.el.showModal() }`. Your `app.js` already imports `phoenix-colocated/quacks`.
  Use this only if the 1-line listener is not enough.

### C. Bottom sheet CSS (no JS)

```css
@utility sheet {
  position: fixed; inset: auto 0 0 0; margin: 0; width: 100%; max-width: 40rem; margin-inline: auto;
  max-height: 85dvh; overflow-y: auto; overscroll-behavior: contain;
  border-radius: 1rem 1rem 0 0; padding-bottom: max(1rem, env(safe-area-inset-bottom));
  translate: 0 0; transition: translate .3s cubic-bezier(.32,.72,0,1), overlay .3s allow-discrete, display .3s allow-discrete;
  @starting-style { translate: 0 100%; }
}
.sheet:not(:popover-open):not([open]) { translate: 0 100%; }
.sheet::backdrop { background: rgb(0 0 0 / .45); }
@media (prefers-reduced-motion: reduce) { .sheet { transition: none; } }
```
`@starting-style` and `transition-behavior: allow-discrete` are Baseline 2024 ⚠️; older browsers just skip the animation.
On desktop (`md:`), change the sheet to a centred dialog or a right-side panel with the same element.

### D. Viewport and touch rules

| Topic | Rule |
|---|---|
| Height | Use `h-dvh` (Tailwind v4 has `h-dvh`, `h-svh`). `dvh` follows the Safari toolbar. Size the budget for `svh` (toolbar shown) so nothing overflows. |
| Safe area | Change the meta tag to `viewport-fit=cover`; pad the action bar with `pb-[max(0.5rem,env(safe-area-inset-bottom))]`. |
| Touch targets | Minimum 44×44px (Apple HIG; WCAG 2.5.5 AAA). WCAG 2.5.8 AA asks 24px. Use `min-h-11 min-w-11`. |
| Scroll bounce | `html,body { overscroll-behavior: none; }` on the game page; `overscroll-behavior: contain` in sheets. |
| No page scroll | Grid root `h-dvh overflow-hidden`; only sheets scroll. Pot gets `min-h-0` so it can shrink. |
| Double-tap zoom | `touch-action: manipulation` on buttons. |

## 3. Layout proposal

### Phone, 390×844 (Safari visible area ≈ 390×660-750 ⚠️ depends on toolbar)

Root: `grid h-dvh grid-rows-[auto_auto_1fr_auto] overflow-hidden`.

```
┌──────────────────────────────────────┐ 
│ Quacks · ab12      R3/9   ☰          │ 40px  header (menu: lobby, undo, new, rename, seed, rules)
├──────────────────────────────────────┤
│ VP 12 │ ◆3 │ Flask● │ White 5/7      │ 44px  status strip (1 row, 4 stats; phase as colour/pill)
│ 🃏 Fortune: "Living in luxury"  (i)  │ 32px  fortune title → opens card-text sheet
├──────────────────────────────────────┤
│                                      │
│            ( pot SVG )               │ 1fr   pot: aspect-square, h-full, max-w-full, centred
│                                      │       ≈ 366px at 390 wide; shrinks on short screens
│  aside chips overlay bottom-left     │       turn banner / "Exploded" as overlay badge on the pot
├──────────────────────────────────────┤
│ [Bag 14] [Log] [Players] [Shop•]     │ 44px  sheet buttons (• = needs attention)
│ [   Draw   ] [ Stop ] [ Flask ]      │ 56px  primary actions + safe-area padding
└──────────────────────────────────────┘
```
Budget at 660px (worst case): 40+44+32+44+56+safe 20 = 236px fixed → pot gets 424px. The pot
needs 366px (width-limited), so it fits with margin. At 568px tall (iPhone SE 1st gen) the pot shrinks to ~330px.

| Always visible | Behind a sheet button | Auto-open `<dialog>` when the phase starts |
|---|---|---|
| pot SVG, status strip (VP, rubies, flask, white sum), phase/turn badge, fortune title, primary action buttons, coins when buying | log, bag contents, other players' cards, fortune card full text, house rules, books/sets, seed, rename | shop (buy chips), crow-skull offer, fortune choice, explosion choice, mandrake, bonus die, rubies spend, game-over |

Notes:
- `.status` today is `grid-cols-3` with 6 stats + extra rows. Make a compact 1-row variant; put Round and
  Phase in the header, the rest in the strip.
- Spectators: no action bar; the pot is the watched player; "Players" sheet stays.
- Multiplayer turn info: one line in the header, not a separate paragraph.

### Desktop (≥ `lg`, 1024+)

`grid lg:grid-cols-[minmax(0,1fr)_22rem] lg:h-dvh gap-4`.

```
┌──────────────────────────────┬──────────────────┐
│ header + status strip        │ Players (stack)  │
│ fortune card (full text)     │                  │
│                              ├──────────────────┤
│         pot SVG              │ Log (scrolls)    │
│                              │                  │
│ actions                      ├──────────────────┤
│                              │ Bag              │
└──────────────────────────────┴──────────────────┘
```
On desktop, render log/bag/players inline in the right column (`hidden lg:block`) and hide the sheet
buttons (`lg:hidden`). Choices stay as centred `<dialog>` (same element, `lg:` styles), so one code path.

## 4. Skills for the builder

| Skill | What it adds |
|---|---|
| `ponytail:ponytail` | Keeps it to native `<dialog>`/popover + Tailwind; stops a library being added. |
| `frontend-design:frontend-design` | Visual direction so the compact strip and sheets keep the cauldron/parchment look, not a template look. |
| `emil-design-eng` | Sheet polish: easing, enter/exit timing, backdrop, the small details that make a sheet feel native. |
| `apple-design` | Bottom-sheet behaviour, safe areas, 44px targets, drag-to-dismiss and reduced-motion rules. |
| `animate` | Implements the sheet slide and chip-draw motion with the right curve and interruption rules. |

## Sources

- Phoenix 1.8 modal removal: <https://fullstackphoenix.com/tutorials/adding-modals-to-phoenix-one-point-eight-daisyui>, <https://elixirforum.com/t/daisyui-modal-in-phoenix-1-8-code-example/71951>; local `core_components.ex`
- `JS.ignore_attributes/1`, `ColocatedHook`: installed LiveView 1.2.12 docs (via Tidewave `get_docs`)
- SaladUI: <https://salad-ui.hexdocs.pm/readme.html>
- Chelekom TW4: <https://mishka.tools/blog/introducing-mishka-chelekom-v0.0.8-with-tailwind-4-support-and-custom-configuration>
- Petal: <https://github.com/petalframework/petal_components>
- Fluxon pricing: <https://fluxonui.com/pricing>
- Doggo 0.18: <https://github.com/woylie/doggo/releases/tag/0.18.0>
- Versions/dates: `https://hex.pm/api/packages/<name>`
