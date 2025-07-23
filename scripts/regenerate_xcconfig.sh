#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Regenerate ios/Flutter/Generated.xcconfig for flashlights_client
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_DIR="$REPO_ROOT/flashlights_client"
GEN_FILE="$FLUTTER_DIR/ios/Flutter/Generated.xcconfig"

cd "$FLUTTER_DIR"

# Step 1: fetch Flutter dependencies
if command -v flutter >/dev/null 2>&1; then
  echo "📥 Running flutter pub get"
  flutter pub get

  # Step 2: install CocoaPods pods if Podfile exists
  if [ -f ios/Podfile ]; then
    echo "📦 Running pod install"
    (cd ios && pod install)
  fi

  # Step 3: clean old build artifacts
  echo "🧹 Running flutter clean"
  flutter clean

  # Step 4: build iOS project (regenerates configs)
  echo "🚧 Building iOS project"
  flutter build ios --debug
else
  echo "⚠️  flutter command not found; skipping pub get/clean/build" >&2
fi

# Step 5: manually create Generated.xcconfig if missing
if [ ! -f "$GEN_FILE" ]; then
  echo "➕ Creating missing Generated.xcconfig"
  FLUTTER_ROOT="$(dirname "$(dirname "$(command -v flutter || echo /path/to/flutter/bin/flutter)")")"
  FLUTTER_PROJECT_PATH="$FLUTTER_DIR"

  cat > "$GEN_FILE" <<EOT
FLUTTER_ROOT=$FLUTTER_ROOT
FLUTTER_APPLICATION_PATH=$FLUTTER_PROJECT_PATH
COCOAPODS_PARALLEL_CODE_SIGN=true
FLUTTER_TARGET=lib/main.dart
FLUTTER_BUILD_DIR=build
SYMROOT=\${SOURCE_ROOT}/../build/ios
OTHER_LDFLAGS=\$(inherited) -framework Flutter
FLUTTER_FRAMEWORK_DIR=\${FLUTTER_ROOT}/bin/cache/artifacts/engine/ios
TRACK_WIDGET_CREATION=true
EOT
fi

# Step 6: final check
if [ -f "$GEN_FILE" ]; then
  echo "✅ Generated.xcconfig is present at $GEN_FILE"
else
  echo "❌ Failed to create $GEN_FILE" >&2
  exit 1
fi
