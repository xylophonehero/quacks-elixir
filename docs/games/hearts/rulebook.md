# Hearts rulebook

The rules that the `Hearts.Game` engine uses. Each rule has a number (§x.y). The tests refer to these numbers with `@tag rule: "§x.y"` (see `test-plan.md`).

Sources:

- [pagat] John McLeod, "Hearts", pagat.com: <https://www.pagat.com/reverse/hearts.html> (read 2026-10-16).
- [bicycle] Bicycle Cards, "How to play Hearts": <https://bicyclecards.com/how-to-play/hearts> (read 2026-10-16).

⚠️ = the sources do not agree, or do not say. The engine uses the reading given here. An option (§6) gives the other reading where one is useful.

## §1 Players and cards

- **§1.1** The base game has 4 players. It uses a standard deck of 52 cards: 4 suits (clubs ♣, diamonds ♦, spades ♠, hearts ♥), 13 ranks each. The ace is high, the 2 is low. There are no trumps. [pagat]
- **§1.2** Each hand, the engine shuffles the deck and deals all cards, one at a time, so each player has 13 cards. [pagat]
- **§1.3** 3 players: remove the 2♦; each player gets 17 cards. 5 players: remove the 2♣ and the 2♦; each player gets 10 cards. [pagat] ⚠️ [bicycle] removes the 2♣ for 3 players; we use pagat.
- **§1.4** Play goes clockwise: seat 0, 1, 2, 3, then seat 0 again. The player on your left is the next seat (`seat + 1`). The player on your right is the seat before you (`seat - 1`).

## §2 Passing

- **§2.1** Before the play of a hand, each player chooses 3 cards from their hand. All players choose at the same time, in secret. When all players have chosen, all the cards move together. A player cannot see the cards that they get before they choose. A choice is final. [pagat]
- **§2.2** 4 players: the direction changes each hand in a cycle of 4: hand 1 left, hand 2 right, hand 3 across, hand 4 no pass. Then the cycle starts again. [pagat]
- **§2.3** 3 and 5 players: the cycle has 3 hands: left, right, no pass. [pagat gives this as one of the correct cycles] ⚠️ pagat also gives "left, right" with no hold hand; we use the cycle with the hold hand.
- **§2.4** On a hand with no pass, the play starts at once.

## §3 Play of the cards

- **§3.1** The player with the 2♣ leads it to the first trick. With 5 players (no 2♣), the player with the 3♣ leads it. [pagat] This is after the pass.
- **§3.2** Each player in turn plays one card. A player must follow suit (play a card of the suit that was led) if they can. If they cannot, they can play any card, but see §3.3. [pagat, bicycle]
- **§3.3** First trick: a player who cannot follow suit must not play a heart or the Q♠. [bicycle; pagat gives it as a variant] Exception: if all the cards in the hand are hearts or the Q♠, the player can play any of them. ⚠️ [bicycle] does not give the exception; [pagat] does. Option `no_points_first_trick` (default `true`).
- **§3.4** A player cannot lead a heart until hearts are broken. Hearts are broken when a heart was played to a trick (as a discard, or led under §3.4's exception). [pagat] Exception: a player whose hand has only hearts can lead a heart. [pagat]
- **§3.5** A player can lead the Q♠ (and any spade) at any time after the first trick. By default the Q♠ does not break hearts. [pagat] ⚠️ [bicycle] says that the Q♠ breaks hearts: option `queen_breaks_hearts` (default `false`).
- **§3.6** The highest card of the suit that was led wins the trick. Cards of other suits cannot win. The winner of a trick leads to the next trick. [pagat]
- **§3.7** The hand ends when all cards are played.

## §4 Scoring

- **§4.1** At the end of a hand, each player gets 1 point for each heart in the tricks that they won, and 13 points for the Q♠. The points of a hand add up to 26. Points are bad. [pagat, bicycle]
- **§4.2** Shooting the moon: if one player wins all 13 hearts and the Q♠, that player gets 0 and each other player gets 26. [bicycle; pagat gives it as one of two choices] Option `moon: :subtract`: the shooter gets −26 and the other players get 0. ⚠️ [pagat] lets the shooter choose each time; the engine has no choice action; the table chooses before the game.
- **§4.3** Variant J♦ (option `jack_of_diamonds`, default `false`): the player who wins the J♦ gets −10. To shoot the moon, a player must still win all hearts and the Q♠ only; the −10 is added after §4.2, also when the shooter has the J♦. [pagat, "Omnibus Hearts"]
- **§4.4** The points of the hand are added to each player's total.

## §5 End of the game

- **§5.1** When a hand ends and a player's total is 100 or more, the game ends. [pagat, bicycle] Option `target` (default `100`). [bicycle: "some play to 50"]
- **§5.2** The player with the lowest total wins. [pagat, bicycle] ⚠️ The sources do not say what to do with a tie for the lowest total. Default: all tied players win (`ties: :share`). Option `ties: :play_on`: play more hands until one player has the lowest total alone. [pagat gives this as a variant]
- **§5.3** If the game does not end, the next hand starts: a new deal (§1.2) and the next pass in the cycle (§2.2, §2.3).

## §6 Options and defaults

| Option | Default | Other values | Rule |
|---|---|---|---|
| `players` | `4` | `3`, `5` | §1.3, §2.3 |
| `no_points_first_trick` | `true` | `false` | §3.3 |
| `queen_breaks_hearts` | `false` | `true` | §3.5 |
| `moon` | `:add_to_others` | `:subtract` | §4.2 |
| `jack_of_diamonds` | `false` | `true` | §4.3 |
| `target` | `100` | any positive integer | §5.1 |
| `ties` | `:share` | `:play_on` | §5.2 |
