#!/usr/bin/env bash
# ops/start-ocr-batch.sh — start an IMAGE-OCR extraction batch (includeImages=true)
# to drain image-only photos that text-only mode can't parse (no caption text).
# A thin wrapper over start-extraction-batch.sh with images turned on, so the
# daily OCR routine has ONE named, allowlistable command (same reason as the
# text-only script: an unattended CCR session's classifier blocks ad-hoc POSTs).
# Honours the same BATCH_LIMIT / BATCH_SPEND_CAP_USD / BATCH_VOTER_SET overrides;
# refuses to start if a job is already running.
set -euo pipefail
exec env BATCH_INCLUDE_IMAGES=true "$(dirname "$0")/start-extraction-batch.sh" "$@"
