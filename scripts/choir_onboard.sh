#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="FlashlightsInTheDark.xcarchive"
IPA="FlashlightsInTheDark.ipa"
APK="flashlights_client/build/app/outputs/flutter-apk/app-release.apk"
MAP="FlashlightsInTheDark/flash_ip+udid_map.json"

# ---------------- iOS ----------------
echo "🔍  Scanning iOS devices..."
mapfile -t IOS_UDIDS < <(cfgutil list --format JSON | jq -r '.Output[].UDID? // empty')
for UDID in "${IOS_UDIDS[@]}"; do
  NAME=$(cfgutil --raw --ecid "$UDID" get DeviceName)
  echo "📱  $NAME ($UDID) – registering"
  fastlane ios register_device udid:"$UDID" name:"$NAME" --quiet
done

if (( ${#IOS_UDIDS[@]} )); then
  echo "🔑  Refreshing ad-hoc profile & exporting IPA"
  fastlane ios sync_code_signing --quiet
  fastlane ios reexport archive_path:"$ARCHIVE" ipa_path:"$IPA" --quiet
  echo "🚚  Installing IPA to all iOS devices"
  cfgutil --foreach install-app "$IPA"
fi

# ---------------- Android ----------------
echo "🔍  Scanning Android devices..."
mapfile -t ANDROID_SERIALS < <(adb devices | awk 'NR>1 && $2=="device"{print $1}')
if (( ${#ANDROID_SERIALS[@]} )); then
  echo "⚙️   Assembling Flutter APK"
  (cd flashlights_client && flutter build apk --release -q)
  for S in "${ANDROID_SERIALS[@]}"; do
    echo "🤖  installing on $S"
    adb -s "$S" install -r "$APK"
  done
fi

# ---------------- mapping file ----------------
echo "🗺   Updating IP/UDID map"
python - <<'PY'
import json, subprocess, os, sys, re, ipaddress
MAP = "FlashlightsInTheDark/flash_ip+udid_map.json"
try:
    data = json.load(open(MAP))
except: data = {}
hosts = subprocess.check_output(["arp","-a"]).decode()
for line in hosts.splitlines():
    m=re.search(r'\(([\d\.]+)\).* ([0-9a-f:]{17})', line, re.I)
    if m: data[m.group(2)] = {"ip": m.group(1)}
json.dump(data, open(MAP,'w'), indent=2)
PY
echo "✅  All done – singers can unplug."
