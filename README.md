# Flashlights In The Dark

## Last updated July 12th 2025

A nine-minute electro-acoustic work for 54-voice choir, 28 smartphones & a Mac-based control system


# Table of Contents

## Project Snapshot

## System Architecture

## How the Performance Unfolds

## Setup & Requirements

## Running a Performance

## Director & Ensemble Checklist

## Repository Tour

## Contact & Support



# Project Snapshot

## Commissioned by    Philharmonic Chorus of Madison

Forces    54 singers • 28 smartphones • Mac control computer
Duration    ~9 minutes
Core idea    Smartphones become distributed “instruments,” projecting light & sound that weave into the live choral texture.
Status    Actively developed – software & docs evolve with each rehearsal cycle.




# System Architecture


## 1. Conductor’s Computer (Mac)

The “brain” of the piece – sends OSC messages over a closed Wi-Fi network.

Accepts manual, timeline, or MIDI-triggered cues.


## 2. Smartphone Clients (x28)

Cross-platform Flutter app (flashlights_client) for iOS 16+ & Android 10+.

Reacts to incoming OSC commands to:<br> • Toggle flashlight<br> • Play pre-loaded audio samples<br> • (Experimental) record short mic snippets


## 3. Closed Wi-Fi Network

Stand-alone router or Mac-hosted hotspot.

Isolated from the internet ➜ <10 ms latency typical.


## 4. Optional MIDI Controller / DAW

Map notes/CC to cue groups of phones or global actions.

Enables click-track or fully sequenced automation.



# How the Performance Unfolds

mermaid

graph LR
A[Mac Console] -- /hello ➜ B(Smartphones)
B -- /present(ID) ➜ A
A -- OSC cues ➜ B
Device Discovery

Phones power up & broadcast /hello → Mac records slot IDs (1-54).

## Clock Synchronization

Mac sends periodic /sync pulses (NTP time tags) → devices adjust drift.

## Triggering Events

Flashlight ⚡️ | Audio 🔊 | Mic 🎙 — individually or in groups.

## Visual & Aural Choreography

Waves of light, spatialised chords, or percussive “tick-tock” clicks.

Fallback Safety

“All Off” & resync buttons built into the console for quick recovery.



# Setup & Requirements

## Hardware Checklist

Qty    Item    Notes
1    Mac (2020 or newer)    Wi-Fi + Python 3 + Xcode (for builds)
28    Smartphones    Mix-and-match iOS & Android; torch & speaker must work
1    Wi-Fi Router    Dedicated SSID, no internet, client isolation off
(opt.)    MIDI Keyboard / DAW    For live or pre-programmed cues



# Software & Deployment

<details> <summary><strong>iOS On-Boarding (TestFlight)</strong></summary>

1. Each singer supplies their Apple ID email in the choir survey.
2. On App Store Connect, open the **TestFlight** tab for the Flashlights Client.
3. Add the emails to a testing group and send invitations.
4. Singers install the **TestFlight** app from the App Store and accept the invite to download the client build.

</details> <details> <summary><strong>Android On-Boarding</strong></summary>

bash

```bash
# install prerequisites (Flutter SDK and Android platform tools)
brew bundle --file=scripts/Brewfile    # installs adb via platform-tools
flutter --version && adb version

# configure Flutter project for iOS/Android builds
scripts/setup_platforms.sh

# apply required permissions to AndroidManifest.xml
scripts/patch_manifests.sh

# build the APK and deploy to all connected Android phones
scripts/choir_onboard.sh
```

1. Enable **Developer Options** and **USB debugging** on each phone.
2. Connect all devices via USB; the script installs the APK automatically.
3. Disconnect the cables and join each phone to the closed performance Wi‑Fi network.
4. Launch the Flashlights Client and confirm the status reads `Connected · Singer #X`.

</details>

### Light Chorus Spreadsheet Builder

- Create or activate a Python 3.11+ virtualenv inside the repo and install the helper app dependencies:
  `python3 -m venv .venv && .venv/bin/pip install -r light_chorus_app/requirements.txt`.
- Launch the GUI with `python light_chorus_app_gui.py` (run from the repository root so relative paths resolve).
- Click **Browse…** to select a Light Chorus MIDI export (e.g. `flashlights_client/FlashlightsInTheDark_SingerScore24.midi`), pick an output `.xlsx`, choose the octave numbering style, then press **Generate Spreadsheet**.
- The tool writes an "Event Recipes" style workbook; each populated cell lists the pitch on the first line and the corresponding `primerTones/shortXX.mp3` asset on the second.



# Running a Performance

## Pre-concert

Launch Flashlights Client on each phone → confirm “Connected · Singer #X”.

Mac console shows a green list of all active devices.

Sound & Light Checks

⌘+Shift+L (All Lights On) — verify brightness uniformity.

⌘+Shift+A (All Audio Test) — set phone volumes to 100 %.

Press `\` (backslash) to toggle all flashlights on/off.

During the Piece

Follow score or DAW timeline.

Manual overrides always available (click device tiles, press mapped MIDI keys).

Post-concert

Collect devices, stop console (logs auto-saved to logs/YYYY-MM-DD.txt).

## Run-time Validation Checklist

Build & run the macOS app.
On first launch every real slot shows ✔︎ next to ch10 and its primer + event channels exactly as in the color-group spec.
Pick one slot, uncheck ch10 ⇒ its flashlight no longer responds. Re-check ⇒ it responds again.

Network

Run at least one phone with the Flutter client on the same Wi-Fi.
In Xcode’s console you should see "✅ [OSC] Sent to <phone-IP> …" lines; on the phone’s debug console you’ll see "📲 OSC <<< …" mirrors.

Session files

File ▸ Save '.flashlights' Session produces a file with the current JSON.
File ▸ Open '.flashlights' Session immediately updates all check-marks.



## Director & Ensemble Checklist

✓    Task

Reserve extra rehearsal time with phones in hand.
Dim venue lights sufficiently for flashlight effects.
Enable Do Not Disturb & Guided Access / Screen On on all phones.
Charge devices (or supply battery packs) before each run-through.
Have a tech lead familiar with Apple provisioning & Wi-Fi troubleshooting.

# **Provide audience advisories if using rapid strobe patterns.**


==========================================================================

# Repository Tour

See [Repository Guidelines](AGENTS.md) for contributor expectations and workflow tips.

flashlights-in-the-dark/
├── AGENTS.md                  # contributor guide
├── flashlights_client/        # Flutter mobile app
├── FlashlightsInTheDark_MacOS/  # Swift-based conductor console
├── scripts/
│   ├── choir_onboard.sh       # Android deployment & device mapping helper
│   ├── Brewfile               # Homebrew dependencies
│   └── …                      # misc. debugging helpers
├── docs/
│   ├── EnableDeveloperMode.mobileconfig
│   └── osc-schema.md          # OSC message reference
└── README.md                  # ← you are here


## Contact & Support

Composer / Developer: Jon D. Nelson
✉️ email: jdnelsonmusic@gmail.com

For bug reports or feature requests, please open an issue in the GitHub repository or reach out directly.

“Flashlights In The Dark aims to invite singers to paint the air with beams of light and fragments of electronic sound, blurring the line between choral traditions and modern technological systems.” — Composer’s note

© 2025 Jon D. Nelson — Licensed for performance by the Philharmonic Chorus of Madison. Contributions welcome!








=============================================================
=============================================================
=============================================================
=============================================================
=============================================================
=============================================================








Dry/Technical README:


# Overview:

Flashlights In The Dark is a nine-minute electro-acoustic composition that integrates a traditional choir performance with modern technology. Commissioned by the Philharmonic Chorus of Madison, this piece involves a 54-voice choir, 28 smartphones, a central computer, and a closed wireless network working in unison. Each participating singer carries a smartphone that becomes an interactive instrument – its flashlight and speaker are used as extensions of the musical performance. The central computer runs custom software to synchronize light and sound events across all devices in real time, triggered via MIDI or pre-programmed cues. The result is an immersive experience where the choir’s voices blend with orchestrated flashes of light and distributed sounds, enhancing the live performance with an otherworldly “photo-acoustic” dimension. This system is currently under active development. However, this document will give board members and future choir directors a clear picture of the project’s vision, how it operates, and what resources are required to successfully stage Flashlights In The Dark.

# System Components

## Flashlights In The Dark consists of several interconnected components:

Conductor’s Computer (Mac): A macOS laptop or desktop running the Flashlights In The Dark control software. This application is the “brain” of the system – it sends out cues to all smartphones, controls timing, and optionally responds to MIDI input. We recommend using a Mac for compatibility with the provided provisioning and networking tools.

Smartphone Clients (Singers’ Devices): Each participating singer carries a smartphone (iOS or Android) with the Flashlights Client app installed. This custom app listens for commands from the conductor’s computer over a dedicated Wi-Fi network. When it receives a command, it can turn the phone’s flashlight (torch) on/off, play back audio samples through the phone’s speaker, or even briefly access the microphone. Both iPhones and Android phones are supported, and they can be used together in the same performance.

Closed Wi-Fi Network: All devices (the conductor’s computer and the smartphones) must be connected to the same local network, isolated from the public internet. This is to ensure low-latency, reliable communication and to prevent disruptions (like notifications or calls) during the performance. In practice, this can be achieved by using a standalone Wi-Fi router at the venue or a Mac-hosted network. Each phone connects to this network (via Wi-Fi) and the computer either connects via Wi-Fi or Ethernet to the same router.

MIDI Controller / Sequencer (Optional): The system can be driven by MIDI signals. The conductor or a technician can use a MIDI keyboard, pad controller, or a digital audio workstation (DAW) to trigger events. Each light or sound event is mapped to specific MIDI notes or control messages, enabling integration with a musical score or click-track. This MIDI interface is optional but provides a powerful way to synchronize the technology with live performance cues or automation from a DAW.

# How It Works

During the performance, the conductor’s computer and the singers’ smartphones work together to create synchronized light and sound effects that augment the choir’s singing. Here’s a high-level summary of the system in action:

Initial Setup: Before the performance, the Flashlights Client app is installed on all 28 smartphones and each device is registered in the system. The devices are assigned unique IDs (slots 1–54), though only 28 of those slots correspond to actual devices in this piece (the rest remain unused placeholders). Each device’s slot ID is used to target that specific phone with cues (for example, “flashlight on for device #5”). The mapping of slot numbers to physical phones is configurable and stored in a JSON file on the computer for reference.

Network Connection: All smartphones join the closed Wi-Fi network. The Flashlights Client app will automatically discover the conductor’s computer on the network by listening for a broadcast “hello” signal. When a connection is established, each phone reports its presence (announcing its slot ID to the computer) and then continuously listens for incoming control messages. The app’s main screen will display a status (e.g., “Connected”) and identify the device as “Singer #X” with its slot number.

Conductor’s Console: On the Mac, the conductor or tech runs the Flashlights In The Dark control software. This software maintains a list of all expected devices (54 slots, of which 28 are actual). It highlights which devices are “live” (connected) and can flag if any device loses connection. The console provides manual control over each device’s flashlight and audio, as well as global actions. It can also react to MIDI input or pre-set cues:

If using a MIDI keyboard or the computer’s keyboard, pressing certain keys will trigger corresponding phones. For example, a key can be mapped to turn on the flashlight for a particular singer or play a tone on that singer’s phone.

Pre-programmed sequences (via MIDI or an internal timeline) can be used to execute precise patterns of light and sound (for instance, a rapid cascade of flashes or a chord of phone tones at an exact time). This is useful if the piece is performed with a click track or needs exact synchronization with the choir.

Realtime Performance Cues: Throughout the 9-minute piece, the conductor’s software sends out Open Sound Control (OSC) messages over UDP to all phones (using broadcast or targeted messaging). Key types of cues include:

Flashlight On/Off: Instantly turns a specific phone’s camera flashlight on or off. The conductor’s software can trigger any subset of phones or all phones at once, creating patterns (e.g., flickering lights traveling through the choir). The system currently supports full on/off (not variable brightness through the torch due to hardware limitations), but smooth effects can be achieved by choreographing timing (for example, rapid toggling or staggered pulses).

Sound Playback: Triggers a phone to play an audio sample through its speaker. Each phone can have a set of pre-loaded audio files (e.g., sustained tones, sound effects, or speech recordings). The conductor’s computer will specify which file to play and at what volume. For example, phones might emit a soft drone or a sparkling sound effect to complement the choir’s singing. Multiple phones can play different parts of a chord, creating a spatial audio effect around the audience.

Microphone Capture: In experimental moments, the system can remotely activate a phone’s microphone for a short, specified duration. This could be used to capture a snippet of live singing or ambient sound from a singer’s location. (In the current implementation, recorded audio isn’t transmitted or saved; this feature was added for testing and could enable future real-time processing or analytical feedback.)

Synchronization Pulse: The software periodically sends out a sync message containing a timestamp. This allows each phone to adjust its internal clock slightly, aligning all devices to within a few milliseconds. This clock sync feature ensures that time-based events (like a metronomic click or simultaneous flash) remain tightly coordinated across all phones, accounting for any network delay.

## Choir Integration: The singers on stage incorporate the phones into their performance as directed by the piece’s score. For example:

At certain moments, singers might hold up their phones to shine the flashlight toward the audience or ceiling when cued, creating a wave of light.

Singers might listen to a tone or chord played on their phone as a reference for singing microtonal harmonies (a concept referred to as “ToneGlows”). The piece might present a cluster of pitches through the phones, and the choir then imitates or harmonizes with those electronic tones.

In sections of the piece, the phones may produce percussive or environmental sounds (like a clock’s “tick-tock” or other effects) in sync with the choir’s rhythm, testing how precisely the technology can align with live singers.

The dynamic range and brightness of phones are also considered. For instance, a segment might explore very loud electronic sounds from the phones against the choir (to test system limits and balance), or use total darkness with only the phone flashlights flickering to create a visual atmosphere.

## Control Modes: The conductor’s software is flexible:

It can be operated manually in real time (for improvisational control or interactive conducting). A technician or the composer could “play” the choir of phones like an instrument via the computer keyboard or a MIDI controller, turning lights and sounds on/off as needed.

It can run in a sequenced mode where cues are pre-arranged on a timeline or driven by a MIDI track. This is useful for complex sections that require absolute precision or for when the tech operator needs to focus on other tasks.

These modes are not mutually exclusive – for example, a base layer of events could be automated while the conductor manually adds spontaneous light flashes in response to the live performance.

Throughout the performance, the goal is to maintain seamless integration: the technology should feel like an organic extension of the choir. The system’s low-latency design (using a dedicated network and lightweight OSC messages) means that when a flash or sound is cued on the computer, the phones react almost instantaneously. In testing, the delay between a command and the phone’s response is minimal (on the order of a few tens of milliseconds or better), allowing for tight rhythmic coordination.

# Setup and Requirements

To successfully stage Flashlights In The Dark, you will need to prepare both the hardware and software in advance. Below is a rundown of what’s required and the setup process:
Central Mac Computer: A modern MacBook Pro/Air or iMac/Mac Mini with macOS (2020+ model recommended for performance). This computer will run the control software. It should have:

A stable Wi-Fi interface (or Ethernet if connecting to a router).

Python 3 installed (for running setup scripts, if needed).

Xcode and developer tools if you intend to build the software or the mobile app yourself (alternatively, the software can be provided pre-built).

Optionally, any MIDI hardware or DAW software if you plan to trigger cues via MIDI.

Smartphones: 28 smartphones (the exact number can be adjusted, but the composition is written with 28 in mind). Both iOS and Android devices are supported. Key considerations:

iPhones: Ideally running iOS 16 or later for best compatibility. The Flashlights Client is distributed via TestFlight. Each singer should provide their Apple ID so you can invite them to the testing group and they can install the app from TestFlight.

Android phones: Running Android 10 or later. The app can be installed via an APK file. Developer mode and USB debugging should be enabled to allow our deployment script to install the app. After installation, the app does not require any special debug mode.

It’s fine to mix iPhones and Androids in the ensemble. The app is cross-platform and will behave the same way on both.

All phones should have functional cameras (for the flashlight) and speakers. It’s recommended to use phones with decent flashlight brightness and sound volume for maximum effect.

Battery and power: Ensure devices are fully charged before the performance. Depending on the duration of use and battery health, consider having portable battery packs or a way to plug in devices between rehearsals. The flashlight, in particular, can drain battery quickly if used extensively.

Networking Equipment: A dedicated Wi-Fi router (or a Mac that creates a local hotspot network). This network should not have internet access or any other devices besides the performance devices, to minimize latency and interference. A simple router with a 2.4GHz and 5GHz band is sufficient:

Use a unique SSID and passphrase, and ensure it’s a private network (no external users).

It’s often best to disable any “client isolation” features so that the broadcast messages can reach all devices.

All phones should connect to this Wi-Fi and disable mobile data during rehearsals/performance (to prevent notifications or network switching).

The Mac can connect via Wi-Fi or Ethernet (Ethernet to the router can be very reliable if the router supports bridging to Wi-Fi clients).

Flashlights Client App Deployment: We have provided scripts and a workflow to simplify getting the app onto all the singer’s phones:

For iOS devices, distribute the app via **TestFlight**:

1. Collect each singer’s Apple ID through the choir survey.
2. In App Store Connect, open the TestFlight section for the Flashlights Client and add those emails to a testing group.
3. Once invited, singers install the TestFlight app from the App Store and download the Flashlights Client build.

This approach eliminates the need for local device registration or Fastlane scripts.

For Android devices, the same script will detect devices via adb and install the pre-built APK to each one. Ensure Android phones have file transfer or debugging mode on and are connected via USB.

The script also maintains a JSON map of devices (flash_ip+udid_map.json), recording each device’s unique ID (UDID for iOS or a MAC address for Android) and assigned slot number. This mapping ensures that the system knows which singer/device corresponds to which slot ID (so cues are sent to the correct phone). After onboarding, this map file should be saved (committed in version control) so that reconnections or app restarts can remember the assignment.

For MIDI integration, you can optionally include a channel_map.json file alongside the Mac app. This JSON lists each slot number and the MIDI channels it should respond to. When present, the app loads this file on launch and overrides the compiled defaults, making it easy to tweak channel assignments without rebuilding.

Alternatively: If the above automation is not feasible, you can manually install the app on each phone (for iOS, via TestFlight or Configurator, and for Android, by sending the APK). In that case, you’d manually maintain the device-to-slot assignments in the JSON file or in the app UI (our app allows a manual override of its slot number if needed). However, using the provided tools is highly recommended for efficiency, especially with many devices.

Rehearsal and Configuration: Once all devices are on the network and the app is running, do a thorough test:

Connection check: The conductor’s console software shows which phones are connected. Each singer’s app displays “Connected” and their slot number. Verify all expected devices show up. (Our software will continuously monitor – if a device drops out, its status changes to “Lost Connection” on the console.)

Flashlight test: Try triggering a flashlight cue to all phones simultaneously (e.g., a test command for “all flashlights on”). In a dark room, observe if any phone is significantly lagging or if brightness differs. Small differences in flashlight color temperature or brightness are normal due to hardware variance, but they are usually not distracting. The system currently triggers flashlights in an on/off manner; for “smooth” brightness swells, you might simulate it by quickly pulsing the flash on and off in a pattern (from the audience perspective this can appear as dimming). This is something to experiment with in rehearsal (as noted, we want to test slow swells in brightness).

Audio test: Play a test tone or sample on all phones. Ensure volumes are up (have each singer turn their volume to maximum and disable silent mode on iPhones). You’ll want to gauge the aggregate volume of 28 phones. It can be surprisingly loud when they all play together, but certain frequencies or samples might not project far. Identify if any phone’s speaker is much quieter and consider repositioning that phone or swapping it out.

Latency and sync: Try the “tick-tock” test – use the software to play a metronome-like click on all phones in unison. Stand around the choir to listen for flams or echoes. Ideally, the clicks should sound as one; if not, we may adjust network/router settings. The built-in clock sync will calibrate periodically, but environmental factors (Wi-Fi interference) can cause slight variances.

Microphone test (if used): If you plan to use the microphone capture feature (for example, capturing the choir’s sound via distributed phones), test one phone at a time. The current implementation simply records to the phone’s memory (not streamed), and is mainly to experiment with what could be done (like having a phone sample a singer’s voice for later playback). This is an advanced feature and not critical for a basic performance, so it can be skipped unless you have specific plans for it in the artistic design.

# Performing the Piece

With everything set up, here’s what a typical performance run might look like from a technical standpoint:

Pre-concert: All smartphones are turned on, volumes up, and the Flashlights Client app is launched. Each singer either holds their phone (if it will be used mid-song) or has it placed securely (e.g., on a stand or in a pocket) until needed. It’s important the app stays active – on Android, we use a foreground service to keep it alive even if the screen is off. On iPhone, we recommend enabling guided access or auto-lock “Never” for the performance duration to prevent the screen from locking and pausing the app. Also, enable Do Not Disturb on all devices to avoid any notifications or calls from interrupting.

Conductor checks in: The tech/operator opens the Mac control app, confirming all devices show “live”. If any are missing, the operator can identify which singer’s device isn’t connected (we label devices by singer name in the console if provided) and address it (perhaps toggle Wi-Fi or reopen the app on that phone).

During performance: The operator follows the score and triggers cues as composed. For instance, at measure X the score might call for “Sparkling sound cluster (phones) emerges and crescendos for 5 seconds.” The operator can execute this by selecting a predefined sequence or pressing a mapped key that sends out a series of /audio/play commands to a group of phones with the desired samples. Similarly, a notation for light (e.g., flashes sweeping from left to right through the choir) would be executed by triggering those phones’ flashlights in the correct order, either manually (pressing keys 1 by 1 in rhythm) or via an automated pattern.

Fallbacks: The system is designed so that even if a phone misses a command (due to a brief network hiccup), it will catch up on the next one. In critical sections, the operator can resend a cue or have an “all off” command ready in case, for example, a flashlight got stuck on. In testing, such events are rare, but having a manual override (like an emergency “all lights off” button) is part of the interface.

Post-performance: After the piece, all phones can be collected (if they’re ensemble-owned devices) or returned to singers. The app does not require internet, so nothing needs to be uploaded or saved. Devices can be powered down or left alone. The tech operator can save any logs if needed (the console app keeps an event log of cues, which can be useful for debugging or archival).

# Questions and Considerations for Future Directors

Flashlights In The Dark is a unique piece merging choral artistry with tech. Future choir directors considering this piece should assess the following:

Technical Assistance: Ensure you have access to someone who can handle the technical setup – either the composer/developer or a tech-savvy collaborator. While the README and tools make it as straightforward as possible, deploying apps to dozens of devices and managing a network during a concert does require careful preparation.

Rehearsal Time: Plan extra rehearsal time for the choir to practice with the phones. Singing in near-darkness with flashing lights or following audio cues from phones can be unusual for performers. The choir should rehearse the timing of any actions they need to do with the devices (such as raising them up at a certain time) and get comfortable with the additional stimuli.

Equipment Budget: If the choir or organization doesn’t already own the required smartphones, you may need to source them. They need not be the latest models – used or older smartphones can work as long as they run the app and have functional flashlights and speakers. Alternatively, you might scale the piece for fewer devices if needed, but note that the artistic intent is designed around a broad distribution (28 devices for a 54-piece choir) to envelop the audience in sound.

Venue Logistics: Consider how the use of phones fits into your venue. Dimming the house lights is crucial to make the flashlight effects visible. Check if any Wi-Fi restrictions exist (some halls may have congested signal environments – using our own router usually avoids this). Also, think about sound projection: 28 phones can create interesting localized sounds, but they won’t replace a PA for very loud effects. If needed, subtle amplification or positioning of devices can enhance audibility (for example, placing a phone near a microphone if you want its sound picked up).

Permission and Safety: Using smartphones should be safe and straightforward, but remind performers of basic etiquette: silence notifications, secure their device (to not drop it), and be mindful of not shining lights in each other’s eyes. From an audience perspective, ensure that the flashing lights are not so intense as to cause discomfort (the piece can be adjusted if there’s concern about sensitive viewers – e.g., avoid very rapid strobe patterns).

Collaboration with the Composer: If you’re taking on this piece, coordinating with Jon D. Nelson (the composer) or the tech team is recommended. As this system is custom-built, they can provide updated software, support, or even be on-site to run the tech during performances. The README and documentation will continue to evolve as the software is refined through its premiere and subsequent performances.

Flashlights In The Dark offers an exciting blend of visual, electronic, and vocal elements. With proper preparation, your choir can deliver a performance that captivates both the ears and eyes of the audience. This README should provide a solid starting point for understanding the system. For detailed technical guidance, refer to the AGENTS.md document (intended for developers/technicians) and the comments within the code if you are exploring the software. Good luck, and enjoy the intersection of choral tradition and technological innovation that this piece represents!

# Deployment Tools and Repository

(This section provides a brief overview of the developer tools included in the project repository, for those interested. Choir directors may not need to use these directly but having an idea of what’s under the hood can be helpful when coordinating with tech staff.)

Repository Structure: The project’s code is organized into multiple parts – a Flutter mobile app (flashlights_client), a macOS control application (FlashlightsInTheDark_MacOS), and various scripts for deployment and testing. The source code is open (for commissioned use) and documented to facilitate maintenance and future adaptations.

Flashlights Client (Mobile App): A cross-platform app written in Dart/Flutter. It uses plugins for accessing the flashlight (torch_light), playing audio (just_audio), recording audio (mic_stream), and network communication (osc for OSC messages). When you launch the app on a phone, it immediately starts listening on UDP port 9000 for OSC messages and sends out a broadcast /hello announcement. The UI is minimal – it primarily shows the piece title, connection status, and the device’s assigned ID. There is also a hidden dropdown for overriding the ID in case a phone needs to be manually re-assigned (for example, if two phones got mixed up, one can select its correct “Singer #” from the list).

Conductor’s Console (Mac App): A Swift application that provides a user interface for controlling the piece. It’s effectively the “control panel” for all the phones. The console displays a list or grid of all 54 possible device slots, highlighting which ones are active. Each device entry shows the singer’s name (if given), and indicators if the flashlight is currently on or if a sound is playing on that device. The software allows the operator to trigger events either via mouse/keyboard or by reacting to MIDI. For instance, clicking on a device’s icon could toggle its flashlight; selecting a preset sound and clicking “Play on All” could send that sound to all phones. There are also grouping functions (e.g., trigger a predefined group of 3 devices with one button – these groups correspond to certain musical clusters in the score).

MIDI Integration: The control software can appear as a virtual MIDI device (“Flashlights Bridge”) on the Mac. This means you can route MIDI from a DAW like Logic or Ableton into the Flashlights app. Each relevant MIDI note or control change can correspond to an action (for example, Note C2 might map to turning on all lights, or a range of notes might map chromatically to different phones’ flashlights). The app uses a specific mapping (embedded from earlier prototypes) where a 32-note range is mapped to the 28 actual device slots in a musically convenient way (skipping unused slots). This mapping aligns with the composer’s intended scale and chords for the piece. Additionally, certain MIDI CC messages (like the sustain pedal) are mapped to global functions (e.g., sustain could latch lights on until released).

Automation and Scripting: The repository includes Python-based prototype tools such as Flashlights_Midi_Panel_Simulator.py, which was an earlier GUI to simulate the system. While the final performance will rely on the native Mac app, these tools were invaluable during development to test the concept quickly. They also serve as a backup: for instance, the Python OSC sender script can manually send flashlight commands if needed. The presence of these scripts means the project can be operated in a pinch even outside the Mac app (via command-line or different OS), though with less convenience.

Clock Synchronization: Both the Mac software and the mobile app implement a simple clock sync mechanism using OSC time tags (NTP format). The Mac periodically sends a /sync message containing its current time; each phone calculates the difference between its local clock and the received time and slowly adjusts for any drift. This keeps all devices within a close temporal alignment for the duration of the performance. In practice, this is hands-off and just improves reliability of simultaneous events.

Logging and Monitoring: The Mac console logs each OSC message it sends and each “hello” it receives from devices. This is useful for debugging (for example, if one phone isn’t responding, you can see if it sent a hello or if it missed a command). We recommend saving these logs for the first few rehearsals to identify any patterns of technical issues (like a particular device that tends to disconnect – you might then swap it out).

By covering the above points, this README has aimed to give both a broad conceptual understanding and a practical guide to using Flashlights In The Dark in performance. The piece represents a fusion of choral music with interactive technology, and while it introduces new logistical challenges, it offers an exciting palette of artistic possibilities. With careful preparation and the provided tools, an ensemble and its director should feel empowered to bring this innovative work to life. Enjoy exploring and please reach out to the composer/development team with any questions as you get ready to shine some lights in the dark!
