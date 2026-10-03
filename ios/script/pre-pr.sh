#!/bin/sh

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

cd "$repo_root"

for tool in xcodebuild xcodegen xcrun python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing prerequisite: $tool" >&2
    exit 1
  fi
done

if [ -n "${DESTINATION:-}" ]; then
  echo "Use IPHONE_SIMULATOR_ID and IPAD_SIMULATOR_ID instead of DESTINATION." >&2
  exit 1
fi

git diff --check
xcodegen generate

simulator_ids=$(python3 <<'PY'
import json
import os
import subprocess
import sys

devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "--json"]
))["devices"]
runtimes = sorted(
    (runtime for runtime in devices
     if runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-26-")),
    key=lambda runtime: tuple(int(part) for part in runtime.split("iOS-")[1].split("-")),
    reverse=True,
)

for family, variable in [("iPhone", "IPHONE_SIMULATOR_ID"), ("iPad", "IPAD_SIMULATOR_ID")]:
    requested = os.environ.get(variable)
    candidates = [
        (runtime, device)
        for runtime in runtimes
        for device in devices[runtime]
        if device.get("isAvailable")
        and device.get("deviceTypeIdentifier", "").startswith(
            "com.apple.CoreSimulator.SimDeviceType." + family
        )
        and (not requested or device["udid"] == requested)
    ]
    if not candidates:
        print(f"No available iOS 26 {family} simulator matches {variable}. "
              "Install an iOS 26 runtime and create a matching simulator in Xcode.",
              file=sys.stderr)
        sys.exit(1)
    runtime, device = next(
        ((runtime, device) for runtime, device in candidates
         if device["name"].startswith(family)),
        candidates[0],
    )
    version = runtime.split("iOS-")[1].replace("-", ".")
    print(f"{family}: {device['name']} (iOS {version}, {device['udid']})", file=sys.stderr)
    print(device["udid"])
PY
)
iphone_id=$(printf '%s\n' "$simulator_ids" | sed -n '1p')
ipad_id=$(printf '%s\n' "$simulator_ids" | sed -n '2p')

mkdir -p .derived-data/pre-pr
run_dir=$(mktemp -d "$repo_root/.derived-data/pre-pr/run.XXXXXX")
summary_file="$run_dir/summary.txt"
overall_status=0

echo "Local pre-PR results: $run_dir"
echo "Unit tests run on iPhone; fixture UI tests run on iPhone and iPad."
echo "Seeded PocketBase tests are excluded. Screenshot, system accessibility, and"
echo "photo-picker checks remain opt-in; device-specific tests may also skip."

run_suite() {
  suite_name=$1
  simulator_id=$2
  test_target=$3
  result_bundle="$run_dir/$suite_name.xcresult"
  log_file="$run_dir/$suite_name.log"

  echo "Running $suite_name (log: $log_file)..."
  if xcodebuild test \
    -project OrganizedGlitter.xcodeproj \
    -scheme OrganizedGlitter \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$run_dir/DerivedData" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO \
    -only-testing:"$test_target" \
    -skip-testing:OrganizedGlitterUITests/OrganizedGlitterUITests/testSeededBackendLoadsOverviewAndLibrary \
    -skip-testing:OrganizedGlitterUITests/OrganizedGlitterUITests/testSeededBackendCreatesEditsAndDeletesDiamondProject \
    >"$log_file" 2>&1; then
    suite_status=PASS
  else
    suite_status=FAIL
    overall_status=1
  fi

  if xcrun xcresulttool get test-results summary --path "$result_bundle" \
    >"$run_dir/$suite_name.json" 2>>"$log_file"; then
    if counts=$(python3 - "$run_dir/$suite_name.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as report:
    summary = json.load(report)
print(f"{summary['passedTests']} passed, {summary['failedTests']} failed, "
      f"{summary['skippedTests']} skipped")
sys.exit(0 if summary["passedTests"] > 0 and summary["failedTests"] == 0 else 1)
PY
    ); then
      :
    else
      suite_status=FAIL
      overall_status=1
    fi
  else
    counts="test summary unavailable; inspect the log"
    suite_status=FAIL
    overall_status=1
  fi

  printf '%s: %s (%s)\n' "$suite_name" "$suite_status" "$counts" | tee -a "$summary_file"
  sed -n '/Test Case .* skipped/p' "$log_file"
}

run_suite unit-tests "$iphone_id" OrganizedGlitterTests
run_suite iphone-ui "$iphone_id" OrganizedGlitterUITests
run_suite ipad-ui "$ipad_id" OrganizedGlitterUITests

echo ""
echo "Local pre-PR summary:"
cat "$summary_file"
echo "Logs and Xcode result bundles: $run_dir"
exit "$overall_status"
