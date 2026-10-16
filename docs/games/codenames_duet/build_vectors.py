#!/usr/bin/env python3
"""Build priv/games/codenames_duet/vectors.bin from GloVe (the Duet bot's word vectors).

Source: GloVe 6B (Pennington, Socher, Manning 2014), https://nlp.stanford.edu/projects/glove/
Licence: Public Domain Dedication and License v1.0 (PDDL). See docs/CREDITS.md.

Usage (needs numpy; glove.6B.zip is 822 MB, download it once outside the repo):

    unzip glove.6B.zip glove.6B.100d.txt
    python3 docs/games/codenames_duet/build_vectors.py glove.6B.100d.txt

The file keeps:

- the board words (priv/games/codenames_duet/words.txt), all of them;
- a clue vocabulary: the most frequent GloVe words (GloVe lists them by
  frequency) that are 3..12 lower-case letters, a word in lower case in
  /usr/share/dict/words (a base form: no plurals or past tenses, and most names
  drop out, as the dictionary has them with a capital letter only), not a stop
  word and not in BLOCK. (The bot reads a clue such as "ships" as "ship".)

Format (little endian), read by CodenamesDuet.AI.Vectors.Data:

    "CDV1"  u32 count  u16 dim  u16 k
    count x (u8 flags, u8 length, bytes)      flags: 1 = clue word, 2 = board word
    count x dim x i8                          each vector scaled to max |x| = 127
    for each board word, in words.txt order:  k x (u16 index, i8 cosine x 127)
                                              its k nearest clue words, nearest first
"""
import re
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
WORDS = ROOT / "priv/games/codenames_duet/words.txt"
OUT = ROOT / "priv/games/codenames_duet/vectors.bin"
SCAN = 45_000  # the most frequent GloVe words to read
CLUES = 20_000  # the clue vocabulary, at most (45,000 words give about 17,500)
K = 300  # nearest clue words per board word

STOP = set("""
a about above after again against all also am an and any are as at be because been
before being below between both but by can could did do does doing done down during
each either else ever every few for from further had has have having he her here hers
herself him himself his how however i if in into is it its itself just let like may me
might mine more most much must my myself neither no nor not now of off on once one only
or other ought our ours ourselves out over own per rather same shall she should since so
some such than that the their theirs them themselves then there these they this those
though through thus to too under until up upon us very was we were what when where
whether which while who whom whose why will with within without would yet you your yours
yourself yourselves said says say saying told tell according also although among amongst
another anyone anything around away back became become becomes did even get gets getting
got gotten goes going gone made make makes many still well went whatever whenever whereas
wherever whichever whoever already almost always often never sometimes usually yes okay
mr mrs ms dr inc ltd etc via vs ago yesterday today tomorrow tonight percent
amid amidst near nearest nearby toward towards across along alongside onto beside besides
despite unlike regarding whereby thereby hence inside outside beyond behind
""".split())

# Not family-friendly, or a slur, or too grim for a party game.
BLOCK = set("""
abortion abuse abused abuser abusive addict anal anus arse arsehole ass asses asshole
bastard bitch bitches blowjob bollocks boner boob boobs booty breast breasts brothel bugger
butt buttocks cocaine cock cocks condom condoms crap crack cum cunt damn damned dick dicks
dildo dope drunk drunken dyke ejaculate erection erotic erotica fag faggot fags fetish
fornication fuck fucked fucker fucking gay gays genital genitalia genitals genocide gonorrhea
heroin hitler holocaust homo homosexual horny hooker hookers incest jihad jihadist kinky
lesbian lesbians lust masturbate masturbation meth molest molestation molested naked nazi
nazis negro nigger nipple nipples nude nudes nudity orgasm orgy paedophile pedophile
pedophilia penis penises piss pissed porn porno pornographic pornography prostitute
prostitutes prostitution pubic pussy queer racist rape raped rapes rapist rapists retard
retarded scrotum semen sex sexes sexual sexuality sexually sexy shit shits shitty slave
slavery slaves slut sluts sodomy sperm stripper suicide suicides syphilis terrorism
terrorist terrorists testicle testicles tits titty torture tortured transvestite twat
urine vagina viagra vibrator whore whores wank wanker
""".split())


def dictionary():
    words = Path("/usr/share/dict/words").read_text().split()
    return {w for w in words if w.islower()}


def main(glove):
    board = [w.strip() for w in WORDS.read_text().split("\n") if w.strip()]
    board_set = set(board)
    lower = dictionary()

    vectors, clue_words, board_vecs = {}, [], {}
    with open(glove, encoding="utf8") as f:
        for i, line in enumerate(f):
            word, rest = line.split(" ", 1)
            if word in board_set and word not in board_vecs:
                board_vecs[word] = np.array(rest.split(), dtype=np.float32)
            if (
                i < SCAN
                and len(clue_words) < CLUES
                and re.fullmatch("[a-z]{3,12}", word)
                and word not in STOP
                and word not in BLOCK
                and word in lower
            ):
                clue_words.append(word)
                vectors[word] = np.array(rest.split(), dtype=np.float32)
            if i >= SCAN and len(board_vecs) == len(board_set):
                break

    missing = [w for w in board if w not in board_vecs]
    if missing:
        sys.exit(f"board words not in GloVe: {missing}")

    # The order: the clue words (by frequency), then the board words not among them.
    clue_set = set(clue_words)
    order = clue_words + [w for w in board if w not in clue_set]
    index = {w: i for i, w in enumerate(order)}
    mat = np.stack([vectors[w] if w in vectors else board_vecs[w] for w in order])
    dim = mat.shape[1]

    unit = mat / np.linalg.norm(mat, axis=1, keepdims=True)
    q = np.round(unit / np.abs(unit).max(axis=1, keepdims=True) * 127).astype(np.int8)

    clue_idx = np.arange(len(clue_words))
    out = bytearray(b"CDV1")
    out += struct.pack("<IHH", len(order), dim, K)
    for w in order:
        flags = (1 if w in clue_set else 0) | (2 if w in board_set else 0)
        b = w.encode()
        out += struct.pack("<BB", flags, len(b)) + b
    out += q.tobytes()

    clue_unit = unit[clue_idx]
    for w in board:
        sims = clue_unit @ unit[index[w]]
        if index[w] < len(clue_words):
            sims[index[w]] = -1
        top = np.argsort(-sims)[:K]
        for j in top:
            out += struct.pack("<Hb", int(j), int(round(float(sims[j]) * 127)))

    OUT.write_bytes(out)
    print(f"{OUT}: {len(order)} words ({len(clue_words)} clues), {dim}d, k={K}, {len(out)} bytes")


if __name__ == "__main__":
    main(sys.argv[1])
