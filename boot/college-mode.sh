#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot entry point and watchdog.
# Install: mkdir -p ~/.termux/boot && cp boot/college-mode.sh ~/.termux/boot/ && chmod +x ~/.termux/boot/college-mode.sh
# Expects the repo at ~/college-mode (or set COLLEGE_MODE_SCRIPT in ~/.college-mode.env).
# Configuration lives in ~/.college-mode.env (COLLEGE_LAT, COLLEGE_LON, and any
# other variable from the README), so no coordinates are stored in this repo.
#
# Android can SIGKILL background processes without warning. This script runs the
# daemon as a child and starts it again if it dies. A deliberate stop (SIGTERM or
# Ctrl-C, exit 143/130), a clean exit, or a configuration error (exit 1) ends
# supervision instead, since restarting would not help.

command -v termux-wake-lock > /dev/null 2>&1 && termux-wake-lock

# shellcheck source=/dev/null
[ -f "$HOME/.college-mode.env" ] && . "$HOME/.college-mode.env"

LOG_FILE="${LOG_FILE:-$HOME/college.log}"
RESTART_DELAY="${RESTART_DELAY:-30}"
SUPERVISOR_PID_FILE="${SUPERVISOR_PID_FILE:-$HOME/.college-mode-supervisor.pid}"

log() { echo "[$(date '+%H:%M:%S')] watchdog: $*" >> "$LOG_FILE"; }

# The clone location by default; COLLEGE_MODE_SCRIPT in the env file overrides it.
SCRIPT="${COLLEGE_MODE_SCRIPT:-}"
if [ -z "$SCRIPT" ]; then
  for candidate in "$HOME/college-mode/college_mode.sh" "$HOME/college_mode.sh"; do
    [ -f "$candidate" ] && SCRIPT="$candidate" && break
  done
fi
if [ -z "$SCRIPT" ]; then
  command -v termux-toast > /dev/null 2>&1 && termux-toast "college-mode: college_mode.sh not found"
  log "college_mode.sh not found"
  exit 1
fi

# One supervisor at a time, so a second launch can't start a competing daemon.
if [ -f "$SUPERVISOR_PID_FILE" ]; then
  old=$(cat "$SUPERVISOR_PID_FILE" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2> /dev/null; then
    if [ ! -r "/proc/$old/cmdline" ] || grep -q college-mode "/proc/$old/cmdline" 2> /dev/null; then
      log "already supervising (pid $old)"
      exit 0
    fi
  fi
fi
echo $$ > "$SUPERVISOR_PID_FILE"

CHILD=""
stop() {
  [ -n "$CHILD" ] && kill -TERM "$CHILD" 2> /dev/null && wait "$CHILD" 2> /dev/null
  rm -f "$SUPERVISOR_PID_FILE"
  exit 0
}
trap stop INT TERM

log "supervising $SCRIPT (pid $$)"
while true; do
  bash "$SCRIPT" < /dev/null > /dev/null 2>&1 &
  CHILD=$!
  wait "$CHILD"
  rc=$?
  CHILD=""
  case "$rc" in
    0|1|130|143)
      log "daemon exited with $rc, not restarting"
      break
      ;;
  esac
  log "daemon died (exit $rc), restarting in ${RESTART_DELAY}s"
  sleep "$RESTART_DELAY" &
  wait $!
done
rm -f "$SUPERVISOR_PID_FILE"
