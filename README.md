# Chess Coach

An iPhone app that reviews your Chess.com games and explains your mistakes in plain English.
The chess engine is written from scratch in Rust and runs on the phone itself.

## What's inside

```
core/      Rust engine (the hard part)
  bitboard.rs   board representation + attack tables
  position.rs   chess rules, move generation (verified with perft)
  notation.rs   SAN moves and PGN parsing
  eval.rs       position evaluation
  search.rs     alpha-beta search (iterative deepening, transposition table,
                quiescence, null move, late move reductions, killers/history)
  analysis.rs   game review: grades every move, detects hanging pieces, forks,
                pins, missed mates, missed free material, and writes explanations
  ffi.rs        C interface the iPhone app calls
cli/       command-line tool for testing the engine on your Mac
ios/       SwiftUI iPhone app (games list, review board, summary, habits)
scripts/   build-ios.sh packages the Rust engine for iPhone
```

## Commands

Run all of these from this folder.

```sh
# Engine tests
cargo test --release

# Review a PGN file on the Mac
cargo run --release -p chess_cli -- review game.pgn julius201

# Rebuild the engine for iPhone (run after changing any Rust code)
./scripts/build-ios.sh

# Regenerate the Xcode project (run after adding Swift files)
cd ios && xcodegen generate
```

## Putting it on your iPhone

1. Run `./scripts/build-ios.sh`, then `cd ios && xcodegen generate`.
2. Open `ios/ChessCoach.xcodeproj` in Xcode.
3. Plug in your iPhone and unlock it. Tap **Trust** if asked.
4. In Xcode, go to **Settings → Accounts** and sign in with your Apple ID.
5. Click the **ChessCoach** project, then the **Signing & Capabilities** tab, and choose your
   Apple ID under **Team**. If Xcode says the bundle ID is taken, change
   `com.julius201.chesscoach` to something unique.
6. Pick your iPhone at the top of the Xcode window and press **▶ Run**.
7. On the phone, the first time: **Settings → Privacy & Security → Developer Mode → On**
   (the phone restarts), then **Settings → General → VPN & Device Management** and trust your
   Apple ID.

With a free Apple ID the app stops opening after 7 days; just press Run in Xcode again.
A paid Apple Developer account ($99/year) removes that limit.
