#!/usr/bin/env bash
# Validates status/BACKLOG.md. Run it before you push a new row; CI runs it too
# (.github/workflows/backlog-check.yml).
#
# Why this exists: on 2026-09-02 three row numbers (#108, #109, #110) each
# existed TWICE, filed by two sessions on the same day that both picked "the
# next number" from a stale read. A lane greps `^| 109 |` to claim work and
# would have got two unrelated rows — Indonesia/Thailand and a value-meter
# redefinition. Radu: "always ensure no duplicates."
#
# #182: rows are archived to status/archive/BACKLOG-done.md once nothing open
# depends on them, so BOTH files are read here. Row numbers are NEVER reused —
# a duplicate across the two files is the same hazard as a duplicate within one
# (a lane greps only the live file and would silently get the wrong history),
# and a `needs` pointing at an archived row is perfectly valid.
set -uo pipefail
cd "$(dirname "$0")/.."
F=status/BACKLOG.md
A=status/archive/BACKLOG-done.md
[ -f "$F" ] || { echo "check-backlog: $F not found"; exit 1; }
# The archive is optional: a fresh checkout before #182's split has no such
# file, and this check must not start failing because of that.
FILES=("$F")
[ -f "$A" ] && FILES+=("$A")

fail=0

dupes=$(grep -hoE '^\| *[0-9]{1,3} *\|' "${FILES[@]}" | tr -d '| ' | sort -n | uniq -d)
if [ -n "$dupes" ]; then
  echo "FAIL duplicate row numbers:"
  for n in $dupes; do
    echo "  #$n appears $(grep -hcE "^\| *$n *\|" "${FILES[@]}" | paste -sd+ | bc) times across $(printf '%s ' "${FILES[@]}"):"
    grep -hE "^\| *$n *\|" "${FILES[@]}" | cut -c1-110 | sed 's/^/      /'
  done
  fail=1
fi

# every `needs` must point at a row that exists
known=$(grep -hoE '^\| *[0-9]{1,3} *\|' "${FILES[@]}" | tr -d '| ' | sort -n | uniq)
missing=""
while IFS= read -r line; do
  row=$(echo "$line" | awk -F'|' '{gsub(/ /,"",$2); print $2}')
  for dep in $(echo "$line" | awk -F'|' '{print $6}' | grep -oE '[0-9]{1,3}'); do
    echo "$known" | grep -qx "$dep" || missing="$missing\n  #$row needs #$dep, which does not exist"
  done
done < <(grep -E '^\| *[0-9]{1,3} *\|' "$F")
if [ -n "$missing" ]; then
  echo "FAIL dangling needs:"; echo -e "$missing" | sed '/^$/d'; fail=1
fi

# A row that VANISHES is the failure this script kept missing. It catches
# duplicates and dangling needs, but on 2026-08-29 a full-file overwrite
# silently deleted #102-#104 and reverted #92, and on 2026-09-14 another session
# did it again — #210, #211 and #212 disappeared in the same commit that added
# #213, and nothing went red. `sync-backlog-rows.sh` exists precisely to stop
# that, but it only helps the sessions that use it.
#
# So: compare against the previous COMMITTED copy. Every row number that existed
# then must still exist, in the live file or the archive. Deleting a row on
# purpose is rare enough to deserve an explicit override; renumbering is not
# deletion, because the old number would still have to go somewhere.
#
# Skipped when there is no git history to compare against (a fresh clone with no
# HEAD, or the file is newly added), and by BACKLOG_ALLOW_DELETIONS=1.
if [ "${BACKLOG_ALLOW_DELETIONS:-0}" != "1" ] && git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  prev=$(git show HEAD:"$F" 2>/dev/null | grep -oE '^\| *[0-9]{1,3} *\|' | tr -d '| ' | sort -n | uniq)
  if [ -n "$prev" ]; then
    vanished=""
    for n in $prev; do
      echo "$known" | grep -qx "$n" || vanished="$vanished $n"
    done
    if [ -n "$vanished" ]; then
      echo "FAIL rows present in the last commit are gone now:$vanished"
      echo "  A row number is never reused, so a row must be edited or archived, never deleted."
      echo "  If this really is intentional, re-run with BACKLOG_ALLOW_DELETIONS=1."
      fail=1
    fi
  fi
fi

if [ "$fail" = 0 ]; then
  live=$(grep -cE '^\| *[0-9]{1,3} *\|' "$F")
  total=$(echo "$known" | wc -l | tr -d ' ')
  echo "check-backlog: OK — $live live + $((total - live)) archived = $total rows, no duplicates, no dangling needs"
fi
exit $fail
