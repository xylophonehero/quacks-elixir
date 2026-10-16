# Credits

## Icons

Icons by Lorc, Delapouite, Skoll, Cathelineau and DarkZaitzev from [game-icons.net](https://game-icons.net), licensed [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Changes: the black background is removed and the fill is `currentColor` (recoloured in the app). The paths are not changed.

The files are in `priv/static/images/icons/`. The app shows this credit in the lobby footer (`#credits`).

| File | Used for | Original icon | Author |
|---|---|---|---|
| `cherry-bomb-1.svg` | white chip (cherry bomb) | unlit-bomb | Lorc |
| `pumpkin-1.svg` | orange chip (pumpkin) | pumpkin | Delapouite |
| `spider-1.svg` | green chip (garden spider) | hanging-spider | Lorc |
| `toadstool-1.svg` | red chip (toadstool) | spotted-mushroom | Lorc |
| `ghosts-breath-1.svg` | purple chip (ghost's breath) | ghost | Lorc |
| `locoweed-2.svg` | locoweed | herbs-bundle | Delapouite |
| `flask-1.svg` | flask glyph | round-bottom-flask | Lorc |
| `droplet-1.svg` | droplet glyph | drop | Lorc |
| `ruby-1.svg` | ruby | cut-diamond | Lorc |
| `rat-1.svg` | rat stone, rat tails | rat | Delapouite |
| `die-1.svg` | bonus die glyph | perspective-dice-six-faces-random | Delapouite |
| `victory-point-1.svg` | victory points | laurel-crown | Lorc |
| `spell-book-1.svg` | book glyph | spell-book | Delapouite |
| `test-tube-1.svg` | test tube glyph | corked-tube | Lorc |
| `bag-1.svg` | bag glyph | swap-bag | Lorc |
| `cauldron-2.svg` | cauldron glyph | cauldron | DarkZaitzev |
| `pot-1.svg` | ruby spend: pot droplet (round 29) | cauldron | Lorc |
| `penny-1.svg` | witch pennies | two-coins | Delapouite |
| `witch-1.svg` | herb witches | witch-flight | Lorc |
| `patient-nervousness-2.svg` | Nervousness | worried-eyes | Lorc |
| `patient-ear-worm-1.svg` | Ear worm | earth-worm | Cathelineau |
| `patient-carrot-nose-1.svg` | Carrot nose | carrot | Delapouite |
| `patient-wing-ears-3.svg` | Wing ears | bat-wing | Lorc |
| `patient-chicken-eyes-1.svg` | Chicken eyes | chicken | Delapouite |
| `patient-witch-hump-1.svg` | Witch's hump | back-pain | Lorc |
| `patient-forgetfulness-1.svg` | Forgetfulness | brain-leak | Delapouite |
| `patient-vampirism-2.svg` | Vampirism | fangs | Skoll |

Our own icons, drawn for this project (same licence as the project; no attribution needed): `crow-skull.svg` (blue chip), `mandrake.svg` (yellow chip), `hawkmoth.svg` (black chip), `coin.svg` (coins, round 20), `boom.svg` (explosion: a 💥-shaped burst in red, orange and yellow from fixed radii, round 31; it replaces Lorc's explosion-rays). The paths are hand-written; reference pictures were used only to study the shapes (see `docs/research/art-assets.md`).

Our own SVG in the templates (no licence needed): the pot flask, the droplet on the pot, the bag beside the pot, the bonus die faces, the cauldron board and the test tubes.

The other candidates and their sources: `docs/research/art-assets.md`.

## Card table colour themes

The colour values of the card table themes (Emerald, Light, Cupcake, Retro, Nord,
Forest, Dracula, Night) come from [daisyUI](https://daisyui.com) 5.0.42, MIT
License, Copyright (c) 2020 Pouya Saadeghi. Only the values are copied, into
`assets/css/table.css` as `--tb-*` tokens. daisyUI itself is not installed.

The card faces, the suit shapes and the card back are our own drawings
(`TableWeb.Components.Cards`).

## Codenames Duet word list

`priv/games/codenames_duet/words.txt` (599 words) is the noun part of
C. K. Ogden's **Basic English** word list: the 400 "general" words and the 200
"picturable" words, less the word "sex" and one heading line. Ogden published the
list in *Basic English: A General Introduction with Rules and Grammar* (1930).
The book is in the public domain in the United States (published 1930, so its
95-year term ended on 1 January 2026), and a plain list of common English words
has little or no copyright of its own.

We took the words from the transcription on Wiktionary,
[Appendix:Basic English word list](https://en.wiktionary.org/wiki/Appendix:Basic_English_word_list)
(read 2026-10-16; Wiktionary text is CC BY-SA 4.0, credited here). We copied only
the words, in lower case, one per line, in alphabetical order.

This list is not the Codenames word list. Codenames and Codenames: Duet are games
by Vlaada Chvátil and Scot Eaton, © Czech Games Edition; we do not copy their
words, rules text or art. The rules in `docs/games/codenames_duet/rulebook.md` are
in our own words.
