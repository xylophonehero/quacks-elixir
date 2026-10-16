# Codenames Duet rulebook

The rules that the `CodenamesDuet.Game` engine uses, in our own words. Each rule has a number (§x.y). The tests refer to these numbers with `@tag rule: "§x.y"` (see `test-plan.md`).

Codenames and Codenames: Duet are games by Vlaada Chvátil and Scot Eaton, published by Czech Games Edition (CGE). This file does not copy their text or their word list. The code name of the game is `codenames_duet` for now; a new name is a later decision.

Sources:

- [rules] CGE, "Codenames: Duet" rulebook, English, June 2017 (12 pages). Read 2026-10-16 from a library copy: <https://lot.ahml.info/CodenamesDuet.pdf>. The page "Secrets of the key card" (p. 12) gives the key layout.
- [rulespal] "Codenames Duet rulebook" summary, rulespal.com: <https://rulespal.com/codenames-duet/rulebook> (read 2026-10-16).
- [geeky] "Codenames Duet board game review and rules", geekyhobbies.com: <https://www.geekyhobbies.com/codenames-duet-board-game-review-and-rules/> (search result only).

⚠️ = the sources do not agree, do not say, or the engine must choose something that people at a table decide for themselves. The engine uses the reading given here.

## §1 Players, words and the key

- **§1.1** 2 players. The game is cooperative: both players win or both lose. The players sit on opposite sides of the table: seat 0 and seat 1. [rules p. 1–2] Groups of more than 2 → out of scope (§7.2).
- **§1.2** The engine deals 25 different words at random from the word list (`priv/games/codenames_duet/words.txt`) into a 5 × 5 grid. A word has an index 0..24, row by row from the top left. [rules p. 2]
- **§1.3** The key card has two sides, one for each seat. On each side: 9 green words (agents), 3 black words (assassins) and 13 tan words (bystanders). [rules p. 3]
- **§1.4** All key cards follow one layout [rules p. 12]. As pairs (seat 0 side / seat 1 side):

  | Seat 0 | Seat 1 | Words |
  |---|---|---|
  | green | green | 3 |
  | green | bystander | 5 |
  | bystander | green | 5 |
  | green | assassin | 1 |
  | assassin | green | 1 |
  | assassin | assassin | 1 |
  | assassin | bystander | 1 |
  | bystander | assassin | 1 |
  | bystander | bystander | 7 |
  | **total** | | **25** |

  So each side has 9 green (3 + 5 + 1), 3 assassins (1 + 1 + 1) and 13 bystanders (5 + 1 + 7). There are 15 different green words (3 + 5 + 5 + 1 + 1). Of the 3 assassins on a side, 1 is an assassin on both sides, 1 is green on the other side and 1 is a bystander on the other side. [rules p. 12] The rulebook gives the counts for "your" side; the bystander/bystander count (7) is what is left of 25. The engine puts the 25 pairs on the 25 words at random (§1.2), so the key is not one of the printed key cards. ⚠️ The printed cards have their own arrangements; the counts are the same.
- **§1.5** The time bank has 9 timer tokens. Option `timer`: 10 or 11 makes the game easier [rules p. 2]; the missions of the map use 6 to 11 (§7.1).
- **§1.6** A seat sees only its own side of the key. A seat never tells its partner about its side, except that it must say when all its green words are found (§2.4). [rules p. 7] The engine shows each seat only its own side (`view/2`).

## §2 Turns

- **§2.1** Either player can give the first clue. [rules p. 4] The engine lets both seats give a clue until one of them does.
- **§2.2** A turn has exactly one clue and one or more guesses. The player who gives the clue is the **clue giver**; the other player is the **guesser**. [rules p. 5, 12]
- **§2.3** The players alternate: the guesser of this turn gives the clue on the next turn. [rules p. 5] Variant "looser turn order" (two clues in a row) → out of scope (§7.3).
- **§2.4** When all 9 words that a player sees as green are found, that player tells the partner. From then on, the partner gives all the clues. [rules p. 5] The engine logs `{:side_done, seat}` and skips that seat as clue giver.

## §3 Clues

- **§3.1** A clue is one word and one number. The number tells how many words on the table relate to the word. The number can be 0 ("avoid this"). [rules p. 4, 10] The engine accepts the numbers 0..9. ⚠️ The rulebook gives no maximum and no "unlimited"; 9 is the most green words on one side. There is no "unlimited" clue in Duet, because the number of guesses is always unlimited (§4.2).
- **§3.2** The clue word cannot be a visible word, any form of a visible word, or a part of a visible compound word. A word is **visible** until it is covered by an agent (§4.2), or marked as a bystander from both sides (§4.5). [rules p. 10]
- **§3.3** How the engine checks §3.2 (it cannot know English word forms): the clue and each visible word are compared in lower case, after trimming. The clue is refused when (a) they are equal, (b) they are equal after removing one of the endings `s`, `es`, `ed`, `d`, `ing`, `er` from either, or (c) one contains the other and the shorter is 4 letters or more. Examples: `apples` for APPLE (b), `earth` for EARTHQUAKE (c) are refused; `ear` for EARTHQUAKE is accepted, as the rulebook says. ⚠️ The check is not the same as the rule: `hideous` for HIDE is refused (the rulebook allows it) and `hid` for HIDE is accepted (the rulebook does not). The players judge the rest.
- **§3.4** One word: letters only, with an inside hyphen or apostrophe allowed (`x-ray`, `o'clock`), at most 30 letters. [rules p. 10: proper names are fine if they are one word] Multi-word clues are a house rule [rules p. 10] → out of scope.
- **§3.5** A clue must be about the meaning of the words, not about letters, positions or sounds. [rules p. 10] ⚠️ The engine cannot check this; the players do.
- **§3.6** Penalty for an invalid clue: discard one timer token, then play on. [rules p. 10] ⚠️ The engine refuses a clue that fails §3.3 or §3.4 (nothing changes), so it has no penalty. A clue that breaks §3.5 is not found by the engine.

## §4 Guesses

- **§4.1** The guesser touches one word. Only the **clue giver's** side of the key decides what the word is. [rules p. 4, 12]
- **§4.2** Green: the word is covered by an agent card, and the guesser can guess again. The number of guesses is unlimited while they are correct; the number in the clue is not a limit. [rules p. 4, 12] A green word counts even when it is not a word that the clue giver meant. A word that is green on both sides is found for both sides at once. [rules p. 5]
- **§4.3** Bystander: the clue giver marks the word with a timer token (this is the token of this turn, §5.1), on the clue giver's side. The turn ends at once. The word stays visible. [rules p. 4–5]
- **§4.4** Assassin: the game ends and both players lose. [rules p. 4, 7]
- **§4.5** A word marked as a bystander from one side can still be guessed when the other player gives the clue (it can be green on that side). It cannot be guessed again on a turn of the same clue giver: that guess would not be correct. When a word is marked from both sides, it is covered and nobody can guess it. [rules p. 5, 12] ⚠️ The rulebook does not say "cannot be guessed again" for one mark; the engine refuses it because the result is known.
- **§4.6** The guesser can end the turn after one or more guesses. Even after a 0 clue, the guesser must make at least one guess. [rules p. 5, 10]
- **§4.7** A guess does not have to relate to the current clue: words from earlier clues are fine. [rules p. 5]
- **§4.8** When the clue giver's last green word is found during a turn, and green words are still left on the other side, the turn ends at once (the guesser stops and takes the timer token, §5.1). ⚠️ At a table the clue giver says "no words left" (§2.4) and the guesser stops; any further guess would be wrong. The engine does the stop.

## §5 The timer

- **§5.1** Each turn uses exactly one timer token: the clue giver puts it on the bystander that ends the turn (§4.3), or the guesser takes it to stop (§4.6, §4.8). [rules p. 5, 12]
- **§5.2** The number of tokens in the time bank is the number of turns (and clues) left. [rules p. 5]
- **§5.3** When a turn finds the last green word, the game ends at once (§6.1). The engine does not take a token for that turn, because the game is over. The score (§6.4) counts that token as used, as the rulebook says. [rules p. 8]

## §6 End of the game

- **§6.1** When all 15 green words are found, both players win at once. [rules p. 7]
- **§6.2** When a guesser touches an assassin (of the clue giver's side), both players lose. [rules p. 7]
- **§6.3** Sudden death: when the last timer token is used and green words are left, there are no more clues. Each seat that still has words to guess (green words on its partner's side not found) is a guesser. The guessers guess in any order; they do not take turns. A guess by a seat is decided by the partner's side. Any wrong guess (a bystander or an assassin) ends the game and both lose. When the last green word is found, both win. [rules p. 7, 12] A word marked as a bystander from the partner's side cannot be guessed (§4.5).
- **§6.4** Score of a won game (optional) [rules p. 8]: 3 points for each token left in the time bank after the winning turn (the engine takes 1 off `timer` for that turn, §5.3; in sudden death there are 0), plus 1 point for each token that a guesser took to stop after a correct guess (§4.6, §4.8), minus 1 if the sudden death was needed. "More than 5 is really good; 9 or 10 is awesome." The engine gives a `score` only for a win.

## §7 Out of scope

- **§7.1** The mission map (campaign): each mission has a number of turns and a number of "acceptable mistakes"; after these, a bystander costs 2 tokens and a turn that needs more tokens than are left loses at once. [rules p. 9] Not in the engine. Only the number of tokens is an option (`timer`).
- **§7.2** More than 2 players (two groups that act as one seat each). [rules p. 11] The engine has 2 seats; a group can share a seat.
- **§7.3** Looser turn order: a player can give two clues in a row. [rules p. 11]
- **§7.4** "Pass": [rulespal] says that a player can pass, and the partner then gives all clues. ⚠️ The CGE rulebook (June 2017) has no such rule. Not in the engine.
- **§7.5** Combining Duet with other Codenames sets and Codenames Pictures. [rules p. 12]

## §8 Options and defaults

| Option | Default | Other values | Rule |
|---|---|---|---|
| `timer` | `9` | `1..11` | §1.5, §5 |
