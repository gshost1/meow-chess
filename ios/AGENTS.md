# iOS app guide

These rules apply inside `ios/`. Follow the root `AGENTS.md` unless this file says otherwise.
Commands below run from `ios/`.

## Commands

- Regenerate the Xcode project (needed after adding or removing Swift files, or editing `project.yml`):
  `xcodegen generate`
- Build for the simulator:
  `xcodebuild -project MeowChess.xcodeproj -scheme MeowChess -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
- Install and launch (simulator `8F7FAA96-1BC9-4E27-8818-0850699CB8D7` is the iPhone 17 Pro):
  `xcrun simctl install <id> build/Build/Products/Debug-iphonesimulator/MeowChess.app`
  then `xcrun simctl launch --terminate-running-process <id> com.julius201.meowchess -username julius201`
- Screenshot: `xcrun simctl io <id> screenshot ../screenshots/<name>.png`

Wrap every `simctl` call in `timeout 60` (or longer for installs). The simulator sometimes hangs;
if it does, run `xcrun simctl shutdown <id>`, then boot it again.

## Launch arguments for demos and screenshots

- `-username julius201`: sets the Chess.com user
- `-openGame N`: opens the Nth game in the list
- `-jumpToMistake 1`: starts the review at the player's first mistake
- `-showSummary 1`: opens the summary sheet
- `-showBest 1`: opens the review with the best move shown
- `-tab coach`: starts on that tab (`games`, `coach`, `practice`, `settings`)
- `-autoReview N`: reviews the N most recent games in the background (runs on the Meowy tab)
- `-strength fast|normal|deep`: analysis strength
- `-quizMode all|key|off`: how often the "what was your idea?" quiz appears

## Layout

- `MeowChessApp.swift`: app entry, tabs, welcome screen
- `Store.swift`: state, Chess.com download, saved reviews (`Documents/analyses/<gameId>.json`),
  quiz answers, solved puzzles
- `Engine.swift`: wraps the Rust C functions; runs them off the main thread
- `Models.swift`: Codable mirror of the engine JSON and the Chess.com API
- `BoardView.swift`: board, arrows, eval bar, move animations, tap-to-move
- `CatPieces.swift`: cat pieces drawn with SwiftUI shapes, with moods
- `SoundPlayer.swift` + `Sounds/*.wav`: meow effects (regenerate with `scripts/make_sounds.py`)
- `AIService.swift`: optional bring-your-own-key AI (OpenAI-compatible chat, Jev decisions);
  keys live in the Keychain
- `GamesView.swift`, `ReviewView.swift`, `MeowyChatView.swift`, `CoachView.swift`,
  `PracticeView.swift`, `SettingsView.swift`: screens
- `Assets.xcassets`: app icon and accent color

The rating formula lives in both `rating_from_acpl` (`core/src/analysis.rs`) and
`CoachView.rating`; change them together.

## Conventions

- Swift 5 language mode, iOS 17+, SwiftUI only, no third-party packages.
- `Store` is `@MainActor`. Engine calls run in `Task.detached` and report back on the main actor.
- Dark theme; grade colors come from `Grade.color` in `BoardView.swift`.
- Square indices match Rust (0 = a1). Use `uciSquares` and `parseBoard` instead of new parsers.
- Keep features that need chess rules (legal moves, applying moves) in Rust and call them through
  the C interface, so Swift never duplicates move generation.
