# Go Fish (generic table)

Spec: `priv/games/generic/go_fish.json`. No referee yet: step B (an LLM referee) plays it from these
notes. Public-domain rules, in a short form.

## Set-up

- 2 to 6 players, one standard deck of 52 cards.
- Shuffle. Deal 7 cards to each player with 2 or 3 players, else 5. The rest of
  the deck is the **ocean** (face down).

## A turn

- Ask one other player for a rank that you have in your hand ("Do you have any
  sevens?").
- If that player has cards of that rank, the player gives you all of them, and
  you ask again.
- If not, the player says "Go fish": you draw the top card of the ocean. If it is
  the rank that you asked for, show it and ask again. Else the turn goes to the
  next player.
- When you have all 4 cards of a rank (a **book**), put them face up in front of you.
- A player with no cards draws one card from the ocean on the turn; when the
  ocean is empty, that player is out of the game.

## End

- The game ends when all 13 books are made. The player with the most books wins.

## In the engine

| Rule | Ops |
|---|---|
| the ask | `ask seat` with choices like `"1:7"` (seat 1, rank 7) |
| give cards | `move` each card `hand:<a>` → `hand:<b>` |
| go fish | `move` top 1 `ocean` → `hand:<s>` |
| a book | `move` the 4 cards `hand:<s>` → `books:<s>`, `add "books:<s>" 1` |
| the end | `end` with the books as scores |
