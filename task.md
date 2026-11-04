# Current task: Meow Chess v2 (done)

Goal: make the review feel like chess.com's, explain moves in more depth, ask the player what they
were trying to do, estimate their strength and style, and help them improve. Use cute hand-drawn
cat pieces and meow sound effects.

Status key: `[x]` done, `[~]` in progress, `[ ]` not started.

## Engine (Rust)

- [x] Move ideas (`core/src/ideas.rs`): capture, trade, check, fork, pin, attack, discovered
  attack, threat (found by a null-move search), saving a piece, defending, stopping a threat,
  attacking the king, development, castling, center, rook files, passed pawns, king activity.
  4 unit tests.
- [x] Per-move fields in `analysis.rs`: `ideas`, `ideas_text`, `best_ideas`, `best_text`,
  `opponent_threat`, `best_line_moves` and `reply_line_moves` (each `{san, uci, fen}`), `cp_loss`
- [x] Per-side summary: `acpl`, `estimated_rating` (`4000 * e^(-0.035 * acpl)`, rounded to 25; calibrated on real ~400-rated games, the first formula rated them ~1,600),
  `plan` (`style`, `style_detail`, `focus`, `highlights`), `idea_counts`
- [x] Better text for plain pawn moves (for example: "stops pieces from using g4", "opens a
  diagonal for the bishop") instead of "pushes a pawn"
- [x] `cc_legal_moves(fen)` in the C interface, returning `[{uci, san, fen, from, to}]` for
  tap-to-move in puzzles
- [x] Rebuild with `./scripts/build-ios.sh`

## Sounds

- [x] Synthesize meows as WAV files with a script (pure Python; numpy isn't installed), saved to
  `ios/MeowChess/Sounds/`: move, capture, check, checkmate, castle, blunder (sad), mistake
  (questioning), best (happy chirp), puzzle correct, puzzle wrong
- [x] `SoundPlayer` using AVAudioPlayer with the `.ambient` audio session; on/off switch in Settings
- [x] Sound priority for each move: checkmate > blunder > check > capture > castle > best > move

## Cat pieces and board

- [x] Draw cat pieces in SwiftUI (no images): pawn = kitten, knight = helmet with plume,
  bishop = pointed mitre hat, rook = castle-tower hat, queen = tiara, king = crown. White pieces
  are cream-colored cats, black pieces are dark gray cats.
- [x] Moods: normal, happy (best move), sad (blunder), worried (mistake), shocked (king in check),
  dizzy (checkmated king)
- [x] Moving piece slides and hops into place (GeometryEffect); captured piece poofs; castling
  also moves the rook
- [x] Tap-to-move mode with dots on legal squares (for puzzles)

## Review screen

- [x] "Best move" button on every move, not just mistakes; plays through `best_line_moves`
- [x] Explanation sections: what the move does (`ideas_text`), what it allowed (`explanation`),
  what was better and why (`best_text`), the threat that existed (`opponent_threat`)
- [x] "What was your idea?" quiz on the player's own moves. Options are the move's idea
  categories plus distractors, and "Not sure". Feedback says whether the move really does that,
  whether the idea was good, and if not, which move achieved it (from `best_ideas`). Save answers
  per game and move. Setting: all my moves / key moments / off.
- [x] Play a sound on every step

## Coach tab (replaces My Habits)

- [x] Estimated rating across reviewed games (average ACPL, then converted), compared with the
  Chess.com rating
- [x] Style (attacker / defender / builder / balanced) and which side of the board they play on
- [x] Plans and highlights from recent games
- [x] Existing habit list, plus a training plan built from the top 3 habits
- [x] How often the player's answers to the idea quiz were right

## Practice tab

- [x] Puzzles from the player's own mistakes and blunders: start from `fen_before`, find
  `best_uci`, with tap-to-move, sounds, and the explanation afterwards. Track how many are solved.

## Finish

- [x] `xcodegen generate`, simulator build, screenshots of each new screen, commit

## Ideas for next time

- [ ] Optional Stockfish for deeper checks
- [ ] Recalibrate the rating formula once more games at other ratings are reviewed

## Testing feedback (November 3, 2026)

- [x] Choose Cat or Classic at sign-up and in Settings; persist the choice and use it for
  board, sliding/captured pieces, and piece illustrations. Bundle cburnett SVGs under its
  BSD 3-Clause option, with a Settings credit and the full license.
- [x] Filter games by Bullet / Blitz / Rapid, adding Daily only when needed; start at the
  latest game's time control and remember an explicit selection.
- [x] Show `Acc 87` in the list and `Accuracy 87.3` in reviews, without percent signs.
- [x] Hide the review tab bar and reduce board side margins; restore tabs on return.
- [x] Replace the old buzzy meows with original short, quiet, smoothly enveloped synthesis;
  normal moves last 90 ms. Preserve SoundPlayer timing and file names.
- [x] Automatically review the newest ten games after loading, skipping saved/running work.
  Unfinished recent rows are disabled and show waiting/reviewing progress; older games
  retain analysis on opening. Persist reviews atomically before making them available.
- [x] Default questions to Key moments: deterministically select up to three worst losses,
  then at most one successful tactic if a slot remains. Review toggle shares the setting.
- [x] Regenerated the engine framework and Xcode project; `cargo test --release` passed
  all 30 tests without warnings. The final simulator build printed `BUILD SUCCEEDED`.
- [x] Added three question-selection regression tests (all pass) and expanded UI coverage
  for piece selection, tab filtering/persistence, Daily visibility, pending rows, review
  sizing, tab-bar restoration, accuracy labels, and the shared question setting.
- [x] Saved and inspected all four screenshots in `screenshots/testing-feedback/`.
  The pending-games screenshot uses deterministic debug fixtures and the real engine.
- [x] Reviewed the implementation diff, including asset attribution and persisted-review
  handling. No Rust, authentication, secret handling, or SoundPlayer trigger changes.
- [x] Make the complete UI suite green. Root cause of the flaky taps: every piece observed the
  whole Store, so each analysis progress tick redrew every board and row. Pieces now read the
  setting directly and progress is throttled to 2% steps. The board also shrinks when the keyboard
  is up so the typed answer stays visible. Mock AI is on port 18765 (8765 was taken).
  `MEOW_BUILD="$PWD/ios/build/UITestBuild" scripts/run-ui-tests.sh`: `** TEST SUCCEEDED **`,
  3 unit tests and 4 UI tests passed.
- [x] Review fixes: a failed automatic review no longer locks the game, the retry button shows
  only after a failed review, a username change mid-refresh keeps the new user's games, the review
  Questions switch restores the previous mode, and mistake ranking no longer mixes units.
- [ ] Visual follow-up: disabled rows are quite dim, and the black classic preview piece has low
  contrast against the dark welcome screen.
- [ ] Owner to listen to the new sounds on a phone.

## QA fixes (November 3, 2026)

First pass over the tester shots. Swift only. The ACPL rating curve stays in the engine and in
saved JSON so old reviews still load; the app just stops showing it.

- [x] Review board keeps one size for the whole review so it doesn't jump between moves: full width
  with questions off, and with questions on it leaves 250pt for the question card (168pt of chrome).
  With the keyboard up it leaves 120pt for the typed answer. Explanations scroll inside the card.
- [x] Loading games skips only months Chess.com answers with 404 (an empty current month). Any other
  failure stops the load and keeps the cached games.
- [x] Usernames: dashes fixed and ends trimmed; any other character Chess.com doesn't allow is refused
  with a hint instead of silently removed. Meowy chat gets the player's real Chess.com rating.
- [x] Questions control is a toolbar button (`review-questions`). The move strip has the full width.
- [x] Next mistake jumps to mistakes and blunders, and to inaccuracies only when the game has
  nothing worse. Red arrows still mark inaccuracies.
- [x] An empty time-control tab says "No rapid games in your recent games." when other games loaded.
- [x] A Chess.com month that 404s is skipped. The load fails only when the archives list fails, or
  every month fails.
- [x] A failed load shows one message. An unknown player says there is no Chess.com player by that name.
- [x] Usernames drop spaces and symbols, turn an em dash into `--` and an en dash into `-`, and a
  field that is only junk shows "Enter your Chess.com username".
- [x] The eval number stays on one line.
- [x] Answer counts read "1 answer" / "2 answers".
- [x] A bad quiz reply is a full sentence, for example "But it backfired: the move ignores a threat."
- [x] The sign-up tagline wraps, and the hero art hides while the keyboard is up.
- [x] "Played like ~N" is gone from the review intro, the summary accuracy blocks, the Meowy chat
  rating, and the Meowy tab. Accuracy stays, and the Meowy tab still shows the real Chess.com rating.
- [x] `cargo test --release`: 30 passed. `MEOW_BUILD="$PWD/ios/build/UITestBuild" scripts/run-ui-tests.sh`:
  `** TEST SUCCEEDED **`, 7 unit tests and 4 UI tests. Rust sources were not changed.
- [x] Checked on MeowQA-1: the quiz fits without scrolling, Rapid shows the empty-filter message,
  a missing player shows only the not-found message, and Meowy shows accuracy without a rating
  estimate. Shots are in `screenshots/qa-fixes/`.

## Practice and board polish (November 4, 2026)

- [x] Quick shared board glide, capture timing, castling and clearer highlights.
- [x] Three original sound packs, persisted Settings picker and Mac previews.
- [x] Wrong-move demonstration with engine reply and animated undo; deselection.
- [x] Puzzle modes with classifier tests, continuation controls and smooth next puzzle.
- [ ] Rust tests, iOS framework, simulator build, full UI tests and inspected screenshots.
- [ ] Review, commit, push `feat/practice-polish` and open a PR against main.

Implementation checks so far:
- Rust: 32 tests pass without warnings. Framework regenerated; simulator `** BUILD SUCCEEDED **`.
- Initial FFI fixture was rejected correctly because the non-moving king was already in check;
  corrected the fixture. Initial run: `test result: FAILED. 31 passed; 1 failed`.
- Three packs each have 11 unique WAVs, peaks below 0.25 and silent endpoints; copied to Mac previews.
- CLI reviewed a downloaded Julius201 game at 150 ms/move and the beginner explanations were read.
