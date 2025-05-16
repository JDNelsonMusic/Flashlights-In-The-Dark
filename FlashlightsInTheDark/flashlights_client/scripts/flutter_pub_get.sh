#!/usr/bin/env bash
set -e

echo "📦 Fetching Flutter dependencies…"
flutter pub get
echo "✅  Done"
chmod +x "$0"