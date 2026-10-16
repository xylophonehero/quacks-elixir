# No Thanks! glossary

Terms for code, tests and docs. Source: `docs/games/no_thanks/rulebook.md` (§ numbers below). Names in `code` are proposals for the engine (issue #85, step 2); the engine can change them, and then this file changes too.

| Term | Meaning |
|---|---|
| **card** | One of 33 cards, numbers 3 to 35, each number one time (§1.1). A card is an integer in the engine. Its points equal its number (§1.3). |
| **chip** | A counter. All chips are equal (§1.2). A player's chips are an integer, `chips[seat]`. At the end each chip is −1 point (§5.4). The rulebook S1 says "counter"; we say "chip". |
| **removed cards** | The 9 cards put back in the box unseen at the set-up (§2.1). They never come into play and nobody sees them (§6.1). `game.removed`, zone `:hidden`. |
| **deck** | The 24 face-down cards that are left after the set-up (§2.2). Its order is hidden; its size is public (§6.2, §6.3). `game.deck`. |
| **offer** | The face-up card that the active seat must take or pay for (§3.1). `game.offer` (nil only when the game is over). |
| **pot** | The chips on the offer (§3.3, §6.5). Public. `game.pot`. Not the Quacks pot. |
| **take** | Action `:take`: the seat gets the offer and the pot (§3.4), then the next card becomes the offer and the same seat acts again (§3.5). Always legal (§3.8). |
| **no thanks** | Action `:no_thanks`: the seat puts 1 chip on the offer and the turn goes left (§3.3). Legal only with 1 or more chips (§3.6). |
| **seat** | A player's place, `0..n-1`, n = 3 to 7 (§2.4). Turn order goes up by one, mod n ("left", §2.6). |
| **active seat** | The seat that must act on the offer now. `game.active`. |
| **start seat** | The seat that acts first (§2.5). ⚠️ Seat 0 or from the seed: an open decision. |
| **tableau** | The cards in front of one seat, face up (§6.4). `tableau[seat]`, a sorted list. |
| **run** | Two or more cards with consecutive numbers in one tableau (§5.1). A run counts only its lowest card (§5.2). A card that is not in a run is a **single**. |
| **score** | Lowest card of each run + each single − chips (§5.5). Lower is better; it can be negative (§5.8). |
| **winner** | The seat or seats with the lowest score. A tie is a shared win; there is no tie-breaker (§5.7). |
| **chips in play** | 11 × n for 3-5 players, 9 × 6, 7 × 7 (§2.3). This total never changes (§7.1). |
| **over** | The game is over when the deck is empty and the last offer is taken (§4.1). |
| **show chips** | Proposed house rule `show_chips` (default off): `view/2` shows every seat's chip count (§6.6, §8.2). Off: each seat sees only its own count until the end (§6.8). |
| **tactical variant** | Proposed house rule (§8.1): 10 chips each, cards 10, 20 and 30 always removed, then 6 more at random. |
