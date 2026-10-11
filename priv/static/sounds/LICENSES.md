# Sound licences

All files are mono AAC-LC `.m4a`, 44.1 kHz, 64 kbps (`docs/research/sounds.md` §1.4).
Only CC0 sources. `QuacksWeb.Sounds` is the manifest.

| File | Source | Licence |
|---|---|---|
| `boom.m4a` | X1, a mix of three sounds: unfa "Cartoon Pop (Clean)" (https://freesound.org/people/unfa/sounds/245645/, from the freesound preview MP3), Kenney Sci-fi Sounds `lowFrequency_explosion_001` (https://kenney.nl/assets/sci-fi-sounds) at +40 ms, OpenGameArt `bubble_01` (https://opengameart.org/content/40-cc0-water-splash-slime-sfx) at +150 ms | CC0 (all three) |
| `ruby.m4a` | R2, Kenney Interface Sounds `glass_001` (https://kenney.nl/assets/interface-sounds) | CC0 |
| `gameover.m4a` | G1, Kenney Music Jingles `jingles_PIZZI07` (https://kenney.nl/assets/music-jingles) | CC0 |
| `chip-white-1.m4a`, `chip-white-2.m4a`, `chip-white-3.m4a` | W1 synth fizz. Own synthesis (numpy/scipy, sounds-v2 `designs.py`); no third-party source | none needed |
| `chip-blue-1.m4a`, `chip-blue-2.m4a`, `chip-blue-4.m4a` | B1 single caw: freesound 361470, Jofae, "Crow Caw", https://freesound.org/people/Jofae/sounds/361470/ | CC0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `chip-green-1.m4a`, `chip-green-2.m4a`, `chip-green-4.m4a` | GR3 scuttle, then gasp: freesound 580511 KL_Falcon "Spider_Scuttle.wav" (https://freesound.org/people/KL_Falcon/sounds/580511/), 686364 SumRandomDewd "Cartoony Gasp.wav" (https://freesound.org/people/SumRandomDewd/sounds/686364/), 812418 CuboRodante "Exaggerated Surprised Gasp!" (https://freesound.org/people/CuboRodante/sounds/812418/) | CC0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `chip-orange-1.m4a`, `chip-orange-2.m4a`, `chip-orange-6.m4a` | O1 splash: OpenGameArt "40 CC0 water/splash/slime SFX" (`splash_05/07/10/11/14`), https://opengameart.org/content/40-cc0-water-splash-slime-sfx | CC0 |
| `chip-red-1.m4a`, `chip-red-2.m4a`, `chip-red-4.m4a` | RD1 reed honk + sparkles. Own synthesis (numpy/scipy, sounds-v2 `designs.py`); no third-party source | none needed |
| `chip-yellow-1.m4a`, `chip-yellow-2.m4a`, `chip-yellow-4.m4a` | Y1 small creature shriek: freesound 744792 and 744794, qubodup, "Small Evil Creature Attack Shout 1/3", https://freesound.org/people/qubodup/sounds/744792/, https://freesound.org/people/qubodup/sounds/744794/ | CC0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `chip-purple-1.m4a` | P2 synth ooo-rise. Own synthesis (numpy/scipy, sounds-v2 `designs.py`); no third-party source | none needed |
| `chip-black-1.m4a` | K2 synth flutter. Own synthesis (numpy/scipy, sounds-v2 `designs.py`); no third-party source | none needed |
| `chip-locoweed-1.m4a`, `chip-locoweed-2.m4a`, `chip-locoweed-3.m4a`, `chip-locoweed-4.m4a`, `chip-locoweed-5.m4a`, `chip-locoweed-6.m4a` | LW1 rustle + woody pluck: freesound 538152, Fupicat, "Game Rustle Leaves", https://freesound.org/people/Fupicat/sounds/538152/ | CC0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `fortune.m4a` | CB3 mystic swell (the crystal ball). Own synthesis (numpy/scipy, sounds-v2 `designs.py`); no third-party source | none needed |

The chip and fortune files are the recommended set of the sounds-v2 work (session
`03974705`, `scratchpad/sounds-v2/LICENSES.md` has every candidate). Each freesound
licence was read on its page on 2026-10-11. ⚠️ The freesound parts are from the
public previews (lossy 128 kbps); download the originals with a free account before
a final release and build the files again.

Synth sounds (Web Audio in `assets/js/sound.js`, no file, no licence): `plop` (a chip
with no file of its own), `bloop` (the droplet moves), `chime` (the fortune teller
when `fortune.m4a` is missing).
