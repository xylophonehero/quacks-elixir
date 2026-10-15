# Hearts glossary

Terms used in code, tests and docs for Hearts. Source: `docs/games/hearts/rulebook.md` (§ numbers below point there). Shared card terms (card, suit, rank, deck, deal) will move to a playing-cards glossary when a second card game lands (see `docs/games/card-family.md`).

| Term | Meaning |
|---|---|
| **card** | One of the 52 playing cards: a `{rank, suit}` tuple, `rank` an integer 2..14 (11 = J, 12 = Q, 13 = K, 14 = A), `suit` one of `:clubs`, `:diamonds`, `:spades`, `:hearts`. Written `2♣`, `Q♠`, `10♥` in docs; code uses the tuple (`{12, :spades}`); tests use a parse helper (`c("QS")`). Ace is high (§1). |
| **suit** | `:clubs`, `:diamonds`, `:spades`, `:hearts`. No suit outranks another; Hearts has **no trumps** (§1, §9). |
| **rank** | 2..14, A high. Compared only within the led suit (§9). |
| **deck** | The 52 cards (51 with 3 players, 50 with 5; §14.1, §14.2), shuffled with the game's RNG state (`:rand` `_s` API). |
| **seat** | A player position 0..n−1, clockwise. "Left" of seat `s` is `s + 1 mod n`. |
| **dealer** | The seat that deals this round; moves one seat left each round (§2). Has no rules role in 4-player Hearts. |
| **deal** | Shuffling the deck and giving every seat its cards (13 each with 4 players). Also used loosely for the event `{:deal, round}` in the log. |
| **hand** | The cards a seat currently holds (`game.hands[seat]`). ⚠️ Pagat and most books also say "hand" for one deal-play-score cycle; in our code that is a **round**, never "hand". |
| **round** | One cycle: deal, pass, 13 tricks, scoring (§3). `game.round` is 1-based and picks the pass direction. |
| **pass** | Before the first trick, every seat gives exactly 3 cards to another seat (§4). Action `{:pass, [c1, c2, c3]}`. All seats choose first, then the cards move at once; a seat's **passed cards** are hidden from the receiver until the exchange, and a seat's **received cards** are hidden from it until it has passed. |
| **pass direction** | `:left`, `:right`, `:across` or `:hold`, from `round` (1 left, 2 right, 3 across, 4 hold, then repeat; §4). |
| **hold** | A round with no pass (§4.4). Sometimes called "keeper" or "no-pass" round. |
| **trick** | One card from each seat, in clockwise order from the leader. `game.trick` is the list of `{seat, card}` played so far. |
| **first trick** | Trick 1 of a round. The 2♣ must be led (§5) and penalty cards may not be played unless there is nothing else (§7). |
| **lead** / **leader** | The first card of a trick / the seat that plays it. The 2♣ holder leads trick 1; the winner of a trick leads the next (§5, §8). |
| **led suit** | The suit of the lead card. Decides who must follow and who wins. |
| **follow (suit)** | Play a card of the led suit. Compulsory when able (§6). |
| **void** | Holding no card of a suit. A seat void in the led suit may **discard** any card (§6.2), except penalty cards on the first trick (§7). |
| **discard** | Playing a card not of the led suit when void. A discard never wins the trick. Also called "slough". |
| **win / take a trick** | The highest card of the led suit wins (§9). The winner adds the trick's cards to their **taken** pile (`game.taken[seat]`) and leads next. |
| **penalty card** | A card worth points: each heart (1) and the Q♠ (13). Also "point card". 26 points in all (§10). |
| **Q♠** | The queen of spades, "the Black Lady" or "Black Maria", 13 points. Does not break hearts by default (§8.4). |
| **break hearts** / **hearts broken** | The first time a heart is played in a round (usually a discard), hearts become leadable (§8.2). `game.hearts_broken?` resets each round. A seat holding only hearts may lead one before then, which breaks hearts (§8.3). |
| **legal cards** | `Hearts.legal_cards(game, seat)`: the cards the seat may play now, after follow-suit (§6), first-trick (§7) and breaking (§8) rules. Never empty when it is the seat's turn. |
| **round points** | Penalty points a seat took in this round (0..26), before moon adjustment. |
| **shoot the moon** / **moon** | One seat takes all 13 hearts and the Q♠ in a round (§11). Default: that seat scores 0 and every other seat scores 26 (`moon: :add_to_others`). |
| **score** / **game score** | A seat's running total across rounds (`game.scores[seat]`). Lower is better. |
| **target** | The score that ends the game, default 100 (`target:`). The game ends after the round in which any score reaches it (§12). |
| **winner(s)** | The seat(s) with the lowest score at game end. Ties for lowest share the win by default (§12.3). |
| **house rules** | Options on `Hearts.new/1` that change rules (`moon:`, `queen_breaks_hearts:`, `omnibus:`, `players: 3 \| 5`, …; §14). All off by default. |
| **view** | `Hearts.view(game, seat)`: what one seat may see. Own hand, all played/taken cards, scores, counts of other hands; never other hands, nor cards passed to the seat before it has passed. |
