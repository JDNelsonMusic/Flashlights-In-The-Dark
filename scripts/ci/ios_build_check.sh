set -euo pipefail

cd "$(git rev-parse --show-toplevel)/flashlights_client"
flutter clean
flutter pub get
cd ios
rm -rf Pods Podfile.lock
pod install
xcodebuild -workspace Flashlights-ITD-Client.xcworkspace \
           -scheme Flashlights-ITD-Client \
           -destination 'generic/platform=iOS Simulator' \
           -configuration Debug \
           build
