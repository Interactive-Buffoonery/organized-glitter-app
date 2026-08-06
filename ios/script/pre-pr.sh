#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
destination=${DESTINATION:-platform=iOS Simulator,name=iPhone 17}

cd "$repo_root"

git diff --check

xcodebuild test \
  -project OrganizedGlitter.xcodeproj \
  -scheme OrganizedGlitter \
  -destination "$destination" \
  -derivedDataPath .derived-data/pre-pr
