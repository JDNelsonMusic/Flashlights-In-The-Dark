#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
#  Fix "Invalid depfile" build errors for flashlights_client
# ----------------------------------------------------------------------------

# Step 1: print Flutter & Dart versions
echo "🔎 Checking Flutter and Dart versions"
FLUTTER_OUTPUT=$(flutter --version 2>&1)
FLUTTER_VERSION=$(echo "$FLUTTER_OUTPUT" | head -n1 | awk '{print $2}')
DART_VERSION=$(echo "$FLUTTER_OUTPUT" | grep -oE 'Dart [0-9.]+' | awk '{print $2}')

echo "📦 Flutter $FLUTTER_VERSION / Dart $DART_VERSION"

# require Flutter >= 3.19
REQUIRED_MAJOR=3
REQUIRED_MINOR=19
FLUTTER_MAJOR=$(echo "$FLUTTER_VERSION" | cut -d. -f1)
FLUTTER_MINOR=$(echo "$FLUTTER_VERSION" | cut -d. -f2)
if (( FLUTTER_MAJOR < REQUIRED_MAJOR || (FLUTTER_MAJOR == REQUIRED_MAJOR && FLUTTER_MINOR < REQUIRED_MINOR) )); then
  echo "❌ Flutter 3.19 or newer is required. Please upgrade." >&2
  exit 1
fi

# Step 2: clean caches
echo "🧹 Removing old build caches"
rm -rf flashlights_client/build flashlights_client/.dart_tool
( cd flashlights_client && flutter clean )

# Step 3: fetch packages
echo "📥 Running flutter pub get"
( cd flashlights_client && flutter pub get )

# Step 4: upgrade packages
echo "⬆️  Running flutter pub upgrade (optional)"
( cd flashlights_client && flutter pub upgrade )

# Step 5: configure iOS/Android namespaces
echo "🔧 Running scripts/setup_platforms.sh"
./scripts/setup_platforms.sh

# Step 6: run the Flutter app
echo "🚀 Launching flashlights_client"
( cd flashlights_client && flutter run )
