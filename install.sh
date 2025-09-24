#!/bin/bash

set -e

# Lock the build to a single macOS destination so xcodebuild stops warning.
DESTINATION="platform=macOS,arch=arm64"

echo "🔐 Requesting sudo access (will be needed for installation)..."
sudo echo "✅ Sudo access granted"

echo "🧹 Cleaning previous build..."
xcodebuild -project GitX.xcodeproj -scheme Release -destination "$DESTINATION" clean

echo "🔨 Building GitX app in Release configuration..."
xcodebuild -project GitX.xcodeproj -scheme Release -configuration Release -destination "$DESTINATION" build

echo "🔨 Building gitx CLI tool..."
xcodebuild -project GitX.xcodeproj -target "cli tool" -configuration Release -destination "$DESTINATION" build

echo "📦 Getting app path..."
APP_PATH=$(xcodebuild -project GitX.xcodeproj -scheme Release -configuration Release -destination "$DESTINATION" -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | grep -oE "/.*")
APP_NAME=$(xcodebuild -project GitX.xcodeproj -scheme Release -configuration Release -destination "$DESTINATION" -showBuildSettings | grep -m 1 "FULL_PRODUCT_NAME" | grep -oE "[^=]*$" | xargs)

FULL_APP_PATH="$APP_PATH/$APP_NAME"

echo "📍 App built at: $FULL_APP_PATH"

echo "🗑️  Removing existing /Applications/GitX.app..."
sudo rm -rf /Applications/GitX.app

echo "📦 Moving app to /Applications/GitX.app..."
sudo mv "$FULL_APP_PATH" /Applications/GitX.app

echo "📦 Adding CLI tool to app bundle..."
cp build/Release/gitx /Applications/GitX.app/Contents/Resources/

echo "🔗 Installing command line tool..."
sudo mkdir -p /usr/local/bin
sudo ln -sf "/Applications/GitX.app/Contents/Resources/gitx" /usr/local/bin/gitx

echo "✅ GitX installed successfully!"
echo "   App: /Applications/GitX.app"
echo "   CLI: /usr/local/bin/gitx"
