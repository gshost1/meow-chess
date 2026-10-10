# Meow Chess

An iPhone app that reviews your Chess.com games and explains your mistakes in plain English.
The chess engine is written from scratch in Rust and runs on the phone itself.

## Features

- **Games**: downloads your recent Chess.com games and reviews them on the phone.
- **Review**: grades every move, shows the best move on any move (and lets you play through the
  engine's line), and explains what your move did, what it allowed, and what was better.
- **"What was your idea?"**: on your own moves, Meowy asks what you were trying to do, then tells
  you whether the move really did that. Change how often in Settings.
- **Meowy (coach)**: a rough estimate of how strong you play compared with your Chess.com rating,
  your style, your plans, your habits, and a training plan.
- **Practice**: puzzles made from your own mistakes. Tap a piece, then tap where it should go.
- Cat pieces drawn in code, with moods, hop and poof animations, and meow sounds for moves,
  captures, checks, blunders and more (`scripts/make_sounds.py` makes the sounds).

## Optional AI (bring your own key)

Everything above works with no internet AI. To chat with Meowy about a move or get an AI training
plan, open **Settings → Meowy AI** and fill in:

- **Server URL**: any OpenAI-compatible server. The default is OpenRouter
  (`https://openrouter.ai/api/v1`). A local server such as Ollama or LM Studio also works
  (for example `http://192.168.1.20:11434/v1`).
- **Model name**: copied from your provider.
- **API key**: from your provider. It is stored in the iPhone Keychain, never in this project.
  Leave it empty for local models.

**Jev** (a decision model by TypeSafe, served through OpenRouter) can read what you type in the
idea quiz and pick which idea you meant. Turn on **Use Jev to understand your ideas**; it uses your
OpenRouter key unless you enter a separate one.

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
                pins, missed mates, missed free material, and writes explanations;
                rating estimate, style and plans
  ideas.rs      what a move is trying to do (attack, defend, develop, threats)
  ffi.rs        C interface the iPhone app calls
cli/       command-line tool for testing the engine on your Mac
ios/       SwiftUI iPhone app (games, review, Meowy coach, practice, settings)
scripts/   build-ios.sh packages the Rust engine for iPhone; make_sounds.py makes the meows
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
2. Open `ios/MeowChess.xcodeproj` in Xcode.
3. Plug in your iPhone and unlock it. Tap **Trust** if asked.
4. In Xcode, go to **Settings → Accounts** and sign in with your Apple ID.
5. Click the **MeowChess** project, then the **Signing & Capabilities** tab, and choose your
   Apple ID under **Team**. If Xcode says the bundle ID is taken, change
   `com.julius201.meowchess` to something unique.
6. Pick your iPhone at the top of the Xcode window and press **▶ Run**.
7. On the phone, the first time: **Settings → Privacy & Security → Developer Mode → On**
   (the phone restarts), then **Settings → General → VPN & Device Management** and trust your
   Apple ID.

With a free Apple ID the app stops opening after 7 days; just press Run in Xcode again.
A paid Apple Developer account ($99/year) removes that limit.
