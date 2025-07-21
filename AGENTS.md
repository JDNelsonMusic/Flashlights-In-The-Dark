AGENTS.md
Technical Overview and Code Structure for Flashlights In The Dark Document Purpose: This document is intended for developers, technical collaborators, or AI assistants (like GitHub Copilot, OpenAI Codex, etc.) who need a comprehensive understanding of the Flashlights In The Dark codebase. It outlines how the repository is structured, explains the key components and their interactions, and provides insight into the design decisions behind the implementation. This will help anyone diving into the code to navigate it efficiently and make informed modifications or debugging.
High-Level Architecture
Flashlights In The Dark is a multi-part system combining a mobile client application (for the performers’ devices) with a conductor’s control application (for the central computer), along with various support scripts and tools. The communication between the conductor’s app and the mobile clients is done via Open Sound Control (OSC) messages over UDP on a local network. Additionally, the system integrates MIDI for input/output to facilitate musical control. The codebase can be thought of in three main layers:
Mobile Client (Flutter/Dart, cross-platform): Listens for OSC commands and executes actions on the smartphone (flashlight, audio, etc.).
Conductor’s Control Software:
Mac/Desktop Application (Swift, SwiftUI + Combine, macOS specific): Provides a user interface and logic for sending OSC messages to clients, handling MIDI I/O, and managing device states. This is the primary control program for real performances.
Python Prototypes (Tkinter GUI and scripts, cross-platform): Early versions and utility scripts that can simulate or send OSC commands. These are not used in the final performance environment but are useful for testing and understanding the control logic.
Deployment and Configuration Tools (Python scripts, Fastlane, etc.): Automate tasks like registering devices, installing the mobile app on devices, and maintaining the device mapping (slot assignments).
Below is a detailed breakdown of the repository contents and how each part functions.
Repository Structure
graphql
Copy

Flashlights-In-The-Dark/
├── FlashlightsInTheDark_MacOS/       # macOS Conductor's app (Swift, Xcode project)
│   ├── Model/                        # Data models representing devices and possibly other structures
│   ├── ViewModel/                    # The core logic and state management (uses Combine/SwiftUI)
│   ├── View/                         # SwiftUI views for the user interface
│   ├── Network/                      # OSC networking layer (sending/receiving OSC)
│   ├── Resources/                    # Resources like the device mapping JSON, possibly sounds for Mac (if any)
│   ├── AppDelegate.swift             # Handles app lifecycle and global key event capturing (for keyboard control)
│   └── FlashlightsInTheDark.xcodeproj# Xcode project file for the Mac app
├── flashlights_client/               # Flutter mobile client app for iOS/Android
│   ├── lib/
│   │   ├── main.dart                 # Flutter app entry point and UI initialization
│   │   ├── network/
│   │   │   ├── osc_listener.dart     # OSC listening logic and handlers on the client
│   │   │   └── osc_messages.dart     # (If present) structured representations of OSC messages (not heavily used on client side)
│   │   ├── model/
│   │   │   └── client_state.dart     # Client state management (holds connected status, current slot ID, etc.)
│   │   ├── color_theme.dart          # Defines app theme colors (background and highlight colors matching aesthetic)
│   │   └── version.dart              # App version info
│   ├── android/                      # Android-specific code and config
│   │   ├── app/src/main/java/.../
│   │   │   └── KeepAliveService.kt   # Android foreground service to keep the app alive in background
│   │   └── build.gradle, AndroidManifest.xml, etc. # Standard Flutter Android setup
│   ├── ios/                          # iOS-specific config (Info.plist, Runner Xcode project for Flutter embedding)
│   ├── windows/, macos/, linux/, web/ # Flutter desktop/web scaffolding (unused in performance, but present as Flutter supports it)
│   ├── pubspec.yaml                  # Flutter project configuration (dependencies listed here)
│   └── available-sounds/             # Directory for audio assets to be played on phones (e.g., tone samples, etc.)
├── scripts/                          # Deployment and utility scripts
│   ├── choir_onboard.py              # Python script for onboarding a single device (registers it and assigns a slot)
│   ├── choir_onboard.sh              # Bulk Android deployment & device mapping (legacy iOS support via fastlane)
│   ├── Brewfile                      # List of Homebrew dependencies for the project (cfgutil, fastlane, etc.)
│   └── (possibly other helper scripts or files for deployment)
├── Flashlights_Midi_Panel_Simulator.py # A standalone Python GUI application to simulate the lighting control via MIDI/keyboard
├── Little_OSC_Test-sender.py         # A simple Python script/GUI to send test OSC messages (flash on/off) to clients
├── fastlane/                         # Fastlane configuration for iOS device registration and code signing
│   ├── Fastfile                      # Defines lanes: register_device, sync_code_signing, reexport IPA
│   └── README.md                     # (Auto-generated) Info about fastlane usage
├── FlashlightsInTheDark.xcworkspace  # (If present) Combined workspace for Xcode if needed
├── flash_ip+udid_map.json            # JSON mapping of device slots to UDIDs, IPs, and names (generated during onboarding)
├── README.md                         # (Original readme – replaced by the content we’re improving on)
└── AGENTS.md                         # This technical overview document

Next, we’ll dive into each major component and explain how it works internally.

Mobile Client Application (flashlights_client)
Platform: Flutter (Dart) – runs on iOS, Android, and can be compiled for other platforms if needed. Purpose: Listens for OSC commands from the conductor’s computer and executes actions on the device (turn flashlight on/off, play/stop sounds, record audio snippet). It also announces its presence to allow the conductor’s app to detect and map it. Key elements of the client:
OSC Listener: Implemented in lib/network/osc_listener.dart. When the app starts, it creates a singleton OscListener that:
Binds to UDP port 9000 on all interfaces and enables broadcast listening.
Continuously listens for incoming UDP packets on that port. When a packet is received, it’s parsed as an OSC message (the code includes a custom _parseMessage method to handle the basic OSC binary format into an address and arguments).
For each recognized OSC address, it dispatches to a handler:
/flash/on – Turn on the flashlight if the message’s target ID matches this device’s ID. The Flutter app uses the torch_light plugin to control the camera flash. Because most phone flash APIs only support on/off, any intensity value in the message is currently ignored (the message format includes intensity for future expansion or screen-dimming, but right now we treat it as on/off).
/flash/off – Turn off the flashlight (if target ID matches the device).
/audio/play – Play an audio file on the phone. The message includes the target ID, a filename, and a gain (volume) value. If the ID matches this device, the app will:
Look for the audio file in its bundled assets (the available-sounds directory in the app package). Filenames might be things like “a5.mp3”, “c12.mp3” corresponding to different tone sets and slot numbers (more on naming convention below).
Use the just_audio plugin to load and play the asset. The gain (0.0 to 1.0) is applied to the player’s volume. If the asset isn’t found but the filename looks like a URL, it will attempt to stream from URL (this allows flexibility if we wanted to host sounds externally, though in practice all needed sounds are packaged in the app).
Update a audioPlaying state variable (so the UI can show a music note icon when a sound is playing).
The audio player is a single instance; if another /audio/play comes in, it will stop the current sound and play the new one (no layering on a single device unless we add multiple players).
/audio/stop – Stop playback on the phone (if ID matches). This simply calls stop on the audio player and updates state.
/mic/record – Activate the microphone for a short duration. The message provides a target ID and a duration in seconds. If it matches this device, the app uses the mic_stream plugin to start capturing raw audio from the microphone. It doesn’t save or transmit this audio (the data is just read and discarded); after the specified duration, it stops. This feature was included for experimentation (to see if real-time capture for local analysis or future expansion is viable). The app sets a recording flag to true during recording (though in the current UI, we don’t expose a lot of mic status).
/set-slot – Dynamically reassign this device’s slot ID. The message might contain a new slot number that this phone should consider itself as. Upon receiving, the app updates its internal myIndex (ID) to the new number. This can be useful if, for instance, two devices were swapped and the conductor wants to correct their IDs remotely, or to re-map roles on the fly.
/sync – Time synchronization message. The conductor sends out an NTP timestamp (as a 64-bit value representing seconds since 1900) in this message. The phone calculates the difference between the received time and its current local time. It then computes a running average offset (client.clockOffsetMs) that smooths out jitter. We don’t actually adjust the device clock; instead, this offset could be used to schedule future events accurately. For example, if the conductor sends “play sound X at time T”, each phone can add its offset to T to get the correct local trigger time. (In this system, we haven’t implemented scheduled future events yet – we trigger in real-time – but the clock sync lays groundwork for tight simultaneous scheduling.)
/hello – Heartbeat/announcement message. The phone treats any incoming /hello as a signal that the connection to the server is alive and well. The app sets its connected status to true when a hello is received, and if it doesn’t hear any for a few seconds, it will mark itself disconnected. In practice, the phone also sends out /hello broadcasts (see below), but hearing one from the server can also update UI status.
Broadcast Announcements: The client’s OscListener periodically sends out a broadcast message: /hello with its own ID. This is done every 2 seconds (using a Timer.periodic). It sends to the address 255.255.255.255:9000 (as well as each subnet’s broadcast address as a fallback, to work with routers that don’t propagate global broadcasts). The broadcast mechanism means the conductor’s computer doesn’t need to know each phone’s IP – as long as they’re on the same subnet, it will get these hello messages. Each hello includes the phone’s current slot ID so the server can register “device #5 is on the network at IP X”.
The OSC listener runs in the background for the life of the app, and it cleans up on app dispose.
App UI and State (main.dart & client_state.dart): The user interface on the phone is intentionally simple to avoid distracting the singers:
When opened, the app requests permissions for the camera (for flashlight) and microphone (for the mic feature) on iOS/Android.
The UI (in main.dart) shows the title “Flashlights In The Dark” and a text status line that updates with the app version, platform, and connection status (“Connected” or “Searching…”) – this status is driven by a ValueListenable<bool> (client.connected) which is toggled by the OscListener when it hears from the server.
It also displays “Singer #X” where X is the device’s slot number. This number is stored in client.myIndex (a ValueNotifier). Normally, the slot is determined automatically during device onboarding (we assign in the JSON and ideally the app could load that if bundled, but currently each client defaults to an ID from the map or 0 if not set). For flexibility, the UI includes a dropdown list of possible slots (the list of 28 “real” slot numbers) so a user can manually select their correct identity if needed. This is mostly a debugging/assignment feature – in performance, we aim to preset these IDs.
Two icons are shown: a flashlight icon and a musical note icon. These are indicators only (not buttons). The flashlight icon lights up when the phone’s torch is currently on, and the music note icon lights up when a sound is currently playing. These use ValueListenableBuilder widgets bound to client.flashOn and client.audioPlaying states, respectively. This gives the performer visual feedback that a command was received (useful if, say, they need to know when their sound has started or ended, though typically they can hear it).
At the bottom of the UI is a small credit text.
There are no interactive controls required by the singer – the app is essentially autonomous once launched.
Persistence: The Flutter client doesn’t persist state between runs (no need to save anything permanently). If it needed to remember its assigned slot, that could be added (for example, saving the last used slot in local storage so that on relaunch it keeps the same ID). Currently, the slot could reset if the app restarts unless the conductor uses /set-slot or the manual dropdown again. In practice, before a performance, the tech can set all phones to the correct slot once and it shouldn’t change as long as the app stays open.
Packages and Plugins (from pubspec.yaml):
osc – Provides basic OSC networking capabilities (sockets). Note: We wrote a custom parser instead of using a higher-level OSC server in Dart due to wanting fine control and because the OSC package is minimal.
torch_light – Enables flashlight control. Simple API: enableTorch() and disableTorch().
just_audio – High-level audio playback library supporting assets and URLs.
mic_stream – Gives raw microphone stream access.
permission_handler – Handles runtime permission requests for camera and mic on both Android and iOS.
The app is built with Flutter 3.10+/Dart 3, which allows modern language features and robust iOS/Android integration.
Android Specifics: On Android, apps can be killed if they go to background. Since a singer might accidentally turn off the screen or switch apps, we use a foreground service (KeepAliveService.kt) to keep the process alive. This service is started via a platform channel call (MethodChannel('ai.keex.flashlights/client')) in main.dart after getting permissions. The Kotlin service simply shows a persistent notification “Flashlights Client is running” and ensures the app isn’t killed by the system while idle. (On iOS, we can’t run indefinitely in background unless we pretend to be a specific type of app like audio-playing or navigation; for now we assume the app stays foreground or screen stays on. In rehearsals, one might set auto-lock to never or just ask singers to keep it awake.)
iOS Specifics: The iOS app is generated by Flutter. We have to include the camera usage description in Info.plist (for torch) and microphone usage description. Distribution is handled through TestFlight, so singers simply install the TestFlight build once invited.
Asset Management: The available-sounds/ folder in flashlights_client would contain audio files (e.g., MP3 or WAV). The naming scheme, as hinted by the Mac code, is likely a<slot>.mp3, b<slot>.mp3, etc., corresponding to different tone sets (A, B, C, D) for each slot number. For example, device slot 5 might have a5.mp3, b5.mp3, etc., which are different notes or sounds that that phone can play for different musical sections. These files would be included in the app bundle via pubspec.yaml. (In the current repository snapshot, the sounds might not be present or are represented generically – they could be added closer to final rehearsals). The app logic simply plays whatever file name it’s told; it doesn’t generate audio tones on the fly, so all needed sounds should be prepared ahead of time.
Development Note: The Flutter project is standard; one can open it with Android Studio or VSCode and run on a device or simulator for testing. The client app can actually run on desktop too (with flutter run -d macos or windows) for debugging, but obviously flashlight control will do nothing on a PC, and audio will play through the PC speakers. Still, having that desktop capability was useful for quick iteration.
In summary, the mobile client is relatively lightweight. It’s essentially a headless OSC client with a status UI. Most complexity (timing, grouping, logic) happens in the conductor’s software.
Conductor’s Control Application (MacOS)
Platform: macOS (written in Swift, using SwiftUI for the interface and Combine for reactive state, plus SwiftNIO for network and CoreMIDI for MIDI integration). Purpose: This application is the command center. It maintains the list of devices (with their assigned slots and names), shows their status, and allows the user to trigger events (either via GUI or automatically from MIDI input). It handles sending OSC messages out to all clients or specific ones. It also optionally manages building/deploying the mobile apps, though that part is partly handled by external scripts as well. Major components of the Mac app:
Data Model – ChoirDevice: Defined in FlashlightsInTheDark_MacOS/Model/ChoirDevice.swift. This is a simple struct representing a device (singer’s phone):
Properties:
id (Int): A zero-based index (0 for slot 1, 1 for slot 2, etc.). This is used internally and often corresponds to array indices.
listeningSlot (Int): The 1-based slot number that the physical device is listening for. By default we set listeningSlot = id + 1, meaning each device listens to the slot equal to its 1-based index. If we send a /set-slot, this value might change for a given device (e.g., device that had id 0 might now listen to slot 5, so listeningSlot becomes 5).
name (String): The singer’s name or a label for that device.
udid (String): For iOS, the device UDID; for Android, we might leave this blank or use some identifier. This is used to launch or install apps onto that device from the Mac (with flutter run or other tools).
ip (String): The last known IP address of that device on the network. This is filled in from the mapping JSON or via hello messages.
torchOn, audioPlaying, micActive (Bools): Live status of whether that device’s flashlight is currently on, whether it’s currently playing audio, or recording audio. These get updated when we send a command (we optimistically update state) or if we get some feedback (in our current protocol, we don’t have explicit ACKs from phone for these actions, so the Mac app assumes a command succeeded).
isPlaceholder (Bool): Indicates this slot is not actually used by a real device. In our scenario, we have 54 slots but only 28 real devices – the remaining 26 are placeholders. We mark those so the UI can grey them out or ignore them. Placeholders have dummy UDIDs (like all zeroes or containing “x”) and name “”. They simply serve to complete the numbering scheme (some design choices might have the grid symmetric, etc.).
There is a static demo array which initializes the list of 54 ChoirDevice entries. This uses a predefined set realSlots (the 28 actual slot numbers) and marks any slot not in that set as a placeholder. Initially, all names and UDIDs are blank (to be filled in by loading flash_ip+udid_map.json).
Application State (ConsoleState): Found in ViewModel/ConsoleState.swift. This is the central class that holds the state of the console and orchestrates actions. It’s marked as an ObservableObject so that SwiftUI views can bind to its published properties. Some key aspects of ConsoleState:
It starts an OscBroadcaster (defined in Network/OscBroadcaster.swift) in a separate Task. OscBroadcaster is an actor that manages the low-level UDP socket for broadcasting OSC messages. The use of Swift’s concurrency (async/await) and actors ensures thread-safe operations on the networking.
It holds an array of devices: [ChoirDevice] (Published) representing all slots (0–53). This is initialized with ChoirDevice.demo (so with placeholders).
It loads the mapping JSON (flash_ip+udid_map.json) on startup via refreshDevices(). This JSON is expected to have entries for each slot number as keys. The console parses it and updates the corresponding ChoirDevice entries with the known name, UDID, and maybe IP. This gives context of which device is which. If the JSON isn’t found or a slot is missing, those entries remain blank.
It maintains a dictionary of statuses: [Int: DeviceStatus] that track build/run status for each device (this is more relevant if the app is used to deploy or launch apps on devices). DeviceStatus is an enum (Clean, Build Ready, Build Failed, Run Failed, Live, Lost Connection). When the devices connect (send hello), we mark them Live. If we haven’t heard in a while, we mark lost connection, etc.
MIDI Manager: It instantiates a MIDIManager class (not shown in snippet but implied by usage in AppDelegate and ConsoleState). This likely wraps CoreMIDI to list available MIDI ports and to send/receive messages. ConsoleState keeps lists of input/output MIDI device names and allows selection. It also provides handlers for incoming MIDI messages (note on/off, CC) which call methods like handleNoteOn/handleNoteOff (likely mapping those to triggering lights/sounds in UI as well as possibly echoing to OSC).
Output Channel: There is a notion of an output MIDI channel (default 1). When sending MIDI out (for example, echoing a triggered event as a MIDI note to external synth), it uses this channel.
Logging: midiLog (Published [String]) holds recent MIDI message descriptions for debugging. lastLog (Published String) holds a human-readable last action or status (e.g., “Ready – tap a tile” or “/audio/play [5 file.mp3] sent” etc., to show feedback in UI).
Triggered/Glowing Slots: The console visualizes feedback for triggers:
triggeredSlots (Set<Int>) – slots currently pressed via keyboard (this might highlight them).
glowingSlots (Set<Int>) – slots that should “glow” briefly when a signal is sent (to give a blink effect in UI). There are functions glow(slot:) which adds a slot to glowingSlots then removes it after a short delay.
These are purely for UI representation so the operator knows something was triggered.
Keyboard Trigger Mode: An enum (Torch, Sound, Both) that determines what happens when the operator presses a key on the keyboard. In Torch mode, keyboard keys will only flash lights; Sound mode will only play sounds; Both does both on the respective device. This is a convenience for testing or performance – e.g., one can decide to use the computer keyboard to either flash lights like a “light piano” or to send sounds to phones like a “sound sampler”, or both simultaneously.
Triple Triggers (Preset Groups): There’s a tripleTriggers dictionary (same mapping as groupSlots in AppDelegate) which maps numbers 1–9 to groups of 3 slot numbers (the “triple trigger group”). The idea is that pressing function keys (F1–F9) will trigger three devices at once (e.g., a triad of lights/sounds). These groups were likely chosen to correspond to particular chords or voice-part groupings in the composition.
OSC Send Functions: ConsoleState has methods that interact with the OscBroadcaster actor to send messages:
e.g. flashOn(id: Int) – Marks the device’s torchOn state, and asynchronously sends an OSC /flash/on message targeted to that device’s slot. Under the hood it calls something like osc.send(FlashOn(index: id+1, intensity: 1)). It uses the actor’s send method which broadcasts to all or specific addresses. Because we give the slot number, the phones themselves filter if it’s for them.
flashOff(id: Int) similarly sends /flash/off.
triggerSound(device: ChoirDevice) – Sends one or multiple /audio/play messages to the device’s slot. The code here loops through active tone sets (A, B, C, D) that are currently selected (ConsoleState has activeToneSets: Set<String> which the UI can control—this allows layering multiple sound sets). For each active set, it constructs a filename like "a<slot>.mp3", "b<slot>.mp3", etc., and sends an OSC message with that file and a gain (set to 1.0 now, but could be dynamic). It also logs the action, and for each tone set it sends a corresponding MIDI note-on (this is interesting: they derive a base MIDI note from device.id * 4 and an offset per tone set (A=0, B=1, C=2, D=3). This suggests each device corresponds to a cluster of 4 MIDI pitches, one for each tone variant. Potentially, this could be used to route to a synth for monitoring or reinforcement of what the phones play).
stopSound(device: ChoirDevice) – Sends /audio/stop for that slot (stopping any sound on that phone). Also sends corresponding MIDI note-offs for the cluster of notes associated with that device (to stop any sustained external sound).
These OSC send calls are asynchronous (they use Swift concurrency). The UI can fire them without blocking.
Clock Sync: Upon creating the OscBroadcaster, ConsoleState also creates a ClockSyncService (not fully shown in snippet, but we see self.clockSync = ClockSyncService(broadcaster: broadcaster)). Likely this service is an async task that periodically sends /sync messages containing the current time. The code might use OSCKit’s OSCTimeTag for an accurate timestamp. Possibly every couple of seconds it broadcasts a sync (maybe aligned to when the phones send hello).
Device Discovery & Status Updates: The console listens for incoming /hello messages from clients. The OscBroadcaster has a callback for inbound data (see HelloDatagramHandler in OscBroadcaster.swift, which calls owner.emitHello(slot: ip:) on the actor). The ConsoleState probably registers a handler via osc.registerHelloHandler to get notified when a device says hello. When that happens:
If the slot is known and matches one of our devices, we mark that device as connected (DeviceStatus -> .live, and maybe update its IP if changed).
We might also use the dynamic IP info to allow targeted unicast sending. The OscBroadcaster keeps dynamicIPs[slot] up-to-date. When sending messages, the broadcaster’s send method does broadcast to all, but there’s also sendUnicast(toSlot:) which can directly send to a specific IP if known. This could be used if we wanted to send heavy traffic (like an audio stream) to just one device rather than broadcasting. As of now, we mostly broadcast small control messages, which is fine.
If a device hasn’t said hello in >2 seconds, the broadcaster triggers a disconnect callback, and ConsoleState can mark that device as .lostConnection (and the UI might color it differently). The system is robust to brief dropouts – as soon as the phone sends hello again, it’ll flip back to live.
Automated Build/Run (Experimental): The presence of runProcesses and the DeviceStatus enum implies the Mac app can initiate building or launching the Flutter app on connected devices. It’s not fully fleshed out in the excerpt, but possibly:
The Mac app might call flutter run -d <udid> for each iPhone to launch the app in debugging mode (this requires devices to be connected via USB or on same network with some tools like ios-deploy). Similarly for Android via adb.
runProcesses[Int: Process] could track subprocesses for each device running a flutter run or similar command, so we know if it’s running and can kill it later.
This approach is ambitious (launching 28 Flutter debug sessions is heavy). More likely, this was attempted for small scale testing or an alternative to using TestFlight. In practice, using the pre-built ad-hoc app is more practical for performance. But for development, having a one-button “build & launch all devices” is a cool idea.
In ConsoleState, there might be methods like buildAll() or runDevice(slot) that call out to shell scripts or Fastlane. The code snippet around lines 290+ in ConsoleState shows some context of reading process output “[Build&Run] ...”.
The DeviceStatus values “Build Ready”, “Build Failed”, “Run Failed”, etc., would be set according to those operations. This part of the system is likely in progress or optional. It doesn’t affect performance once devices are already set up, so it can be ignored unless actively using the Mac app to manage device deployment.
OSC Networking (OscBroadcaster): Implemented as an async actor in Network/OscBroadcaster.swift.
When initialized, it reads the flash_ip+udid_map.json from the app bundle (that’s the routingFile parameter default). It decodes that into a dictionary of slot -> SlotInfo (which contains ip, udid, name). This gives a static reference of known IPs (maybe from last wired sync) but note: if IPs change (DHCP, etc.), those can be outdated. However, the actor also tracks dynamicIPs which are updated whenever it hears a /hello from a device at runtime (mapping slot -> the source IP of the hello packet). This ensures we always have a current address for each device that’s online.
It binds a UDP socket to port 9000 on 0.0.0.0 (all interfaces), similar to the client. It enables broadcastEnabled so it can send to x.x.x.255 addresses.
It gathers all local broadcast addresses: this means if the Mac has multiple network interfaces (Ethernet, Wi-Fi, etc.), it will compute the broadcast address for each (replacing last octet with 255 for IPv4).
It adds a HelloDatagramHandler to the pipeline, which likely inspects incoming packets for “/hello” messages and if found, extracts the slot (and maybe expects the message might contain the hostname or something – but the phone currently sends just an int slot argument). The handler then calls oscBroadcaster.emitHello(slot, ip) where ip is the source IP of the datagram.
The actor provides:
send(OSCMessage) to broadcast a given OSC message to all broadcast addresses. We typically use this for cues since the phones all listen to broadcast.
sendUnicast(OSCMessage, toSlot:) to send directly to a single device. It checks dynamicIPs for that slot (preferring runtime info) or falls back to the static slotInfos (from the JSON) for an IP. If found, it sends just to that IP. If not, it falls back to broadcast (so the device will still get it along with others).
registerHelloHandler(callback): Allows ConsoleState to supply a closure to be notified when a hello arrives. This callback is executed on every /hello reception, giving the slot and IP.
announceSelf(): The Mac, upon starting, also sends out a /hello message containing its hostname and an integer (they set slot=0 or a special value via a user default key "slot"). This isn’t strictly necessary for function, but it lets clients know “a server is here.” We saw the client simply marks connected when seeing any /hello, which includes this server announcement. So the Mac’s announceSelf essentially flips all connected apps to “Connected” state immediately once the server is up.
The Mac does this announce once at startup (and possibly we could call it periodically, but it might rely on the clients’ periodic hello to maintain connection).
SwiftNIO is used for UDP: it’s efficient and gives us async handlers. The code handles things in an actor to ensure single-threaded access to the socket. The printouts (like “UDP broadcaster ready” and each send printing → /flash/on to 192.168...) are handy for debugging. In a GUI, those messages might be routed to a console view.
User Interface (SwiftUI Views):
The main UI likely has something like ComposerConsoleView (which appears in search results) that uses a grid or list to display each ChoirDevice entry. It would show their name, slot number, and have controls for flashlight and sound.
There may be an interactive grid of tiles (54 tiles) visualizing each slot as a small square or circle (like the LampGrid in Python prototype). Active devices might be colored differently than placeholders.
The UI likely highlights any slot in triggeredSlots (e.g., if the operator is holding a key down corresponding to that slot, show it pressed) and maybe outlines those in glowingSlots when a command is sent, briefly.
There will be controls to select which tone sets (A, B, C, D) are active – perhaps toggles or buttons so the operator can choose which samples to trigger for sounds.
There might be buttons for group triggers (F1–F9 mapping) if not solely via keyboard, or maybe just a note in the UI about the keyboard shortcuts.
The status bar might display lastLog messages to give the operator feedback on actions (like confirming a message was sent or a device connected).
Also UI elements for:
Refresh device list (re-read JSON mapping if devices were added).
Broadcast “hello”/“sync” manually (for testing).
Possibly controlling global envelope (ADSR) parameters for light intensity envelope – the ConsoleState has attackMs, decayMs, sustainPct, releaseMs and an envelopeTask to do a global lamp fade in/out (the AppDelegate mapping for key "0" triggers an envelope on all lights). Likely there is a control to start an All-lamps ADSR envelope: pressing 0 on keyboard triggers all lights on with an envelope (the code in ConsoleState for startEnvelopeAll() and related functions gradually increases intensity by repeatedly sending FlashOn to all devices in small increments, simulating a fade-in since hardware doesn’t support actual dimming).
So the UI might have sliders for ADSR and a button to trigger an all-lights fade (for example, for a particular effect in the piece).
AppDelegate & Keyboard: AppDelegate.swift captures physical key presses even when the SwiftUI view might not by default (especially for function keys, etc. – SwiftUI might not handle global shortcuts easily, so they used an NSApplicationDelegate to intercept).
It maps F1–F9 key codes to group numbers and calls state.triggerSlots(realSlots: [slot, slot, slot]) for those groups (which likely sends FlashOn for those three slots, possibly one after the other or simultaneously). The state.triggerSlots may either spawn tasks to send or directly call flashOn on each.
It maps number and letter keys to individual slots using a dictionary identical to the Python key_to_slot. When a key is pressed (KeyDown):
If it’s already held, ignore repeats (ensures one trigger per key press).
Mark the slot as held (so repeated keyDown doesn’t retrigger until keyUp clears it).
Remove it from sustained list (if it was there from a previous pedal hold).
Depending on keyboardTriggerMode, call flashOn(id:) and/or triggerSound(device:) for that slot.
Also send a MIDI Note On out using the scale mapping (this is to echo to perhaps an external synth or just a virtual MIDI out for recording what was triggered).
On KeyUp:
If sustain pedal is on (spacebar), we don’t turn off immediately; we remove from held but add to sustained list (meaning it will remain lit/sounding until pedal release).
If sustain pedal is off, we call flashOff(id:) and/or stopSound(device:) for that slot, and send MIDI Note Off for the corresponding note.
The mapping of keyboard letters to slots is crafted such that they correspond to musically meaningful groupings (likely aligning with the composer’s desired layout on a QWERTY keyboard for convenience).
Spacebar toggles the sustainOn boolean. When space is pressed down, sustainOn = true and a MIDI CC 64 (sustain pedal) with value 127 is sent out (e.g., to an external synth if needed). On release of space, sustainOn = false, and for all slots in sustainedSlots, it issues flashOff/stopSound and cleans up. Also sends MIDI CC 64 with 0.
This mechanism mimics a piano-style sustain pedal for lights/sounds. Practically, it allows the operator to, say, press a bunch of keys to turn on a chord of phone lights, hold them by pressing space (so they stay on after releasing keys), then release space to turn all off together. This is a very useful performance control to create sustained light scenes or chords without having to keep keys pressed.
MIDI Integration Details:
The Mac app likely uses CoreMIDI via a wrapper (MIDIManager). It creates virtual MIDI ports named something like “Flashlights Bridge” and “Flashlights Bridge In” (we see filtering out of names "Flashlights Bridge" in refreshMidiDevices to avoid listing itself).
Virtual MIDI Out: The app probably creates a virtual MIDI output to send signals to other software or hardware. For example, when the operator triggers a phone sound or light, it also sends a corresponding MIDI note (this could be connected to a DAW to record the performance automation, or to a synth to augment phone sounds).
Virtual MIDI In: Similarly, it creates a virtual MIDI input port to receive MIDI from other software. This means a DAW could send a track’s MIDI notes into “Flashlights Bridge In” to automate the phone cues. The midi.noteOnHandler in ConsoleState is set up to handle incoming notes: it calls handleNoteOn(note: velocity:), which likely just calls the same logic as if a key was pressed (mapping note to slot and triggering).
The note mapping likely assumes a certain MIDI note range corresponds to the 32 (or 54) slots. Given baseNote = 36 (C2) and their noteOffsets (0,1,3,4,7,8,10,11) across octaves, they essentially define a custom scale for mapping MIDI to slots:
If a MIDI Note On is received, handleNoteOn would translate the note number to a slot: they likely use the inverse mapping of what they do for sending. In AppDelegate, they compute noteOut = baseNote + octaveOffset + offset for triggers. For input, the code in midi_in_worker (Python) and presumably in MIDIManager or ConsoleState might map incoming note to slot by checking if it matches CFG.all_note (84 for “ALL lights” maybe) or one of the note numbers in the grid.
Actually, we see in Python midi_in_worker: if msg.note == CFG.all_note (84) they queue "ALL". If note in note_to_slot, they queue that slot. So similarly, the Mac app’s handleNoteOn likely uses the same noteOffsets and base to determine slot. It could do:
If note corresponds to the special “all lights” note (they defined all_note = 84 which is C6 if base was C2 and 4 rows of 12 – indeed 36 base + 48 offset = 84), then turn all on.
Otherwise calculate row = (note - baseNote) / 12, offset = see if (note mod 12) is in the noteOffsets list, and find the corresponding column index. Then slot = row*8 + col (if note fits the pattern). This yields a slot index 0–31. If the note doesn’t match the scale, ignore.
Given that mapping, a composer could prepare a MIDI file such that a certain track’s notes trigger the exact intended devices at the right times.
The Mac app echoes outgoing OSC as MIDI CC too in flashOn (it does midi.sendControlChange(control=id+1, value=127)) and presumably in flashOff (maybe CC with 0). This might be for feedback into a lighting console or recording which lights are on. Using control change with controller number = slot ID is an interesting choice – it could be so an external system (like a DMX lighting board or visualization) can represent each phone light as a channel with 0/127 = off/on.
All these MIDI integration points make the system flexible in a larger production environment, allowing interfacing with other software or simply logging the performance data.
UI and Concurrency: The Mac uses SwiftUI/Combine, meaning the UI updates automatically when @Published vars change (like device statuses, connection flags, etc.). Because OSC and MIDI events might come on background threads, many handler closures use Task { @MainActor in ... } or DispatchQueue.main.async to update Published properties (ensuring UI thread update). The OscBroadcaster actor calls the helloHandler on the actor’s context by default (which might not be MainActor), so the closure might do a Task { @MainActor in ... } inside. We saw e.g., in triggerSound, they capture self.lastLog = "..."; self.glow(slot:) via await MainActor.run { ... } to update UI after sending.
There is careful use of Swift’s concurrency to not block the UI. E.g., sending OSC is awaited but done in a detached Task, etc. The Combine pipelines keep track of devices’ torchOn etc., so toggling devices[idx].torchOn.toggle() (with objectWillChange.send()) triggers UI icon change.
Device Onboarding Integration: While primary device onboarding is via external script, the Mac app could incorporate that:
The Mac app has the static JSON of devices (with placeholders). After running choir_onboard.sh, that JSON in the app bundle would need to be updated (meaning you’d rebuild or repackage the Mac app with the new JSON if it’s embedded as resource). To avoid rebuilding, they might locate the JSON in a known file path (not just bundle) – possibly in the working directory or a predetermined location (ConsoleState looks for Bundle.main.url(forResource: "flash_ip+udid_map", withExtension:"json")). If running from Xcode, it uses the bundled one. If they update that file and rebuild the app, it includes new devices.
Alternatively, they might plan a UI to load an updated mapping file (maybe via a “refresh devices” button that reads the JSON from the project directory if running in dev mode).
The app previously supported invoking fastlane register_device, but with TestFlight distribution this step is rarely necessary and onboarding is typically handled outside the app.
Summary of Mac App: It’s a fairly sophisticated console combining network, MIDI, and UI. It translates user inputs (keyboard, UI actions, or MIDI messages) into OSC commands that control the phones. It keeps track of state to provide visual feedback and ensures devices are in sync. The design borrows some concepts from the Python prototype (like mapping and sustaining) but takes advantage of Swift’s modern features for concurrency and SwiftUI for a dynamic interface.
Python Prototypes and Utilities
Even though the Mac app is the primary performance tool, the repository contains Python-based tools which serve both as documentation of logic and as backup/testing utilities:
Flashlights_Midi_Panel_Simulator.py: This is a Python 3 GUI application using Tkinter (with ttk for styling). It simulates a 32-lamp grid (4 rows x 8 columns) which correspond conceptually to the 32 core notes of the chosen musical scale (even though we have 54 slots, the original design focused on 32 active note positions, excluding some that might not fit a scale).
It displays a grid of lamp indicators (circles) on screen that light up when triggered. This was used to design and test the MIDI mapping and the idea of an "ADS envelope" for lights.
It creates a Virtual MIDI Port named “Flashlights Out” (and a corresponding input “Flashlights In”) using the mido library with the python-rtmidi backend. This is analogous to what the Mac app does with CoreMIDI. The Python program can thus receive MIDI from other software via “Flashlights In” and send out via “Flashlights Out”.
It binds keyboard events: keys 2,3,4,5,... etc. trigger lamp toggles (the mapping dictionary is exactly the same as in the Mac’s AppDelegate for consistency). Space acts as sustain. Enter key commits ADSR edits (if any GUI controls for envelope).
It also supports using an external MIDI controller: any note-on/off that comes in on “Flashlights In” will update the lamps (the code uses note_to_slot mapping to turn a lamp on/off when a MIDI note is received).
When a lamp is toggled on via keyboard or mouse, it sends a MIDI note out (through “Flashlights Out”) with a certain note number (so that external synths or software can respond). This note mapping corresponds to actual musical pitches (so one could plug “Flashlights Out” into a soft-synth to play the chord that the lights are representing).
It includes UI controls for velocity (which might correspond to brightness in a hypothetical analog light scenario, but here mainly to send different MIDI velocities to a synth) and channel selection.
Importantly, this Python simulator does not send OSC to phones – it was built before the OSC network was finalized. It focuses on the MIDI bridging aspect. However, one could extend it to send OSC: for example, on lamp on, also send an OSC message to actual devices. That would require importing something like python-osc’s UDP client. In fact:
There is Little_OSC_Test-sender.py which does use python-osc to send /flash/on and /flash/off to devices. The simulator could integrate similar calls.
Given that the Mac app supersedes this, the Python GUI was likely used for quick experiments in early development. It’s still useful for offline testing or in case someone without a Mac wants to trigger the system via a Windows/Linux laptop (they could run this Python tool to send OSC if modified, since python-osc works cross-platform).
The Python simulator’s code reflects much of the logic that ended up in the Mac app:
The same note_offsets scale and base note.
The sustain logic and all-notes-off panic (they implement an “ALL” note which triggers all lights off).
The grouping of lights into an ADSR envelope (there are spinboxes for Attack/Decay/Sustain/Release in the UI to animate all lamps’ brightness – in Python they simulate brightness by changing the fill color of the drawn ovals gradually).
If needed, this simulator can be connected to the phone clients by bridging MIDI to OSC:
One approach: run the Python simulator and the Little_OSC_Test sender together – the simulator sends MIDI events out, and a small script listens for those and converts to OSC.
Or modify simulator to directly send OSC (not complicated: just send the same messages as Little_OSC_Test when a light toggles).
However, given the Mac app exists, such workarounds might not be used in production.
Little_OSC_Test-sender.py: A very small Tkinter UI that directly sends OSC messages:
It uses python-osc’s SimpleUDPClient to send to a specified IP/port. By default, it suggests using a broadcast address (like 192.168.x.255), but in the code snippet provided, DEST_IP was set to 192.168.0.150 as an example (which could have been a test device’s IP).
The UI has two input fields: Singer ID (integer) and Intensity (float 0–1), and two buttons “Flash ON” and “Flash OFF”.
Hitting “Flash ON” sends /flash/on [id, intensity].
Hitting “Flash OFF” sends /flash/off [id].
It prints or displays the exact packet info sent. This tool is purely for testing that a phone responds to commands. It was used to confirm the phone app lights the torch and to manually try different intensities (even though intensity isn’t used by torch, one could imagine if using phone screen for light, intensity might have mattered).
It also warns if python-osc is not installed.
This script can be helpful for quickly verifying network connectivity and that a specific device is reacting, without launching the full control app.
Device Onboarding Scripts (scripts/ directory):
choir_onboard.py: A Python script that handles one device at a time.
It finds a connected iPhone’s UDID using idevice_id -l (from libimobiledevice).
It can optionally take --udid and --ip if you want to manually specify or do an Android (for Android, idevice_id won’t list anything, so you’d use --udid perhaps as an identifier).
It ensures only one device is connected at a time (to avoid confusion).
It then finds the next available slot in flash_ip+udid_map.json that is empty (the JSON likely initially has placeholders like name “xxx” or UDID “0000...” for unused).
It assigns that slot number to this device, filling in the UDID, name, and IP address, and writes it back to the JSON.
Then it called fastlane register_device with that UDID and name to add it to Apple Dev Portal and updated the provisioning profile. This workflow was used when distributing the iOS build via Ad Hoc profiles.
You’d still need to install the app on each device. With the move to TestFlight, this script is mostly useful for updating the device mapping JSON if needed.
choir_onboard.sh: A shell script for bulk operation.
It scans all connected iOS devices using cfgutil list (Apple Configurator command-line) and extracts UDIDs.
Originally it registered each device via fastlane and installed the IPA using cfgutil. iOS deployments now rely on TestFlight, so these steps are rarely needed.
Scans for Android devices via adb devices and if any are found:
Builds the Flutter app’s APK (flutter build apk --release) if not already built.
Installs the APK on each detected Android.
Updates the flash_ip+udid_map.json: It runs an arp -a scan to get IP and MAC addresses of devices on the network. It then populates the JSON mapping with IP addresses, keyed by device MAC (or merges into existing entries). The script uses Python inline to do this mapping. This suggests:
After installing apps, perhaps you connect the devices to Wi-Fi and then run this script’s end part (or run the script while devices are on Wi-Fi). It will detect their IP/MAC via ARP (if the devices are associated with the Mac via USB or same network).
It writes those IPs into the JSON. So each slot entry in JSON will have UDID, name, and IP.
Output messages (with emojis like 📱, 🤖, etc.) guide through the process.
After completion, it says “singers can unplug” meaning the phones are all set with the app installed and known to the system.
This script is meant to be run once right before a rehearsal when all devices are gathered. It dramatically speeds up what would otherwise be a manual process of adding devices and installing apps one by one.
The script expects some environment setup (like a pre-built IPA path is hardcoded; in practice, we’d adjust that or ensure the IPA is at that location).
The use of Brewfile to install dependencies (fastlane, cfgutil, etc.) is a convenience to quickly set up a Mac for deployment.
fastlane Configuration:
The Fastfile in fastlane/ defines simple lanes:
register_device(udid: , name:) which is essentially a wrapper around Fastlane’s built-in register_device action (which calls the Apple Developer API to add the device to your profile).
sync_code_signing(type:"adhoc") which uses match or automatic code signing to update the provisioning profiles. Likely, they use match or manual manage codesigning – here, they call sync_code_signing which for fastlane’s match means fetch or update profiles. Setting readonly: false suggests it can update.
reexport which re-exports an existing Xcode archive to an IPA (not used in scripts explicitly, but could be handy if you already have an .xcarchive and just need a new IPA with updated profile).
The fastlane is minimal because the actual heavy lifting (like building the app) is done by Flutter’s build system. We likely manually build the Flutter iOS app via Xcode or flutter build ios to produce an archive, then use fastlane to manage devices and re-sign that archive for distribution.
flash_ip+udid_map.json: This JSON is central to tracking devices. Its structure is like:
json
Copy
{
  "1": { "udid": "<device1_udid>", "name": "Singer Name1", "ip": "192.168.0.101" },
  "2": { "udid": "<device2_udid>", "name": "Singer Name2", "ip": "192.168.0.102" },
  ...
  "27": { "udid": "...", "name": "...", "ip": "..." },
  "28": { ... },
  "29": { "udid": "xxxxxxxx", "name": "xxx", "ip": "" },   // placeholders probably filled with "xxx"
  ...
  "54": { "udid": "xxxxxxxx", "name": "xxx", "ip": "" }
}
Initially, after running the onboard scripts, slots 1–28 would be filled with actual data, and 29–54 remain dummy. The Mac app’s bundle should include this or have it accessible to map devices. If a device’s IP changes (for example, it reconnects to network and gets different IP), the dynamic discovery via /hello is relied upon. The static IP here is a fallback or initial knowledge (and helpful for direct unicast if known ahead).
For iOS devices on a closed network without DHCP (if using a Mac’s peer-to-peer or similar), IP may not be easily known until runtime, so the dynamic hello capture is key.
Why specific slot numbers? One might wonder why the 28 “real” slots are those particular numbers (1,3,4,5,7,9,12,...54). This selection comes from the noteOffsets pattern across octaves:
The chosen note offsets: 0,1,3,4,7,8,10,11 correspond to a diatonic scale with chromatic passing tones: basically a major scale plus a minor second and minor seventh in each octave (or some mode). It excludes 2, 5, 6, 9 in each octave (which corresponds to skipping some scale degrees). The exact musical reasoning might be that these notes form particular harmonies the composer wants to emphasize.
When you map those offsets over 4 octaves from base note 36 (C2) to 83 (B5), you get 32 MIDI note values. The mapping from note to slot in Python’s Config means:
Slot 0 -> note 36 (C2)
Slot 1 -> note 37 (C#2)
Slot 2 -> note 39 (D#2)
Slot 3 -> note 40 (E2)
Slot 4 -> note 43 (G2)
Slot 5 -> note 44 (G#2)
Slot 6 -> note 46 (A#2)
Slot 7 -> note 47 (B2)
Slot 8 -> note 48 (C3)
Slot 9 -> note 49 (C#3)
... and so on up to Slot 31 -> note 83 (B5).
Now, the "realSlots" list in ChoirDevice.demo is exactly the set of note values that appear as keys in that note_to_slot mapping plus the “all note” maybe? Actually, checking:
The Python key_to_slot mapping had weird values like 34, 38, etc., which we determined might actually have been mistakes (since slot indices don’t go that high). It turns out, the Mac AppDelegate’s keyToSlot mapping lists those same numbers as “real slot” numbers. Possibly there was a confusion: those numbers above 31 are not slot indices, they are the actual note numbers for the higher slots (e.g., slot 30 corresponds to note 82, but their mapping shows 82 is not listed but 54 is, which wasn’t in the 0-31 scheme).
Actually, looking closely: in ChoirDevice.demo’s realSlots set, the numbers look random up to 54, but they match the key characters mapping. Possibly they mis-labeled: maybe they intended those as slot IDs directly. But since we know the code uses id = index = slot-1 in many places, it’s safe: they treat those realSlots as 1-based indices of actual devices.
The first 28 entries of that realSlots set presumably correspond to the actual devices in ascending order: {1,3,4,5,7,9,12,14,...54}. Maybe they intentionally left gaps for a visual symmetrical arrangement (like maybe in a hypothetical 6x9 grid representing the choir, those indices are spaced out evenly by section or voice? It’s speculative, but e.g., slot 1 and 3 and 4 and 5 might all be in one section cluster, etc).
For our purposes, it means not all numbers 1–54 are used. If a phone got an ID that’s not in that set, it may be considered “unused”.
The conductor software focuses on those 28, and a lot of logic (like F1-F9 groups each of size 3) covers exactly 27 of them (9 groups * 3 = 27, likely leaving one device not grouped or maybe group 9 includes 3 numbers making total 27? Actually group 9 covers [40,53,54] which are three, so indeed 9 groups cover 27 devices; possibly one device (maybe slot 8 which is 23? Actually 23 is in group 7; maybe slot 2 (id1) which is 3 is covered, etc. All given 28 are present in those groups? Quick check:
All real slots: 1,3,4,5,7,9,12,14,15,16,18,19,20,21,23,24,25,27,29,34,38,40,41,42,44,51,53,54.
Groups 1–9 combine:
1:[27,41,42], 2:[1,14,15], 3:[16,29,44], 4:[3,4,18], 5:[7,19,34], 6:[9,20,21], 7:[23,38,51], 8:[12,24,25], 9:[40,53,54].
Collect all these: {1,3,4,7,9,12,14,15,16,18,19,20,21,23,24,25,27,29,34,38,40,41,42,44,51,53,54}.
That set appears to be exactly the 28 except maybe one missing? Let's see: which real slot is not listed? It seems all 28 are present in at least one group; let’s count them. Possibly I missed checking 8? But 8 is not a slot, 8 was a note offset scenario. Actually, the number 8 is not in list, 8 is not used. All numbers in the set are unique and count is likely 27 or 28. Counting quickly: group1(3) + g2(3)+...+g9(3) = 27 unique if disjoint. Are they disjoint? They were chosen likely disjoint. So that covers 27 unique slots. One slot from the 28 might be left out of group triggers, which likely is slot 8 (Singer #8 i.e., device with slot ID 8). Indeed, 8 is not in any group list and also not in the realSlots set (because 8 is not in that set of 28 – correct, 8 was one of the excluded offsets).
Actually, correction: realSlots set doesn’t include 8, includes 7 and 9 but not 8. So slot 8 is placeholder, not a real device. So maybe 27 devices? But we were told 28 smartphones. Let's cross-check: The set has 28 entries (we should count them explicitly):
Counting the values:
Row how many?
In each group list, they skip some. Possibly miscount, let's get number: Provided in code as set literal:
javascript
Copy
let realSlots: Set<Int> = [
    1, 3, 4, 5, 7, 9, 12,
    14, 15, 16, 18, 19, 20, 21, 23, 24, 25,
    27, 29, 34, 38, 40,
    41, 42, 44, 51, 53, 54
]
Put them in order with count:
1,3,4,5,7,9,12,14,15,16,18,19,20,21,23,24,25,27,29,34,38,40,41,42,44,51,53,54.
That's 28 numbers listed (we can count separated by comma: first line 7 numbers (1,3,4,5,7,9,12), second line 8 numbers (14..25), third line 7 numbers (27,29,34,38,40), fourth line 6 numbers (41..54). Actually by lines: (7 + 8 + 5 + 6) = 26 by that breakdown; maybe mis-read newlines:
Let's count properly:
1(1), 3(2),4(3),5(4),7(5),9(6),12(7),
14(8),15(9),16(10),18(11),19(12),20(13),21(14),23(15),24(16),25(17),
27(18),29(19),34(20),38(21),40(22),
41(23),42(24),44(25),51(26),53(27),54(28).
Yes, that’s 28. Good.
And group triggers cover all except one maybe:
Checking which of those 28 is missing in groups: it looks like all group lists union results in skipping maybe one: Did we see 5 in any group?
Group lists:
1: {27,41,42}
2: {1,14,15}
3: {16,29,44}
4: {3,4,18}
5: {7,19,34}
6: {9,20,21}
7: {23,38,51}
8: {12,24,25}
9: {40,53,54}
Union all: let's see what number from realSlots isn't in any group:
5 is not present in any group list above. Indeed group4 had 3,4,18 skipping 5; group5 had 7 but skip 5; looks like 5 was left out.
So probably device slot 5 is not assigned to a triple group (maybe an extra or reserved for a solo? If 28 devices and only triple groups of 3, one will be left over since 28 is not divisible by 3).
Which device is slot 5? Possibly they left out something like maybe the conductor’s own phone or a test device? Or it’s arbitrary.
Anyway, not too important; for completeness, an AI or dev might be curious, but it’s just a design detail.
)
The All note feature: In Python they had ALL_NOTES_OFF_CC = 123 (MIDI CC 123 all-notes-off message) which they send as panic to turn all notes off and all lights off. In Mac, they might similarly have a special handle for note 84 (they did in Python and presumably in handleNoteOff maybe they treat CC 123 or note 84 as all off). The AppDelegate doesn’t explicitly mention All except the “0” key triggers an all-lamp envelope, not an immediate all off. Possibly they rely on the sustain pedal or an explicit UI “All Off” button for panic.
Testing/Running: The repository likely allows:
Running the Flutter app on a device (for development).
Running the Mac app via Xcode or compiled binary.
Using the Python scripts directly by running them with Python 3 (ensuring dependencies installed).
The Mac app has a Tests target (FlashlightsInTheDarkTests.swift) which might have some basic tests (maybe verifying OSC message encoding/decoding, or the mapping logic).
If an AI developer wanted to extend or debug:
For example, to change how brightness is handled, you could modify the mobile client to use the screen with adjustable brightness instead of the torch (which is only on/off).
Or to allow overlapping audio playback, one could give each phone multiple audio players or use a mixer.
Or integrate a streaming microphone feature (like send mic audio back to Mac via OSC or WebSocket).
The code structure is modular enough: the OSC messages and addresses are clearly defined in both Swift and Dart.
The mapping and group logic is all in one place and can be altered if the artistic direction changes (say, use different groupings or more devices).
The Mac app’s use of SwiftUI/Combine means any UI changes should be done carefully to keep state consistent (but since logic is largely in ConsoleState, you can alter state and the UI auto-updates).
The Python prototypes are separate, so changes there don’t affect the Mac or client, but they are good reference or can be used to test ideas quickly in isolation.
OSC Message Protocol Summary
For clarity, here are the OSC addresses used in the system and their payloads (the “language” the conductor’s app and phones speak):
/hello:
Sent by clients: ["<slot_id_int>"] – The phone broadcasts its slot ID periodically. The Mac uses the source IP of this packet to note where that slot is.
Sent by server (Mac): [ "<hostname_str>", <slot_int> ] – The Mac sends a hello containing its name and an int (likely 0 or unused). Phones ignore the content and just mark connected true when they see any hello.
Usage: Announce presence and maintain connection status.
/flash/on:
Arguments: [ <target_slot_int>, <intensity_float> ]. Intensity is from 0–1, but currently phones treat this as binary (if message is received and the ID matches, turn on flashlight).
The Mac always sends intensity=1.0 for now (full on). In the future, if we implement screen brightness or a method to dim, we could use intermediate values and have the client show a proportional brightness (e.g., by quickly modulating the torch or using screen).
If target_slot equals the phone’s slot, it turns on the torch. If a phone receives /flash/on for a different ID, it ignores it.
/flash/off:
Arguments: [ <target_slot_int> ].
Turns off the flashlight on the matching phone.
/audio/play:
Arguments: [ <target_slot_int>, <file_name_str>, <gain_float> ].
Instructs the target phone to play an audio asset. The file_name can be just a name (which the app will look for in its bundled assets) or a full URL (in which case the app will attempt to stream it). The gain is a volume factor (0.0 = silence, 1.0 = full volume). The app sets its audio player volume to this gain.
The Mac uses file names like "a5.mp3" meaning tone set “A” for slot 5, etc. Gains usually 1.0 or less if we want a softer sound.
The phone sets a flag audioPlaying=true immediately after starting playback (meaning sound is currently playing). In practice, it doesn’t send a message back when done, but the Mac might keep track by duration or separate cues.
/audio/stop:
Arguments: [ <target_slot_int> ].
Stops any audio playback on that phone immediately (audioPlaying=false on client side).
Mac sends this typically when a note-off or stop event happens (like releasing a key or stopping a tone cluster).
/mic/record:
Arguments: [ <target_slot_int>, <duration_float_seconds> ].
Commands a phone to start recording from its mic for the given number of seconds. The phone will stop automatically after that duration.
No audio data is actually sent over the network in the current design; it’s just local capture. There’s also no OSC message back when done (the phone only prints a log).
This is used experimentally; if integration were needed (say to sample a singer and then maybe the Mac triggers that sample back via /audio/play), the mechanism would have to be expanded to send the recorded file back or store it where the app can play it. This is not implemented yet – currently it’s more a placeholder demonstrating the capability.
/sync:
Arguments: [ <ntp_timestamp_bigint> ].
The Mac sends this to broadcast the current time. The timestamp is in NTP format (64-bit, where the integer part is seconds since 1900 and fractional part for sub-second).
The phone upon receiving calculates offset = server_time - local_time and averages it into client.clockOffsetMs.
This message is intended to be sent periodically (e.g., every few seconds). The Mac’s ClockSyncService likely does so.
With synchronized clocks, one could schedule an event: e.g., Mac could send “/flash/on 5 at_time 12345678” – but OSC doesn’t inherently have timed delivery unless using bundles with timetags (which is another approach not currently used). Instead, we might use the sync info to decide when multiple phones do something simultaneously if it wasn’t triggerable by one broadcast (but since broadcast reaches all at nearly same time, we haven’t had to schedule on client).
Nevertheless, it’s good to keep clocks roughly aligned to mitigate any network jitter (the clients effectively adjust for any consistent latency).
/set-slot:
Arguments: [ <new_slot_int> ].
Tells a client to change its slot ID. If a phone receives this, it will from then on consider itself as that new slot for all future commands.
The Mac might send this if it realizes two phones are swapped. It’s easier than asking the singers to swap phones – we just re-label them in software.
Our deployment script assigns fixed slots via JSON, so ideally this isn’t needed often. But it’s a handy command for flexibility (for example, if one device fails mid-rehearsal and you bring a spare, you could give the spare the missing device’s slot number via this command).
These messages cover all current functionality. They are all simple and lightweight (small payloads). The choice of broadcast for most means we don’t worry about IP addresses and ports beyond initial setup – any new device running the app will announce itself and respond to relevant commands.
Conclusion and Tips for Developers
With the above overview, a developer or AI agent working on this codebase should be able to navigate to relevant sections quickly:
If modifying mobile client behavior: Focus on flashlights_client/lib/osc_listener.dart and perhaps main.dart. That’s where incoming commands are handled. For example, to add a new OSC command (say /vibrate to make the phone vibrate), you would:
Add a case in _dispatch for /vibrate, use Flutter’s vibration plugin to vibrate if ID matches.
Add that plugin to pubspec.yaml.
Possibly update the Mac’s OscMessages.swift to define the message structure for /vibrate and then use it in the Mac app’s logic.
If changing the number of devices or mapping: The source of truth is the JSON map and the realSlots set in ChoirDevice.demo. To use, say, 40 devices instead of 28, you’d update realSlots to include the desired slot numbers (and ensure to mark others placeholders) and adjust the JSON accordingly. The Mac UI would then account for those. The keyboard mappings and groupings might also need to be updated to cover new slots or remove ones.
If debugging network issues: Use the Python test sender or simply run the Mac app in Xcode with console logging. The Mac app prints every OSC message it sends (“→ /flash/on ...”) and the OscBroadcaster logs when it starts. The phones, if run via flutter run, print when they get a message and any errors (like torch errors if camera is in use by another app, etc.). This can help pinpoint if messages are reaching or if an IP is wrong.
Extending audio capabilities: All phone audio is handled by AudioPlayer _player (just_audio). If overlapping sounds are needed, one might create multiple players or use a mix of just_audio’s features. Also consider latency: playing a sound on 28 phones concurrently will have some device-to-device slight timing differences, but usually within tens of milliseconds which is acceptable for ambient sounds (the sync helps, but audio hardware buffers on each phone could differ slightly).
Memory and performance: The phone app is simple and should run fine on older devices. Flashlight usage is the biggest battery/thermal cost. The Mac app might consume moderate CPU when sending rapid OSC (but it’s mostly I/O bound). SwiftNIO can handle hundreds of messages per second easily on modern Macs.
AI assistance: If using an AI (like ChatGPT via deep-research) to answer questions about the code, it should now have a clear “map” of where to look:
For questions about how the flashlight control works, check osc_listener.dart and the OSC message definitions.
For how to add a new device, refer to onboarding scripts and JSON structure.
For understanding the MIDI mappings or key triggers, see AppDelegate.swift and ConsoleState.swift (and the Python simulator for reference).
For issues on a specific platform (e.g., Android background), see KeepAliveService.kt or Flutter plugin docs if needed.
For potential errors (like “Torch error” prints), searching the code for “Torch error” (we saw in dart it prints catch exceptions) can give hints.
By organizing the code in this way and documenting it, we aim to make the project maintainable and adaptable. Future contributors should be able to build on this foundation, whether that means scaling up the system, repurposing it for another piece, or simply ensuring the performance runs smoothly.
