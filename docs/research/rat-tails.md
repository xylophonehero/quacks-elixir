# Rat tail positions on the scoring track

Research date: 2026-10-03. Scope: the original main board (Schmidt 2018 / North Star /
Schmidt English 2024 printings, which use the same board art).

## Result

The current engine list is **wrong**. Use this list.

A tail "after VP t" sits between space `t` and space `t + 1`.

```
1, 4, 7, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48
```

- 23 tails in total.
- From 1 to 10 the step is 3 (after 1, 4, 7, 10).
- From 10 to 48 the step is 2 (after every even VP from 10 to 48).
- No tail after 0, 2, 3, 5, 6, 8, 9, 49 or 50.
- No tail between 50 and 1 (the corner where the track laps).

Elixir: `@tails [1, 4, 7, 10] ++ Enum.to_list(12..48//2)`

### Difference from the old assumption

Old: `[1, 3] ++ Enum.to_list(6..50//2)` (25 entries).

| VP gap | Old | Board |
|---|---|---|
| after 3 | tail | no tail |
| after 4 | no tail | tail |
| after 6 | tail | no tail |
| after 7 | no tail | tail |
| after 8 | tail | no tail |
| after 50 | tail | no tail (no effect in play) |

From 10 to 48 the two lists agree. The old list came from Quackulator
(`data.py` `RAT_TAIL_VP`), which marks itself as "reconstructed — verify".

## Confidence: HIGH

Three independent sources agree on every gap:

1. **Clear photo of the full board** (BGG image 4953930, 4584x2628). I cropped each
   edge and counted the tails one gap at a time. Each tail hangs across the border of
   two number tiles, so the gap is easy to read.
2. **Official rulebook, page 3** (Schmidt English 2024, S1). The rat example shows
   spaces 6 to 24. It shows tails after 7, 10, 12, 14, 16, 18, 20, 22, 24, and no tail
   after 6, 8, 9, 11. The example text agrees: green on 20, blue on 19 = 0 tails,
   yellow on 17 = 1 tail, red on 16 = 2 tails.
3. **Fan app LeQuacks** (github.com/gitGut01/LeQuacks,
   `app/src/main/java/com/example/quacks/BuyItems/FragmentRattails.java`). Its
   `pointBoard` list puts a `-1` (tail) after 1, 4, 7, 10 and after every even VP from
   12 to 48. This is the same list.

A second photo (BGG image 8807552, "Score track comparison") shows the original board
again and agrees.

## Board layout notes

- The track spaces are numbered **1 to 50**. There is no printed "0" space. A marker
  on 0 sits on the 0/50 seal tile (in the box the quack holds). Space 1 is the
  bottom-left corner, and space 50 is next to it.
- Route: 1 (bottom-left) up the left side to 11, top row 12 to 26 (left to right),
  right side 27 to 36 (down), bottom row 37 to 50 (right to left).
- The engine counts tails strictly between two markers. That formula does not change.
  Only the list changes.

## Other edition (do not use for the base game)

BGG image 8807552 also shows a **different, purple board** (a newer reprint / other
product with purple rat meeples). Its tail positions look different. If Nick's copy has
a purple board, tell me and I will read that board too. The list above is for the
brown/wooden board with the turban quack.

## Sources and images

| File | Source |
|---|---|
| `docs/assets/scoring-track-bgg4953930.jpg` | https://boardgamegeek.com/image/4953930 (original: https://cf.geekdo-images.com/N_4ItiC2g8s7raxa96mfAg__original/img/Y6B97xjESSM_0LN0XSsvB1q21NA=/0x0/filters:format(jpeg)/pic4953930.jpg) |
| `docs/assets/scoring-track-rulebook-p3.jpg` | Crop of page 3, https://www.schmidtspiele.de/files/Retail/72dpi_PNG/88220_Quack_rules_english_2024.pdf |
| `docs/assets/scoring-track-bgg8807552-compare.jpg` | https://boardgamegeek.com/image/8807552 |

Also checked:
- Rulebook page 1 (contents) has a small picture of the full board. It is too blurry
  to count all tails, but it agrees where it is readable.
- Quackulator (S7): source of the old, reconstructed list. Not independent.
- Rival Quack (S8): no tail positions in the code (the player counts them by hand).
- BGA repo TacoV/TheQuacksOfQuedlinburg: empty stub, no data.

## Follow-up for code (not done here)

- Change `@tails` in `lib/quacks/rules/scoring_track.ex` and its moduledoc.
- Update `docs/research/rulebook.md` §1.2 to point to this file.
- Doctest `rat_tails(3, 12)` changes from 4 to 3 (tails after 4, 7, 10). Fix it.

## What Nick can photograph (optional)

Confidence is high, so this is not necessary. To confirm on the physical box, take one
photo of the bottom-left corner of the main board (spaces 1 to 11). That is the only
section where the old and new lists differ.
