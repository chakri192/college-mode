#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# college-mode — Auto volume manager for Android via Termux
# ============================================================

set -u

# ── CONFIG (override via env vars in test mode) ──────────────
COLLEGE_LAT="${COLLEGE_LAT:-0.000000}"
COLLEGE_LON="${COLLEGE_LON:-0.000000}"
RADIUS_METERS="${RADIUS_METERS:-150}"
EXIT_RADIUS_METERS="${EXIT_RADIUS_METERS:-250}"   # hysteresis: leave only past this, so GPS jitter can't flap in/out
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
RESET_MINUTES="${RESET_MINUTES:-5}"
COLLEGE_MEDIA_PCT="${COLLEGE_MEDIA_PCT:-20}"
COLLEGE_RINGER="${COLLEGE_RINGER:-0}"
NORMAL_RINGER_PCT="${NORMAL_RINGER_PCT:-100}"
ACTIVE_START="${ACTIVE_START:-0730}"              # HHMM; outside this window the daemon is dormant
ACTIVE_END="${ACTIVE_END:-1730}"
MAX_ITERATIONS="${MAX_ITERATIONS:-}"              # unset = run forever (used by tests)
PID_FILE="${PID_FILE:-${HOME}/.college-mode.pid}"
TERMUX_TIMEOUT="${TERMUX_TIMEOUT:-30}"            # seconds; a hung termux-* call must not freeze the daemon

# ── TEST MODE ────────────────────────────────────────────────
TEST_MODE="${TEST_MODE:-0}"
TEST_LAT="${TEST_LAT:-0.000000}"
TEST_LON="${TEST_LON:-0.000000}"
TEST_MUSIC_VOL="${TEST_MUSIC_VOL:-5}"
TEST_MAX_VOL="${TEST_MAX_VOL:-25}"
TEST_HEADPHONES="${TEST_HEADPHONES:-0}"
TEST_BLUETOOTH="${TEST_BLUETOOTH:-0}"
# Scripted scenario: one line per poll, space-separated key=value tokens
# (lat lon hp bt time min vol loc). Keys persist until overridden; loc is one-shot.
TEST_SEQUENCE="${TEST_SEQUENCE:-}"
TEST_NOW=""       # HHMM override for the active-window check
TEST_MIN=0        # simulated minutes elapsed, for the override timer
TEST_LOC=""       # "bad" makes the location provider return null coordinates
TEST_EPOCH_BASE=$(date +%s)

# ── LOGGING ──────────────────────────────────────────────────
LOG_FILE="${LOG_FILE:-${HOME}/college.log}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-1048576}"
LOG_KEEP_LINES="${LOG_KEEP_LINES:-1000}"

# Writes only to the log file, plus stdout when attached to a terminal —
# so `nohup ... > college.log` doesn't double every line.
log() {
  local line
  line="[$(date '+%H:%M:%S')] $*"
  [ -t 1 ] && echo "$line"
  echo "$line" >> "$LOG_FILE"
}

# Truncate in place (same inode) so any open descriptor stays valid.
rotate_log() {
  [ -f "$LOG_FILE" ] || return 0
  local size
  size=$(wc -c < "$LOG_FILE")
  size=${size// /}
  if [ "${size:-0}" -gt "$LOG_MAX_BYTES" ]; then
    tail -n "$LOG_KEEP_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" \
      && cat "${LOG_FILE}.tmp" > "$LOG_FILE"
    rm -f "${LOG_FILE}.tmp"
  fi
}

# ── TERMUX ABSTRACTION LAYER ──────────────────────────────────
# Every termux-* call goes through tmx so a hang (e.g. background location
# denied) turns into a logged warning instead of a stalled daemon.
tmx() { timeout "$TERMUX_TIMEOUT" "$@"; }

_get_location() {
  if [ "$TEST_MODE" = "1" ]; then
    if [ "$TEST_LOC" = "bad" ]; then
      echo '{"latitude": null, "longitude": null}'
    else
      echo "{\"latitude\": $TEST_LAT, \"longitude\": $TEST_LON, \"provider\": \"test\"}"
    fi
    return
  fi
  local result
  result=$(tmx termux-location -p network -r once 2>/dev/null </dev/null)
  [ -z "$result" ] && result=$(tmx termux-location -p gps -r once 2>/dev/null </dev/null)
  echo "$result"
}

_get_volume_info() {
  if [ "$TEST_MODE" = "1" ]; then
    echo "[{\"stream\":\"music\",\"volume\":$TEST_MUSIC_VOL,\"max_volume\":$TEST_MAX_VOL},{\"stream\":\"ring\",\"volume\":7,\"max_volume\":7},{\"stream\":\"notification\",\"volume\":5,\"max_volume\":7}]"
    return
  fi
  tmx termux-volume 2>/dev/null </dev/null
}

_set_volume() {
  local stream=$1 level=$2
  if [ "$TEST_MODE" = "1" ]; then
    log "[SIM] set $stream → $level"
    [ "$stream" = "music" ] && TEST_MUSIC_VOL=$level
    return
  fi
  tmx termux-volume "$stream" "$level" 2>/dev/null </dev/null
}

# termux-audio-info reports both wired and Bluetooth (A2DP) output in one call.
_is_headphones_connected() {
  if [ "$TEST_MODE" = "1" ]; then
    [ "$TEST_HEADPHONES" = "1" ] || [ "$TEST_BLUETOOTH" = "1" ]
    return
  fi
  tmx termux-audio-info 2>/dev/null </dev/null \
    | grep -Eq '"(WIREDHEADSET_IS_CONNECTED|BLUETOOTH_A2DP_IS_ON)"[[:space:]]*:[[:space:]]*true'
}

_toast() {
  [ "$TEST_MODE" = "1" ] && { log "[TOAST] $*"; return; }
  tmx termux-toast "$*" 2>/dev/null </dev/null
}

# ── CLOCK (overridable in test mode) ──────────────────────────
current_hhmm() {
  if [ "$TEST_MODE" = "1" ] && [ -n "$TEST_NOW" ]; then
    echo "$TEST_NOW"
  else
    date +%H%M
  fi
}

now_epoch() {
  if [ "$TEST_MODE" = "1" ] && [ -n "$TEST_SEQUENCE" ]; then
    echo $(( TEST_EPOCH_BASE + TEST_MIN * 60 ))
  else
    date +%s
  fi
}

in_window() {
  local now start end
  now=$((10#$(current_hhmm)))
  start=$((10#$ACTIVE_START))
  end=$((10#$ACTIVE_END))
  [ "$now" -ge "$start" ] && [ "$now" -le "$end" ]
}

nap() {
  # sleep in the background and wait, so INT/TERM traps fire immediately
  # instead of after the foreground sleep finishes
  sleep "$1" &
  wait $!
}

# ── PARSERS (values arrive via argv, never interpolated into code) ──
# stdin: termux-location JSON.  argv: target lat, target lon.
# stdout: "lat lon distance_m", or nothing if the fix is unusable.
PY_LOCATE='
import sys, json, math
try:
    d = json.load(sys.stdin)
    la, lo = float(d["latitude"]), float(d["longitude"])
    tla, tlo = float(sys.argv[1]), float(sys.argv[2])
    for v, lim in ((la, 90), (lo, 180)):
        if not math.isfinite(v) or abs(v) > lim:
            raise ValueError
    p1, l1, p2, l2 = map(math.radians, (la, lo, tla, tlo))
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin((l2 - l1) / 2) ** 2
    print(la, lo, int(6371000 * 2 * math.asin(math.sqrt(a))))
except Exception:
    pass
'

# stdin: termux-volume JSON.  stdout: "music_vol music_max ring_max".
PY_VOLUMES='
import sys, json
try:
    d = {i["stream"]: i for i in json.load(sys.stdin)}
    print(int(d["music"]["volume"]), int(d["music"]["max_volume"]), int(d["ring"]["max_volume"]))
except Exception:
    pass
'

# One termux-volume call and one python call fill all three values.
MUSIC_VOL="" MUSIC_MAX="" RING_MAX=""
read_volumes() {
  local out
  out=$(_get_volume_info | python3 -c "$PY_VOLUMES" 2>/dev/null)
  read -r MUSIC_VOL MUSIC_MAX RING_MAX <<< "$out"
  [ -n "$MUSIC_VOL" ] && [ -n "$MUSIC_MAX" ] && [ -n "$RING_MAX" ]
}

# Integer rounding: pct% of max, clamped to [0, max].
pct_to_level() {
  local pct=$1 max=$2 level
  level=$(( (max * pct + 50) / 100 ))
  [ "$level" -gt "$max" ] && level=$max
  [ "$level" -lt 0 ] && level=0
  echo "$level"
}

# Cached per poll (reset at the top of the loop) so the audio probe
# runs at most once per iteration.
HP_CACHE=""
headphones_connected() {
  if [ -z "$HP_CACHE" ]; then
    if _is_headphones_connected; then HP_CACHE=1; else HP_CACHE=0; fi
  fi
  [ "$HP_CACHE" = "1" ]
}

# ── STATE ─────────────────────────────────────────────────────
IN_COLLEGE=0
LAST_VOLUME_CHANGE=0
COLLEGE_MEDIA_LEVEL=""
PENDING=""          # "college" | "normal": a profile still owed, e.g. deferred by headphones
POLL_COUNT=0
OWNS_LOCK=0

# ── VOLUME ACTIONS ────────────────────────────────────────────
# Both return 0 when applied and 1 when skipped; a skipped profile stays in
# PENDING and is retried on later polls, so state never drifts from the volume.
apply_college_mode() {
  if headphones_connected; then
    log "Headphones connected — deferring college volume change"
    return 1
  fi
  if ! read_volumes; then
    log "WARN: Could not read volume info"
    return 1
  fi
  local level
  level=$(pct_to_level "$COLLEGE_MEDIA_PCT" "$MUSIC_MAX")
  COLLEGE_MEDIA_LEVEL="$level"
  _set_volume music "$level"
  _set_volume ring "$COLLEGE_RINGER"
  _set_volume notification 0
  _toast "College mode: vibrate + ${COLLEGE_MEDIA_PCT}%"
  log "Applied college mode (media=${level}/${MUSIC_MAX}, ringer=${COLLEGE_RINGER})"
  PENDING=""
}

apply_normal_mode() {
  if headphones_connected; then
    log "Headphones connected — deferring normal volume restore"
    return 1
  fi
  if ! read_volumes; then
    log "WARN: Could not read volume info"
    return 1
  fi
  local ringer
  ringer=$(pct_to_level "$NORMAL_RINGER_PCT" "$RING_MAX")
  _set_volume music "$MUSIC_MAX"
  _set_volume ring "$ringer"
  _set_volume notification "$RING_MAX"
  _toast "Normal mode: full volume"
  log "Applied normal mode (media=${MUSIC_MAX}/${MUSIC_MAX}, ringer=${ringer}/${RING_MAX})"
  PENDING=""
}

flush_pending() {
  [ -n "$PENDING" ] || return 0
  headphones_connected && return 0
  case "$PENDING" in
    college) apply_college_mode ;;
    normal)  apply_normal_mode ;;
  esac
}

begin_visit() {
  IN_COLLEGE=1
  LAST_VOLUME_CHANGE=0
  PENDING=college
  apply_college_mode
}

end_visit() {
  IN_COLLEGE=0
  LAST_VOLUME_CHANGE=0
  COLLEGE_MEDIA_LEVEL=""
  PENDING=normal
  apply_normal_mode
}

# ── STARTUP: validation, lock, cleanup ────────────────────────
die() { log "ERROR: $*"; echo "college-mode: $*" >&2; exit 1; }

validate_config() {
  local num='^-?[0-9]+(\.[0-9]+)?$' zero='^-?0*(\.0*)?$' hhmm='^([01][0-9]|2[0-3])[0-5][0-9]$'
  [[ $COLLEGE_LAT =~ $num && $COLLEGE_LON =~ $num ]] \
    || die "COLLEGE_LAT/COLLEGE_LON must be decimal numbers (got '${COLLEGE_LAT}', '${COLLEGE_LON}')"
  if [[ $COLLEGE_LAT =~ $zero && $COLLEGE_LON =~ $zero ]]; then
    die "COLLEGE_LAT/COLLEGE_LON are still 0,0 — set your coordinates first"
  fi
  local v
  for v in RADIUS_METERS EXIT_RADIUS_METERS RESET_MINUTES COLLEGE_MEDIA_PCT COLLEGE_RINGER NORMAL_RINGER_PCT; do
    [[ ${!v} =~ ^[0-9]+$ ]] || die "$v must be a non-negative integer (got '${!v}')"
  done
  [[ $CHECK_INTERVAL =~ ^[0-9]+$ ]] || die "CHECK_INTERVAL must be a non-negative integer"
  [[ $TERMUX_TIMEOUT =~ ^[1-9][0-9]*$ ]] || die "TERMUX_TIMEOUT must be a positive integer"
  [ "$EXIT_RADIUS_METERS" -gt "$RADIUS_METERS" ] \
    || die "EXIT_RADIUS_METERS ($EXIT_RADIUS_METERS) must exceed RADIUS_METERS ($RADIUS_METERS)"
  [[ $ACTIVE_START =~ $hhmm && $ACTIVE_END =~ $hhmm ]] \
    || die "ACTIVE_START/ACTIVE_END must be HHMM, 0000-2359 (got '${ACTIVE_START}', '${ACTIVE_END}')"
  [ "$((10#$ACTIVE_START))" -lt "$((10#$ACTIVE_END))" ] \
    || die "ACTIVE_START must be earlier than ACTIVE_END"

  local cmd
  for cmd in python3 $([ "$TEST_MODE" = "1" ] || echo timeout termux-location termux-volume termux-audio-info termux-toast); do
    command -v "$cmd" > /dev/null 2>&1 || die "required command not found: $cmd"
  done
}

acquire_lock() {
  if [ -f "$PID_FILE" ]; then
    local old
    old=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      # After a reboot the PID may have been reused; where /proc is readable,
      # require the process to actually be this script.
      if [ ! -r "/proc/$old/cmdline" ] || grep -q college_mode "/proc/$old/cmdline" 2>/dev/null; then
        die "already running (pid $old); stop it first or remove $PID_FILE"
      fi
    fi
  fi
  echo $$ > "$PID_FILE"
  OWNS_LOCK=1
}

# On any exit, leave the phone in normal mode if we changed it, then drop the lock.
on_exit() {
  trap - EXIT
  [ "$OWNS_LOCK" = "1" ] || return 0
  if [ "$IN_COLLEGE" -eq 1 ] || [ "$PENDING" = "normal" ]; then
    log "Shutting down — restoring normal volume"
    apply_normal_mode
  fi
  rm -f "$PID_FILE"
}

# ── TEST SCENARIO LOADER ──────────────────────────────────────
load_test_step() {
  { [ "$TEST_MODE" = "1" ] && [ -n "$TEST_SEQUENCE" ]; } || return 0
  local total n line tok
  total=$(wc -l < "$TEST_SEQUENCE")
  total=${total// /}
  n=$POLL_COUNT
  [ "$n" -gt "$total" ] && n=$total
  line=$(sed -n "${n}p" "$TEST_SEQUENCE")
  TEST_LOC=""
  for tok in $line; do
    case "$tok" in
      lat=*)  TEST_LAT=${tok#lat=} ;;
      lon=*)  TEST_LON=${tok#lon=} ;;
      hp=*)   TEST_HEADPHONES=${tok#hp=} ;;
      bt=*)   TEST_BLUETOOTH=${tok#bt=} ;;
      time=*) TEST_NOW=${tok#time=} ;;
      min=*)  TEST_MIN=${tok#min=} ;;
      vol=*)  TEST_MUSIC_VOL=${tok#vol=} ;;
      loc=*)  TEST_LOC=${tok#loc=} ;;
    esac
  done
}

# ── MAIN LOOP ─────────────────────────────────────────────────
validate_config
acquire_lock
trap 'exit 130' INT
trap 'exit 143' TERM
trap on_exit EXIT

log "========================================"
log "college-mode daemon starting (pid $$)"
log "Target: ${COLLEGE_LAT}, ${COLLEGE_LON} (enter ${RADIUS_METERS}m, exit ${EXIT_RADIUS_METERS}m)"
log "Window: ${ACTIVE_START}-${ACTIVE_END} | Interval: ${CHECK_INTERVAL}s | Revert: ${RESET_MINUTES}m"
[ "$TEST_MODE" = "1" ] && log "*** TEST MODE ACTIVE ***"
log "========================================"

while true; do
  POLL_COUNT=$((POLL_COUNT + 1))
  if [ -n "$MAX_ITERATIONS" ] && [ "$POLL_COUNT" -gt "$MAX_ITERATIONS" ]; then
    break
  fi
  HP_CACHE=""
  load_test_step
  rotate_log

  if ! in_window; then
    if [ "$IN_COLLEGE" -eq 1 ]; then
      log "Active window closed while on site — restoring normal volume"
      end_visit
    else
      flush_pending
    fi
    nap "$CHECK_INTERVAL"
    continue
  fi

  flush_pending

  location=$(_get_location)
  if [ -z "$location" ]; then
    log "WARN: Could not get location"
    nap "$CHECK_INTERVAL"
    continue
  fi

  # One python call parses the fix and computes the distance.
  parsed=$(printf '%s' "$location" | python3 -c "$PY_LOCATE" "$COLLEGE_LAT" "$COLLEGE_LON" 2>/dev/null)
  read -r CURR_LAT CURR_LON DIST <<< "$parsed"

  if ! [[ ${DIST:-} =~ ^[0-9]+$ ]]; then
    log "WARN: Unusable location fix"
    nap "$CHECK_INTERVAL"
    continue
  fi

  log "Coords: ${CURR_LAT}, ${CURR_LON} | Dist: ${DIST}m | In college: ${IN_COLLEGE}"

  # Hysteresis: enter when within RADIUS_METERS, but only leave once past the
  # larger EXIT_RADIUS_METERS — so GPS jitter near the boundary can't flap.
  if [ "$IN_COLLEGE" -eq 0 ]; then

    if [ "$DIST" -le "$RADIUS_METERS" ]; then
      log ">>> Entered college (${DIST}m)"
      begin_visit
    fi

  else

    if [ "$DIST" -gt "$EXIT_RADIUS_METERS" ]; then
      log "<<< Left college (${DIST}m)"
      end_visit
    elif [ -n "$COLLEGE_MEDIA_LEVEL" ] && ! headphones_connected && read_volumes; then
      log "Volume check: current=${MUSIC_VOL} target=${COLLEGE_MEDIA_LEVEL}"

      if [ "$MUSIC_VOL" != "$COLLEGE_MEDIA_LEVEL" ]; then
        NOW=$(now_epoch)
        if [ "$LAST_VOLUME_CHANGE" -eq 0 ]; then
          LAST_VOLUME_CHANGE=$NOW
          log "Volume manually changed: ${MUSIC_VOL} → will revert in ${RESET_MINUTES}m"
        else
          ELAPSED=$(( (NOW - LAST_VOLUME_CHANGE) / 60 ))
          log "Timer: ${ELAPSED}/${RESET_MINUTES}m"
          if [ "$ELAPSED" -ge "$RESET_MINUTES" ]; then
            log "Reverting volume after ${ELAPSED}m"
            apply_college_mode
            LAST_VOLUME_CHANGE=0
          fi
        fi
      else
        [ "$LAST_VOLUME_CHANGE" -ne 0 ] && log "Volume at college level — timer reset"
        LAST_VOLUME_CHANGE=0
      fi
    else
      # headphones on, or volume unreadable: don't run the override timer
      LAST_VOLUME_CHANGE=0
    fi

  fi

  nap "$CHECK_INTERVAL"
done
