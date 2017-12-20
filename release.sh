echo "🔔 You are creating a Noti release. 🔔";

rm -R build/
pod install
xcodebuild -workspace Noti.xcworkspace -scheme Noti -configuration Release -derivedDataPath build
npx appdmg dmg-resources/release.json build/Noti.dmg