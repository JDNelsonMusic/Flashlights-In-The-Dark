# Repository Guidelines

## Project Structure & Module Organization
The macOS conductor console lives in `FlashlightsInTheDark_MacOS/` with `Model/`, `ViewModel/`, and `View/` separated for SwiftUI + Combine logic; resources such as `flash_ip+udid_map.json` sit under `Resources/`. Unit (`FlashlightsInTheDarkTests/`) and UI (`FlashlightsInTheDarkUITests/`) targets accompany the console project. The Flutter client is under `flashlights_client/` with `lib/` for Dart sources, `available-sounds/` for bundled audio, and platform folders (`ios/`, `android/`, etc.). Automation scripts (onboarding, setup, cleanup) are in `scripts/`, while Fastlane lanes for iOS provisioning sit in `fastlane/`. Support material, including the Pro Tools session and documentation, stays in `docs/` and `FlashlightsInTheDark_Protools-Session/`.

## Build, Test, and Development Commands
- `open FlashlightsInTheDark_MacOS/FlashlightsInTheDark.xcodeproj` — launch the Swift console in Xcode.
- `xcodebuild -project FlashlightsInTheDark.xcodeproj -scheme FlashlightsInTheDark -destination 'platform=macOS' build` — command-line build for macOS.
- `cd flashlights_client && flutter pub get` — sync Flutter dependencies.
- `cd flashlights_client && flutter analyze` — run static analysis with the project lints.
- `cd flashlights_client && flutter test` — execute widget and logic tests.
- `scripts/choir_onboard.sh` — bulk-install the mobile client to connected Android devices.

## Coding Style & Naming Conventions
Swift code follows Xcode defaults: 4-space indentation, PascalCase types, camelCase members, and OSC message structs grouped in `Model/`. Adopt protocol extensions for shared behavior and keep networking actors in `Network/`. Dart code uses 2-space indentation and the `flutter_lints` ruleset; files are `lower_snake_case.dart`, classes `UpperCamelCase`, and constants `SCREAMING_SNAKE_CASE`. Assets in `available-sounds/` follow the tone-set convention (e.g., `a05.mp3`, `b05.mp3`).

## Testing Guidelines
Run `xcodebuild test` with the same scheme to cover OSC message encoders/decoders and UI smoke tests; add new XCTest cases as `FeatureNameTests.swift`. Keep widget or integration coverage in Flutter under `test/` as `*_test.dart`; when adding OSC handlers, include golden or behavior tests validating state changes. Ensure scripts affecting deployments include dry-run paths or logging and manually verify on at least one physical device.

## Commit & Pull Request Guidelines
Write commit subjects in imperative voice (`feat: add triple trigger routing`) and keep them under 72 characters when possible; the history mixes conventional prefixes (`feat:`, `fix:`) with plain sentences—prefer the prefixed style for clarity. Each PR should explain the conductor/ client impact, note any scripts touched, and link back to rehearsal notes or issues. Include screenshots or terminal snippets when UI or onboarding behavior changes, and list manual tests (e.g., `flutter test`, `xcodebuild test`) in the description.
