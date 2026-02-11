#!/bin/bash

set -euo pipefail

pgrep -xq GitX && { echo "❌ GitX is currently running. Quit it first."; exit 1; }

# Lock the build to a single macOS destination for scheme-based builds.
DESTINATION="platform=macOS,arch=arm64"

run_quiet_xcodebuild() {
  local args=("$@")
  local include_destination=0

  for arg in "${args[@]}"; do
    if [[ "$arg" == "-scheme" ]]; then
      include_destination=1
      break
    fi
  done

  if (( include_destination )); then
    xcodebuild -project GitX.xcodeproj -destination "$DESTINATION" "${args[@]}" -quiet
  else
    xcodebuild -project GitX.xcodeproj "${args[@]}" -quiet
  fi
}

echo "🔐 Requesting sudo for installation"
sudo -v
echo "🧹 Cleaning previous builds"
run_quiet_xcodebuild -scheme Release clean

echo "🔨 Building GitX app"
run_quiet_xcodebuild -scheme Release -configuration Release build

echo "🔨 Building gitx CLI"
run_quiet_xcodebuild -target "cli tool" -configuration Release build

echo "📦 Gathering build settings"
BUILD_SETTINGS=$(xcodebuild -project GitX.xcodeproj -scheme Release -configuration Release -destination "$DESTINATION" -showBuildSettings)
APP_PATH=$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '/BUILT_PRODUCTS_DIR/ {print $2; exit}')
APP_NAME=$(printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' '/FULL_PRODUCT_NAME/ {print $2; exit}')

FULL_APP_PATH="$APP_PATH/$APP_NAME"

# install the app
sudo rm -rf /Applications/GitX.app
sudo mv "$FULL_APP_PATH" /Applications/GitX.app
cp build/Release/gitx /Applications/GitX.app/Contents/Resources/

# install command line tool
sudo mkdir -p /usr/local/bin
sudo ln -sf "/Applications/GitX.app/Contents/Resources/gitx" /usr/local/bin/gitx

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleGitVersion" /Applications/GitX.app/Contents/Info.plist 2>/dev/null || echo "unknown")
echo "✅ GitX: $VERSION"
