=============================

Flashlights In the Dark:

=============================

Commissioned by the Philharmonic Chorus of Madison, Flashlights-In-The-Dark is Creative MacOS system capable of serving to a dozens of assorted client smartphones on a low-latency closed network. The key purpose is to enable MIDI-triggered 32chan control over a system of 32 smartphones' flashlights, speakers, and microphones. Ideal for live electroacoustic integration with contemporary-classical performing ensembles. 

=============================

May 16 2025 Journal Entry (May 19th Tech-Rehearsal Prep):

=============================

Things I want to try during the tech rehearsal:

(It needs to be recorded)

Try speaking through a microphone and streaming to all the phones in real time to see if it works. 

Try playing a pre-written track of triggered tones after each singer connects to the app

Try sounding specific microtonal sonorities as “ToneGlows” and see how well the chorus can sing them back. (first give an efficient quick lesson on acoustically-informed microtonality)

Test how loud the phone system can get.

Test the flashlight features in the dark. Check to see how similar everyone’s flashlight colors and brightness levels are. 

Try some slow swells in brightness to see how smoothly they can be executed. 

Trying singing some Filidei-style “Brass Impacts” with space in between while sparkly sounds are dancing around the chorus just to see how it feels. 

Try using a “Tick-Tock” clock ticking sound just to see how precisely everything lines up. 

=============================


Potential language to include in email to singers with iPhones: 
Ready-to-paste mini-guide (Configurator method)
How to grab your UDID directly on your phone (takes <1 min)
    1.    Open Safari or Chrome on your iPhone.
    2.    Go to: https://get.udid.io
    3.    Tap “Tap to find UDID”
    4.    Tap Allow when prompted to install the configuration profile.
    5.    Go to Settings > Profile Downloaded
    6.    Tap Install, then Install again.
    7.    Once installed, you’ll be redirected to a page showing your device’s:
        •    UDID
        •    Device name
        •    Model and iOS version
    8.    You can copy these values, including the UDID, or simply screenshot it and send the screenshot to jdnelsonmusic@gmail.com

That’s all—thank you!

=============================


Potential language to include in email to singers with Android:  Subject: Installing the Flashlights app on Android
    0.    Open Settings → Security & privacy → Install unknown apps. Tap the app you use to download files (Chrome, Gmail, Drive). Turn on Allow from this source.
    0.    Download FlashlightsClient.apk from this link: <your-link>.
    0.    When the download finishes, tap the file → Install.
    0.    Launch the app, tap Allow for Camera (controls flashlight) and Microphone (future feature).
    0.    You can turn Allow from this source back off afterwards.

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
