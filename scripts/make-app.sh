#!/bin/sh
# Assembles build/ShiftPick.app from the release build and signs it with the Wooflab team's Developer ID,
# under the Hardened Runtime, so that the result can be notarized and opens on a Mac that did not build it.
# SIGN_IDENTITY="-" in the environment signs ad-hoc instead, for a throwaway build that cannot be shipped.
#
# The app's name and identifier come from scripts/signing.env, which is the one place they are written.
set -eu

VERSION="0.0.1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/signing.env"
APP="$ROOT/build/$APP_NAME.app"

swift build -c release --package-path "$ROOT" --product "$APP_NAME"
BIN="$ROOT/.build/release"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# The icon ships in two forms. Assets.car, compiled by actool from the Icon Composer bundle, is what macOS
# renders with Liquid Glass; AppIcon.icns is the flat form for whatever reads CFBundleIconFile instead of the
# catalogue. Nothing is cached: both are rebuilt every run.
rm -rf "$ROOT/build/icon" "$ROOT/build/AppIcon.iconset" "$ROOT/build/AppIcon.icns"

# actool lives in full Xcode, not the Command Line Tools. Without it the app still builds and still has an
# icon — it just loses the glass on macOS 26+.
if xcrun --find actool >/dev/null 2>&1; then
  mkdir -p "$ROOT/build/icon"
  xcrun actool "$ROOT/Resources/AppIcon.icon" \
    --compile "$ROOT/build/icon" \
    --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/build/icon/partial.plist" \
    --platform macosx --minimum-deployment-target 26.0 \
    --output-format human-readable-text >/dev/null
  cp "$ROOT/build/icon/Assets.car" "$APP/Contents/Resources/Assets.car"
  ICON_NAME_KEY='    <key>CFBundleIconName</key><string>AppIcon</string>'
else
  echo "WARNING: actool not found (needs full Xcode) — icon built without Liquid Glass" >&2
  ICON_NAME_KEY=''
fi

# actool's own AppIcon.icns carries 16 px and 128 px only; everything larger is expected to come from
# Assets.car. So the .icns is rasterised here from the 1024 px master, which already carries the rounded
# mask an .icns is required to bake in.
ICONSET="$ROOT/build/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
            128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 512:icon_256x256@2x \
            512:icon_512x512 1024:icon_512x512@2x; do
  sips -z "${spec%%:*}" "${spec%%:*}" \
    "$ROOT/Resources/previews/$APP_NAME-preview-1024.png" \
    --out "$ICONSET/${spec#*:}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# ShiftPick needs no usage description: the Accessibility permission has no Info.plist key, and nothing
# else is claimed. The two .lproj directories ship anyway, because their presence beside
# CFBundleLocalizations is what puts the app in System Settings > Language & Region's per-app list, which
# is how a French Mac can be told to show this one in English.
for lproj in en fr; do
  mkdir -p "$APP/Contents/Resources/$lproj.lproj"
done
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<STRINGS
"CFBundleDisplayName" = "$APP_NAME";
STRINGS
cat > "$APP/Contents/Resources/fr.lproj/InfoPlist.strings" <<STRINGS
"CFBundleDisplayName" = "$APP_NAME";
STRINGS

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
${ICON_NAME_KEY}
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>fr</string></array>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Personal build.</string>
    <!-- Where the update check looks. Written from scripts/signing.env so that GITHUB_REPO is named in one
         place and the app reads its own back (Sources/ShiftPickCore/AppIdentity.swift). -->
    <key>SPUpdateRepository</key><string>${GITHUB_REPO}</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

# A real identity gets the Hardened Runtime and a trusted timestamp, both of which notarization refuses a
# build without. There is nothing nested to sign: one executable, no frameworks, no resource bundles.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    # Ad-hoc: it cannot be notarized, and every build gives the app a new code identity, so macOS asks for
    # Accessibility again — and forgets the grant the owner has already given. It exists to read something a
    # signed build will not show, and it is never made unless the owner has asked for one: DEBUG_OK=1 is how
    # the caller says so.
    if [ "${DEBUG_OK:-0}" != "1" ]; then
        echo "refusing an ad-hoc build without the owner asking for it." >&2
        echo "An ad-hoc build cannot be notarized and is not a way to install the app: scripts/install.sh is." >&2
        echo "If the owner has asked for one, run: DEBUG_OK=1 sh scripts/make-app.sh" >&2
        exit 1
    fi
    echo "warning: ad-hoc signing — this build cannot be notarized, and every build gives the app a new" >&2
    echo "         code identity, so the Accessibility grant is lost. Ship with scripts/release.sh." >&2
    SIGN_FLAGS=""
else
    SIGN_FLAGS="--options runtime --timestamp"
fi
ENTITLEMENTS="$ROOT/Resources/$APP_NAME.entitlements"
codesign --force $SIGN_FLAGS --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP"
