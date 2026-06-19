#!/bin/bash
# Build GardenApp and run it as a proper .app bundle.
#
# Why a bundle? A bare SwiftPM executable launched via `swift run` is not treated
# as a real foreground app by macOS, so its window shows but never becomes active
# and never receives mouse/keyboard events. Wrapping the binary in a minimal
# .app bundle and launching with `open` fixes activation and input.
set -e
cd "$(dirname "$0")"

swift build

APP="dist/GardenApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/debug/GardenApp "$APP/Contents/MacOS/GardenApp"

# `open` only re-activates an already-running app; it won't swap in the freshly
# built binary. Kill any running instance first so we always launch the new build.
# (`-x` matches the exact process name, never this script's command line.)
pkill -x GardenApp 2>/dev/null || true
sleep 0.5

# Optional "Talk to your flowers" (Gemini) feature: an app launched via `open`
# does NOT inherit this shell's environment, so push the key into the user's
# launchd domain — LaunchServices-started apps inherit that. No key? The game
# still runs fine; the natural-language box just reports it's unavailable.
if [ -n "$GEMINI_API_KEY" ]; then
  launchctl setenv GEMINI_API_KEY "$GEMINI_API_KEY"
  echo "GEMINI_API_KEY detected — 'Talk to your flowers' enabled."
else
  echo "No GEMINI_API_KEY — 'Talk to your flowers' disabled (game still works)."
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Alan's Garden</string>
    <key>CFBundleDisplayName</key>     <string>Alan's Garden</string>
    <key>CFBundleIdentifier</key>      <string>com.alansgarden.app</string>
    <key>CFBundleExecutable</key>      <string>GardenApp</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
</dict>
</plist>
PLIST

open "$APP"
echo "Launched $APP — look for the 'Alan's Garden' window (Cmd+Tab if hidden)."
