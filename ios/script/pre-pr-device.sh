#!/bin/sh
set -eu

cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
run_dir=$1
family=$2
simulator_id=$3
summary_file="$run_dir/summary-$family.txt"
mkdir -p "$run_dir"
overall_status=0
if [ "$family" = iphone ]; then
  xcodegen generate || exit 75
fi
if ! git diff --check; then
  echo "Workspace has whitespace errors; see git diff --check output above." >&2
  exit 1
fi

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
    ${SIMLOCK_IOS_DEVICE_SET:+"-DVTSimulatorSetLocation=$SIMLOCK_IOS_DEVICE_SET"} \
    -derivedDataPath "$run_dir/DerivedData-$family" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO \
    -only-testing:"$test_target" \
    -skip-testing:OrganizedGlitterUITests/OrganizedGlitterUITests/testSeededBackendLoadsOverviewAndLibrary \
    -skip-testing:OrganizedGlitterUITests/OrganizedGlitterUITests/testSeededBackendCreatesEditsAndDeletesDiamondProject \
    >"$log_file" 2>&1; then
    suite_status=PASS
  else
    xcodebuild_status=$?
    case "$xcodebuild_status" in 74|75|129|130|143) exit "$xcodebuild_status" ;; esac
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

if [ "$family" = iphone ]; then
  run_suite unit-tests "$simulator_id" OrganizedGlitterTests
  run_suite iphone-ui "$simulator_id" OrganizedGlitterUITests
else
  run_suite ipad-ui "$simulator_id" OrganizedGlitterUITests
fi
exit "$overall_status"
