#!/usr/bin/env bash
# One-time setup for auto-updating the unpacked extension (Radu, 2026-09-09:
# "make it auto updateable, too much manual work").
#
# Run this ONCE:
#     bash extension/install-autoupdate.sh
#
# It installs a launchd agent that runs `git pull` in this repo every hour. The
# extension's own hourly check (update.js) notices the new version and calls
# chrome.runtime.reload(), which for an unpacked extension re-reads every file
# from disk. Between the two, updates land with nothing for you to do.
#
# Why both halves are needed: an unpacked extension cannot write its own files,
# so something outside Chrome has to fetch them; and nothing outside Chrome can
# make Chrome re-read them, so the extension has to reload itself. Neither half
# works alone.
#
# Undo:  launchctl bootout gui/$(id -u)/ro.climbagain.mycoffee.extension-update
#        rm ~/Library/LaunchAgents/ro.climbagain.mycoffee.extension-update.plist
set -euo pipefail

LABEL="ro.climbagain.mycoffee.extension-update"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$HOME/Library/Logs/mycoffee-extension-update.log"

if [ "$(uname)" != "Darwin" ]; then
  echo "This installer is macOS-only (launchd)." >&2
  echo "On Linux, do the same with a cron entry:" >&2
  echo "  0 * * * * git -C '$REPO' pull --rebase --quiet" >&2
  exit 1
fi

if [ ! -d "$REPO/.git" ]; then
  cat >&2 <<MSG
$REPO is not a git checkout, so there is nothing to pull.

Auto-update needs the extension to come from a clone, not a downloaded ZIP.
The smallest way to get one — just the extension folder, ~88 KB:

    git clone --filter=blob:none --sparse https://github.com/Climb-Again/MyCoffee.git mycoffee-ext
    cd mycoffee-ext && git sparse-checkout set extension

Then point Chrome at mycoffee-ext/extension and run this script from there.
MSG
  exit 1
fi

GIT="$(command -v git)"
mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$GIT</string>
    <string>-C</string>
    <string>$REPO</string>
    <string>pull</string>
    <string>--rebase</string>
    <string>--quiet</string>
  </array>
  <key>StartInterval</key><integer>3600</integer>
  <!-- Also pull at login, so a laptop that was closed catches up immediately. -->
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLISTEOF

# bootout first so re-running this script is safe; ignore "not loaded".
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Installed: $LABEL"
echo "  repo : $REPO"
echo "  every: 1 hour, and at login"
echo "  log  : $LOG"
echo
echo "The extension checks for a new version every 3 hours and reloads itself"
echo "when it finds one, so from here on updates are automatic."
echo
echo "Check it works:  launchctl list | grep mycoffee"
