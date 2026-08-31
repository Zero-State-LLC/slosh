#!/usr/bin/env bash
# Creates the Slosh work board as a GitHub Project and files every open issue
# into a lane. See docs/WORK_PLAN.md for what the lanes mean.
#
# Requires the `project` scope, which is not granted by default:
#     gh auth refresh -s project
#
# Safe to re-run: it reuses a board of the same title rather than making a
# second one, and item-add is idempotent per issue.

set -euo pipefail

GH=/opt/homebrew/bin/gh
ORG=Zero-State-LLC
REPO="$ORG/slosh"
TITLE="Slosh"

command -v "$GH" >/dev/null || GH=gh

if ! "$GH" auth status >/dev/null 2>&1; then
  echo "Not logged in. Run: $GH auth login --web" >&2
  exit 1
fi
if ! "$GH" project list --owner "$ORG" >/dev/null 2>&1; then
  echo "Missing the project scope. Run: $GH auth refresh -s project" >&2
  exit 1
fi

echo "==> Finding or creating the board"
NUMBER=$("$GH" project list --owner "$ORG" --format json \
  | python3 -c "import json,sys;p=[x for x in json.load(sys.stdin)['projects'] if x['title']=='$TITLE'];print(p[0]['number'] if p else '')")

if [ -z "$NUMBER" ]; then
  NUMBER=$("$GH" project create --owner "$ORG" --title "$TITLE" --format json \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['number'])")
  echo "    created project #$NUMBER"
else
  echo "    reusing project #$NUMBER"
fi

# A single-select "Lane" field is what makes the board readable as a plan
# rather than a pile. Status is left as the built-in field.
echo "==> Ensuring the Lane field"
if ! "$GH" project field-list "$NUMBER" --owner "$ORG" --format json \
  | grep -q '"name":"Lane"'; then
  "$GH" project field-create "$NUMBER" --owner "$ORG" \
    --name "Lane" --data-type SINGLE_SELECT \
    --single-select-options "A · Hardware and product,B · Data domain,C · Hardening and verification" \
    >/dev/null
  echo "    created"
else
  echo "    already present"
fi

FIELD_JSON=$("$GH" project field-list "$NUMBER" --owner "$ORG" --format json)
LANE_FIELD_ID=$(python3 -c "
import json,sys
f=[x for x in json.loads('''$FIELD_JSON''')['fields'] if x['name']=='Lane'][0]
print(f['id'])
")
option_id() {
  python3 -c "
import json,sys
f=[x for x in json.loads('''$FIELD_JSON''')['fields'] if x['name']=='Lane'][0]
o=[x for x in f['options'] if x['name'].startswith('$1')]
print(o[0]['id'] if o else '')
"
}
A=$(option_id "A"); B=$(option_id "B"); C=$(option_id "C")

# issue number -> lane option id
assign() {
  local num="$1" lane="$2"
  local url="https://github.com/$REPO/issues/$num"
  local item
  item=$("$GH" project item-add "$NUMBER" --owner "$ORG" --url "$url" --format json \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])") || return 0
  "$GH" project item-edit --id "$item" --project-id \
    "$("$GH" project view "$NUMBER" --owner "$ORG" --format json | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")" \
    --field-id "$LANE_FIELD_ID" --single-select-option-id "$lane" >/dev/null
  echo "    #$num -> lane"
}

echo "==> Filing open issues into lanes"
# Lane B: data domain and forward feature work
for n in 18 21; do assign "$n" "$B"; done
# Lane C: hardening and verification
for n in 19 20 17; do assign "$n" "$C"; done

echo
echo "Board: https://github.com/orgs/$ORG/projects/$NUMBER"
echo "Lane A items are hardware and product decisions — see docs/WORK_PLAN.md;"
echo "they have no issues yet because none of them are code."
