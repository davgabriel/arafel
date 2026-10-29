#!/bin/zsh
[ -n "${ZSH_VERSION:-}" ] || exec /bin/zsh "$0" "$@"   # started with bash or sh: rerun in zsh
# Builds Arafel.app with SwiftPM (no Xcode) and installs it in ~/Applications.
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
APP=build/Arafel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp .build/release/Arafel "$APP/Contents/MacOS/Arafel"
cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Arafel</string>
  <key>CFBundleIdentifier</key><string>com.davidgabriel.arafel</string>
  <key>CFBundleName</key><string>Arafel</string>
  <key>CFBundleDisplayName</key><string>Arafel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$(git rev-list --count HEAD 2>/dev/null || echo 1)</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>NSHumanReadableCopyright</key><string>David Gabriel</string>
</dict>
</plist>
PLIST
codesign --force --sign - --timestamp=none "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/Arafel.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/Arafel.app"
