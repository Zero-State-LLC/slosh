#!/usr/bin/env bash
# Creates the repo, pushes both branches, and opens the pull request.
#
# Run `gh auth login --web` first — that step is yours, not something to
# automate, since it involves your GitHub credentials.
#
#   ./PUBLISH.sh <org> [danny-github-handle]
#
# Defaults to a PRIVATE repo. Flipping to public later is one click; un-publishing
# code is not, so the safe direction is the default.

set -euo pipefail

GH=/opt/homebrew/bin/gh
ORG="${1:?usage: ./PUBLISH.sh <org> [reviewer]}"
REVIEWER="${2:-}"
REPO="$ORG/slosh"

if ! "$GH" auth status >/dev/null 2>&1; then
  echo "Not logged in. Run:  $GH auth login --web" >&2
  exit 1
fi

echo "==> Creating $REPO (private)"
# `repo create --push` pushes whatever branch is checked out, and that branch
# becomes the default. Start from main so the feature branch has something to
# open a pull request against.
git checkout main
"$GH" repo create "$REPO" \
  --private \
  --description "An ocean on your wrist — fifteen interactive water modes for Apple Watch, rendered with a SpriteKit fragment shader" \
  --source=. --remote=origin --push

echo "==> Pushing feature branch"
git checkout feat/water-shader-app
git push -u origin feat/water-shader-app

echo "==> Opening pull request"
PR_URL=$("$GH" pr create \
  --repo "$REPO" \
  --base main \
  --head feat/water-shader-app \
  --title "Water renderer, fifteen modes, and the docs to go with them" \
  --body-file .github/PULL_REQUEST_BODY.md)

echo "$PR_URL"

if [ -n "$REVIEWER" ]; then
  echo "==> Requesting review from $REVIEWER"
  # Review request and an explicit mention: the request drives their queue,
  # the comment says what is actually being asked of them.
  "$GH" pr edit "$PR_URL" --add-reviewer "$REVIEWER" || \
    echo "    (could not add reviewer — check the handle and that they are in the org)"
  "$GH" pr comment "$PR_URL" --body "@${REVIEWER} — ready for your eyes.

Two things worth your attention over the code itself:

1. **It has never run on real hardware.** Simulator only. The tilt axis and the
   shader's frame cost both need a physical watch, and either could force
   rework. See \`docs/ROADMAP.md\` Phase 0.
2. **\`docs/ECONOMICS.md\`** argues this is a portfolio piece rather than a
   business, and says why. That is the part I would most like disagreement on.

Start with \`docs/DECISIONS.md\` if you only read one thing — it covers the
renderer that got built and thrown away."
fi

echo
echo "Done. Repo is PRIVATE — make it public with:"
echo "  $GH repo edit $REPO --visibility public --accept-visibility-change-consequences"
