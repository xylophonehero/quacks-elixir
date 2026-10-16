# Hearts test plan

One line per test. The § numbers refer to `rulebook.md`. Files: `test/hearts/game_test.exs` (G), `test/hearts/property_test.exs` (P), `test/hearts/ai/bots_test.exs` (B). Table builders: `test/support/hearts_scenario.ex`.

## Rules

- §1.1 §1.2 (G) 4 players get 13 cards each; the hands are the full 52-card deck with no card twice; the first event is the deal.
- §1.2 (G) The same seed deals the same hands; another seed deals other hands.
- §1.2 (P) A seed and the same actions give the same game.
- §1.3 (G) 3 players: no 2♦, 17 cards each.
- §1.3 (G) 5 players: no 2♣ and no 2♦, 10 cards each.
- §1.4 (G) Left is the next seat, right is the seat before, across is two seats on.
- §2.1 (G) A seat chooses 3 cards in secret; no card moves until all seats have chosen; a second choice is refused.
- §2.1 (G) A pass must be 3 different cards from the own hand; a play during the pass is refused.
- §2.1 (G) The view shows the own hand and the sizes of the other hands; the deal event hides the other hands.
- §2.1 (G) After the pass, a seat sees only the cards that it gave and got.
- §2.1 (G) A spectator sees no hand and has no actions.
- §2.1 (P) `view/2` never shows a card of another seat's hand or another seat's chosen pass.
- §2.1 §2.2 (G) 4 players: hand 1 left, hand 2 right, hand 3 across, hand 5 left again; the passed cards are in the target's hand.
- §2.2 §2.4 (G) Hand 4 has no pass: the play starts at once.
- §2.3 (G) 3 and 5 players: left, right, no pass, left.
- §3.1 (G) After the pass, the holder of the 2♣ must lead it.
- §3.1 (G) 5 players: the holder of the 3♣ leads it.
- §3.2 (G) A player must follow suit; a void player can play any card; wrong turn and a card not in hand are refused.
- §3.2 §3.6 (P) Each trick has one card per seat, in play order, and the winner played the highest card of the suit led.
- §3.2 (P) An illegal action returns `{:error, _}` (and the game does not change).
- §3.3 (G) First trick: a void player cannot play a heart or the Q♠ when they have another card.
- §3.3 (G) First trick: a hand of only hearts and the Q♠ can play any of them.
- §3.3 (G) First trick: with `no_points_first_trick: false` a heart is a legal discard.
- §3.4 (G) A heart cannot be led before hearts are broken.
- §3.4 (G) A hand of only hearts can lead a heart before hearts are broken.
- §3.4 (G) A heart discard breaks hearts (event `{:hearts_broken, seat}`); then hearts can be led.
- §3.5 (G) The Q♠ can be led after the first trick and does not break hearts.
- §3.5 (G) With `queen_breaks_hearts: true` the Q♠ breaks hearts.
- §3.6 (G) The highest card of the suit led wins, not a higher card of another suit; the winner leads next.
- §3.7 (G) The hand ends after all tricks; one `:hand_scored` event.
- §3.7 §5.1 (P) Random legal play always ends; a total is at or above the target; the winners have the lowest total (one winner with `ties: :play_on`).
- §4.1 (G) 1 point per heart, 13 for the Q♠; the hand adds up to 26.
- §4.1 §4.2 §4.3 (P) Each hand adds up to 26, or to the moon total (26 × other players, or −26), minus 10 with the J♦ variant.
- §4.2 (G) Shooting the moon: the shooter gets 0 and each other player 26.
- §4.2 (G) `moon: :subtract`: the shooter gets −26 and the others 0.
- §4.3 (G) J♦ variant: −10 for the J♦; the moon needs only the hearts and the Q♠; off by default.
- §4.4 (G) The points of the hand are added to the totals.
- §5.1 §5.2 (G) At 100 or more the game ends and the lowest total wins; no actions after the end.
- §5.1 (G) Below the target the game goes on; `target` is an option.
- §5.2 (G) A tie for the lowest total: all tied players win.
- §5.2 (G) `ties: :play_on`: another hand while the lowest total is tied.
- §5.3 (G) The next hand is dealt with the next pass direction.
- §6 (G) The defaults; bad options and a bad seed are refused.

## Bots

- (B) The heuristic passes the high spades first, then the high hearts.
- (B) The heuristic ducks under the trick with its highest lower card.
- (B) The heuristic dumps the Q♠ when void, then the highest heart.
- (B) The heuristic does not win with the Q♠ when it has another card.
- (B) Random and heuristic bots play legal games to the end.
- (B) The heuristic wins more often than a random seat (40 seeded games).
