#!/bin/sh
# Generates SENSE.xcodeproj and opens it in Xcode.
#
# Usage:
#   scripts/setup.sh                       # select your team in Xcode afterwards
#   scripts/setup.sh TEAM_ID               # sign with TEAM_ID, bundle ID app.sense.ios
#   scripts/setup.sh TEAM_ID BUNDLE_ID     # sign with TEAM_ID and a bundle ID of your choice
set -eu
cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Xcode is required. Install it from the Mac App Store, open it once, then run this script again." >&2
    echo "If Xcode is installed, run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        brew install xcodegen
    else
        echo "XcodeGen is required. Install Homebrew from https://brew.sh, then run: brew install xcodegen" >&2
        exit 1
    fi
fi

if [ $# -ge 1 ]; then
    team="$1"
    bundle="${2:-app.sense.ios}"
    printf 'DEVELOPMENT_TEAM = %s\nSENSE_BUNDLE_IDENTIFIER = %s\n' "$team" "$bundle" > Config/Local.xcconfig
    echo "Wrote Config/Local.xcconfig (team $team, bundle ID $bundle)"
fi

xcodegen generate
open SENSE.xcodeproj
