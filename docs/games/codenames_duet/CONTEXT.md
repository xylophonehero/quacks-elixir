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
| **bot** | A bot partner at seat 1, level `:vectors` (`CodenamesDuet.AI.Vectors`): GloVe word vectors (`CodenamesDuet.AI.Vectors.Data`, `priv/games/codenames_duet/vectors.bin`, PDDL), no network. It reads only its own view. Clue: the nearest clue words of its greens, scored by how many greens beat the best other word (an assassin counts 0.1 more) by a margin. Guess: the words nearest the clue, up to the number, one more only when sure. Bench: `CodenamesDuet.AI.Bench` (bot + bot). Set-up: "Partner: a friend / a bot". |

## The board

`CodenamesDuetWeb.Board` (a `TableWeb.Board` on `/games/codenames_duet/<code>`), set-up page `CodenamesDuetWeb.SetupLive`, CSS `assets/css/codenames.css`. Gallery: `/dev/gallery/codenames/board`. The ideas came from the codenames.game Duet flow and the rulebook. ⚠️ Not checked against the live site.

- **Clue entry**: one text field and a number picker 0..9. The engine error (`{:invalid_clue, reason}`) shows under the field (`TableWeb.Board.act_error/3`).
- **Guess**: the guesser taps a card to pick it, then taps it again (or "Guess") to guess. "End guessing" shows after the first guess (`:end_turn` in `legal_actions`).
- **Key tint**: each seat sees its own side as the colour of the whole card (a spymaster view): agent green, assassin near-black with a red edge, bystander sand. An agent has a person icon and an assassin a skull, so the key reads without colour. The fills and their inks are `--cd-*` tokens in `codenames.css`; `test/codenames_duet_web/key_contrast_test.exs` checks 4.5:1 or more for the word in each theme. "Hide my key" takes the key out of the page (for screen sharing). Gallery: `/dev/gallery/codenames/themes`.
- **Marks**: a found agent turns its card dark green, with the word struck through (a flip). A bystander mark is a token on the clue giver's edge: your side at the bottom, your partner's at the top. Two marks cover the card (dark tan, struck through).
- **Status row**: whose turn, the clue, the agents found (x/15), the timer tokens (a used token is a ring). A banner shows in sudden death.
- **Game over**: the result, the score of a win, both sides of the key on every card (your side as the tint, your partner's as a band on the top edge), Play again.
- **Long words**: a word of 9 or more letters gets a soft hyphen before a common ending (or in the middle, from 10 letters), and the font size fits the longest line (`Board.fit/1`).
- Colours: the card table themes (`TableWeb.Components.Theme`, `--tb-*` tokens in `assets/css/table.css`), as on the Hearts board (Nick: "use the Daisy themes again").
