# Meow Chess: agent guide

An iPhone app that reviews a player's Chess.com games. A chess engine written from scratch in Rust
(`core/`) runs on the phone and is called from a SwiftUI app (`ios/`) through a small C interface
that exchanges JSON. The owner is a beginner (~500 rating, Chess.com user `julius201`) and does
not write code, so explain results in plain language.

Current work in progress is tracked in `task.md`. Read it before starting and update it when a step
is done.

## Commands

Run from the repository root unless noted.

- Rust tests: `cargo test --release`
- Build the Mac test tool: `cargo build --release`
- Review a game on the Mac: `./target/release/chess-coach review testdata/game2.pgn julius201 150`
  (add `--json` for the full engine output)
- Other tool commands: `./target/release/chess-coach perft 5`, `./target/release/chess-coach bestmove 2000 "<fen>"`
- Fetch test games: download from `https://api.chess.com/pub/player/julius201/games/<yyyy>/<mm>`
  and save each game's `pgn` field as `testdata/gameN.pgn` (send a `User-Agent` header)
- Rebuild the engine for iPhone after any Rust change: `./scripts/build-ios.sh`
- iOS app commands are in `ios/AGENTS.md`

## Layout

- `core/src/bitboard.rs`: squares (0 = a1 ... 63 = h8), bitboards, attack tables
- `core/src/position.rs`: board state, move generation, make move, perft tests
- `core/src/notation.rs`: SAN in and out, PGN parsing
- `core/src/eval.rs`: static evaluation (centipawns, from the side to move's view)
- `core/src/search.rs`: alpha-beta search, transposition table, mate scores
- `core/src/analysis.rs`: game review (grades, explanations, summaries, rating estimate, plans)
- `core/src/ideas.rs`: what a move is trying to do (attack, defend, develop, threats)
- `core/src/ffi.rs` + `core/include/chess_core.h`: the C interface the app calls
- `cli/`: Mac command-line tool for testing the engine
- `ios/`: SwiftUI app (see `ios/AGENTS.md`)
- `scripts/build-ios.sh`: builds `ios/ChessCore.xcframework`

## Rules

- **Keep the JSON contract in sync.** Any field added to or renamed in the serialized structs in
  `analysis.rs` or `ideas.rs` must also change in `ios/MeowChess/Models.swift`. Swift decodes with
  `convertFromSnakeCase`; the Rust field `class` maps to Swift `grade`. Make new Swift fields
  optional when old saved reviews might lack them.
- **Keep the C interface in sync.** A new `#[no_mangle]` function in `ffi.rs` needs a matching
  declaration in `core/include/chess_core.h`. Every returned string is JSON and must be freed with
  `cc_free_string`.
- **Never panic across the C interface.** Release builds use `panic = "abort"`, so a panic crashes
  the app. Return `{"ok":false,"error":...}` instead.
- **Explanation voice.** Text from `analysis.rs` goes through `Voice` ("You" / "Your opponent" /
  "White"). Text from `ideas.rs` is neutral third person ("attacks the black queen on d8") so it
  reads correctly for either player. Write for beginners: short sentences, no engine jargon.
- **Check rules changes with perft.** Changes to `position.rs` or `bitboard.rs` must keep every
  perft test passing.
- **Add a test for new detectors.** Each new idea or explanation detector needs a unit test with a
  FEN or PGN. Also run `chess-coach review` on a real game in `testdata/` and read the output.
- The engine uses only `serde` and `serde_json`. Don't add Rust dependencies without asking.

## Generated and ignored files

Never edit these by hand; regenerate them instead.

- `ios/ChessCore.xcframework`: `./scripts/build-ios.sh`
- `ios/MeowChess.xcodeproj`: `cd ios && xcodegen generate`
- `target/`, `ios/build/`, `testdata/*.pgn`, `testdata/*.json`: build output and downloaded games

## Verification

Before calling work done:

1. `cargo test --release` passes with no warnings.
2. If Rust changed: `./scripts/build-ios.sh` succeeds.
3. If Swift or Rust changed: the simulator build in `ios/AGENTS.md` prints `BUILD SUCCEEDED`.
4. For visible UI changes: take a simulator screenshot into `screenshots/` and look at it.

## Safety

- No secrets in the repository. The Chess.com API used here is public and needs no key.
- Commit locally when asked or when a stage is finished. Never push without being asked.
