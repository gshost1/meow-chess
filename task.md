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
