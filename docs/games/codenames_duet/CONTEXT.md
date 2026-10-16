# Codenames Duet glossary

Terms used in the code, tests and docs of Codenames Duet. Rules: `rulebook.md`. Engine: `CodenamesDuet.Game` (`lib/codenames_duet/`). The name `codenames_duet` / Duet is a working name (§ top of `rulebook.md`).

| Term | Meaning |
|---|---|
| **seat** | `0` or `1`. The two players sit on opposite sides of the key card. `Game.partner/1` is the other seat. |
| **word** | One of the 25 words on the table, `game.words`, by **index** 0..24 (row by row, 5 × 5). Taken at random from `CodenamesDuet.Words.all/0` (`priv/games/codenames_duet/words.txt`). |
| **key** | `game.key`: `%{0 => side, 1 => side}`, a **side** is 25 colours, one per index. A colour is `:green` (an **agent**, a word to find), `:neutral` (a **bystander**) or `:assassin`. Each side: 9 green, 3 assassins, 13 bystanders. The pairs follow `CodenamesDuet.Key.layout/0` (§1.4). |
| **clue giver** | `game.giver`: the seat that gave the clue of this turn (or gives the next clue). `nil` at the start: both seats can give the first clue (§2.1). |
| **guesser** | The partner of the clue giver. A guess is decided by the **clue giver's** side (§4.1). |
| **clue** | `{:clue, word, number}`: one word (`CodenamesDuet.Clue.check/3`) and 0..9. The engine keeps it trimmed and in lower case (`game.clue`). |
| **visible word** | A word that is not covered: no agent on it, and not marked as a bystander from both sides (`Game.visible_words/1`). A clue cannot be a visible word or a form of one (§3.2, §3.3). |
| **agent** | `game.agents`: `%{index => guesser}`, the green words found. A word green on both sides is found for both (§4.2). 15 agents win (§6.1). |
| **bystander mark** | `game.bystanders`: `%{index => [sides]}`. A wrong guess marks the word for the clue giver's side (§4.3). One mark: the other side can still guess it; two marks: covered (§4.5). |
| **guessable** | `Game.guessable?(game, index, side)`: the word can still be guessed on `side` (no agent, no mark from `side`). |
| **timer** | `game.timer`: the tokens in the time bank = the turns left. Each turn uses exactly one (§5.1). |
| **turn end** | `:neutral` (a bystander), `:stopped` (the guesser stops, `:end_turn`) or `:side_done` (the clue giver's last green found, §4.8). `game.stops` counts the stops for the score. |
| **side done** | `game.done`: the seats whose 9 greens are all found. A done seat gives no more clues (§2.4). |
| **sudden death** | `phase: :sudden_death`: no tokens left and greens left. Each seat with greens left on its partner's side guesses; any wrong guess loses (§6.3). |
| **status** | `Game.status/1`: `{:playing, seats}` (both seats at the first clue and in sudden death, else one seat) or `{:over, %{result: :won \| :lost, reason, timer, score}}`. |
| **score** | `Game.score/1`: the debriefing score of a win (§6.4), else nil. |
| **view** | `Game.view(game, seat \| :spectator)`: the words, the viewer's own side (`key`), its `greens_left`, the marks, timer, clue, `done`, `acting`, `legal_actions` and the `log`. The partner's side is never in the view while the game is on; `revealed_key` shows both sides when it is over. |
| **event log** | `game.log`, newest first; the UI animates from it. Events: `{:setup, words, timer}`, `{:clue, giver, word, number}`, `{:guess, guesser, index, colour}` (the colour of the deciding side, which the table marks), `{:side_done, seat}`, `{:turn_end, guesser, how, timer_left}`, `{:sudden_death, guessers}`, `{:game_over, :won \| :lost, :all_found \| :assassin \| :sudden_death}`. No event holds a hidden colour. |
| **bot** | None. The game needs two people (`CodenamesDuet.Table.bot_levels/0` is `[]`). |

## UI ideas (for the board, not built yet)

From the codenames.game Duet flow and the rulebook. ⚠️ Not checked against the live site in this round.

- Clue entry: one text field and a number picker 0..9; the engine error (`{:invalid_clue, reason}`) shows under the field.
- The guesser touches a card; an "End guessing" button shows after the first guess (`:end_turn` in `legal_actions`).
- Card marks: a green agent card covers a found word; a bystander mark is a small token on the clue giver's edge of the card (one per side); a word with two marks is greyed.
- Each seat sees its own key as a thin colour edge or corner on each card (`view.key`).
- The time bank: 9 tokens in a row; a used token flips (bystander side or check side, from `:turn_end`).
- Colours from the card table themes (`TableWeb.Components.Theme`, the daisyUI values as `--tb-*` tokens in `assets/css/table.css`), as the Hearts board does (Nick: "use the Daisy themes again").
