#!/usr/bin/env bash
set -euo pipefail

###############################################################################
#  Flashlights in the Dark – choir_onboard.sh                                 #
#  • registers every plugged-in iPhone with the Apple Dev Portal              #
#  • refreshes the ad-hoc profile, installs the ready-made IPA                #
#  • builds / installs the Android APK on all connected Android handsets      #
#  • keeps a MAC-IP⇄UDID map for easy Wi-Fi discovery later                   #
###############################################################################

# ——— Fastlane bug-work-around ———
export FASTLANE_DISABLE_COLORS=1      # coloured2 recursion bug on Ruby 3.4

# ——— Paths ———
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARCHIVE="${FLASHLIGHTS_ARCHIVE_PATH:-${REPO_ROOT}/FlashlightsInTheDark.xcarchive}" # only used if you re-export
IPA="${FLASHLIGHTS_IPA_PATH:-${REPO_ROOT}/FlashlightsInTheDark.ipa}"
APK="${REPO_ROOT}/flashlights_client/build/app/outputs/flutter-apk/app-release.apk"
MAP="${FLASHLIGHTS_MAP_PATH:-${REPO_ROOT}/FlashlightsInTheDark_MacOS/flash_ip+udid_map.json}"
export FLASHLIGHTS_MAP_PATH="${MAP}"

###############################################################################
#                               iOS section                                   #
###############################################################################
echo "🔍  Scanning iOS devices…"

# Strip ANSI codes  → extract every “UDID: <value>”
mapfile -t IOS_UDIDS < <(
  cfgutil list         |
  sed $'s/\x1B\\[[0-9;]*[a-zA-Z]//g' |
  grep -oE 'UDID: [A-Za-z0-9-]+'     |
  awk '{print $2}'
)

echo "📋  Found ${#IOS_UDIDS[@]} device(s): ${IOS_UDIDS[*]:-(none)}"

for UDID in "${IOS_UDIDS[@]}"; do
  # `cfgutil -u <UDID> get DeviceName` → friendlier than the ECID variant
  NAME=$(cfgutil -u "$UDID" --raw get DeviceName 2>/dev/null || echo "$UDID")
  echo "📱  $NAME ($UDID) – registering…"
  fastlane ios register_device udid:"$UDID" name:"$NAME"
done

if (( ${#IOS_UDIDS[@]} )); then
  echo "🔑  Refreshing ad-hoc profile & installing IPA…"
  fastlane ios sync_code_signing
  # Install the pre-built IPA on every connected iPhone
  cfgutil --foreach install-app "$IPA"
fi

###############################################################################
#                             Android section                                 #
###############################################################################
echo "🔍  Scanning Android devices…"
mapfile -t ANDROID_SERIALS < <(adb devices | awk 'NR>1 && $2=="device"{print $1}')

if (( ${#ANDROID_SERIALS[@]} )); then
  echo "⚙️   Building Flutter APK (release)…"
  (cd "${REPO_ROOT}/flashlights_client" && flutter build apk --release -q)

  for S in "${ANDROID_SERIALS[@]}"; do
    echo "🤖  Installing on $S…"
    adb -s "$S" install -r "$APK" >/dev/null
  done
fi

###############################################################################
#                       update  (MAC-IP) ⇆ (UDID) map                         #
###############################################################################
echo "🗺   Updating IP ⇄ UDID map…"
python3 - <<'PY'
import os
import json, subprocess, re, pathlib, ipaddress
MAP = pathlib.Path(os.environ["FLASHLIGHTS_MAP_PATH"])
data = json.load(MAP.open()) if MAP.exists() else {}

arp = subprocess.check_output(["arp", "-a"]).decode()
for line in arp.splitlines():
    m = re.search(r'\(([\d.]+)\).*? ([0-9a-f:]{17})', line, re.I)
    if not m:
        continue
    ip, mac = m.group(1), m.group(2).lower()
    try:
        ipaddress.ip_address(ip)          # skip malformed / IPv6 / link-local
    except ValueError:
        continue
    data[mac] = {"ip": ip}

MAP.write_text(json.dumps(data, indent=2) + "\n")
PY

echo "✅  All done – singers can unplug."
