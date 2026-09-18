#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot entry point.
# Install: mkdir -p ~/.termux/boot && cp boot/college-mode.sh ~/.termux/boot/ && chmod +x ~/.termux/boot/college-mode.sh
# Configuration lives in ~/.college-mode.env (COLLEGE_LAT, COLLEGE_LON, and any
# other variable from the README), so no coordinates are stored in this repo.

termux-wake-lock

# shellcheck source=/dev/null
[ -f "$HOME/.college-mode.env" ] && . "$HOME/.college-mode.env"

exec bash "$HOME/college_mode.sh" < /dev/null > /dev/null 2>&1
