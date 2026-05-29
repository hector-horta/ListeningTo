#!/bin/bash
set -e

# Change to script directory
cd "$(dirname "$0")"

echo "==> Building ListeningTo macOS App Bundle <=="

# 1. Check for icon.png
if [ ! -f "icon.png" ]; then
    echo "Error: icon.png not found in macos-swift directory."
    exit 1
fi

# 2. Create the temporary iconset folder
ICONSET_DIR="AppIcon.iconset"
echo "--> Creating multi-resolution icon assets..."
mkdir -p "$ICONSET_DIR"

# List of target sizes
sips -s format png -z 16 16     icon.png --out "$ICONSET_DIR/icon_16x16.png" > /dev/null 2>&1
sips -s format png -z 32 32     icon.png --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
sips -s format png -z 32 32     icon.png --out "$ICONSET_DIR/icon_32x32.png" > /dev/null 2>&1
sips -s format png -z 64 64     icon.png --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
sips -s format png -z 128 128   icon.png --out "$ICONSET_DIR/icon_128x128.png" > /dev/null 2>&1
sips -s format png -z 256 256   icon.png --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
sips -s format png -z 256 256   icon.png --out "$ICONSET_DIR/icon_256x256.png" > /dev/null 2>&1
sips -s format png -z 512 512   icon.png --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
sips -s format png -z 512 512   icon.png --out "$ICONSET_DIR/icon_512x512.png" > /dev/null 2>&1
sips -s format png -z 1024 1024 icon.png --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1

# 3. Compile the iconset to an .icns file
echo "--> Compiling AppIcon.icns using iconutil..."
iconutil -c icns "$ICONSET_DIR"

# Clean up temporary iconset directory
rm -rf "$ICONSET_DIR"

# 4. Compile the Swift code in release mode
echo "--> Compiling Swift application in release mode..."
swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist

# 5. Create app bundle structure
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/ListeningTo.app"
echo "--> Packaging application into $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy compiled binary
cp ".build/release/ListeningTo" "$APP_BUNDLE/Contents/MacOS/ListeningTo"

# Copy Info.plist
cp "Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Move AppIcon.icns to Resources
mv "AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# 6. Ad-hoc sign the app bundle (vital for macOS TCC permissions and private API loading)
echo "--> Ad-hoc signing the app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Success! Built $APP_BUNDLE successfully."
echo "You can run the app with: open $APP_BUNDLE"
