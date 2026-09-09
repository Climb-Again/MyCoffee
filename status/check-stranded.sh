#!/usr/bin/env bash
# Reports `claude/*` branches carrying commits that exist on NEITHER `main` nor
# `ios-staging` — i.e. lane work that will be silently lost. CI runs it daily
# (.github/workflows/stranded-branches.yml); run it locally any time.
#
# Why this exists: CCR routine sessions commit to their OWN branch, not `main`
# (CLAUDE.md §12). When nobody merges that branch the work is invisible, and the
# next session redoes it. On 2026-09-09 an audit of 19 such branches found the
# browser-extension spec Radu locked on 2026-09-04 sitting unmerged for five
# days while a replacement was being written from scratch, the Brew lab spec
# (PLAN.md §14, 399 lines) never landed at all, and #76's Add Coffee wizard
# shell surface (407 lines) built twice for want of one merge. CLAUDE.md §12
# said to add an integration guard "if lanes keep producing orphan branches".
# They did.
#
# Branches already audited are listed in status/stranded-ok.txt and skipped, so
# this is GREEN today and goes RED on the next NEW orphan rather than nagging
# about known history. When you audit a branch, either merge it or add it there
# with a reason.
set -uo pipefail
cd "$(dirname "$0")/.."

GRACE_DAYS="${STRANDED_GRACE_DAYS:-3}"
ALLOW=status/stranded-ok.txt
now=$(date +%s)
cutoff=$((now - GRACE_DAYS * 86400))

for base in main ios-staging; do
  git rev-parse --verify --quiet "origin/$base" >/dev/null || {
    echo "check-stranded: origin/$base not fetched — run with fetch-depth 0"; exit 1; }
done

allowed() {
  [ -f "$ALLOW" ] || return 1
  grep -vE '^\s*(#|$)' "$ALLOW" | awk '{print $1}' | grep -qx "$1"
}

found=0
while IFS= read -r ref; do
  branch=${ref#origin/}
  n=$(git rev-list --count "$ref" --not origin/main origin/ios-staging 2>/dev/null) || continue
  [ "${n:-0}" -gt 0 ] || continue

  ts=$(git log -1 --format=%ct "$ref" 2>/dev/null) || continue
  # Still inside the grace window: a session may be mid-flight. Not an orphan yet.
  [ "$ts" -lt "$cutoff" ] || continue

  allowed "$branch" && continue

  age=$(((now - ts) / 86400))
  echo "STRANDED  $branch — $n commit(s) on no shared branch, untouched ${age}d"
  git log --oneline "$ref" --not origin/main origin/ios-staging | sed 's/^/            /'
  echo
  found=$((found + 1))
done < <(git for-each-ref --format='%(refname:short)' 'refs/remotes/origin/claude/*')

if [ "$found" -gt 0 ]; then
  cat <<MSG
FAIL: $found branch(es) carry work that is on neither main nor ios-staging.

Work on these is invisible to every lane and WILL be redone from scratch.
For each one, do exactly one of:
  1. Merge it:    git checkout main && git merge --no-ff origin/<branch> && git push origin main
  2. Port it:     cherry-pick or re-file the rows, renumbering if they collide
  3. Dismiss it:  add the branch to $ALLOW with a one-line reason
MSG
  exit 1
fi

echo "check-stranded: OK — no claude/* branch older than ${GRACE_DAYS}d holds unshared work"
