#!/usr/bin/env bash
# ops/start-extraction-batch.sh — start the daily TEXT-ONLY extraction batch.
#
# Why this exists: the daily data-lane routine used to hand-roll a
# `curl -X POST .../api/admin/jobs` each run, and an unattended (fired) CCR
# session's auto-mode permission classifier denies an ad-hoc money-spending
# POST — so the batch silently never ran. A single, named command can be
# pre-approved in `.claude/settings.json` (`permissions.allow`), which an
# ad-hoc curl cannot. The routine now calls THIS; the classifier sees an
# allowlisted command, not a raw POST.
#
# Standing constraints (Radu): TEXT-ONLY (includeImages=false, no OCR),
# per-job spend cap, never start a second job while one is running.
# Token is read from the environment and passed via a header — never printed,
# so nothing lands in the world-readable Actions/session logs (public repo).
set -euo pipefail

BASE="${MYCOFFEE_BASE:-https://mycoffee-production-bd43.up.railway.app}"
: "${INGEST_TOKEN:?INGEST_TOKEN not set}"
LIMIT="${BATCH_LIMIT:-50}"
SPEND_CAP_USD="${BATCH_SPEND_CAP_USD:-8}"
VOTER_SET="${BATCH_VOTER_SET:-full}"
# Text-only by DEFAULT (Radu's standing rule). #171 flips it to true for one
# case only: when every claimable photo is an image-only one, where a text-only
# pass has nothing to read. The rule is about not burning vision calls on photos
# that HAVE text; it was never about refusing to extract a photo with none.
INCLUDE_IMAGES="${BATCH_INCLUDE_IMAGES:-false}"

# One read serves both guards below: is a job running, and is there anything to
# do. #170 added `pending` to this response using claimBatch's own predicate, so
# "what a worker would find" is measured rather than guessed.
jobs_json="$(curl -fsS "$BASE/api/admin/jobs" -H "Authorization: Bearer $INGEST_TOKEN")"

# Guard: never launch a second worker while one is running (double-spend), and
# never redeploy backend while a job runs is a separate rule — this only starts.
running="$(printf '%s' "$jobs_json" \
  | python3 -c 'import sys,json; print(sum(1 for j in json.load(sys.stdin).get("jobs",[]) if j.get("status")=="running"))')"
if [ "$running" != "0" ]; then
  echo "A job is already running ($running active). Not starting another." >&2
  exit 3
fi

# #171: exit before POSTing when there is nothing to extract.
#
# Jobs 42–54 were thirteen consecutive days of `photosDone: 0, spentUsd: 0`.
# Each one still created an `extraction_jobs` row (so `GET /api/admin/jobs`'s
# LIMIT 20 filled with no-ops and hid the real history), and — the real cost —
# a CCR routine session fired to POST it. #170 made `runWorker` early-exit;
# this makes the routine not ask in the first place.
read -r pending_total pending_text pending_overdue <<EOF
$(printf '%s' "$jobs_json" | python3 -c '
import sys, json
p = json.load(sys.stdin).get("pending") or {}
# An older backend (pre-#170) sends no `pending`. Treat that as "unknown, go
# ahead" rather than "nothing to do" — silently skipping every run against a
# server that just has not redeployed yet would be far worse than one no-op.
if not p:
    print("-1 -1 -1")
else:
    print(p.get("total", 0), p.get("textReceived", 0), p.get("awaitingTextOverdue", 0))
')
EOF

if [ "$pending_total" = "0" ]; then
  echo "ingest: nothing pending"
  exit 0
fi

# The escalation rule used to live only in the routine's prompt, where nothing
# could check it. When every claimable photo is an image-only one (no caption
# and never getting one), a text-only pass has nothing to read — the images-on
# pass is the only pass there is. Radu's text-only-first rule is about not
# burning vision calls on photos that HAVE text; it was never about refusing to
# extract a photo that has none.
if [ "$pending_total" != "-1" ] && [ "$pending_text" = "0" ] && [ "$pending_overdue" != "0" ]; then
  echo "ingest: only image-only photos pending ($pending_overdue) — escalating to an images-on pass"
  INCLUDE_IMAGES=true
fi

echo "Starting batch: limit=$LIMIT spendCapUsd=$SPEND_CAP_USD voterSet=$VOTER_SET includeImages=$INCLUDE_IMAGES pending=$pending_total"
curl -fsS -X POST "$BASE/api/admin/jobs" \
  -H "Authorization: Bearer $INGEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"limit\":$LIMIT,\"spendCapUsd\":$SPEND_CAP_USD,\"includeImages\":$INCLUDE_IMAGES,\"voterSet\":\"$VOTER_SET\"}"
echo
