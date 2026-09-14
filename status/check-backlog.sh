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

if [ "$fail" = 0 ]; then
  live=$(grep -cE '^\| *[0-9]{1,3} *\|' "$F")
  total=$(echo "$known" | wc -l | tr -d ' ')
  echo "check-backlog: OK — $live live + $((total - live)) archived = $total rows, no duplicates, no dangling needs"
fi
exit $fail
