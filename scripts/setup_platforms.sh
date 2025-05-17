#!/usr/bin/env bash
set -e

echo "🔧 Enabling iOS & Android tool-chains"
flutter config --enable-ios
flutter config --enable-android

IOS_PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
IOS_OLD="com.keex.FlashlightsClient"
IOS_NEW="com.keex.Flashlights-ITD-Client"

if grep -q "${IOS_NEW}" "${IOS_PBXPROJ}"; then
  echo "✅ iOS bundle identifier already set"
else
  echo "✏️  Setting iOS bundle identifier → ${IOS_NEW}"
  perl -pi -e "s/${IOS_OLD}/${IOS_NEW}/g" "${IOS_PBXPROJ}"
fi

ANDROID_GRADLE="android/app/build.gradle"
ANDROID_OLD='applicationId "com.example.flashlightsClient"'
ANDROID_NEW='applicationId "ai.keex.flashlights_client"'

if grep -q "${ANDROID_NEW}" "${ANDROID_GRADLE}"; then
  echo "✅ Android applicationId already set"
else
  echo "✏️  Setting Android applicationId → ai.keex.flashlights_client"
  sed -i '' "s/${ANDROID_OLD}/${ANDROID_NEW}/" "${ANDROID_GRADLE}"
fi

echo "🎉 Platform bootstrap complete"
chmod +x "$0"