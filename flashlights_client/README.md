# flashlights_client

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## iOS build notes

The iOS Runner project uses the `DEVELOPMENT_TEAM` build setting. Set this value in your Xcode environment or define it in `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig`.

### Flutter dependencies

If you encounter build errors mentioning `UnmodifiableUint8ListView` from the
`win32` package, your local pub cache is likely using an outdated version of the
package. Run `flutter pub get` in this directory to refresh dependencies.
The project requires **Flutter 3.19** (Dart 3.7) or newer.
