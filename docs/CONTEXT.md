# Quacks glossary

Terms used in code, tests and docs. Source: `docs/research/rulebook.md`.

| Term | Meaning |
|---|---|
| **chip** | An ingredient token. Has a **colour** (white, orange, green, blue, red, yellow, purple, black; with The Herb Witches also locoweed) and a **value** (1, 2, 3 or 4; the orange 6-chip has 6). White is the only colour that counts toward an explosion. |
| **expansion** | `Game.new(expansion: :herb_witches)` turns on The Herb Witches (`game.expansion`, default `nil`; source `docs/research/herb-witches.md`): the **herb witches** and **witch pennies**, 1-5 players, the expansion chips in the supply (`Chips.supply(:herb_witches)`, ⚠️ rulebook total 153), and orange Set 2 + locoweed Set 5 as defaults. Sets 5 and 6, the black and locoweed books, the orange 6-chip and the **overflow bowl** are in every game (see **sets**, **house rules**). The first log entry is `{:expansion, :herb_witches}`. `Session.new/3` and `GameServer.start/5` take it too, and the configure screen has a "Herb Witches expansion" toggle. |
| **herb witch** | The Herb Witches: 12 cards (`Quacks.Rules.Witches`, ids `:s1`–`:s4`, `:c1`–`:c4`, `:g1`–`:g4`), 4 per penny colour. `Game.new/1` turns up one of each colour from a jump of the seed (`game.witches`, e.g. `%{silver: :s2, copper: :c4, gold: :g4}`); all players share them. A player calls a witch by spending her colour's penny, once per game: `{:witch, colour}`, or `{:witch, colour, choice}` when the card needs a choice. Silver: while brewing (S2, S3) or in the explosion choice (S1, S4). Copper: in the seat's `:shop` sub-phase before it buys (C2, C4 also in round 9). Gold: G1–G3 in the game phase `:witch_choice` after step B (every seat she helps at the same time; `:witch_done` passes), G4 in the `:shop` sub-phase before round 9. Rules in `Quacks.Game.Witches`; see **Witch actions** below. |
| **witch penny** | `Quacks.Player.pennies`, `%{silver: true, copper: true, gold: true}` at the start (empty in the base game). Spent (`false`) when that colour's witch is called. Each unused penny is 2 VP at the end of the game (`{:pennies, vp}`). |
| **locoweed** | The expansion's new colour, `{:locoweed, 1}` (no printed value; the engine uses 1 for every value lookup). Set 5: moves rat stone distance + 1, at most 4 (solo: 1). Set 6: moves and acts on draw as the last coloured chip in the pot (white and locoweed skipped; none: moves 1, no action); ⚠️ it keeps colour locoweed for every count, and step-B actions are not copied. In the shop from round 1 (⚠️). |
| **overflow bowl** | `Quacks.Player.bowl` (house rule `overflow`, default on in every game; `false` keeps every chip on the last space): once a chip sits on the last space (53), every further chip goes in the bowl (`{:overflow, chip}`), newest first. Bowl chips have no action and are not in the pot (not "last" for green/black), but whites count toward the explosion. The flask takes back a white from the bowl. A blue Set 1 or Y2 chip on the last space loses its action for the next chip. Step D: half the bowl's values, rounded down, as VP (`{:bowl, chips, vp}`; ⚠️ not for an exploded player who chose to buy). Every non-exploded player on the spoon rolls the bonus die (they tie on the highest space). |
| **seat** | A player's place at the table, `0..3` in turn order (`0..4` with 5 players, The Herb Witches only). `Quacks.Game.seats` lists them; `players` maps each seat to a `Quacks.Player`. Every player-facing function takes the seat (`legal_actions(game, seat)`, `apply(game, seat, action)`); the 2-arity `apply/2` and 1-arity `legal_actions/1` mean seat 0. |
| **player** | `Quacks.Player`: one seat's bag, pot (`drawn`, `pot_index`), blue offer (`pending`), droplet, flask, rubies, coins, VP, explosion state, rat stone and own potions-phase `phase` / `done?`. |
| **start seat** | The seat that starts the round: `rem(round - 1, players)`, so it rotates one seat per round (`Quacks.Game.start_seat/1`). The evaluation and the round-9 stir steps resolve round the table from here. |
| **concurrent choice** | `:fortune_choice`, `:chip_choice` and `:witch_choice`: every seat with a choice answers at the same time, in any order; its player `phase` is the choice phase until it answers (then back to `:potions` before brewing, `:done` after). The game phase ends when nobody is left. Results touch only the seat's own state; with `supply: :limited` the first to take a chip gets it, and a seat whose options ran out is through. There is no `turn` any more. |
| **soft stop** | `:stop` does not end brewing at once: the player phase becomes `:stopped` (log `{seat, :stopped}`). While another player still brews (player phase `:potions`, `:yellow_choice`, `:blue_choice` or `:chip_choice`), the stopped player's only action is `:resume` (back to `:potions`, log `{seat, :resumed}`); not in round 9 (see **stir**). Once every player is `:stopped` or `:done`, the stops become final in start-seat order (B1, B7 and red chips beside the pot act now) and the evaluation runs. An exploded player cannot resume. Solo: `:stop` evaluates at once, without `:stopped` in the log. On the game page the Stop button becomes "Resume" while stopped, and the player sees "Waiting for N players: names". |
| **stir** | Round 9 "Stir!" with 2+ players (rulebook §3 step 5): all draw together. A brewing seat picks `:draw` or `:stop` for the step; it then waits in player phase `:waiting_stir` (no actions, the pick in `Quacks.Player.pending_choice`). Once every seat still brewing has picked and nobody is in an on-draw choice (yellow, blue, Y6 chip choice, explosion, ...), the picks resolve in seat order from the start seat on the shared rng: draws are placed, stops become `:stopped` (final, no `:resume`), exploded players drop out. On-draw choices are made right after their draw, before the next step. Solo round 9 is a normal round. |
| **shopping** | Game phase `:shopping` (rulebook steps 4e and 4f): every seat at the same time, in one step (player `phase` `:shop`): `{:buy, chips}` at most once (`Quacks.Player.bought?`; `{:buy, []}` = buy nothing), `{:rubies, :droplet \| :flask}` as often as the rubies allow, copper witches (before the buy), gold G4, and `:end_round` ("Done") are all legal together; `:end_round` makes the seat `:ready`, and the last seat's ends the round. An exploded player who took the VP has no buy (unless copper C4 gave them coins). Round 9: no buy, no droplet or flask; `{:rubies, :vp}` turns 2 rubies into 1 VP, and at the seat's `:end_round` its coins (5 → 1 VP) and leftover rubies (2 → 1 VP) convert by themselves (`{:final_conversion, coins, coins_vp, rubies, rubies_vp}`). |
| **bag** | A player's hidden pool of chips. Chips are drawn from it blind. Starting bag: 4x white 1, 2x white 2, 1x white 3, 1x orange 1, 1x green 1. |
| **pot** | The cauldron track: 54 spaces (index 0-53). Each space has a coin number, some have VP and a ruby. Drawn chips are placed on it; a chip lands `value` spaces after the previous chip. Every player has their own pot. |
| **drawn** | The chips in a player's pot this round, as `{chip, index}` pairs, newest first (`Quacks.Player.drawn`). `index` is the 0-53 space the chip sits on, recorded when it is placed. The UI draws chips from these positions; a returned white chip (mandrake) leaves its space empty and later chips keep their index. `Quacks.Game.pot_chips/2` strips the positions. |
| **droplet** | The marker for a player's permanent start position on the pot. The first chip of a round is placed relative to it (or to the rat stone). Moves forward with 2 rubies or chip actions; never moves back. |
| **rat tails** | Marks between some spaces of the 0-50 VP track: after VP 1, 3 and every even VP from 6 to 50 (⚠️ reconstructed, rulebook §1.2). `Quacks.Rules.ScoringTrack.rat_tails(my_vp, leader_vp)` counts the tails strictly between two markers. |
| **rat stone** | From round 2 with 2+ players: every player behind the leader (highest VP; a tie for the lead gives nobody rats) starts the round `rat_tails` spaces past their droplet. `Quacks.Player.rat_stone` holds that distance (0 when none); it is set when a round starts and cleared when it ends. The flask falls back to droplet + rat stone when the pot is empty. |
| **flask** | One-shot per round: put the last drawn white chip back in the bag. Not usable if that chip caused the explosion. Refill for 2 rubies in the end-of-round phase. |
| **explosion** | When the sum of white chip values in the pot reaches 8 or more (the house rule `explode_above` changes the base limit; it can rise: B5 card, Y3 mandrake; see **mods**). The exploding chip stays; the player must stop drawing and must choose VP **or** buying chips, not both. The choice waits on `Quacks.Player.explosion_choice` until the evaluation runs; a player who chose VP skips the shop. |
| **scoring space** | The space directly after the last placed chip. Gives coins, VP and possibly a ruby. |
| **ruby** | Currency for droplet moves and flask refills; 2 rubies = 1 VP in the last round. |
| **round** | One of 9 game turns. Each round runs the phases below. |
| **ingredient book** | The rule card for a colour's chip action and prices. Green, blue, red, yellow and purple each have Sets 1-4; orange and black have one book; white has none. The Herb Witches adds Sets 5 and 6 for green, blue, red, yellow, purple and black, and locoweed (Sets 5 and 6 only). |
| **sets** | `Game.new(sets: %{green: 1..4, blue: 1..4, red: 1..4, yellow: 1..4, purple: 1..4})` picks the book per colour; colours left out use Set 1 (`game.sets`). Prices differ per set: `Quacks.Rules.Chips.price(chip, sets)` (`price/1` = Set 1). Effects dispatch on `{colour, set}` (`Potions.bonus/3`, `Potions.on_draw/4`, `Evaluation.chip_action/3`). All 20 books are supported; G2, G4, P2 and P4 open a **chip choice**, R2 uses **beside the pot**. `Quacks.Session.new/3`, `Session.replay/4` and `Quacks.GameServer.start/4` take the same `sets`; the lobby's "Ingredient books" form picks them, and the shop shows the books and their prices. In every game `sets` takes 1..6 per colour, `black:` 1 (the base book, default), 5 or 6, `orange:` 1 or 2 (Set 2 adds the orange 6-chip at 22 coins) and `locoweed:` `nil` (not in play), 5 or 6; the defaults are orange 1 and no locoweed, with the expansion orange 2 and locoweed 5 (`Chips.set/3`). The chosen book chips go in the shop and the supply (expansion counts). All Set 5/6 books are supported. G5 and P5 open a **chip choice** in step B; R6 sets a chip **beside the pot**; Y6 offers a chip choice on draw (player phase `:chip_choice`). Source: `docs/research/ingredient-sets-and-customisation.md`. |
| **book text** | `Quacks.Rules.Books.get({colour, set})`: the book's official name, a one- or two-sentence text, its `trigger` (`:on_draw`, `:step_b`, `:passive`, `:none`) and prices. `Books.in_play(expansion, sets)` lists a game's books. The configure screen shows the chosen book under each select; the shop has an ⓘ per row and the menu a "Books" sheet. |
| **mods** | `Quacks.Player.mods`, round modifiers from Set 2-4 chips, reset at the end of the round (and by B3): `explode_above` (0 = not raised; Y3: 8 after the 1st yellow, 9 after the 3rd; the limit is the highest of the house rule `explode_above`, this and the B5 card's 9: `Potions.explode_above/2`), `next_chip_x2` (Y2), `white1_plus1` (R4), `protect` (B2: drawn chips left in the crow-skull window). |
| **chip choice** | Step B of the evaluation with G2, G4, G5, P2, P4 or P5: `Quacks.Player.chip_choices` lists what the player may still choose; in the game phase `:chip_choice` every seat with a choice answers at the same time (see **concurrent choice**). It runs after the bonus die and the automatic chip actions, before rubies and VP (steps C/D). Set 1 purple still takes the highest tier automatically. |
| **beside the pot** | Red Set 2: `Quacks.Player.aside`, red chips drawn but not placed. They are not in the bag and stay there across rounds. After stopping (or the explosion choice) the player decides each one in `:red_choice`; the evaluation waits for every player. A placed red moves only its value. Red Set 6: a drawn red puts one more chip from the bag in `aside`. While brewing the player may place it any time with `{:red, {:place, chip}}` (a normal draw, with its action); after stopping or exploding it must be placed (only `:place` in `:red_choice`): it moves its value, no action (⚠️), and a white one can still explode the pot. |
| **starter chips** | Green Set 5: `Quacks.Player.starters`, pot chips chosen in step B (`{:chip, {:starter, chip}}`, worth at most the green) to be the first chips of the next round. `:draw` takes them out of the bag first, in the order chosen (⚠️ "any order" = the order of choosing), with their actions. A starter no longer in the bag is skipped. |
| **supply** | The chips in the box per colour and value (`Quacks.Rules.Chips.supply/0`, `game.supply`), shared by all players. House rule `supply`: `:infinite` (default) never runs out and `game.supply` is never counted down (it stays the box); `:limited` counts down: every starting bag, bought chips, the orange die face and the round-6 white chips come out of it, and a kind with 0 left is not buyable. `Game.in_supply?/3`, `take_supply/2` and `return_supply/2` hide the difference. Yellow is buyable from round 2, purple from round 3. |
| **blue offer** | The extra chips a blue chip draws (`pending` on the player). The player places at most one as the next chip; the rest go back in the bag. |
| **black rule** | Rulebook §4. 2 players: as many black chips as the opponent (and at least 1) → droplet +1; more → droplet +1 and 1 ruby. 3-4 players: more than one neighbour (adjacent seat) → droplet +1; more than both → droplet +1 and 1 ruby. ⚠️ 5 players use the 3-4 side. Black Set 5: a black chip bought (or taken from a card) goes into the bag of the player on the left (the next seat; solo: back to the supply) and the buyer's droplet moves 1; step B: 1 ruby per black chip in the left pot and per black on my last two positions. Black Set 6: the owner(s) of the furthest black chip at the table move the droplet 1, of the second furthest take 1 ruby (⚠️ ranked by distinct space; a tie shares the bonus); solo ranks your own chips. |
| **fortune card** | A Fortune Teller card (rulebook §5, ⚠️ fan transcription). `Quacks.Rules.Fortune` holds the 24 cards (`:b1`–`:b11` blue, `:p1`–`:p13` purple); `Quacks.Game.Fortune` holds their rules. `Game.new(rules: %{fortune: false})` plays without cards (default `true`; `fortune: false` at the top level is an old alias). The deck (`fortune_deck`, ids) is shuffled at `new/1` from a jump of the game's `rng`, so a seed draws the same chips with or without cards. Solo decks leave out P4, P5, P8 and B2; solo skips P7 and P9 when they come up. `fortune_card` is the card of the current round. |
| **purple card** | Resolved once at the start of the round, after the rats: an automatic part for every seat, then `:fortune_choice` for every seat with a choice at the same time (see **concurrent choice**). |
| **blue card** | A rule for the whole round: explosion limit 9 (B5), orange +1 space (B6), first white back (B10), exactly 7 white on stop → droplet (B1), bonus die rolled twice with both rewards (B4), free flask refill after the evaluation (B9), ruby scoring space → 2 VP (B8) or +1 ruby (B11), restart once after the 5th chip (B3), a 5-chip offer on stop (B7), a 2-value chip for the player left of an exploded pot after the potions phase (B2). |
| **black house rule** | ⚠️ Solo has no opponent to compare black chips with. The engine treats 1+ black chip in the pot as "tied with the opponent": droplet +1, no ruby. Rulebook §6.2 suggests droplet +1 and 1 ruby instead; that is the house rule `black_solo: :droplet_ruby`. |
| **house rules** | `Game.new(rules: %{...})`, merged over `Quacks.Game.default_rules/0` (the rulebook game) and kept in `game.rules`: `explode_above` (5..9, default 7), `round6_white` (the white 1-chip before round 6), `fortune` (Fortune Teller cards), `rats` (rat stones, 2+ players), `black_solo` (`:droplet` or `:droplet_ruby`), `die` (`:standard`, or `:no_orange`: the orange face is a second ruby face, ⚠️ unofficial), `starting_rubies` (0..3, default 1), `supply` (`:infinite` default, or `:limited`; see **supply**; the lobby's "Chip supply" option), `overflow` (`true` default: the **overflow bowl**; `false`: chips past the last space stay on it). Unknown rules or bad values raise `ArgumentError`. `Quacks.Session` and `Quacks.GameServer.start/4` pass them on, separate from `sets`. The lobby's "Options" block picks them; the game page lists the non-default ones as "House rules". Source: `docs/research/ingredient-sets-and-customisation.md` Part 2b. |
| **game id** | 6 lowercase letters naming one running game, as in `/g/:id`. `Quacks.GameServer` registers each game process under its id in `Quacks.GameRegistry`. |
| **waiting game** | `GameServer` status `:waiting`, the pre-game lobby: `start/5` opens it with no `Quacks.Game` (`table.game` is `nil`); `claim_seat/2` gives the lowest free seat up to the configured count (`max_players`); `leave_seat/2` frees one (the game page calls it when it closes before the start); `begin/2` (the creator, or any seated browser once the creator left) creates the game with the seats taken, renumbered `0..n-1`, and makes it `:playing`. A solo game begins as soon as its seat is taken. `configure(id, token, %{players:, sets:, rules:, expansion:})` lets the creator (host) change the settings while waiting (any keys; bad values, or fewer players than seated, give `{:error, :invalid}`); waiting pages hear `{:names, id, names}` and re-read the table, which also shows `sets`, `rules` and `expansion`. After game over, `play_again(id, token)` (any seated browser) opens a new waiting game with the same settings, seated tokens, names and host and a new seed, returns `{:ok, new_id}` (the same id when asked again) and broadcasts `{:play_again, id, new_id}`; a solo one begins at once. The lobby lists waiting games with a free seat. The game page shows it as the **waiting room**: one slot per seat (name or "empty"), the share link (a read-only field) and "Start game" for whoever may begin. The game page of a waiting game is the **configure screen**: the lobby's "New game" opens a 2-player waiting game, and the host sets the count, books and options there (`GameServer.configure/3`); the others see them read-only. The host's browser keeps the last settings (localStorage) and applies them to a fresh configure screen. |
| **player token** | A random value in the browser's session cookie (`QuacksWeb.Plugs.PlayerToken`). It stands in for an account: a `GameServer` maps token → seat on the first `claim_seat`. Seats fill lowest-free first; the creator (first token seated) is seat 0. Shown to people as "Seat N" with N = seat + 1, or a nickname. |
| **spectator** | A browser with no seat: the waiting game was full, or the game had begun. It sees every pot and no buttons. |

## Log (`Quacks.Game.log`)

Newest first. Every entry that concerns one player is tagged with the seat: `{seat, entry}`, e.g. `{0, {:drew, {:white, 2}, 5}}`. Applied actions are logged (tagged) and followed by the events they caused. The only untagged entry is `{:round_end, round}`.

| Entry | When |
|---|---|
| `{:drew, chip, index}` | Every placement, including a chip placed through a blue chip. |
| `{:overflow, chip}` | House rule `overflow`: the chip went in the overflow bowl, not the pot. |
| `{:bowl, chips, vp}` | Step D, house rule `overflow`: the bowl's chips (newest first) gave `vp` (half their values, rounded down). |
| `{:returned, chip}` | A chip went back in the bag: flask, mandrake, or the rest of a blue offer. |
| `{:exploded, white_sum}` | The white sum passed 7. |
| `:stopped` | After `:stop` with 2+ players: the player waits and may still resume. |
| `:resumed` | After `:resume`: the player brews again. |
| `{:bought, chips}` | A purchase of one or two chips (`{:buy, []}` logs only the action). |
| `{:rubies_spent, :droplet \| :flask \| :vp}` | Two rubies spent in the shop (`:vp`: round 9, 1 VP). |
| `{:bonus_die, face}` | A die roll in the evaluation; only the seat(s) on the highest scoring space roll. |
| `{:black, :droplet}` | Step B: black paid the droplet only (solo house rule, 2p tie, 3-4p more than one neighbour). |
| `{:black, :droplet_ruby}` | Step B: black paid droplet and ruby (2p more than the opponent, 3-4p more than both neighbours). |
| `{:green_rubies, n}` | Step B: `n` green chips in the last two positions, `n` > 0. |
| `{:purple, tier, payoff}` | Step B, only with 1+ purple: `{:purple, 1, :vp1}`, `{:purple, 2, :vp1_ruby}` or `{:purple, 3, :vp2_droplet}` (3+ purple). |
| `{:pot_ruby, index}` | Step C: the scoring space `index` gave a ruby. |
| `{:pot_vp, vp, index}` | Step D: `vp` > 0 taken from scoring space `index`. Not logged when an exploded player chose to buy. |
| `{:final_conversion, coins, coins_vp, rubies, rubies_vp}` | Round 9, at the seat's `:end_round`: its `coins` gave `coins_vp` (5 each) and its leftover `rubies` gave `rubies_vp` (2 each). |
| `{:pennies, vp}` | Round 9, The Herb Witches: 2 VP per unused witch penny (not logged at 0). |
| `{:witch, id, outcome}` | What herb witch `id` did for this player (see **Witch actions**). |
| `{:rubies_spent, :droplet \| :flask, 1}` | Like `{:rubies_spent, what}`, for 1 ruby (gold witch G4). |
| `{:rats, tails}` | A new round started with this player `tails` spaces ahead on the rat stone. |
| `{:fortune_drawn, id}` | Untagged. A Fortune Teller card was turned up at the start of the round. |
| `{:fortune_skipped, id}` | Untagged. Solo only: P7 or P9 came up and was put aside. |
| `{:fortune, id, outcome}` | What card `id` did for this player (see the table below). |
| `{:effect, {colour, set}, detail}` | A Set 2-6 chip effect (see the table below). |
| `{:round_end, round}` | The last event of every round. Untagged. |
| `{:expansion, :herb_witches}` | Untagged. The first entry of an expansion game. |

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
| R5 | `{:extra, n}` | A higher red was already in the pot: the red moved `n` more (as that red's value). |
| Y5 | `{:peek, chip}` | One more chip was drawn; the yellow moved on by its value (locoweed 1), the chip went back. ⚠️ Read as own value + the peeked value. |
| B5 | `{:vp, n}` | At least `n` (the blue's value) orange chips in the pot: `n` VP. |
| B6 | `{:rubies, n}` | `n` white 1-chips among the `value` chips before the blue. |
| G6 | `{:bonus_die, face}` | Step B: one bonus die roll per green on the last two positions (B4: twice each). |
| P6 | `{:vp, n}` | Step B: per purple, the printed value of the chip right after it (locoweed 1; ⚠️ a purple as the last chip gives 0). |
| Black 5 | `{:to_left, seat}`, `:to_supply` | A bought or card black chip went to the left seat's bag (solo: the supply); droplet +1. |
| Black 5 | `{:rubies, n}` | Step B: `n` black chips in the left pot plus on my last two positions. |
| Black 6 | `:droplet`, `:ruby`, `:droplet_ruby` | Step B: furthest black chip (droplet), second furthest (ruby). |
| Locoweed 5 | `{:moves, n}` | The locoweed moved `n` (rat stone + 1, max 4). |
| Locoweed 6 | `{:copied, chip}` | The locoweed moved and acted as `chip`. |
| G5 | `{:starter, chip}` | Chip choice: `chip` will be a first chip of the next round. |
| G5 | `{:first, chip}` | A starter chip was drawn (after its `{:drew, ...}`). |
| R6 | `{:aside, chip}` | A red drew `chip` and set it aside. |
| Y6 | `{:extra, 3}` | Paid 1 ruby: the yellow moved 3 more. |
| P5 | `{:bought, chips}` | Chip choice: the purple spaces' VP bought `chips` (into the bag; black Set 5 still sends black left). |
| P5 | `{:vp, n}` | Round 9: the purple spaces' VP, 5 for 1. |

`Quacks.Session` replays from its own `actions` list (`[{seat, action}]`, newest first), never from the log.

## Round phases (in order)

| Phase | Name | What happens |
|---|---|---|
| 1 | `:fortune_teller` | Turn up the next Fortune Teller card (`{:fortune_drawn, id}`). A purple card resolves after the rats, before the potions phase. |
| 2 | `:rats` | From round 2 with 2+ players (unless `rats: false`): every player behind the leader places the rat stone `rat_tails` spaces past the droplet (solo: none). Runs inside the previous round's last `:end_round`. |
| 3 | `:potions` | Every player draws chips from their bag one at a time, places them on their pot, stops or explodes. Blue, red, yellow act on draw. Players act simultaneously, in any order; a stop is soft until nobody brews (see **soft stop**). |
| 4a | `:bonus_die` | Among the non-exploded players, the one(s) on the highest scoring space roll the bonus die. |
| 4b | `:chip_actions` | Resolve black, green, purple chips in every pot, start seat first. |
| 4c | `:rubies` | Each player takes a ruby if their scoring space shows one. |
| 4d | `:victory_points` | Each player takes the VP of their scoring space (not an exploded player who chose to buy). |
| 4e–4f | `:shopping` / `:shop` | Every seat at once, in one step: spend the coins of the scoring space on 1 or 2 chips (2 must differ in colour; an exploded player who chose VP buys nothing), spend rubies (droplet forward, refill flask), in any order, then `:end_round` (sub-phase `:ready`). After the last seat's `:end_round` all chips go back in the bags; before round 6 every player adds 1 white 1-chip (unless `round6_white: false`). Round 9: nobody buys; 2 rubies buy 1 VP; coins and leftover rubies become VP at `:end_round`. |

## Engine phases

Steps with no player choice run inside `apply/3`. The game has a coarse `phase`; during `:potions` and `:shopping` each player also has their own `phase`, and `Quacks.Game.phase(game, seat)` returns the one that seat sees.

| Game phase | Who acts | Actions | When |
|---|---|---|---|
| `:fortune_choice` | every seat in player phase `:fortune_choice` | `{:fortune, choice}` | A purple card's choice, all seats with one at once, before `:potions`; or B2's chip after `:potions`, before the evaluation. |
| `:chip_choice` | every seat in player phase `:chip_choice` | `{:chip, choice}`, `:chip_done` | Evaluation step B with G2, G4, G5, P2, P4 or P5, all seats with a choice at once (see **Chip choices** below). A seat is also through when nothing is left to choose. |
| `:witch_choice` | every seat in player phase `:witch_choice` | `{:witch, :gold}`, `:witch_done` | The Herb Witches: after the chip choices, before steps C/D, every seat whose unspent gold witch G1–G3 would give something now, at once. |
| `:potions` | every seat whose player is not `:done` or `:waiting_stir` (a `:stopped` one only while another brews, never in round 9) | see player phases | Drawing chips (round 9: **stir**). Once nobody brews and the last player is done, the evaluation (4a-4d) runs and the game moves on. |
| `:shopping` | every seat not `:ready` | see the sub-phases below | Steps 4e and 4f, all seats at once, one step each. The last `:end_round` ends the round. |
| `:over` | nobody | none | After round 9. |

| Player phase (`Quacks.Player.phase`) | Actions | When |
|---|---|---|
| `:potions` | `:draw`, `:stop`, `:use_flask`; with B3 `{:fortune, :restart_round}`, with B10 `{:fortune, :return_white}`; R6 `{:red, {:place, chip}}`; silver witch S2/S3 | Drawing chips. Red moves extra spaces automatically. While the silver witch S2's offer (`witch_offer`) is out, only `{:witch, :silver, {:place, chip}}` and `{:witch, :silver, :return_all}`. |
| `:chip_choice` | `{:chip, :yellow_ruby}`, `:chip_done` | Yellow Set 6 was drawn and the player has a ruby. |
| `:fortune_choice` | `{:fortune, {:place, chip}}`, `{:fortune, :return_all}` | B7: the player stopped and drew up to 5 chips (`pending`). A placed chip moves its printed value, has no action and cannot explode the pot (see **Rule changes**); then the player is done. |
| `:yellow_choice` | `:return_white`, `:keep` | A yellow chip was drawn directly after a white chip. |
| `:blue_choice` | `{:place, chip}`, `:return_all` | A blue chip drew extra chips (the blue offer). |
| `:explosion_choice` | `{:explosion_choice, :vp \| :buy}`; silver witch S1/S4 | White sum reached 8. |
| `:red_choice` | `{:red, {:place \| :keep \| :return, chip}}` | Red Set 2: the player stopped (or made the explosion choice) with chips beside the pot (now in `pending`). One action per chip; then `:done`. |
| `:stopped` | `:resume` (only while another player brews; never in round 9) | Soft stop; see **soft stop**. |
| `:waiting_stir` | none | Round 9: picked `:draw` or `:stop` (`pending_choice`); waits for the other brewing seats (see **stir**). |
| `:done` | none | The stop is final, or the explosion choice is made; waiting for the other players (`done?` is true). |

| Shopping sub-phase (`Quacks.Player.phase`) | Actions | When |
|---|---|---|
| `:shop` | `{:buy, [chip]}` (once, not in round 9; C3's free copy is the buy), `{:rubies, :droplet \| :flask}` (round 9: `{:rubies, :vp}`), copper witch actions (before the buy; round 9 C2, C4), gold G4 (not round 9), `:end_round` (`{:rubies, :skip}` is an alias) | Steps 4e and 4f in one step, any order. |
| `:ready` | none | Waiting for the other seats to end the round. |

## Fortune choices (`{:fortune, choice}`)

| Choice | Cards |
|---|---|
| `{:take, chip}` | P1 (black 1 or a 2-value chip), P3 (a 1-value chip, not purple, black or locoweed ⚠️; costs 1 ruby), P10 (a 4-value chip), P11 (purple 1, from round 3), B2 (a 2-value chip). Only chips in the shop this round and in the supply. With black Set 5 a black chip goes to the left player (see **black rule**). |
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
| `{:starter, chip}` | G5, once per green chip on the last two positions: a pot chip worth at most that green (locoweed 1) becomes a first chip of the next round. |
| `{:buy, chips}` | P5: one purchase (1 chip, or 2 of different colours) paid with the VP of the spaces holding a purple chip. Never added to the coins. |
| `:yellow_ruby` | Y6, on draw (player phase `:chip_choice`): 1 ruby, the yellow moves 3 more. |
| `:chip_done` | End this seat's choices; whatever is left is skipped. |

## Witch actions

| Witch | Action | When | Outcome logged |
|---|---|---|---|
| S1 flask after explosion | `{:witch, :silver}` | Explosion choice, flask full | `:flask`: the last white back, flask used, brewing again. |
| S2 draw 6 | `{:witch, :silver}`, then `{:witch, :silver, {:place, chip}}` / `{:witch, :silver, :return_all}` | Brewing | `{:offer, n}`. Placed chips act as normal draws; an explosion returns the rest. |
| S3 whites back | `{:witch, :silver, 1 \| 2}` | Brewing, 1+ white in the pot | `{:return_white, n}`: the newest `n` whites back; gaps stay (⚠️ 1 = the newest; bowl whites not counted). |
| S4 no penalty | `{:witch, :silver}` | Explosion choice | `:no_penalty`: `explosion_choice: :witch`, VP and coins, bonus die if on the best space. |
| C1 upgrade | `{:witch, :copper, {:upgrade, chips}}` | Shop | `{:upgrade, chips}`: 1 pot chip, or the last 2, one level up (green/blue/red/yellow 1 → 2, 2 → 4) into the bag; the old chip to the supply. |
| C2 double coins | `{:witch, :copper}` | Shop before the buy (and round 9) | `{:coins, total}`. |
| C3 free copy | `{:witch, :copper, {:buy, chips, copy}}` | Shop | `{:copy, chip}` after `{:bought, chips}`; it is the seat's buy. Only while the supply has the copy (⚠️). |
| C4 rubies to coins | `{:witch, :copper}` | Shop before the buy (and round 9) | `{:coins, added}` (2 per ruby). |
| G1 colours | `{:witch, :gold}` | `:witch_choice` | `{:vp, n}`: 1–4 colours 3, 5 → 4, 6 → 7, 7 → 10, 8 → 14 (⚠️ not after an explosion with "buy"). |
| G2 bag | `{:witch, :gold}` | `:witch_choice` | `{:vp, n}`: 2 per coloured 2/4/6-chip, purple and locoweed in the bag. |
| G3 rubies | `{:witch, :gold}` | `:witch_choice`, ruby scoring space worth 2+ VP | `{:rubies, n}`: `n` = VP - 1, so with step C's ruby it is VP rubies (⚠️ with B11 both count). |
| G4 cheap rubies | `{:witch, :gold}` | Shop, rounds 1–8 | `:ruby_price`: droplet and flask cost 1 ruby for the rest of the round (`Player.ruby_price`). |

## Rule changes

| Date | Change |
|---|---|
| 2026-10-03 | **Round 9 stir, concurrent choices, one-step shop, overflow and black book everywhere, play again** (from the second 2-player game). Round 9 draws in lockstep (**stir**, `:waiting_stir`, no `:resume`). `:fortune_choice`, `:chip_choice` and `:witch_choice` are concurrent; `Game.turn` is gone. The shop is one sub-phase `:shop` (buy once, rubies, "Done"); round 9 offers `{:rubies, :vp}` and logs `{:final_conversion, coins, coins_vp, rubies, rubies_vp}`. House rule `overflow` (default on) replaces the expansion-only bowl. Sets 5–6, black 1/5/6, orange 2 and locoweed in every game. `GameServer.configure/3` and `play_again/2`. |
| 2026-10-03 | **Soft stop, simultaneous shopping, infinite supply, waiting lobby** (from the first real 2-player game). `:stop` is soft (`:stopped`, `:resume`); `:buy_chips` and `:spend_rubies` are replaced by one concurrent `:shopping` phase with per-seat sub-phases `:buy` → `:rubies` → `:ready` (`turn` is `nil`); the house rule `supply` defaults to `:infinite`; `GameServer` waits for players (`:waiting`, `begin/2`, `leave_seat/2`). |
| 2026-10-03 | **Fortune card draws cannot explode the pot** (official ruling in The Herb Witches rulebook, applied to the base game too). B7 Safety Procedure: the placed chip moves its printed value, has no action (no red/Y2 bonus either, ⚠️) and cannot explode the pot. B3 Second Chances: the round's first 5 draws, before the player may start again, cannot explode the pot (⚠️ "the draws the card asks for" read as these 5). The pot can then be over the limit without exploding; the next normal draw explodes it. `Fortune.safe_draw?/2`. |
