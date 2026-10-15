# No Thanks! glossary

Terms used in code, tests and docs. Source: `docs/games/no_thanks/rulebook.md` (§ numbers refer to it). Namespace proposal: `NoThanks.*` (engine `NoThanks.Game`, rules data `NoThanks.Rules`).

| Term | Meaning |
|---|---|
| **card** | A number card, an integer `3..35`. There are 33, one of each value (§1). In code a card is just its value (`integer`). There is no struct. |
| **deck** | All 33 cards (`NoThanks.Rules.cards/0` = `Enum.to_list(3..35)`). |
| **removed** | The 9 cards put back in the box unseen at setup (§2.2), `game.removed` (a list). They are out of the game, never shown by `view/2`, not even at game end. Do not call them "discards". |
| **pile** | The face-down draw pile: 24 cards at setup, minus the first offer (§2.2). `game.pile` is a list and the head is the next card. Views only show `length(pile)`. |
| **offer** | The face-up card being decided on, plus the **pot**. `game.offer` is `integer \| nil`. It is `nil` only once the game is `:over`. "Current card" in prose. |
| **pot** | The chips on the offer, `game.pot` (non-negative integer). It is public. The players who pass grow it. The player who takes empties it. (Same word as Quacks' pot, different meaning. Always qualify it in shared code.) |
| **chip** | A counter (the official English word is "counter", §1). Chips are identical and have no value apart from the −1 point each at scoring. `Player.chips` is an integer. Do not call them "token" or "coin" in code. |
| **starting chips** | Chips per player by player count: 11 for 3–5 players, 9 for 6, 7 for 7 (§2.1). This lives in `NoThanks.Rules.starting_chips/1`. |
| **seat** | A player position, `0..n-1`. Clockwise order is ascending seat numbers, wrapping round. |
| **active seat** | `game.active`: the seat that must act on the offer. |
| **pass** | Action `:pass` ("No thanks!"). Move 1 chip from the active seat to the pot. Then the active seat becomes the next seat (§3.1). Only legal with `chips ≥ 1` (§3.2). |
| **take** | Action `:take`. The active seat adds the offer to its **cards** and the pot to its chips. If the pile is not empty, flip the next card (a new offer with an empty pot), and **the same seat** stays active (§3.3). Otherwise the game is over (§4). Always legal while the game is running. |
| **forced take** | A take by a seat with 0 chips, its only legal action (§3.2). This is a description, not a separate action. |
| **flip** | Turning the pile's head into the new offer. This happens internally after a take, and once at setup. The log entry is `{:flip, card}`. |
| **hand** / **cards** | The cards a seat has taken, `Player.cards`. Store them as a sorted list. They are public (§7.8). Avoid "hand" in code, because in the rules the chips are held "in hand". |
| **run** | A maximal set of consecutive values in one seat's cards (§5), for example `[7, 8, 9]`. A lone card is a run of length 1. `NoThanks.Score.runs/1` turns a card list into a list of runs. |
| **card points** | The sum of the lowest card in each run (§5). |
| **score** | `card points − chips` (§5). Lower is better. It can be negative. |
| **winners** | Every seat with the lowest score. Ties share the win (§6), so this is always a list. |
| **phase** | `game.phase`: `:playing` or `:over`. There are no rounds. |
| **chip visibility** | `game.options.chips_visible` (default `false`, §2.4). When `false`, `view/2` shows a seat its own chip count and `:hidden` for everyone else's. |
| **house rule** | Any rule that is not in the base game: `:two_player` (§8.1), `:tactical` (§8.3), visible chips (§8.2). It is set in `game.options` and listed in the log at the start. |
| **seed** | The `:rand` state (`:exsss`) in `game.rng`. It is used only at setup for shuffling and removal (and for the start seat if chosen randomly). The engine has no other randomness. |
