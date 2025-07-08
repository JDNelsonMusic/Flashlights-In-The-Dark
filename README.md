=============================

Flashlights In the Dark:

=============================

Commissioned by the Philharmonic Chorus of Madison, Flashlights-In-The-Dark is a Creative MacOS system capable of serving to a dozens of assorted client smartphones on a low-latency closed network. The key purpose is to enable MIDI-triggered 32chan control over a system of 32 smartphones' flashlights, speakers, and microphones. The systems is ideal for live electroacoustic integration with contemporary-classical performing ensembles. 

=============================

May 16 2025 Journal Entry (May 19th Tech-Rehearsal Prep):

=============================

Things I want to try during the tech rehearsal:

(It needs to be recorded)

Try speaking through a microphone and streaming to all the phones in real time to see if it works. 

Try playing a pre-written track of triggered tones after each singer connects to the app

Try sounding specific microtonal sonorities as “ToneGlows” and see how well the chorus can sing them back. (first give an efficient quick lesson on acoustically-informed microtonality)

Test how loud the phone system can get. - PLAY LOUD SOUNDS

Test the flashlight features in the dark. Check to see how similar everyone’s flashlight colors and brightness levels are. 

Try some slow swells in brightness to see how smoothly they can be executed. 

Trying singing some Filidei-style “Brass Impacts” with space in between while sparkly sounds are dancing around the chorus just to see how it feels. FOCUS ON THE SOUDNS.

Try using a “Tick-Tock” clock ticking sound just to see how precisely everything lines up. 

=============================


=============================
Singer Phone Onboarding
=============================

We provide a script to streamline registration and provisioning of singers' devices.

Requirements:
- Python 3
- libimobiledevice (for `idevice_id`)
- Fastlane configured (see `fastlane/Fastfile`)

Usage:
```bash
python3 scripts/choir_onboard.py --name "Singer Name"
```

Options:
- --name, -n: Singer's name (required)
- --udid, -u: Device UDID (optional; auto-detected via USB if omitted)
- --ip, -i: Device IP address (optional; auto-detected on macOS via `iPhone USB` interface if omitted)

After running the script, remember to commit the updated map file:
```bash
git add FlashlightsInTheDark/flash_ip+udid_map.json
git commit -m "Onboard device SingerName UDID to slot"
```

=============================








## ⚡ One-command Singer On-Boarding
```bash
brew bundle --file=./scripts/Brewfile      # cfgutil, fastlane, jq, adb
scripts/choir_onboard.sh                   # plug phones first, then run
```

## iOS Client Setup
After renaming the iOS application from `Runner` to `Flashlights-ITD-Client`,
the CocoaPods configuration must be regenerated. Run the following commands
from the `flashlights_client` directory before opening the Xcode workspace:

```bash
flutter pub get
cd ios
pod install
```

This will create `Flashlights-ITD-Client.xcworkspace` with the updated
`Pods-Flashlights-ITD-Client` support files so Xcode can build without the
missing `xcfilelist` errors.
