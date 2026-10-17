#!/usr/bin/env python3
"""Build the Duet bot's word vectors (priv/games/codenames_duet/*.bin).

Two sources:

- ConceptNet Numberbatch 19.08, English (Speer, Chin, Havasi 2017),
  https://github.com/commonsense/conceptnet-numberbatch. Licence: CC BY-SA 4.0;
  the file made from it (vectors.bin) has the same licence. See docs/CREDITS.md.
  The bot plays with these vectors.
- GloVe 6B (Pennington, Socher, Manning 2014), https://nlp.stanford.edu/projects/glove/.
  Licence: PDDL. The bench (CodenamesDuet.AI.Bench) uses glove.bin as a
  "human proxy" guesser: a partner that does not share the bot's vectors.

Usage (needs numpy; download the sources once, outside the repo:
glove.6B.zip is 822 MB, numberbatch-en-19.08.txt.gz is 325 MB):

    unzip glove.6B.zip glove.6B.100d.txt
    python3 docs/games/codenames_duet/build_vectors.py numberbatch \\
        numberbatch-en-19.08.txt.gz glove.6B.100d.txt priv/games/codenames_duet/vectors.bin
    python3 docs/games/codenames_duet/build_vectors.py glove \\
        glove.6B.100d.txt glove.6B.100d.txt priv/games/codenames_duet/glove.bin

The third argument is always a GloVe file: GloVe lists its words by frequency,
and that order selects the clue vocabulary for both sources.

The file keeps:

- the board words (priv/games/codenames_duet/words.txt), all of them;
- a clue vocabulary: the most frequent GloVe words that are 3..12 lower-case
  letters, a word in lower case in /usr/share/dict/words (a base form: no
  plurals or past tenses, and most names drop out, as the dictionary has them
  with a capital letter only), not a stop word, not in BLOCK, and in the source.
  (The bot reads a clue such as "ships" as "ship".)

Format (little endian), read by CodenamesDuet.AI.Vectors.Data:

    "CDV1"  u32 count  u16 dim  u16 k
    count x (u8 flags, u8 length, bytes)      flags: 1 = clue word, 2 = board word
    count x dim x i8                          each vector scaled to max |x| = 127
    for each board word, in words.txt order:  k x (u16 index, i8 cosine x 127)
                                              its k nearest clue words, nearest first
"""
import gzip
import re
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
WORDS = ROOT / "priv/games/codenames_duet/words.txt"
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
due thing things something nothing everything someone everyone somebody nobody lot lots
kind sort way ways able unable likely unlikely possible certain sure etc else instead
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


def candidates(glove, board_set):
    """The clue words in GloVe frequency order (before the source filter)."""
    lower = dictionary()
    out = []
    with open(glove, encoding="utf8") as f:
        for i, line in enumerate(f):
            if i >= SCAN:
                break
            word = line.split(" ", 1)[0]
            if (
                re.fullmatch("[a-z]{3,12}", word)
                and word not in STOP
                and word not in BLOCK
                and word in lower
            ):
                out.append(word)
    return out


def read_source(kind, path, wanted):
    """The vectors of the `wanted` words in the source file."""
    vecs = {}
    opener = gzip.open if str(path).endswith(".gz") else open
    with opener(path, "rt", encoding="utf8") as f:
        for n, line in enumerate(f):
            if kind == "numberbatch" and n == 0:
                continue
            word, rest = line.split(" ", 1)
            if word in wanted and word not in vecs:
                vecs[word] = np.array(rest.split(), dtype=np.float32)
    return vecs


def main(kind, source, glove, out_path):
    board = [w.strip() for w in WORDS.read_text().split("\n") if w.strip()]
    board_set = set(board)
    cands = candidates(glove, board_set)
    vecs = read_source(kind, source, set(cands) | board_set)

    missing = [w for w in board if w not in vecs]
    if missing:
        sys.exit(f"board words not in {source}: {missing}")

    clue_words = [w for w in cands if w in vecs][:CLUES]

    # The order: the clue words (by frequency), then the board words not among them.
    clue_set = set(clue_words)
    order = clue_words + [w for w in board if w not in clue_set]
    index = {w: i for i, w in enumerate(order)}
    mat = np.stack([vecs[w] for w in order])
    dim = mat.shape[1]

    unit = mat / np.linalg.norm(mat, axis=1, keepdims=True)
    q = np.round(unit / np.abs(unit).max(axis=1, keepdims=True) * 127).astype(np.int8)

    out = bytearray(b"CDV1")
    out += struct.pack("<IHH", len(order), dim, K)
    for w in order:
        flags = (1 if w in clue_set else 0) | (2 if w in board_set else 0)
        b = w.encode()
        out += struct.pack("<BB", flags, len(b)) + b
    out += q.tobytes()

    clue_unit = unit[: len(clue_words)]
    for w in board:
        sims = clue_unit @ unit[index[w]]
        if index[w] < len(clue_words):
            sims[index[w]] = -1
        top = np.argsort(-sims)[:K]
        for j in top:
            out += struct.pack("<Hb", int(j), int(round(float(sims[j]) * 127)))

    Path(out_path).write_bytes(out)
    print(f"{out_path}: {len(order)} words ({len(clue_words)} clues), {dim}d, k={K}, {len(out)} bytes")


if __name__ == "__main__":
    if len(sys.argv) != 5 or sys.argv[1] not in ("glove", "numberbatch"):
        sys.exit(__doc__)
    main(*sys.argv[1:])
