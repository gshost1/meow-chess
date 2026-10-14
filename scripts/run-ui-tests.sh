#!/bin/sh
# Runs the end-to-end UI tests on the iPhone simulator, with a mock AI server on 127.0.0.1:8765.
# The build is signed "to run locally" because the simulator Keychain rejects unsigned apps.
# Build output goes outside the repo: the Desktop is in iCloud Drive, whose file tags break code signing.
# Usage: scripts/run-ui-tests.sh [extra xcodebuild args, e.g. -only-testing:MeowChessUITests/MeowChessUITests/test2_SettingsAndOptionalAI]
set -e
cd "$(dirname "$0")/.."
BUILD="${MEOW_BUILD:-$HOME/Library/Developer/MeowChessBuild}"
LOG="$BUILD/mock_ai_requests.jsonl"
mkdir -p "$BUILD"
rm -f "$LOG"
python3 scripts/mock_ai_server.py 8765 "$LOG" &
MOCK=$!
trap 'kill $MOCK 2>/dev/null' EXIT
cd ios
xcodegen generate >/dev/null
set -o pipefail
xcodebuild -project MeowChess.xcodeproj -scheme MeowChess \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$BUILD" \
  -resultBundlePath "$BUILD/UITests-$(date +%Y%m%d-%H%M%S).xcresult" \
  "$@" test 2>&1 \
  | grep -E "error:|Test Case .*(passed|failed)|XCTAssert|TEST (SUCCEEDED|FAILED)|\*\* TEST"
