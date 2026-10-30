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
if [ -z "${IPHONE_SIMULATOR_ID:-}" ] || [ -z "${IPAD_SIMULATOR_ID:-}" ]; then
  echo "Set IPHONE_SIMULATOR_ID and IPAD_SIMULATOR_ID to simulators opened for this run." >&2
  exit 1
fi
git diff --check

mkdir -p .derived-data/pre-pr
run_dir=$(mktemp -d "$repo_root/.derived-data/pre-pr/run.XXXXXX")
overall_status=0
for family in iphone ipad; do
  if [ "$family" = iphone ]; then simulator_id=$IPHONE_SIMULATOR_ID; else simulator_id=$IPAD_SIMULATOR_ID; fi
  summary_file="$run_dir/summary-$family.txt"
  if sh "$repo_root/script/pre-pr-device.sh" "$run_dir" "$family" "$simulator_id"; then
    :
  else
    status=$?
    printf '%s session: FAIL (exit %s)\n' "$family" "$status" | tee -a "$summary_file"
    # pre-pr-device.sh exits 1 for failed checks; anything else means the run was stopped.
    [ "$status" -eq 1 ] || exit "$status"
    overall_status=1
  fi
done
for family in iphone ipad; do
  summary_file="$run_dir/summary-$family.txt"
  if [ -f "$summary_file" ]; then cat "$summary_file"; fi
done
echo "Logs and Xcode result bundles: $run_dir"
exit "$overall_status"
