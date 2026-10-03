# Art assets: licence-safe icon candidates

Date: 2026-10-04. Status: research only. No code changed.

Candidate files: `docs/assets/candidates/` (116 SVG + 3 reference bitmaps, 632 KB).
Comparison page (all candidates inline, on parchment, on chip colours, on iron): `art-candidates.html` in the session scratchpad (published as an artifact on request).

## Rules we keep

- Use only CC0, public domain, CC BY, or MIT / ISC / Apache / OFL icon sets.
- Do not copy art from Schmidt Spiele, North Star Games or BGG photos.
- Keep each file's author and licence in this document. A CC BY file needs a credit line in the app (an "Art credits" line in the footer or an About page is sufficient).

## Sources: what worked

| Source | Licence | Result |
|---|---|---|
| game-icons.net (GitHub `game-icons/icons`, raw SVG) | CC BY 3.0, credit "Icons made by {author}" | Best source. 4,239 icons, one consistent filled style, 512×512. Covers nearly every subject. |
| Kenney Board Game Icons 1.1 (`kenney.nl/assets/board-game-icons`) | CC0 | Good for UI: pouch, flask (full/half/empty), dice, book, token. No ingredients. |
| Pinhead Map Icons (via Iconify API) | CC0 | Small 15×15 map glyphs: pumpkin, bomb, ghost, droplet, die faces, coin, bag. Usable as CC0 fall-backs. |
| Lucide / Lucide Lab (ISC), Tabler (MIT) | permissive | Stroke icons for UI glyphs (droplet, gem, dice, test tube, rat, coins, cauldron). Different style from game-icons (outline vs filled). |
| Twemoji 17 (jdecked fork, via jsDelivr) | CC BY 4.0 (graphics) | Full colour. Good look, but not recolourable to chip colours. Kept for comparison only. |
| Wikimedia Commons | PD / CC BY 2.0 | No usable SVG for mandrake, hawkmoth or bird skull. Downloaded 3 small bitmaps as references for our own redraw. |
| SVG Repo | n/a | Blocked by a Vercel bot check (HTTP 429). Not used. |
| OpenMoji | CC BY-SA 4.0 | Not downloaded. Share-alike: a recoloured or changed icon must also be CC BY-SA. It does not affect our code, but it adds a second licence to track. Avoid unless an icon is missing everywhere else. |
| Noto Emoji | Apache 2.0 / OFL | Not needed. Same problem as Twemoji (full colour). |
| Heroicons | MIT | Already in the app for UI. No game subjects. |

Twemoji codepoints used: bomb 1f4a3, jack-o-lantern 1f383, spider 1f577, skull 1f480, mushroom 1f344, ghost 1f47b, butterfly 1f98b, herb 1f33f, droplet 1f4a7, gem 1f48e, rat 1f400, die 1f3b2, test tube 1f9ea, coin 1fa99, carrot 1f955, worm 1fab1, vampire 1f9db.

## Changes made to the downloaded files

- game-icons.net: removed the black 512×512 background path, changed `fill="#fff"` to `fill="currentColor"`. Paths are not changed. (CC BY 3.0 permits this; we note the change here.)
- Kenney: added `viewBox="-35 -35 70 70"` (the source SVG has none; the art is centred on 0,0) and changed `#FFFFFF` to `currentColor`.
- Iconify-served files (Pinhead, Lucide Lab, Tabler) and Lucide, Twemoji: not changed.

## Recommended set

| Subject | Pick | Set / author | Licence | Note |
|---|---|---|---|---|
| Cherry bomb (white) | `cherry-bomb-1.svg` (unlit-bomb) | game-icons, Lorc | CC BY 3.0 | Round bomb with fuse. Ink icon on the white chip. |
| Pumpkin (orange) | `pumpkin-1.svg` | game-icons, Delapouite | CC BY 3.0 | Plain ribbed pumpkin. |
| Garden spider (green) | `spider-1.svg` (hanging-spider) | game-icons, Lorc | CC BY 3.0 | Clearest silhouette at 16 px. |
| Crow skull (blue) | `crow-skull-2.svg` (raven) | game-icons, Lorc | CC BY 3.0 | Stopgap. No free bird-skull icon. Redraw (below). |
| Toadstool (red) | `toadstool-1.svg` (spotted-mushroom) | game-icons, Lorc | CC BY 3.0 | Spots say "toadstool". |
| Mandrake (yellow) | `mandrake-1.svg` (plant-roots) | game-icons, Delapouite | CC BY 3.0 | Stopgap. Redraw from `mandrake-ref-1.jpg` (Hortus sanitatis 1491, PD). |
| Ghost's breath (purple) | `ghosts-breath-1.svg` (ghost) | game-icons, Lorc | CC BY 3.0 | Wispy tail suggests breath. |
| Hawkmoth (black) | `hawkmoth-1.svg` (butterfly) | game-icons, Lorc | CC BY 3.0 | Stopgap. Redraw from `hawkmoth-ref-1.jpg` (CC BY 2.0). |
| Locoweed | `locoweed-2.svg` (herbs-bundle) | game-icons, Delapouite | CC BY 3.0 | Distinct from spider and mandrake shapes. |
| Flask | `flask-1.svg` (round-bottom-flask) | game-icons, Lorc | CC BY 3.0 | Small glyph only; keep our own pot flask. Kenney `flask-ke*.svg` (CC0) is the alternative with full/empty states. |
| Droplet | `droplet-1.svg` (drop) | game-icons, Lorc | CC BY 3.0 | |
| Ruby | `ruby-1.svg` (cut-diamond) | game-icons, Lorc | CC BY 3.0 | Fill `--color-ruby`. |
| Rat / rat tail | `rat-1.svg` | game-icons, Delapouite | CC BY 3.0 | Long tail visible. |
| Bonus die | `die-1.svg` (perspective dice) | game-icons, Delapouite | CC BY 3.0 | For the roll button. Draw the 6 faces ourselves with our VP/droplet/ruby/pumpkin glyphs. |
| Victory point | `victory-point-1.svg` (laurel-crown) | game-icons, Lorc | CC BY 3.0 | Only candidate; a star is the other choice. |
| Spell book | `spell-book-1.svg` | game-icons, Delapouite | CC BY 3.0 | |
| Test tube | `test-tube-1.svg` (corked-tube) | game-icons, Lorc | CC BY 3.0 | |
| Bag | `bag-1.svg` (swap-bag) | game-icons, Lorc | CC BY 3.0 | Kenney `bag-ke.svg` (CC0) is close. |
| Cauldron | `cauldron-2.svg` | game-icons, DarkZaitzev | CC BY 3.0 | Icon only; the board keeps our SVG pot. |
| Ear worm | `patient-ear-worm-1.svg` (earth-worm) | game-icons, Cathelineau | CC BY 3.0 | Can pair with `patient-ear-worm-2.svg` (ear). |
| Chicken eyes | `patient-chicken-eyes-1.svg` (chicken) | game-icons, Delapouite | CC BY 3.0 | |
| Vampirism | `patient-vampirism-2.svg` (fangs) | game-icons, Skoll | CC BY 3.0 | |
| Carrot nose | `patient-carrot-nose-1.svg` (carrot) | game-icons, Delapouite | CC BY 3.0 | |
| Wing ears | `patient-wing-ears-3.svg` (bat-wing) | game-icons, Lorc | CC BY 3.0 | Elf ear is the alternative. |
| Witch's hump | `patient-witch-hump-1.svg` (back-pain) | game-icons, Lorc | CC BY 3.0 | |
| Forgetfulness | `patient-forgetfulness-1.svg` (brain-leak) | game-icons, Delapouite | CC BY 3.0 | |
| Nervousness | `patient-nervousness-2.svg` (worried-eyes) | game-icons, Lorc | CC BY 3.0 | |
| Pennies | `penny-1.svg` (two-coins) | game-icons, Delapouite | CC BY 3.0 | Tint gold / silver / copper. |
| Witch | `witch-1.svg` (witch-flight) | game-icons, Lorc | CC BY 3.0 | |

With this set, one credit line covers all picks:

> Icons by Lorc, Delapouite, Skoll, Cathelineau and DarkZaitzev from game-icons.net, CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/). Changes: background removed, recoloured.

Missing (no licence-safe icon found): mandrake root, hawkmoth, crow/bird skull. Use the stopgaps and redraw these three.

## Proposed visual system

1. **One family.** Use game-icons.net for all game subjects (filled silhouettes, 512 viewBox). Do not mix in the outline sets (Lucide, Tabler) for game subjects; keep those for UI controls only. Filled icons survive 16 px; stroke icons go thin.
2. **Recolour with `currentColor`.** All candidate SVGs already use `fill="currentColor"`. Inline them as a `<symbol>` sprite in one component (e.g. `QuacksWeb.Icons.icon name={:pumpkin}`) and set colour with a Tailwind text class or `style="color: var(--color-...)"`. No per-icon CSS.
3. **Chip** = disc in the chip colour (existing `--color-chip-*`), icon at 58 % of the disc, value in a small parchment badge with a 2 px ink ring (Kalam 700). Icon colour: white on dark chips; `--color-ink` on white and yellow chips. Add a 3 px inner shadow at the bottom and a 2 px inner highlight at the top for a wooden-token look. The mock-up on the comparison page shows this.
4. **Two contrast modes.** Dark-on-parchment (`--color-ink` icon on `--color-parchment`) for book tiles, logs, shop rows. Light-on-colour (white or `--color-parchment` icon on chip/iron) for chips and buttons.
5. **Book tile** = parchment card, icon 40 px in the ingredient colour at the left, book name in Kalam, the rule text below in the body font.
6. **Stroke weight.** game-icons are filled, so stroke weight does not apply. Where we draw our own SVG, use 3 px strokes in `--color-iron-dark` at a 64-unit scale (the same as the existing flask), `stroke-linejoin="round"`.
7. **Size floor.** 16 px minimum for icons inside chips (`size-4` chips show only the value, no icon).

## Own redraws (if the found icons do not fit)

Keep these in our own SVG (no licence issue):

- **Flask.** Keep the current shape (round-bottom body r=25, neck 14 wide, wooden cork). Add a liquid level: a `clipPath` of the body, a rectangle of `--color-potion` with a wavy top, a linear gradient from `--color-potion-light` (top) to `--color-potion-deep`. Highlight: the existing white ellipse at 35 % opacity plus a 2 px white arc on the right edge at 20 %. Empty flask: grey glass, no liquid.
- **Droplet.** Path: a circle r=10 at the bottom with tangents meeting at a point 2.2 r above the centre. Radial gradient from `#7fb0ff` (top-left) to `--color-droplet` to `#1f4fb0` (edge). One white crescent highlight at upper left (opacity 0.6). 1.5 px stroke `#1f3f8a`.
- **Bag.** A sack: wide rounded bottom (ellipse), a pinched neck, a drawstring as two short wavy lines and a knot. Fill `--color-wood` with a linear gradient to `--color-wood-dark` at the bottom; 3 to 4 short lighter curves for cloth folds. Stroke 3 px `--color-wood-dark`.
- **Cauldron.** The board pot already exists. For the icon, use an iron bowl (half ellipse, wider than tall), a thick rim (rounded rect), three stub legs, green liquid ellipse at the rim with 2 to 3 bubbles. Fill `--color-iron` with a radial gradient light spot at upper left (`#5a5f66`).
- **Mandrake.** Forked root shaped like a small person: carrot-like body, two "leg" forks, two thin "arm" roots, a crown of 5 to 7 broad leaves (rosette) on top. Base it on `mandrake-ref-1.jpg` (1491 woodcut, PD). Single filled silhouette, 512 viewBox, to match game-icons.
- **Hawkmoth.** Thick furry body (long ellipse with 3 bands), swept-back triangular forewings, small hindwings, feathered antennae. Optional pale skull mark on the thorax (death's-head hawkmoth). Reference: `hawkmoth-ref-1.jpg`.
- **Crow skull.** Side-view bird skull: round cranium, big eye socket (negative space), long pointed beak. Filled silhouette.
- **Bonus die faces.** Rounded square (r=6 on 48) in `--color-parchment`, ink border, one glyph in the centre: "1"/"2" VP numbers with the laurel, droplet, ruby, pumpkin (orange chip).

## Reference bitmaps (not for use in the app)

| File | Source | Licence |
|---|---|---|
| `mandrake-ref-1.jpg` | Hortus sanitatis, Mainz 1491; https://commons.wikimedia.org/wiki/File:Hortus_sanitatis_1491_Mandrake.jpg | Public domain |
| `mandrake-ref-2.png` | Leiden Ms Voss. Q.9, 6th century; https://commons.wikimedia.org/wiki/File:Leiden_Mandragora.png | Public domain |
| `hawkmoth-ref-1.jpg` | Plate via rawpixel (Flickr), https://commons.wikimedia.org/wiki/File:Zygaena_filipendulae_(Six-spot_burnet),_Acherontia_atropos_(Death%27s-head_Hawkmoth),_Syntomis_phegea_(Nine-spotted_moth).jpg | CC BY 2.0 ("Free Public Domain Illustrations by rawpixel") |

## All candidate files

Licence sources checked on 2026-10-04: game-icons `license.txt` in `game-icons/icons` (CC BY 3.0, "Icons made by {author}"); Kenney `License.txt` in the zip (CC0); Twemoji `LICENSE-GRAPHICS` (CC BY 4.0); Lucide `LICENSE` (ISC); Iconify collection metadata for Pinhead (CC0, Quincy Morgan), Lucide Lab (ISC), Tabler (MIT, Paweł Kuna).

| File | Rec | Set (original name) | Author | Licence | Source |
|---|---|---|---|---|---|
| `bag-1.svg` | yes | game-icons.net (swap-bag) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/swap-bag.html |
| `bag-2.svg` |  | game-icons.net (powder-bag) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/powder-bag.html |
| `bag-ke.svg` |  | Kenney Board Game Icons 1.1 | Kenney | CC0 1.0 | https://kenney.nl/assets/board-game-icons |
| `bag-ph.svg` |  | Pinhead Map Icons | Quincy Morgan | CC0 1.0 | https://github.com/waysidemapping/pinhead |
| `cauldron-1.svg` |  | game-icons.net (cauldron) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/cauldron.html |
| `cauldron-2.svg` | yes | game-icons.net (cauldron) | DarkZaitzev | CC BY 3.0 | https://game-icons.net/1x1/darkzaitzev/cauldron.html |
| `cauldron-ll.svg` |  | Lucide Lab | Lucide Contributors | ISC | https://github.com/lucide-icons/lucide-lab |
| `cherry-bomb-1.svg` | yes | game-icons.net (unlit-bomb) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/unlit-bomb.html |
| `cherry-bomb-2.svg` |  | game-icons.net (sparky-bomb) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/sparky-bomb.html |
| `cherry-bomb-3.svg` |  | game-icons.net (cherry) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/cherry.html |
| `cherry-bomb-ke.svg` |  | Kenney Board Game Icons 1.1 | Kenney | CC0 1.0 | https://kenney.nl/assets/board-game-icons |
| `cherry-bomb-ph.svg` |  | Pinhead Map Icons | Quincy Morgan | CC0 1.0 | https://github.com/waysidemapping/pinhead |
| `cherry-bomb-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `crow-skull-1.svg` |  | game-icons.net (animal-skull) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/animal-skull.html |
| `crow-skull-2.svg` | yes | game-icons.net (raven) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/raven.html |
| `crow-skull-3.svg` |  | game-icons.net (triple-beak) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/triple-beak.html |
| `crow-skull-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `die-1.svg` | yes | game-icons.net (perspective-dice-six-faces-random) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/perspective-dice-six-faces-random.html |
| `die-2.svg` |  | game-icons.net (rolling-dices) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/rolling-dices.html |
| `die-3.svg` |  | game-icons.net (dice-six-faces-five) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/dice-six-faces-five.html |
| `die-ke.svg` |  | Kenney Board Game Icons 1.1 | Kenney | CC0 1.0 | https://kenney.nl/assets/board-game-icons |
| `die-lu.svg` |  | Lucide | Lucide Contributors | ISC | https://github.com/lucide-icons/lucide |
| `die-ph.svg` |  | Pinhead Map Icons | Quincy Morgan | CC0 1.0 | https://github.com/waysidemapping/pinhead |
| `die-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `droplet-1.svg` | yes | game-icons.net (drop) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/drop.html |
| `droplet-2.svg` |  | game-icons.net (water-drop) | Sbed | CC BY 3.0 | https://game-icons.net/1x1/sbed/water-drop.html |
| `droplet-lu.svg` |  | Lucide | Lucide Contributors | ISC | https://github.com/lucide-icons/lucide |
| `droplet-ph.svg` |  | Pinhead Map Icons | Quincy Morgan | CC0 1.0 | https://github.com/waysidemapping/pinhead |
| `droplet-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `flask-1.svg` | yes | game-icons.net (round-bottom-flask) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/round-bottom-flask.html |
| `flask-2.svg` |  | game-icons.net (bubbling-flask) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/bubbling-flask.html |
| `flask-3.svg` |  | game-icons.net (round-potion) | Caro Asercion | CC BY 3.0 | https://game-icons.net/1x1/caro-asercion/round-potion.html |
| `flask-ke-empty.svg` |  | Kenney Board Game Icons 1.1 | Kenney | CC0 1.0 | https://kenney.nl/assets/board-game-icons |
| `flask-ke.svg` |  | Kenney Board Game Icons 1.1 | Kenney | CC0 1.0 | https://kenney.nl/assets/board-game-icons |
| `flask-lu.svg` |  | Lucide | Lucide Contributors | ISC | https://github.com/lucide-icons/lucide |
| `flask-ph.svg` |  | Pinhead Map Icons | Quincy Morgan | CC0 1.0 | https://github.com/waysidemapping/pinhead |
| `ghosts-breath-1.svg` | yes | game-icons.net (ghost) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/ghost.html |
| `ghosts-breath-2.svg` |  | game-icons.net (floating-ghost) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/floating-ghost.html |
| `ghosts-breath-3.svg` |  | game-icons.net (fluffy-swirl) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/fluffy-swirl.html |
| `ghosts-breath-ph.svg` |  | Pinhead Map Icons | Quincy Morgan | CC0 1.0 | https://github.com/waysidemapping/pinhead |
| `ghosts-breath-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `hawkmoth-1.svg` | yes | game-icons.net (butterfly) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/butterfly.html |
| `hawkmoth-2.svg` |  | game-icons.net (butterfly-flower) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/butterfly-flower.html |
| `hawkmoth-tb.svg` |  | Tabler Icons | Paweł Kuna | MIT | https://github.com/tabler/tabler-icons |
| `hawkmoth-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `locoweed-1.svg` |  | game-icons.net (sprout) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/sprout.html |
| `locoweed-2.svg` | yes | game-icons.net (herbs-bundle) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/herbs-bundle.html |
| `locoweed-3.svg` |  | game-icons.net (vine-leaf) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/vine-leaf.html |
| `locoweed-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `mandrake-1.svg` | yes | game-icons.net (plant-roots) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/plant-roots.html |
| `mandrake-2.svg` |  | game-icons.net (root-tip) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/root-tip.html |
| `mandrake-3.svg` |  | game-icons.net (beet) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/beet.html |
| `patient-carrot-nose-1.svg` | yes | game-icons.net (carrot) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/carrot.html |
| `patient-carrot-nose-2.svg` |  | game-icons.net (nose-side) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/nose-side.html |
| `patient-carrot-nose-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `patient-chicken-eyes-1.svg` | yes | game-icons.net (chicken) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/chicken.html |
| `patient-chicken-eyes-2.svg` |  | game-icons.net (egg-eye) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/egg-eye.html |
| `patient-chicken-eyes-3.svg` |  | game-icons.net (eyeball) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/eyeball.html |
| `patient-ear-worm-1.svg` | yes | game-icons.net (earth-worm) | Cathelineau | CC BY 3.0 | https://game-icons.net/1x1/cathelineau/earth-worm.html |
| `patient-ear-worm-2.svg` |  | game-icons.net (human-ear) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/human-ear.html |
| `patient-ear-worm-3.svg` |  | game-icons.net (leeching-worm) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/leeching-worm.html |
| `patient-ear-worm-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `patient-forgetfulness-1.svg` | yes | game-icons.net (brain-leak) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/brain-leak.html |
| `patient-forgetfulness-2.svg` |  | game-icons.net (thought-bubble) | SeregaCthtuf | CC BY 3.0 | https://game-icons.net/1x1/seregacthtuf/thought-bubble.html |
| `patient-forgetfulness-3.svg` |  | game-icons.net (sleepy) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/sleepy.html |
| `patient-nervousness-1.svg` |  | game-icons.net (screaming) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/screaming.html |
| `patient-nervousness-2.svg` | yes | game-icons.net (worried-eyes) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/worried-eyes.html |
| `patient-nervousness-3.svg` |  | game-icons.net (heart-beats) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/heart-beats.html |
| `patient-vampirism-1.svg` |  | game-icons.net (vampire-dracula) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/vampire-dracula.html |
| `patient-vampirism-2.svg` | yes | game-icons.net (fangs) | Skoll | CC BY 3.0 | https://game-icons.net/1x1/skoll/fangs.html |
| `patient-vampirism-3.svg` |  | game-icons.net (pretty-fangs) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/pretty-fangs.html |
| `patient-vampirism-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `patient-wing-ears-1.svg` |  | game-icons.net (elf-ear) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/elf-ear.html |
| `patient-wing-ears-2.svg` |  | game-icons.net (fairy-wings) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/fairy-wings.html |
| `patient-wing-ears-3.svg` | yes | game-icons.net (bat-wing) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/bat-wing.html |
| `patient-witch-hump-1.svg` | yes | game-icons.net (back-pain) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/back-pain.html |
| `patient-witch-hump-2.svg` |  | game-icons.net (witch-face) | Cathelineau | CC BY 3.0 | https://game-icons.net/1x1/cathelineau/witch-face.html |
| `penny-1.svg` | yes | game-icons.net (two-coins) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/two-coins.html |
| `penny-2.svg` |  | game-icons.net (crown-coin) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/crown-coin.html |
| `penny-ke.svg` |  | Kenney Board Game Icons 1.1 | Kenney | CC0 1.0 | https://kenney.nl/assets/board-game-icons |
| `penny-lu.svg` |  | Lucide | Lucide Contributors | ISC | https://github.com/lucide-icons/lucide |
| `penny-ph.svg` |  | Pinhead Map Icons | Quincy Morgan | CC0 1.0 | https://github.com/waysidemapping/pinhead |
| `penny-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `pumpkin-1.svg` | yes | game-icons.net (pumpkin) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/pumpkin.html |
| `pumpkin-2.svg` |  | game-icons.net (pumpkin-lantern) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/pumpkin-lantern.html |
| `pumpkin-ph.svg` |  | Pinhead Map Icons | Quincy Morgan | CC0 1.0 | https://github.com/waysidemapping/pinhead |
| `pumpkin-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `rat-1.svg` | yes | game-icons.net (rat) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/rat.html |
| `rat-2.svg` |  | game-icons.net (seated-mouse) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/seated-mouse.html |
| `rat-lu.svg` |  | Lucide | Lucide Contributors | ISC | https://github.com/lucide-icons/lucide |
| `rat-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `ruby-1.svg` | yes | game-icons.net (cut-diamond) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/cut-diamond.html |
| `ruby-2.svg` |  | game-icons.net (fire-gem) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/fire-gem.html |
| `ruby-3.svg` |  | game-icons.net (emerald) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/emerald.html |
| `ruby-lu.svg` |  | Lucide | Lucide Contributors | ISC | https://github.com/lucide-icons/lucide |
| `ruby-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `spell-book-1.svg` | yes | game-icons.net (spell-book) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/spell-book.html |
| `spell-book-2.svg` |  | game-icons.net (book-cover) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/book-cover.html |
| `spell-book-3.svg` |  | game-icons.net (secret-book) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/secret-book.html |
| `spell-book-ke.svg` |  | Kenney Board Game Icons 1.1 | Kenney | CC0 1.0 | https://kenney.nl/assets/board-game-icons |
| `spider-1.svg` | yes | game-icons.net (hanging-spider) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/hanging-spider.html |
| `spider-2.svg` |  | game-icons.net (spider-alt) | Carl Olsen | CC BY 3.0 | https://game-icons.net/1x1/carl-olsen/spider-alt.html |
| `spider-3.svg` |  | game-icons.net (long-legged-spider) | Skoll | CC BY 3.0 | https://game-icons.net/1x1/skoll/long-legged-spider.html |
| `spider-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `test-tube-1.svg` | yes | game-icons.net (corked-tube) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/corked-tube.html |
| `test-tube-2.svg` |  | game-icons.net (test-tubes) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/test-tubes.html |
| `test-tube-3.svg` |  | game-icons.net (vial) | Sbed | CC BY 3.0 | https://game-icons.net/1x1/sbed/vial.html |
| `test-tube-lu.svg` |  | Lucide | Lucide Contributors | ISC | https://github.com/lucide-icons/lucide |
| `test-tube-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `toadstool-1.svg` | yes | game-icons.net (spotted-mushroom) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/spotted-mushroom.html |
| `toadstool-2.svg` |  | game-icons.net (mushroom) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/mushroom.html |
| `toadstool-3.svg` |  | game-icons.net (mushrooms) | Delapouite | CC BY 3.0 | https://game-icons.net/1x1/delapouite/mushrooms.html |
| `toadstool-tb.svg` |  | Tabler Icons | Paweł Kuna | MIT | https://github.com/tabler/tabler-icons |
| `toadstool-tw.svg` |  | Twemoji 17 (jdecked fork) | Twitter, Inc. and contributors | CC BY 4.0 | https://github.com/jdecked/twemoji (assets/svg/<codepoint>.svg) |
| `victory-point-1.svg` | yes | game-icons.net (laurel-crown) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/laurel-crown.html |
| `witch-1.svg` | yes | game-icons.net (witch-flight) | Lorc | CC BY 3.0 | https://game-icons.net/1x1/lorc/witch-flight.html |
