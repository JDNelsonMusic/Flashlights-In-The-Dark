#!/usr/bin/env bash
set -e

echo "🔧 Enabling iOS & Android tool-chains"
flutter config --enable-ios
flutter config --enable-android

IOS_PBXPROJ="Software/Singer-Client/ios/Runner.xcodeproj/project.pbxproj"
IOS_OLD="com.keex.FlashlightsClient"
IOS_NEW="com.keex.Flashlights-ITD-Client"

if grep -q "${IOS_NEW}" "${IOS_PBXPROJ}"; then
  echo "✅ iOS bundle identifier already set"
else
  echo "✏️  Setting iOS bundle identifier → ${IOS_NEW}"
  perl -pi -e "s/${IOS_OLD}/${IOS_NEW}/g" "${IOS_PBXPROJ}"
fi

ANDROID_GRADLE="Software/Singer-Client/android/app/build.gradle.kts"
ANDROID_NAMESPACE_NEW='namespace = "ai.keex.Software/Singer-Client"'
ANDROID_APPID_NEW='applicationId  = "ai.keex.Software/Singer-Client"'

if grep -q "${ANDROID_NAMESPACE_NEW}" "${ANDROID_GRADLE}"; then
  echo "✅ Android namespace already set"
else
  echo "✏️  Setting Android namespace → ai.keex.Software/Singer-Client"
  perl -0pi -e 's/namespace\s*=\s*"[^"]*"/'"${ANDROID_NAMESPACE_NEW}"'/' "${ANDROID_GRADLE}"
fi

if grep -q "${ANDROID_APPID_NEW}" "${ANDROID_GRADLE}"; then
  echo "✅ Android applicationId already set"
else
  echo "✏️  Setting Android applicationId → ai.keex.Software/Singer-Client"
  perl -0pi -e 's/applicationId\s*=\s*"[^"]*"/'"${ANDROID_APPID_NEW}"'/' "${ANDROID_GRADLE}"
fi

echo "🎉 Platform bootstrap complete"
chmod +x "$0"