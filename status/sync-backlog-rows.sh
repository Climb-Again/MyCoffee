#!/usr/bin/env bash
# Land specific status/BACKLOG.md row changes from ios-staging onto main.
#
#   bash status/sync-backlog-rows.sh 157 158
#
# WHY THIS EXISTS — the recipe it replaces destroys rows
# ------------------------------------------------------
# `main` is the backlog's single source of truth (CLAUDE.md §10), so an iOS
# lane that flips a row on `ios-staging` must land that flip on `main` in the
# same session. The recipe both iOS lane prompts carried for that was:
#
#     git checkout ios-staging -- status/BACKLOG.md
#
# which is a full-file **overwrite**, not a merge. `main` routinely carries
# rows `ios-staging` has never seen — the backend and data lanes file straight
# to `main` — so that one line silently deletes them. It already happened: on
# 2026-08-29 an ios-ux sync ran it while `main` held #102, #103 and #104, and
# the same commit that correctly synced #93/#94/#99 deleted all three and
# reverted #92 from `done` back to `ready`.
#
# `status/README.md` warned about this; the routine prompts did not, and the
# prompt is what a fired session actually executes. So the safe path is a
# script rather than a warning: this touches ONLY the row numbers you name,
# leaves every other line of main's copy byte-identical, and refuses to push
# anything check-backlog.sh rejects.
set -uo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -eq 0 ]; then
  echo "usage: bash status/sync-backlog-rows.sh <row number> [row number ...]" >&2
  exit 2
fi

for n in "$@"; do
  case "$n" in
    ''|*[!0-9]*) echo "sync-backlog-rows: '$n' is not a row number" >&2; exit 2 ;;
  esac
done

START_BRANCH=$(git rev-parse --abbrev-ref HEAD)
restore() { git checkout -q "$START_BRANCH" 2>/dev/null || true; }

git fetch -q origin main ios-staging || { echo "sync-backlog-rows: fetch failed" >&2; exit 1; }
git checkout -q main || { echo "sync-backlog-rows: cannot check out main" >&2; exit 1; }
git pull -q --rebase origin main || { echo "sync-backlog-rows: pull --rebase failed" >&2; restore; exit 1; }

SOURCE=$(mktemp); trap 'rm -f "$SOURCE"' EXIT
git show origin/ios-staging:status/BACKLOG.md > "$SOURCE" || { echo "sync-backlog-rows: cannot read ios-staging copy" >&2; restore; exit 1; }

applied=()
for n in "$@"; do
  if ! grep -qE "^\| *$n *\|" "$SOURCE"; then
    echo "sync-backlog-rows: #$n is not in ios-staging's copy — skipping" >&2
    continue
  fi
  if ! grep -qE "^\| *$n *\|" status/BACKLOG.md; then
    echo "sync-backlog-rows: #$n does not exist on main — file the row on main first, don't sync it in" >&2
    continue
  fi
  ROW_N="$n" SRC="$SOURCE" python3 - <<'PY'
import os, re, sys
n = os.environ["ROW_N"]
src = os.environ["SRC"]
pattern = re.compile(rf"^\|\s*{n}\s*\|")
new_rows = [l for l in open(src).read().split("\n") if pattern.match(l)]
if len(new_rows) != 1:
    sys.exit(f"sync-backlog-rows: #{n} appears {len(new_rows)} times in ios-staging's copy")
path = "status/BACKLOG.md"
lines = open(path).read().split("\n")
replaced = [new_rows[0] if pattern.match(l) else l for l in lines]
open(path, "w").write("\n".join(replaced))
PY
  # shellcheck disable=SC2181
  [ $? -eq 0 ] && applied+=("$n")
done

if [ ${#applied[@]} -eq 0 ]; then
  echo "sync-backlog-rows: nothing to sync"
  restore
  exit 0
fi

if ! bash status/check-backlog.sh; then
  echo "sync-backlog-rows: check-backlog failed — NOT committing" >&2
  git checkout -- status/BACKLOG.md
  restore
  exit 1
fi

# The Plan tab in the app is generated from this file; regenerate it in the
# same commit so backlog-check.yml's drift check stays green.
if [ -f ops/gen-whatsnew-plan.mjs ]; then
  node ops/gen-whatsnew-plan.mjs || { echo "sync-backlog-rows: plan regen failed" >&2; restore; exit 1; }
fi

if git diff --quiet -- status/BACKLOG.md backend/src/data/whatsnew.json; then
  echo "sync-backlog-rows: rows ${applied[*]} already match main — nothing to commit"
  restore
  exit 0
fi

git add status/BACKLOG.md backend/src/data/whatsnew.json 2>/dev/null
git commit -q -m "Backlog: sync rows ${applied[*]} from ios-staging" || { restore; exit 1; }
git push -q origin main || { echo "sync-backlog-rows: push failed — rerun after resolving" >&2; restore; exit 1; }
echo "sync-backlog-rows: synced ${applied[*]} to main"
restore
