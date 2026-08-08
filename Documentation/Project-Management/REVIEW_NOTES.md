# Flashlights Client – Reviewer Notes

- **Connection flow:** The iOS client discovers the Mac conductor console over the production’s closed Wi-Fi network via Bonjour (`_osc._udp`) and exchanges OSC messages. There is no Bluetooth or external accessory pairing step—joining the Wi-Fi network is the only requirement.
- **How to verify audio:** Keep the app in the foreground on the test iPhone, then from the macOS conductor console send any audio cue (e.g., the **All Audio Test** button). The client will immediately play the short sample routed to that device.
- **Background behavior:** The app now runs without the `UIBackgroundModes/audio` entitlement. It only emits short cues when commanded, so reviewers should leave the app active on-screen while testing.
