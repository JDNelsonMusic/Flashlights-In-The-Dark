# Primer Playback Validation

These checks confirm that each trigger only results in one primer tone per device and that conductor refreshes preserve the canonical colour-slot mapping.

## Prerequisites
- Build the Flutter client in debug mode on a representative iOS and Android device.
- Ensure the conductor is reachable so `/audio/play` and `/event/trigger` messages arrive.

## Android steps
1. Launch the app and keep `flutter logs` running.
2. From the console, send two `/audio/play` commands to the same slot within 150 ms.
3. Observe a single log line for the first trigger (`Native playback invoked`); a second trigger of the same event within ~5 s should produce only an acknowledgement with `Skipping duplicate primer` in the log.
4. Trigger a different event before the first finishes; confirm both tones play simultaneously and Android diagnostics show `activeStreams` ≥ 2 during the overlap.
5. Issue `/audio/stop` and confirm diagnostics shows `activeStreams=0` once all tones finish.

## iOS steps
1. Run the debug build through Xcode so device logs stream into the console.
2. Fire a rapid pair of `/event/trigger` messages for the same slot.
3. Verify only one audible primer plays for the event even if the conductor retries it; the console should show `Skipping duplicate primer` for the retry and still only one tone is heard.
4. Trigger a different event mid-playback; both tones should continue without interruption, and diagnostics will report `playersActive` ≥ 2 while they overlap.
5. Stop playback from the conductor and confirm diagnostics report `playersActive=0` and `currentCanonical=null` once the tones finish.

## Regression checklist
- `flutter analyze`
- `flutter test`
- `xcodebuild -project FlashlightsInTheDark.xcodeproj -scheme FlashlightsInTheDark -destination 'platform=macOS' build`
