#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot entry point.
# Install: mkdir -p ~/.termux/boot && cp boot/college-mode.sh ~/.termux/boot/ && chmod +x ~/.termux/boot/college-mode.sh
# Expects the repo at ~/college-mode (or set COLLEGE_MODE_SCRIPT in ~/.college-mode.env).
# Configuration lives in ~/.college-mode.env (COLLEGE_LAT, COLLEGE_LON, and any
# other variable from the README), so no coordinates are stored in this repo.

termux-wake-lock

# shellcheck source=/dev/null
[ -f "$HOME/.college-mode.env" ] && . "$HOME/.college-mode.env"

# The clone location by default; COLLEGE_MODE_SCRIPT in the env file overrides it.
SCRIPT="${COLLEGE_MODE_SCRIPT:-}"
if [ -z "$SCRIPT" ]; then
  for candidate in "$HOME/college-mode/college_mode.sh" "$HOME/college_mode.sh"; do
    [ -f "$candidate" ] && SCRIPT="$candidate" && break
  done
fi
[ -n "$SCRIPT" ] || { termux-toast "college-mode: college_mode.sh not found"; exit 1; }

exec bash "$SCRIPT" < /dev/null > /dev/null 2>&1
