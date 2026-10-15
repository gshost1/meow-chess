# Meow Chess privacy policy

Effective date: October 15, 2026

Meow Chess is a hobby project. It has no accounts, no analytics, no ads and no tracking, and the
developer has no server. The developer does not collect, receive or sell any of your data.

## What stays on your iPhone

- Your Chess.com username, the games the app downloads, the reviews of those games, your answers to
  the "What was your idea?" quiz, solved puzzles, and your settings. These are stored only on your
  phone, in the app's own storage.
- API keys you enter for the optional AI features. They are stored in the iPhone Keychain.

Chess analysis runs on your phone. The chess engine is part of the app.

## What the app sends, and to whom

**Chess.com.** To download your games, the app asks Chess.com's public API
(`api.chess.com`) for the games of the username you enter. Chess.com's own privacy policy applies
to those requests: https://www.chess.com/legal/privacy

**AI services, only if you turn them on.** The AI features are off until you set them up in
Settings and enter your own API key. Then:

- **Meowy AI chat and the AI training plan** send the conversation to the AI server you chose
  (OpenRouter by default, or any other server you enter, including one on your own computer). The
  conversation includes the Chess.com usernames of both players in the game (yours and your
  opponent's), the move you're asking about, the chess position, the engine's explanation, your
  estimated and Chess.com ratings, statistics from your reviewed games, and the messages you type.
- **Jev (typed ideas in the quiz)** sends what you typed, the move, and the engine's description
  of the move to the server you set (OpenRouter by default).

Your API key goes to that server with each request. Jev requests don't include any usernames.
The AI provider's own privacy policy applies to what you send them, for example
OpenRouter's: https://openrouter.ai/privacy

**Apple.** If you install Meow Chess through TestFlight, Apple handles the installation and may
share crash reports and any feedback you choose to send with the developer, under Apple's
privacy policy: https://www.apple.com/legal/privacy/

## Deleting your data

Settings → Delete all reviews removes saved reviews. Deleting the app removes the games, reviews,
answers and settings it stored. iOS can keep Keychain items after an app is deleted, so clear your
API keys in Settings first if you want them gone too.

## Children

Meow Chess is not directed at children under 13 and does not knowingly collect information from
anyone.

## Changes

If this policy changes, the new version will be posted here with a new effective date.

## Contact

Questions: open an issue at https://github.com/gshost1/meow-chess/issues
