#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Patching AndroidManifest.xml"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/flashlights_client/android/app/src/main/AndroidManifest.xml"

add_android_perm() {
  local PERM=$1
  if ! grep -q "$PERM" "$MANIFEST"; then
    perl -0777 -pi -e "s|</manifest>|  <uses-permission android:name=\"$PERM\"/>\n</manifest>|" "$MANIFEST"
    echo "  + $PERM"
  fi
}

add_android_perm android.permission.CAMERA
add_android_perm android.permission.FLASHLIGHT
add_android_perm android.permission.RECORD_AUDIO
add_android_perm android.permission.WAKE_LOCK
add_android_perm android.permission.CHANGE_WIFI_MULTICAST_STATE

# mark camera as non-location (API 34+)
CAMERA_FLAG='<uses-permission android:name="android.permission.CAMERA" android:usesPermissionFlags="neverForLocation"/>'
if ! grep -q "usesPermissionFlags=\"neverForLocation\"" "$MANIFEST"; then
  perl -0777 -pi -e "s|<uses-permission android:name=\"android.permission.CAMERA\"/>|&\n  $CAMERA_FLAG|" "$MANIFEST"
  echo "  + camera neverForLocation flag"
fi

# Add foreground service inside <application>
if ! grep -q '.KeepAliveService' "$MANIFEST"; then
  perl -0777 -pi -e 's|</application>|  <service android:name=".KeepAliveService" android:exported="false" android:foregroundServiceType="mediaPlayback"/>\n</application>|' "$MANIFEST"
  echo "  + KeepAliveService"
fi

echo "🔧 Patching iOS Info.plist"
PLIST="$REPO_ROOT/flashlights_client/ios/Runner/Info.plist"

insert_plist_key() {
  local KEY=$1; local VALUE=$2
  if ! grep -q "<key>$KEY</key>" "$PLIST"; then
    perl -0777 -pi -e "s|</dict>|  <key>$KEY</key>\n  $VALUE\n</dict>|" "$PLIST"
    echo "  + $KEY"
  fi
}

insert_plist_key NSCameraUsageDescription '<string>Allows this app to control the flashlight.</string>'
insert_plist_key NSMicrophoneUsageDescription '<string>Enables recording for choir synchronization.</string>'

# UIBackgroundModes array
if ! grep -q '<key>UIBackgroundModes</key>' "$PLIST"; then
  perl -0777 -pi -e 's|</dict>|  <key>UIBackgroundModes</key>\n  <array>\n    <string>audio</string>\n  </array>\n</dict>|' "$PLIST"
  echo "  + UIBackgroundModes → audio"
fi

echo "🎉  Manifest patching complete"
