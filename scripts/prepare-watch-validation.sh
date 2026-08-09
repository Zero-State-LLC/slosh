#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/out/physical-watch-validation"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN="$OUT/$STAMP"
mkdir -p "$RUN"

for tool in xcodebuild xcrun swift; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done

cat > "$RUN/report.json" <<EOF
{
  "device": "NOT_RECORDED",
  "watchOS": "NOT_RECORDED",
  "configuration": "NOT_RECORDED",
  "generatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "physicalExecution": "NOT_RUN",
  "physicalExecutionReason": "no accessible paired physical Apple Watch confirmed",
  "tests": []
}
EOF

cat > "$RUN/results.md" <<'EOF'
# Physical Watch validation results

- Device: NOT_RECORDED
- watchOS: NOT_RECORDED
- Wrist/crown configuration: NOT_RECORDED
- Physical execution: NOT_RUN
- Reason: no accessible paired physical Apple Watch confirmed

| Test ID | Mode/place | Start | Duration | Observations | Metrics | Result | Notes |
|---|---|---|---:|---|---|---|---|
EOF

printf '%s\n' '=== Connected and offline devices ==='
xcrun xctrace list devices | tee "$RUN/devices.txt"

printf '%s\n' '=== Debug generic watchOS build (unsigned readiness check) ==='
xcodebuild \
  -project "$ROOT/Slosh/Slosh.xcodeproj" \
  -scheme "Slosh Watch App" \
  -configuration Debug \
  -destination "generic/platform=watchOS" \
  -derivedDataPath "$RUN/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build | tee "$RUN/debug-build.log"

cat <<EOF

Prepared: $RUN

A physical Watch session still requires a human, a configured signing team, and wrist movement.
Open Slosh/Slosh.xcodeproj, select the paired Watch, choose Debug, and set scheme arguments:
  -physicalValidation YES
  -validationRoute calm

Allowed routes: calm, breaking-surf, storm-at-night, san-francisco-bay
Capture logs with Console.app, filtering subsystem com.example.Slosh.watchkitapp
and category PhysicalValidation. Follow docs/PHYSICAL_WATCH_VALIDATION.md.
EOF
