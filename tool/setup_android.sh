#!/usr/bin/env bash
# Generate the Android Gradle scaffolding around lib/ and our AndroidManifest.xml,
# then apply the settings this app needs.
#   Usage (from the repo folder):  bash tool/setup_android.sh com.yourcompany
set -euo pipefail

ORG="${1:-com.sanvidhi}"
cd "$(dirname "$0")/.."

# keep our manifest: flutter create would replace it with the template
cp android/app/src/main/AndroidManifest.xml /tmp/site_manifest.xml
flutter create --platforms=android --org "$ORG" --project-name sanvidhi_site .
cp /tmp/site_manifest.xml android/app/src/main/AndroidManifest.xml
rm -f test/widget_test.dart   # template test references a counter app

GRADLE=android/app/build.gradle.kts
[ -f "$GRADLE" ] || GRADLE=android/app/build.gradle

# secure storage / geolocator need API 24+
sed -i.bak -E 's/minSdkVersion +flutter\.minSdkVersion/minSdkVersion 24/' "$GRADLE"
sed -i.bak -E 's/minSdk *= *flutter\.minSdkVersion/minSdk = 24/' "$GRADLE"
rm -f "$GRADLE.bak"
grep -nE 'minSdk|applicationId' "$GRADLE" || true

flutter pub get
dart run flutter_launcher_icons   # Sanvidhi Site launcher icon from assets/branding
echo
echo "Done. Build a release APK with:"
echo "  flutter build apk --release                      # server typed at login"
echo "  flutter build apk --release --dart-define=SITE_SERVER=https://erp.yourcompany.com"
