# Crazy Eights (generic table)

Spec: `crazy_eights.json`. Referee: `Table.Generic.Referee.Scripted`. Public-domain
rules, in a short form.

## Set-up

- 2 to 5 players, one standard deck of 52 cards.
- Shuffle. Deal 7 cards to each player with 2 players, else 5.
- Turn the top card of the deck face up: it starts the discard pile. If it is an 8,
  put it back into the deck, shuffle, and turn a new card.
- Seat 0 starts. Play goes up the seat numbers.

## A turn

- Play one card on the discard pile. It must match the **suit** to follow or the
  **rank** of the top card. An **8** is wild: you can play it on any card, and then
  you choose the suit to follow.
- Or draw one card. You can draw also when you can play. After a draw, it is
  still your turn.
- When the deck is empty, the discard pile under its top card is shuffled into a
  new deck.
- When you cannot play and nothing is left to draw, you pass.

## End and score

- The first player with no cards wins. The winner scores the cards in the other
  hands: an 8 is 50, a king, queen or jack 10, an ace 1, any other card its
  number. The other players score 0.
- When all players pass in a row (the game is blocked), the player with the
  lowest hand by these points wins and scores the difference to the sum of all hands.

## In the engine

| Rule | Ops |
|---|---|
| set-up | spec `setup`: `shuffle`, `deal` (7 or 5), `move` top 1 to `discard` |
| suit to follow | counter `suit` (`"hearts"`, ...) |
| a play | `move` card `hand:<s>` → `discard`, `set suit`, `turn` |
| an 8 | `phase "choose_suit"`, `ask` the 4 suits |
| a draw | `move` top 1 `deck` → `hand:<s>` (refill: `move` each card, `shuffle`) |
| the prompt | `ask seat`: the playable cards, `"draw"` or `"pass"` |
| the end | `end` with the scores |
