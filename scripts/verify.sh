#!/usr/bin/env bash
# Builds and tests everything: all four Swift-package suites plus all three app
# target configurations. One command, no Xcode UI, no per-machine knowledge.
#
#     ./scripts/verify.sh            # suites + every app target
#     ./scripts/verify.sh --suites   # suites only (no Xcode needed)
#
# Exists because "it builds" previously depended on who last built it locally:
# the package suites cover OceanCore and HydroProviders but never compile a line
# of the Watch or iPhone apps, and one machine had no iOS platform installed at
# all while the iPhone target sat on main.

set -uo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
FAILED=()
SUITES_ONLY=${1:-}

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILED+=("$1"); }

echo "== Swift package suites =="
cd "$ROOT/OceanCore"
if ! swift build >/dev/null 2>&1; then
  fail "swift build"
else
  pass "swift build"
  # Check executables follow the *check naming convention. Operational CLIs may
  # require arguments and are exercised by their owning suite instead.
  for suite in $(swift package describe --type json 2>/dev/null \
      | python3 -c "import json,sys;print(' '.join(t['name'] for t in json.load(sys.stdin)['targets'] if t['type']=='executable' and t['name'].endswith('check')))"); do
    out=$(swift run "$suite" 2>&1)
    status=$?
    # Trust the exit code. Every suite exits non-zero on failure, and scanning
    # all output for "failed" gave false negatives: a passing providercheck
    # prints "NOAA product currents ... failed" from its own default reporter
    # while deliberately exercising the failure path. A verify script that
    # calls a green tree broken is worse than none, because people stop reading
    # it.
    if [ $status -eq 0 ]; then
      pass "$suite — $(tail -1 <<<"$out" | sed 's/^ *//')"
    else
      fail "$suite"
      grep -E "✗|Fatal error" <<<"$out" | head -5 | sed 's/^/      /'
    fi
  done
fi

if [ "$SUITES_ONLY" = "--suites" ]; then
  echo
  [ ${#FAILED[@]} -eq 0 ] && { echo "All suites passed."; exit 0; }
  echo "FAILED: ${FAILED[*]}"; exit 1
fi

echo
echo "== App targets =="
cd "$ROOT/Slosh"
XC=xcodebuild
command -v $XC >/dev/null 2>&1 || XC=/usr/bin/xcodebuild

# An available *watch* simulator specifically. Parsed from JSON by runtime
# rather than grepped for the first UDID on screen, which picks up whatever
# iOS device happens to be listed first.
WATCH_SIM=$(xcrun simctl list devices available --json 2>/dev/null | python3 -c "
import json, sys
try:
    devices = json.load(sys.stdin).get('devices', {})
except Exception:
    sys.exit()
for runtime, entries in devices.items():
    if 'watchOS' not in runtime:
        continue
    for device in entries:
        if device.get('isAvailable'):
            print(device['udid'])
            sys.exit()
" || true)

build() { # name scheme destination configuration
  local label="$1" scheme="$2" dest="$3" cfg="$4"
  local out
  out=$($XC -scheme "$scheme" -destination "$dest" -configuration "$cfg" \
        -derivedDataPath "/tmp/slosh-verify-$cfg-${scheme// /-}" \
        build CODE_SIGNING_ALLOWED=NO 2>&1)
  if grep -q "BUILD SUCCEEDED" <<<"$out"; then
    pass "$label"
  elif grep -q "is not installed" <<<"$out"; then
    # Missing platform is a setup gap, not a code defect — name the fix.
    local plat
    plat=$(grep -oE "(iOS|watchOS) [0-9.]+ is not installed" <<<"$out" | head -1)
    fail "$label — $plat  (fix: xcodebuild -downloadPlatform ${plat%% *})"
  else
    fail "$label"
    grep -E "error:" <<<"$out" | head -5 | sed 's/^/      /'
  fi
}

if [ -n "$WATCH_SIM" ]; then
  build "Watch Debug (simulator)" "Slosh Watch App" "id=$WATCH_SIM" Debug
else
  echo "  (no watch simulator available; skipping the simulator build)"
fi
build "Watch Release (device)"  "Slosh Watch App"  "generic/platform=watchOS" Release
build "iPhone Debug (simulator)" "Slosh iPhone App" "generic/platform=iOS Simulator" Debug
build "iPhone Release (device)"  "Slosh iPhone App" "generic/platform=iOS" Release

echo
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "Everything passed."
  exit 0
fi
printf 'FAILED (%d):\n' "${#FAILED[@]}"
printf '  - %s\n' "${FAILED[@]}"
exit 1
