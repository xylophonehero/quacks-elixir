# Quacks glossary

Terms used in code, tests and docs. Source: `docs/research/rulebook.md`.

| Term | Meaning |
|---|---|
| **chip** | An ingredient token. Has a **colour** (white, orange, green, blue, red, yellow, purple, black) and a **value** (1, 2, 3 or 4). White is the only colour that counts toward an explosion. |
| **bag** | The player's hidden pool of chips. Chips are drawn from it blind. Starting bag: 4x white 1, 2x white 2, 1x white 3, 1x orange 1, 1x green 1. |
| **pot** | The cauldron track: 54 spaces (index 0-53). Each space has a coin number, some have VP and a ruby. Drawn chips are placed on it; a chip lands `value` spaces after the previous chip. |
| **drawn** | The chips in the pot this round, as `{chip, index}` pairs, newest first (`Quacks.Game.drawn`). `index` is the 0-53 space the chip sits on, recorded when it is placed. The UI draws chips from these positions; a returned white chip (mandrake) leaves its space empty and later chips keep their index. `Quacks.Game.pot_chips/1` strips the positions. |
| **droplet** | The marker for the player's permanent start position on the pot. The first chip of a round is placed relative to it. Moves forward with 2 rubies or chip actions; never moves back. |
| **flask** | One-shot per round: put the last drawn white chip back in the bag. Not usable if that chip caused the explosion. Refill for 2 rubies in the end-of-round phase. |
| **explosion** | When the sum of white chip values in the pot reaches 8 or more. The exploding chip stays; the player must stop drawing and must choose VP **or** buying chips, not both. |
| **scoring space** | The space directly after the last placed chip. Gives coins, VP and possibly a ruby. |
| **ruby** | Currency for droplet moves and flask refills; 2 rubies = 1 VP in the last round. |
| **round** | One of 9 game turns. Each round runs the phases below. |
| **ingredient book** | The rule card for a colour's chip action and prices. Phase 1 uses book 1 for each colour. |
| **supply** | The chips left in the box per colour and value (`Quacks.Rules.Chips.supply/0`). The starting bag, bought chips, the orange die face and the round-6 white chip all come out of it. A kind with 0 left is not buyable. Yellow is buyable from round 2, purple from round 3. |
| **blue offer** | The extra chips a blue chip draws (`pending` on the struct). The player places at most one as the next chip; the rest go back in the bag. |
| **black house rule** | ⚠️ Solo has no opponent to compare black chips with. The engine treats 1+ black chip in the pot as "tied with the opponent": droplet +1, no ruby. Rulebook §6.2 suggests droplet +1 and 1 ruby instead; we chose the lower payout. |

## Log (`Quacks.Game.log`)

Newest first. Every applied action is logged, followed by the events it caused:

| Entry | When |
|---|---|
| `{:drew, chip, index}` | Every placement, including a chip placed through a blue chip. |
| `{:returned, chip}` | A chip went back in the bag: flask, mandrake, or the rest of a blue offer. |
| `{:exploded, white_sum}` | The white sum passed 7. |
| `{:bought, chips}` | A purchase of one or two chips (`{:buy, []}` logs only the action). |
| `{:rubies_spent, :droplet \| :flask}` | Two rubies spent in the end-of-round phase. |
| `{:bonus_die, face}` | The die roll after stopping. |
| `{:black, :droplet}` | Step B: the black house rule fired (1+ black chip). |
| `{:green_rubies, n}` | Step B: `n` green chips in the last two positions, `n` > 0. |
| `{:purple, tier, payoff}` | Step B, only with 1+ purple: `{:purple, 1, :vp1}`, `{:purple, 2, :vp1_ruby}` or `{:purple, 3, :vp2_droplet}` (3+ purple). |
| `{:pot_ruby, index}` | Step C: the scoring space `index` gave a ruby. |
| `{:pot_vp, vp, index}` | Step D: `vp` > 0 taken from scoring space `index`. Not logged when an exploded player chose to buy. |
| `{:final_conversion, coins_vp, rubies_vp}` | Round 9 only: VP bought with coins (5 each) and rubies (2 each). |
| `{:round_end, round}` | The last event of every round. |

`Quacks.Session` replays from its own `actions` list, never from the log.

## Round phases (in order)

| Phase | Name | What happens |
|---|---|---|
| 1 | `:fortune_teller` | Read a fortune teller card. **Out of scope in phase 1; skipped.** |
| 2 | `:rats` | From round 2: rat tails give trailing players a head start (solo: none). |
| 3 | `:potions` | Draw chips from the bag one at a time, place them on the pot, stop or explode. Blue, red, yellow act on draw. |
| 4a | `:bonus_die` | Non-exploded player rolls the bonus die. |
| 4b | `:chip_actions` | Resolve black, green, purple chips in the pot. |
| 4c | `:rubies` | Take a ruby if the scoring space shows one. |
| 4d | `:victory_points` | Take the VP of the scoring space. |
| 4e | `:buy_chips` | Spend the coins of the scoring space on 1 or 2 chips (2 must differ in colour). Round 9: buy VP instead (5 coins or 2 rubies each). |
| 4f | `:end_of_round` | Spend rubies (droplet forward, refill flask). All chips go back in the bag. Before round 6 add 1 white 1-chip. |

## Engine phases (`Quacks.Game.phase`)

The struct's `phase` field is coarser than the table above: steps with no player choice run inside `apply/2`.

| Phase | Actions | When |
|---|---|---|
| `:potions` | `:draw`, `:stop`, `:use_flask` | Drawing chips. Red moves extra spaces automatically. |
| `:yellow_choice` | `:return_white`, `:keep` | A yellow chip was drawn directly after a white chip. |
| `:blue_choice` | `{:place, chip}`, `:return_all` | A blue chip drew extra chips (the blue offer). |
| `:explosion_choice` | `{:explosion_choice, :vp \| :buy}` | White sum reached 8. |
| `:buy_chips` | `{:buy, [chip]}` | After the die (step A), chip actions (step B), rubies (C) and VP (D). |
| `:spend_rubies` | `{:rubies, :droplet \| :flask \| :skip}`, `:end_round` | Step F. |
| `:over` | none | After round 9. |
