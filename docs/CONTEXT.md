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
| **explosion** | When the sum of white chip values in the pot reaches 8 or more. The exploding chip stays; the player must stop drawing and must choose VP **or** buying chips, not both. The choice waits on `Quacks.Player.explosion_choice` until the evaluation runs; a player who chose VP skips the shop. |
| **scoring space** | The space directly after the last placed chip. Gives coins, VP and possibly a ruby. |
| **ruby** | Currency for droplet moves and flask refills; 2 rubies = 1 VP in the last round. |
| **round** | One of 9 game turns. Each round runs the phases below. |
| **ingredient book** | The rule card for a colour's chip action and prices. Phase 1 uses book 1 for each colour. |
| **supply** | The chips left in the box per colour and value (`Quacks.Rules.Chips.supply/0`), shared by all players. Every starting bag, bought chips, the orange die face and the round-6 white chips all come out of it. A kind with 0 left is not buyable. Yellow is buyable from round 2, purple from round 3. |
| **blue offer** | The extra chips a blue chip draws (`pending` on the player). The player places at most one as the next chip; the rest go back in the bag. |
| **black rule** | Rulebook §4. 2 players: as many black chips as the opponent (and at least 1) → droplet +1; more → droplet +1 and 1 ruby. 3-4 players: more than one neighbour (adjacent seat) → droplet +1; more than both → droplet +1 and 1 ruby. |
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
| `{:round_end, round}` | The last event of every round. Untagged. |

`Quacks.Session` replays from its own `actions` list (`[{seat, action}]`, newest first), never from the log.

## Round phases (in order)

| Phase | Name | What happens |
|---|---|---|
| 1 | `:fortune_teller` | Read a fortune teller card. **Out of scope in phase 1; skipped.** |
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
| `:potions` | every seat whose player is not `:done` | see player phases | Drawing chips. Once the last player is done, the evaluation (4a-4d) runs and the game moves on. |
| `:buy_chips` | `turn` only | `{:buy, [chip]}` | Step 4e, seat by seat. |
| `:spend_rubies` | `turn` only | `{:rubies, :droplet \| :flask \| :skip}`, `:end_round` | Step 4f, seat by seat. The last `:end_round` ends the round. |
| `:over` | nobody | none | After round 9. |

| Player phase (`Quacks.Player.phase`) | Actions | When |
|---|---|---|
| `:potions` | `:draw`, `:stop`, `:use_flask` | Drawing chips. Red moves extra spaces automatically. |
| `:yellow_choice` | `:return_white`, `:keep` | A yellow chip was drawn directly after a white chip. |
| `:blue_choice` | `{:place, chip}`, `:return_all` | A blue chip drew extra chips (the blue offer). |
| `:explosion_choice` | `{:explosion_choice, :vp \| :buy}` | White sum reached 8. |
| `:done` | none | Stopped, or the explosion choice is made; waiting for the other players (`done?` is true). |
