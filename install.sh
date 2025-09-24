#!/bin/bash

set -euo pipefail

# Lock the build to a single macOS destination so xcodebuild stops warning.
DESTINATION="platform=macOS,arch=arm64"

run_quiet_xcodebuild() {
  xcodebuild -project GitX.xcodeproj -destination "$DESTINATION" "$@" -quiet
}

echo "🔐 Requesting sudo access (will be needed for installation)..."
sudo -v
echo "🧹 Cleaning previous build..."
run_quiet_xcodebuild -scheme Release clean

echo "🔨 Building GitX app in Release configuration..."
run_quiet_xcodebuild -scheme Release -configuration Release build

echo "🔨 Building gitx CLI tool..."
run_quiet_xcodebuild -target "cli tool" -configuration Release build

echo "📦 Gathering build settings..."
BUILD_SETTINGS=$(xcodebuild -project GitX.xcodeproj -scheme Release -configuration Release -destination "$DESTINATION" -showBuildSettings)
APP_PATH=$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '/BUILT_PRODUCTS_DIR/ {print $2; exit}')
APP_NAME=$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '/FULL_PRODUCT_NAME/ {print $2; exit}')

FULL_APP_PATH="$APP_PATH/$APP_NAME"

echo "📍 App built at: $FULL_APP_PATH"
echo "📦 Moving app to /Applications/GitX.app..."
sudo rm -rf /Applications/GitX.app
sudo mv "$FULL_APP_PATH" /Applications/GitX.app
cp build/Release/gitx /Applications/GitX.app/Contents/Resources/

echo "🔗 Installing command line tool..."
sudo mkdir -p /usr/local/bin
sudo ln -sf "/Applications/GitX.app/Contents/Resources/gitx" /usr/local/bin/gitx

echo "✅ GitX installed successfully!"
