#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SIM_DURATION_SEC="${SIM_QUICK_DURATION_SEC:-120}"
SIM_CLIENTS="${SIM_CLIENTS:-28}"
SIM_LOSS_PCT="${SIM_LOSS_PCT:-2}"
SIM_JITTER_MS="${SIM_JITTER_MS:-30}"
SIM_DUPLICATION_PCT="${SIM_DUPLICATION_PCT:-3}"
SIM_REORDERING_PCT="${SIM_REORDERING_PCT:-3}"
SIM_MIN_ACK_RATIO="${SIM_MIN_ACK_RATIO:-0.97}"

echo '== Flutter checks =='
pushd "$ROOT_DIR/flashlights_client" >/dev/null
flutter pub get
if command -v dart >/dev/null 2>&1; then
  dart format lib test
fi
flutter analyze
flutter test
popd >/dev/null

echo '== macOS conductor checks =='
xcodebuild \
  -project "$ROOT_DIR/FlashlightsInTheDark.xcodeproj" \
  -scheme FlashlightsInTheDark \
  -destination 'platform=macOS' \
  build

xcodebuild \
  -project "$ROOT_DIR/FlashlightsInTheDark.xcodeproj" \
  -scheme FlashlightsInTheDark \
  -destination 'platform=macOS' \
  -only-testing:FlashlightsInTheDarkTests \
  test

echo '== Quick concert sim =='
python3 "$ROOT_DIR/tools/concert_sim.py" \
  --duration-sec "$SIM_DURATION_SEC" \
  --clients "$SIM_CLIENTS" \
  --loss-pct "$SIM_LOSS_PCT" \
  --jitter-ms "$SIM_JITTER_MS" \
  --duplication-pct "$SIM_DUPLICATION_PCT" \
  --reordering-pct "$SIM_REORDERING_PCT" \
  --min-ack-ratio "$SIM_MIN_ACK_RATIO"

echo 'VERIFY RESULT: PASS'
