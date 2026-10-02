# Quacks glossary

Terms used in code, tests and docs. Source: `docs/research/rulebook.md`.

| Term | Meaning |
|---|---|
| **chip** | An ingredient token. Has a **colour** (white, orange, green, blue, red, yellow, purple, black) and a **value** (1, 2, 3 or 4). White is the only colour that counts toward an explosion. |
| **seat** | A player's place at the table, `0..3` in turn order. `Quacks.Game.seats` lists them; `players` maps each seat to a `Quacks.Player`. Every player-facing function takes the seat (`legal_actions(game, seat)`, `apply(game, seat, action)`); the 2-arity `apply/2` and 1-arity `legal_actions/1` mean seat 0. |
| **player** | `Quacks.Player`: one seat's bag, pot (`drawn`, `pot_index`), blue offer (`pending`), droplet, flask, rubies, coins, VP, explosion state, rat stone and own potions-phase `phase` / `done?`. |
| **start seat** | The seat that starts the round: `rem(round - 1, players)`, so it rotates one seat per round (`Quacks.Game.start_seat/1`). The shop and the rubies phase go round the table from here; the evaluation visits seats in this order too. |
| **turn** | `Quacks.Game.turn`: the one seat that may act in `:buy_chips` and `:spend_rubies`. `nil` during `:potions`, where every seat not yet done may act. |
| **bag** | A player's hidden pool of chips. Chips are drawn from it blind. Starting bag: 4x white 1, 2x white 2, 1x white 3, 1x orange 1, 1x green 1. |
| **pot** | The cauldron track: 54 spaces (index 0-53). Each space has a coin number, some have VP and a ruby. Drawn chips are placed on it; a chip lands `value` spaces after the previous chip. Every player has their own pot. |
| **drawn** | The chips in a player's pot this round, as `{chip, index}` pairs, newest first (`Quacks.Player.drawn`). `index` is the 0-53 space the chip sits on, recorded when it is placed. The UI draws chips from these positions; a returned white chip (mandrake) leaves its space empty and later chips keep their index. `Quacks.Game.pot_chips/2` strips the positions. |
| **droplet** | The marker for a player's permanent start position on the pot. The first chip of a round is placed relative to it (or to the rat stone). Moves forward with 2 rubies or chip actions; never moves back. |
| **rat tails** | Marks between some spaces of the 0-50 VP track: after VP 1, 3 and every even VP from 6 to 50 (⚠️ reconstructed, rulebook §1.2). `Quacks.Rules.ScoringTrack.rat_tails(my_vp, leader_vp)` counts the tails strictly between two markers. |
| **rat stone** | From round 2 with 2+ players: every player behind the leader (highest VP; a tie for the lead gives nobody rats) starts the round `rat_tails` spaces past their droplet. `Quacks.Player.rat_stone` holds that distance (0 when none); it is set when a round starts and cleared when it ends. The flask falls back to droplet + rat stone when the pot is empty. |
| **flask** | One-shot per round: put the last drawn white chip back in the bag. Not usable if that chip caused the explosion. Refill for 2 rubies in the end-of-round phase. |
| **explosion** | When the sum of white chip values in the pot reaches 8 or more (the limit can rise: B5 card, Y3 mandrake; see **mods**). The exploding chip stays; the player must stop drawing and must choose VP **or** buying chips, not both. The choice waits on `Quacks.Player.explosion_choice` until the evaluation runs; a player who chose VP skips the shop. |
| **scoring space** | The space directly after the last placed chip. Gives coins, VP and possibly a ruby. |
| **ruby** | Currency for droplet moves and flask refills; 2 rubies = 1 VP in the last round. |
| **round** | One of 9 game turns. Each round runs the phases below. |
| **ingredient book** | The rule card for a colour's chip action and prices. Green, blue, red, yellow and purple each have Sets 1-4; orange and black have one book; white has none. |
| **sets** | `Game.new(sets: %{green: 1..4, blue: 1..4, red: 1..4, yellow: 1..4, purple: 1..4})` picks the book per colour; colours left out use Set 1 (`game.sets`). Prices differ per set: `Quacks.Rules.Chips.price(chip, sets)` (`price/1` = Set 1). Effects dispatch on `{colour, set}` (`Potions.bonus/3`, `Potions.on_draw/4`, `Evaluation.chip_action/3`). All 20 books are supported; G2, G4, P2 and P4 open a **chip choice**, R2 uses **beside the pot**. `Quacks.Session.new/3`, `Session.replay/4` and `Quacks.GameServer.start/3` take the same `sets`. Source: `docs/research/ingredient-sets-and-customisation.md`. |
| **mods** | `Quacks.Player.mods`, round modifiers from Set 2-4 chips, reset at the end of the round (and by B3): `explode_above` (7; Y3: 8 after the 1st yellow, 9 after the 3rd; the B5 card's 9 still counts, the higher limit wins: `Potions.explode_above/2`), `next_chip_x2` (Y2), `white1_plus1` (R4), `protect` (B2: drawn chips left in the crow-skull window). |
| **chip choice** | Step B of the evaluation with G2, G4, P2 or P4: `Quacks.Player.chip_choices` lists what the player may still choose; the game phase `:chip_choice` gives each seat with a choice the `turn`, from the start seat. It runs after the bonus die and the automatic chip actions, before rubies and VP (steps C/D). Set 1 purple still takes the highest tier automatically. |
| **beside the pot** | Red Set 2: `Quacks.Player.aside`, red chips drawn but not placed. They are not in the bag and stay there across rounds. After stopping (or the explosion choice) the player decides each one in `:red_choice`; the evaluation waits for every player. A placed red moves only its value. |
| **supply** | The chips left in the box per colour and value (`Quacks.Rules.Chips.supply/0`), shared by all players. Every starting bag, bought chips, the orange die face and the round-6 white chips all come out of it. A kind with 0 left is not buyable. Yellow is buyable from round 2, purple from round 3. |
| **blue offer** | The extra chips a blue chip draws (`pending` on the player). The player places at most one as the next chip; the rest go back in the bag. |
| **black rule** | Rulebook §4. 2 players: as many black chips as the opponent (and at least 1) → droplet +1; more → droplet +1 and 1 ruby. 3-4 players: more than one neighbour (adjacent seat) → droplet +1; more than both → droplet +1 and 1 ruby. |
| **fortune card** | A Fortune Teller card (rulebook §5, ⚠️ fan transcription). `Quacks.Rules.Fortune` holds the 24 cards (`:b1`–`:b11` blue, `:p1`–`:p13` purple); `Quacks.Game.Fortune` holds their rules. `Game.new(fortune: false)` plays without cards (default `true`). The deck (`fortune_deck`, ids) is shuffled at `new/1` from a jump of the game's `rng`, so a seed draws the same chips with or without cards. Solo decks leave out P4, P5, P8 and B2; solo skips P7 and P9 when they come up. `fortune_card` is the card of the current round. |
| **purple card** | Resolved once at the start of the round, after the rats: an automatic part for every seat, then a `:fortune_choice` turn for each seat with a choice, in seat order from the start seat. |
| **blue card** | A rule for the whole round: explosion limit 9 (B5), orange +1 space (B6), first white back (B10), exactly 7 white on stop → droplet (B1), bonus die rolled twice with both rewards (B4), free flask refill after the evaluation (B9), ruby scoring space → 2 VP (B8) or +1 ruby (B11), restart once after the 5th chip (B3), a 5-chip offer on stop (B7), a 2-value chip for the player left of an exploded pot after the potions phase (B2). |
| **black house rule** | ⚠️ Solo has no opponent to compare black chips with. The engine treats 1+ black chip in the pot as "tied with the opponent": droplet +1, no ruby. Rulebook §6.2 suggests droplet +1 and 1 ruby instead; we chose the lower payout. |
| **game id** | 6 lowercase letters naming one running game, as in `/g/:id`. `Quacks.GameServer` registers each game process under its id in `Quacks.GameRegistry`. |
| **player token** | A random value in the browser's session cookie (`QuacksWeb.Plugs.PlayerToken`). It stands in for an account: a `GameServer` maps token → seat on the first `claim_seat`. Seats fill in join order; the creator is seat 0. Shown to people as "Seat N" with N = seat + 1, or a nickname. |
| **spectator** | A browser on a full game that has no seat. It sees every pot and no buttons. |

## Log (`Quacks.Game.log`)

Newest first. Every entry that concerns one player is tagged with the seat: `{seat, entry}`, e.g. `{0, {:drew, {:white, 2}, 5}}`. Applied actions are logged (tagged) and followed by the events they caused. The only untagged entry is `{:round_end, round}`.

| Entry | When |
|---|---|
| `{:drew, chip, index}` | Every placement, including a chip placed through a blue chip. |
| `{:returned, chip}` | A chip went back in the bag: flask, mandrake, or the rest of a blue offer. |
| `{:exploded, white_sum}` | The white sum passed 7. |
| `{:bought, chips}` | A purchase of one or two chips (`{:buy, []}` logs only the action). |
| `{:rubies_spent, :droplet \| :flask}` | Two rubies spent in the end-of-round phase. |
| `{:bonus_die, face}` | A die roll in the evaluation; only the seat(s) on the highest scoring space roll. |
| `{:black, :droplet}` | Step B: black paid the droplet only (solo house rule, 2p tie, 3-4p more than one neighbour). |
| `{:black, :droplet_ruby}` | Step B: black paid droplet and ruby (2p more than the opponent, 3-4p more than both neighbours). |
| `{:green_rubies, n}` | Step B: `n` green chips in the last two positions, `n` > 0. |
| `{:purple, tier, payoff}` | Step B, only with 1+ purple: `{:purple, 1, :vp1}`, `{:purple, 2, :vp1_ruby}` or `{:purple, 3, :vp2_droplet}` (3+ purple). |
| `{:pot_ruby, index}` | Step C: the scoring space `index` gave a ruby. |
| `{:pot_vp, vp, index}` | Step D: `vp` > 0 taken from scoring space `index`. Not logged when an exploded player chose to buy. |
| `{:final_conversion, coins_vp, rubies_vp}` | Round 9 only: VP bought with coins (5 each) and rubies (2 each). |
| `{:rats, tails}` | A new round started with this player `tails` spaces ahead on the rat stone. |
| `{:fortune_drawn, id}` | Untagged. A Fortune Teller card was turned up at the start of the round. |
| `{:fortune_skipped, id}` | Untagged. Solo only: P7 or P9 came up and was put aside. |
| `{:fortune, id, outcome}` | What card `id` did for this player (see the table below). |
| `{:effect, {colour, set}, detail}` | A Set 2-4 chip effect (see the table below). |
| `{:round_end, round}` | The last event of every round. Untagged. |

Card outcomes (`{seat, {:fortune, id, outcome}}`):

| Card | Outcomes |
|---|---|
| B1 | `:droplet` |
| B2, P1, P3, P5, P10, P11 | `{:take, chip}` (the chip went from the supply to the bag) |
| B3 | `:restart_round` |
| B7 | `{:place, chip}`, `:return_all` |
| B8 | `{:vp, 2}` |
| B9 | `:flask` |
| B10 | `:return_white` |
| B11, P4, P8 | `:ruby` |
| P1 | `:rubies` (3) |
| P2, P11 | `:droplet` (P2: 1 space, P11: 2) |
| P3, P9, P13 | `:skip` |
| P6 | `{:vp, 4}`, `:remove_white` |
| P7 | `{:rats, extra}` |
| P8 | `{:take, {:blue, 2}}` |
| P9 | `{:rats_back, n}` |
| P10 | `{:vp, n}` |
| P12 | the die face, e.g. `{:vp, 2}` or `:ruby` |
| P13 | `{:upgrade, chip}` (`chip` went to the supply, the next value up to the bag), `{:take, {:green, 1}}` |

B4 logs nothing of its own: the second `{:bonus_die, face}` shows it.

Chip effects (`{seat, {:effect, {colour, set}, detail}}`), logged after the chip's `{:drew, ...}` (or in step B):

| Book | Detail | When |
|---|---|---|
| G3 | `{:moved_last, n}` | Step B, exactly 7 white: the last chip moved `n` (sum of the green values) spaces, before steps C/D. |
| B2 | `{:protect, window}` | A crow skull was drawn: the next `window` drawn chips are protected (the larger of what was left and the chip value; windows do not add up). |
| B2 | `:protected_explosion` | The pot exploded inside the window: after `{:exploded, sum}`, no choice; the player gets the VP **and** the coins, no bonus die. |
| B3 | `:ruby` | The blue chip landed on a ruby space: 1 ruby. |
| B4 | `{:vp, n}` | The blue chip landed on a ruby space: `n` = its value in VP. |
| R3 | `{:extra, w}` | The red chip came right after a white `w` chip: `w` more spaces. |
| R4 | `:white_plus1` | A white 1-chip moved 2 because a red chip is in the pot. |
| Y2 | `{:doubled, move}` | The chip after a mandrake moved double (its full move, bonuses included). A yellow chip that is doubled arms the next chip again. |
| Y3 | `{:limit, 8 \| 9}` | The 1st (8) or 3rd (9) yellow chip raised the white limit. |
| Y4 | `{:extra, n}` | The `n`-th yellow chip of the round (1-3) moved `n` more spaces. |
| P3 | `{:vp, n}` | Step B: `n` > 0 VP from purple chips by pot field (0-9: 0, 10-19: 1, 20-29: 2, 30+: 3 each). |
| G2 | `{:gain, chip}` | Chip choice: `chip` went from the supply to the bag. |
| G4 | `{:droplet, n}` | Chip choice: paid `n` rubies, droplet +`n`. |
| P2 | `{:trade, tier}` | Chip choice: `tier` purple chips went back to the supply; 1 → black 1, 1 VP, 1 ruby; 2 → green 1, blue 2, 3 VP, droplet +1; 3 → yellow 4, 6 VP, 1 ruby, droplet +2. |
| P4 | `{:upgrade, from, to}` | Chip choice: `from` left the pot for the supply, `to` went into the bag. |
| R2 | `{:aside, chip}` | A red chip was drawn and put beside the pot. Placing it later logs `{:drew, chip, index}`, returning it `{:returned, chip}`; keeping it logs only the action. |

`Quacks.Session` replays from its own `actions` list (`[{seat, action}]`, newest first), never from the log.

## Round phases (in order)

| Phase | Name | What happens |
|---|---|---|
| 1 | `:fortune_teller` | Turn up the next Fortune Teller card (`{:fortune_drawn, id}`). A purple card resolves after the rats, before the potions phase. |
| 2 | `:rats` | From round 2 with 2+ players: every player behind the leader places the rat stone `rat_tails` spaces past the droplet (solo: none). Runs inside the previous round's last `:end_round`. |
| 3 | `:potions` | Every player draws chips from their bag one at a time, places them on their pot, stops or explodes. Blue, red, yellow act on draw. Players act simultaneously, in any order. |
| 4a | `:bonus_die` | Among the non-exploded players, the one(s) on the highest scoring space roll the bonus die. |
| 4b | `:chip_actions` | Resolve black, green, purple chips in every pot, start seat first. |
| 4c | `:rubies` | Each player takes a ruby if their scoring space shows one. |
| 4d | `:victory_points` | Each player takes the VP of their scoring space (not an exploded player who chose to buy). |
| 4e | `:buy_chips` | One seat at a time from the start seat: spend the coins of the scoring space on 1 or 2 chips (2 must differ in colour). An exploded player who chose VP skips this. Round 9: nobody buys; coins become VP at the end. |
| 4f | `:end_of_round` | One seat at a time from the start seat: spend rubies (droplet forward, refill flask), then `:end_round`. After the last seat's `:end_round` all chips go back in the bags; before round 6 every player adds 1 white 1-chip. |

## Engine phases

Steps with no player choice run inside `apply/3`. The game has a coarse `phase`; during `:potions` each player also has their own `phase`, and `Quacks.Game.phase(game, seat)` returns the one that seat sees.

| Game phase | Who acts | Actions | When |
|---|---|---|---|
| `:fortune_choice` | `turn` only | `{:fortune, choice}` | A purple card's choice, seat by seat from the start seat, before `:potions`; or B2's chip after `:potions`, before the evaluation. |
| `:chip_choice` | `turn` only | `{:chip, choice}`, `:chip_done` | Evaluation step B with G2, G4, P2 or P4, seat by seat from the start seat (see **Chip choices** below). The turn also ends when nothing is left to choose. |
| `:potions` | every seat whose player is not `:done` | see player phases | Drawing chips. Once the last player is done, the evaluation (4a-4d) runs and the game moves on. |
| `:buy_chips` | `turn` only | `{:buy, [chip]}` | Step 4e, seat by seat. |
| `:spend_rubies` | `turn` only | `{:rubies, :droplet \| :flask \| :skip}`, `:end_round` | Step 4f, seat by seat. The last `:end_round` ends the round. |
| `:over` | nobody | none | After round 9. |

| Player phase (`Quacks.Player.phase`) | Actions | When |
|---|---|---|
| `:potions` | `:draw`, `:stop`, `:use_flask`; with B3 `{:fortune, :restart_round}`, with B10 `{:fortune, :return_white}` | Drawing chips. Red moves extra spaces automatically. |
| `:fortune_choice` | `{:fortune, {:place, chip}}`, `{:fortune, :return_all}` | B7: the player stopped and drew up to 5 chips (`pending`). Placing one may explode the pot; otherwise the player is done. |
| `:yellow_choice` | `:return_white`, `:keep` | A yellow chip was drawn directly after a white chip. |
| `:blue_choice` | `{:place, chip}`, `:return_all` | A blue chip drew extra chips (the blue offer). |
| `:explosion_choice` | `{:explosion_choice, :vp \| :buy}` | White sum reached 8. |
| `:red_choice` | `{:red, {:place \| :keep \| :return, chip}}` | Red Set 2: the player stopped (or made the explosion choice) with chips beside the pot (now in `pending`). One action per chip; then `:done`. |
| `:done` | none | Stopped, or the explosion choice is made; waiting for the other players (`done?` is true). |

## Fortune choices (`{:fortune, choice}`)

| Choice | Cards |
|---|---|
| `{:take, chip}` | P1 (black 1 or a 2-value chip), P3 (a 1-value chip, not purple or black; costs 1 ruby), P10 (a 4-value chip), P11 (purple 1, from round 3), B2 (a 2-value chip). Only chips in the shop this round and in the supply. |
| `:rubies` | P1: 3 rubies. |
| `:vp` | P6: 4 VP. P10: 1 VP per rat tail behind the leader (offered only when behind; never in solo). |
| `:remove_white` | P6: a white 1 leaves the bag for the supply. |
| `{:rats_back, n}` | P9: rat stone `n` (1-3, at most its value) back, `n` rubies. |
| `:droplet` | P11: droplet 2 forward. |
| `{:upgrade, chip}` | P13: trade `chip` from the 4 drawn for the next value up (green, blue, red, yellow; not white). |
| `:skip` | P3, P9, P13: decline. |
| `:restart_round` | B3: pot back in the bag, start again (once, right after the 5th chip). |
| `:return_white` | B10: the first white chip of the round back in the bag (free, like the flask). |
| `{:place, chip}`, `:return_all` | B7: place one chip of the 5-chip offer, or none. |

## Chip choices (`{:chip, choice}`)

| Choice | Book |
|---|---|
| `{:gain, chip}` | G2, once per green chip on the last two positions: green 1 → orange 1; green 2 → blue 1 or red 1; green 4 → yellow 1 or purple 1 (⚠️ also before that book is in the shop). Only while the supply has one. |
| `{:pay_ruby_move, n}` | G4: `n` (1 up to the greens on the last two positions, and the rubies you have) rubies → droplet +`n`. |
| `{:purple_trade, tier}` | P2: trade `tier` (1 up to the purple chips, max 3) purple chips; one tier only. |
| `{:upgrade, from, to}` | P4: 1 purple: a 1-chip → 2-chip; 2: 2 → 4 (or 1 → 2); 3+: 1 → 4 (or a lower tier). Same colour, only green, blue, red, yellow. |
| `:chip_done` | End this seat's choices; whatever is left is skipped. |
