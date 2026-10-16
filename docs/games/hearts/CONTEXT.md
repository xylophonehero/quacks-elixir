# Hearts glossary

Terms used in the code, tests and docs of Hearts. Rules: `rulebook.md`. Engine: `Hearts.Game` (`lib/hearts/`).

| Term | Meaning |
|---|---|
| **card** | `{rank, suit}`, rank 2..14 (11 J, 12 Q, 13 K, 14 A), suit `:clubs`, `:diamonds`, `:spades` or `:hearts` (`Table.Kit.PlayingCards`). Tests write cards as `"2C QS 10H"` (`Hearts.Scenario.cards/1`). |
| **seat** | A player's place, `0..players-1`. Play goes up the seat numbers (clockwise). **Left** is `seat + 1`, **right** is `seat - 1`, **across** is `seat + 2` (§1.4). |
| **hand** | Two meanings. (1) The cards that a seat holds (`game.hands[seat]`, sorted clubs, diamonds, spades, hearts by `Game.sort_hand/1`). (2) One deal played out, `game.hand_no` from 1. |
| **pass** | Before the play of a hand, each seat chooses 3 cards (`{:pass, cards}`). All seats choose at the same time, in secret (`game.passes`); when the last seat chooses, all passes move together. **Pass direction** (`Game.pass_direction/1`): `:left`, `:right`, `:across` or `:none` (§2.2, §2.3). |
| **trick** | One card from each seat, `game.trick` as `{seat, card}` in play order. The first card is the **lead** and its suit is the **suit led**. `game.tricks` counts the tricks done in this hand; the **first trick** is `tricks == 0`. |
| **follow suit** | Play a card of the suit led when you have one (§3.2). A seat with no card of that suit is **void** and **discards**. |
| **penalty card** | A heart (1 point) or the Q♠ (13 points). Points are bad. With `jack_of_diamonds`, the J♦ is −10 (a bonus, not a penalty card). |
| **hearts broken** | `game.hearts_broken`: a heart was played in this hand (or the Q♠ with `queen_breaks_hearts`). Before that, a seat cannot lead a heart unless it has only hearts (§3.4). |
| **taken** | `game.taken[seat]`: the cards of the tricks that a seat won in this hand. |
| **shoot the moon** | One seat takes all 13 hearts and the Q♠ (§4.2). Default: 0 for that seat, 26 for each other seat. |
| **score** | `game.scores`: the totals of the game. The game ends after a hand when a total is at or above `target` (100); the lowest total wins (`game.winners`, a list: a tie shares the win by default). |
| **status** | `Game.status/1`: `{:playing, seats}` (the seats that can act now: every seat that has not passed, or the seat whose turn it is) or `{:over, scores}`. |
| **view** | `Game.view(game, seat \| :spectator)`: a map with what that seat may see: its own `hand` and chosen `pass`, `hand_sizes`, `passed` (seats that chose), the table (`trick`, `turn`, `taken`, `points_taken`, `scores`), its `legal_actions`, and the `log` with other hands and passes as card counts. Bots use only the view. |
| **event log** | `game.log`, newest first; the UI animates from it. Events: `{:deal, hand_no, direction, hands}`, `{:pass_chosen, seat}`, `{:pass, direction, %{from => {to, cards}}}`, `{:play, seat, card}`, `{:hearts_broken, seat}`, `{:trick_won, seat, cards, points}`, `{:hand_scored, %{hand, points, moon, totals}}`, `{:game_over, winners, totals}`. In a view, `:deal` and `:pass` show a number in place of the cards that the viewer may not see. |
| **bot** | A module with `choose(view, state) :: {action, state}`. `Hearts.AI.Random` (random legal action, own rng) and `Hearts.AI.Heuristic` (rules of thumb). `Hearts.AI.Bench.run/1` plays one heuristic seat against random seats. |
