# Sound licences

All files are mono AAC-LC `.m4a`, 44.1 kHz, 64 kbps (`docs/research/sounds.md` §1.4).
Only CC0 sources. `QuacksWeb.Sounds` is the manifest.

| File | Source | Licence |
|---|---|---|
| `boom.m4a` | X1, a mix of three sounds: unfa "Cartoon Pop (Clean)" (https://freesound.org/people/unfa/sounds/245645/, from the freesound preview MP3), Kenney Sci-fi Sounds `lowFrequency_explosion_001` (https://kenney.nl/assets/sci-fi-sounds) at +40 ms, OpenGameArt `bubble_01` (https://opengameart.org/content/40-cc0-water-splash-slime-sfx) at +150 ms | CC0 (all three) |
| `ruby.m4a` | R2, Kenney Interface Sounds `glass_001` (https://kenney.nl/assets/interface-sounds) | CC0 |
| `gameover.m4a` | G1, Kenney Music Jingles `jingles_PIZZI07` (https://kenney.nl/assets/music-jingles) | CC0 |
| `chip-white-1.m4a`, `chip-white-2.m4a`, `chip-white-3.m4a` | W3 pot bubble + fizz: OpenGameArt "40 CC0 water/splash/slime SFX" (https://opengameart.org/content/40-cc0-water-splash-slime-sfx), `bubble_02.ogg` | CC0 |
| `chip-blue-1.m4a`, `chip-blue-2.m4a`, `chip-blue-4.m4a` | B3 skull rattle + caw: freesound 361470, Jofae, "Crow Caw", https://freesound.org/people/Jofae/sounds/361470/; Kenney Impact Sounds `impactWood_light_000`-`004` (https://kenney.nl/assets/impact-sounds) | CC0, both (https://creativecommons.org/publicdomain/zero/1.0/) |
| `chip-green-1.m4a`, `chip-green-2.m4a`, `chip-green-4.m4a` | GR2 synth leg clicks. Own synthesis (numpy/scipy, sounds-v2 `designs.py`); no third-party source | none needed |
| `chip-orange-1.m4a`, `chip-orange-2.m4a`, `chip-orange-6.m4a` | O3 gloop into the brew: OpenGameArt "40 CC0 water/splash/slime SFX" (https://opengameart.org/content/40-cc0-water-splash-slime-sfx), `slime_02.ogg`, `slime_05.ogg`, `splash_11.ogg` | CC0 |
| `chip-red-1.m4a`, `chip-red-2.m4a`, `chip-red-4.m4a` | RD2 voice honk + sparkle: freesound 319333, Kurck, "toet.ogg", https://freesound.org/people/Kurck/sounds/319333/; freesound 511485, MLaudio, "cartoon_wink_magic_sparkle.wav", https://freesound.org/people/MLaudio/sounds/511485/ | CC0, both (https://creativecommons.org/publicdomain/zero/1.0/) |
| `chip-yellow-1.m4a`, `chip-yellow-2.m4a`, `chip-yellow-4.m4a` | Y2 tiny cartoon scream: freesound 788867, riippumattog, "Short Scream", https://freesound.org/people/riippumattog/sounds/788867/ | CC0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `chip-purple-1.m4a` | P3 spectral whisper: freesound 856169, brktkrgll, "Spectral Ghost Whisper Breeze Whoosh", https://freesound.org/people/brktkrgll/sounds/856169/ | CC0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `chip-black-1.m4a` | K2 synth flutter. Own synthesis (numpy/scipy, sounds-v2 `designs.py`); no third-party source | none needed |
| `chip-locoweed-1.m4a`, `chip-locoweed-2.m4a`, `chip-locoweed-3.m4a`, `chip-locoweed-4.m4a`, `chip-locoweed-5.m4a`, `chip-locoweed-6.m4a` | LW2 dry herb crackle, one file per space the locoweed moves (1 to 6; `QuacksWeb.Sounds.pot_sound/3`). Own synthesis (numpy/scipy, sounds-v2 `designs.py`); no third-party source | none needed |
| `fortune.m4a` | CB3 mystic swell (the crystal ball). Own synthesis (numpy/scipy, sounds-v2 `designs.py`); no third-party source | none needed |
| `shuffle-sh1.m4a` | SH1 (round 45, the game's chip shuffle): freesound 546121, el_boss, "Board Start.mp3" (wooden pieces scattered on a board), https://freesound.org/people/el_boss/sounds/546121/ | CC0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `shuffle-sh2.m4a` | SH2 (round 45, candidate): Kenney Casino Audio `chips-handle-4`, `chips-handle-6`, `chips-collide-2` (https://kenney.nl/assets/casino-audio) | CC0 |
| `shuffle-sh3.m4a` | SH3 (round 45, candidate): freesound 817567, SilverDubloons, "clatter10" (clay chips on wood), https://freesound.org/people/SilverDubloons/sounds/817567/ | CC0 (https://creativecommons.org/publicdomain/zero/1.0/) |
| `flask.m4a` | FL1 (round 45, the flask): Kenney Interface Sounds `glass_004` (https://kenney.nl/assets/interface-sounds), OpenGameArt "40 CC0 water/splash/slime SFX" `bubble_01.ogg` (https://opengameart.org/content/40-cc0-water-splash-slime-sfx) | CC0 (both) |

The chip and fortune files are Nick's picks of the sounds-v2 work (2026-10-11: W3,
B3, GR2, O3, RD2, Y2, P3, K2, LW2, CB3; session `03974705`,
`scratchpad/sounds-v2/final-picks/LICENSES.md` has the rows per file). Each freesound
licence was read on its page on 2026-10-11. ⚠️ The freesound parts are from the
public previews (lossy 128 kbps); download the originals with a free account before
a final release and build the files again.

Synth sounds (Web Audio in `assets/js/sound.js`, no file, no licence): `plop` (a chip
with no file of its own), `bloop` (the droplet moves), `chime` (the fortune teller
when `fortune.m4a` is missing).
