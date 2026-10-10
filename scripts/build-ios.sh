#!/bin/sh
# Builds the Rust engine for iPhone + simulator and packages it as ios/ChessCore.xcframework.
set -eu
cd "$(dirname "$0")/.."

export IPHONEOS_DEPLOYMENT_TARGET=17.0
rustup target add aarch64-apple-ios aarch64-apple-ios-sim >/dev/null

cargo build --release -p chess_core --target aarch64-apple-ios
cargo build --release -p chess_core --target aarch64-apple-ios-sim

rm -rf ios/ChessCore.xcframework
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libchess_core.a -headers core/include \
  -library target/aarch64-apple-ios-sim/release/libchess_core.a -headers core/include \
  -output ios/ChessCore.xcframework >/dev/null

echo "Built ios/ChessCore.xcframework"
