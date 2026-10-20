#!/bin/sh
set -eu
repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"
for tool in heavy-gate xcodebuild xcodegen xcrun python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing prerequisite: $tool" >&2
    exit 1
  fi
done
if [ -n "${HEAVY_GATE_LEASE_TOKEN:-}" ]; then
  echo "Run pre-pr.sh directly; it queues two sequential simulator sessions." >&2
  exit 75
fi
if [ -n "${DESTINATION:-}" ]; then
  echo "Use IPHONE_SIMULATOR_ID and IPAD_SIMULATOR_ID instead of DESTINATION." >&2
  exit 1
fi
git diff --check
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
        and device.get("state") == "Shutdown"
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
for family in iphone ipad; do
  if [ "$family" = iphone ]; then simulator_id=$iphone_id; else simulator_id=$ipad_id; fi
  if heavy-gate --simulator-session "$simulator_id" -- \
    sh "$repo_root/script/pre-pr-device.sh" "$run_dir" "$family" "$simulator_id"; then
    :
  else
    status=$?
    printf '%s session: FAIL (exit %s)\n' "$family" "$status" | tee -a "$summary_file"
    if [ "$status" -eq 75 ]; then
      echo "Session did not complete. Inspect the gate or worker diagnostic above." >&2
      echo "Check heavy-gate --status and --help; simulator-session and lease-token support are required." >&2
    fi
    case "$status" in 74|75|129|130|143) exit "$status" ;; esac
    overall_status=1
  fi
done
cat "$summary_file"
echo "Logs and Xcode result bundles: $run_dir"
exit "$overall_status"
