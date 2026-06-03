#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# college-mode — Auto volume manager for Android via Termux
# ============================================================

# ── CONFIG (override via env vars in test mode) ──────────────
COLLEGE_LAT="${COLLEGE_LAT:-0.000000}"
COLLEGE_LON="${COLLEGE_LON:-0.000000}"
RADIUS_METERS="${RADIUS_METERS:-150}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
RESET_MINUTES="${RESET_MINUTES:-5}"
COLLEGE_MEDIA_PCT="${COLLEGE_MEDIA_PCT:-20}"
COLLEGE_RINGER="${COLLEGE_RINGER:-0}"
NORMAL_RINGER_PCT="${NORMAL_RINGER_PCT:-100}"

# ── TEST MODE ────────────────────────────────────────────────
TEST_MODE="${TEST_MODE:-0}"
TEST_LAT="${TEST_LAT:-0.000000}"
TEST_LON="${TEST_LON:-0.000000}"
TEST_MUSIC_VOL="${TEST_MUSIC_VOL:-5}"
TEST_MAX_VOL="${TEST_MAX_VOL:-25}"
TEST_HEADPHONES="${TEST_HEADPHONES:-0}"
TEST_BLUETOOTH="${TEST_BLUETOOTH:-0}"

# ── LOGGING ──────────────────────────────────────────────────
LOG_FILE="${LOG_FILE:-${HOME}/college.log}"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ── TERMUX ABSTRACTION LAYER ──────────────────────────────────
_get_location() {
  if [ "$TEST_MODE" = "1" ]; then
    echo "{\"latitude\": $TEST_LAT, \"longitude\": $TEST_LON, \"provider\": \"test\"}"
    return
  fi
  local result
  result=$(termux-location -p network -r once 2>/dev/null)
  [ -z "$result" ] && result=$(termux-location -p gps -r once 2>/dev/null)
  echo "$result"
}

_get_volume_info() {
  if [ "$TEST_MODE" = "1" ]; then
    echo "[{\"stream\":\"music\",\"volume\":$TEST_MUSIC_VOL,\"max_volume\":$TEST_MAX_VOL},{\"stream\":\"ring\",\"volume\":7,\"max_volume\":7},{\"stream\":\"notification\",\"volume\":5,\"max_volume\":7}]"
    return
  fi
  termux-volume 2>/dev/null
}

_set_volume() {
  local stream=$1 level=$2
  if [ "$TEST_MODE" = "1" ]; then
    log "[SIM] set $stream → $level"
    return
  fi
  termux-volume "$stream" "$level" 2>/dev/null
}

_is_wired_headphones() {
  [ "$TEST_MODE" = "1" ] && { [ "$TEST_HEADPHONES" = "1" ] && return 0 || return 1; }
  local state
  state=$(termux-audio-info 2>/dev/null | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('WIREDHEADSET_IS_CONNECTED',False))" 2>/dev/null)
  [ "$state" = "True" ]
}

_is_bluetooth_connected() {
  [ "$TEST_MODE" = "1" ] && { [ "$TEST_BLUETOOTH" = "1" ] && return 0 || return 1; }
  local state
  state=$(termux-bluetooth-info 2>/dev/null | python3 -c \
    "import sys,json; d=json.load(sys.stdin)
pairs=d.get('paired_devices',[])
print(any(x.get('connected') for x in pairs))" 2>/dev/null)
  [ "$state" = "True" ]
}

_toast() {
  [ "$TEST_MODE" = "1" ] && { log "[TOAST] $*"; return; }
  termux-toast "$*" 2>/dev/null
}

# ── HELPERS ───────────────────────────────────────────────────
haversine() {
  python3 -c "
import math
lat1,lon1,lat2,lon2 = map(math.radians, [$1,$2,$3,$4])
dlat=lat2-lat1; dlon=lon2-lon1
a=math.sin(dlat/2)**2+math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
print(int(6371000*2*math.asin(math.sqrt(a))))
"
}

get_stream_volume() {
  _get_volume_info | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  for item in d:
    if item.get('stream')=='$1':
      print(item.get('volume',0)); break
except: print('')
" 2>/dev/null
}

get_stream_max() {
  _get_volume_info | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  for item in d:
    if item.get('stream')=='$1':
      print(item.get('max_volume',15)); break
except: print('15')
" 2>/dev/null
}

pct_to_level() {
  python3 -c "print(max(0, min($2, round($2 * $1 / 100))))"
}

headphones_connected() {
  _is_wired_headphones && return 0
  _is_bluetooth_connected && return 0
  return 1
}

# ── VOLUME ACTIONS ────────────────────────────────────────────
apply_college_mode() {
  if headphones_connected; then
    log "Headphones connected — skipping college volume change"
    return
  fi
  local media_max ringer_max college_media
  media_max=$(get_stream_max music)
  college_media=$(pct_to_level "$COLLEGE_MEDIA_PCT" "$media_max")
  COLLEGE_MEDIA_LEVEL="$college_media"
  _set_volume music "$college_media"
  _set_volume ring "$COLLEGE_RINGER"
  _set_volume notification 0
  _toast "College mode: vibrate + ${COLLEGE_MEDIA_PCT}%"
  log "Applied college mode (media=${college_media}/${media_max}, ringer=0)"
}

apply_normal_mode() {
  if headphones_connected; then
    log "Headphones connected — skipping normal volume restore"
    return
  fi
  local media_max ringer_max normal_media normal_ringer
  media_max=$(get_stream_max music)
  ringer_max=$(get_stream_max ring)
  normal_media=$(pct_to_level 100 "$media_max")
  normal_ringer=$(pct_to_level "$NORMAL_RINGER_PCT" "$ringer_max")
  _set_volume music "$normal_media"
  _set_volume ring "$normal_ringer"
  _set_volume notification "$ringer_max"
  _toast "Normal mode: full volume"
  log "Applied normal mode (media=${normal_media}/${media_max}, ringer=${normal_ringer}/${ringer_max})"
}

# ── STATE ─────────────────────────────────────────────────────
IN_COLLEGE=0
LAST_VOLUME_CHANGE=0
COLLEGE_MEDIA_LEVEL=""

# ── MAIN LOOP ─────────────────────────────────────────────────
log "========================================"
log "college-mode daemon starting"
log "Target: ${COLLEGE_LAT}, ${COLLEGE_LON} (r=${RADIUS_METERS}m)"
log "Interval: ${CHECK_INTERVAL}s | Revert: ${RESET_MINUTES}m"
[ "$TEST_MODE" = "1" ] && log "*** TEST MODE ACTIVE ***"
log "========================================"

while true; do
HOUR=$(date +%H%M)
  if [ "$HOUR" -lt "0730" ] || [ "$HOUR" -gt "1730" ]; then
    sleep 60
    continue
  fi


  location=$(_get_location)

  if [ -z "$location" ]; then
    log "WARN: Could not get location"
    sleep "$CHECK_INTERVAL"
    continue
  fi

  CURR_LAT=$(echo "$location" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('latitude',''))" 2>/dev/null)
  CURR_LON=$(echo "$location" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('longitude',''))" 2>/dev/null)

  if [ -z "$CURR_LAT" ] || [ -z "$CURR_LON" ]; then
    log "WARN: Empty coordinates"
    sleep "$CHECK_INTERVAL"
    continue
  fi

  DIST=$(haversine "$CURR_LAT" "$CURR_LON" "$COLLEGE_LAT" "$COLLEGE_LON")

  log "Coords: ${CURR_LAT}, ${CURR_LON} | Dist: ${DIST}m | In college: ${IN_COLLEGE}"

  if [ "$DIST" -le "$RADIUS_METERS" ]; then

    if [ "$IN_COLLEGE" -eq 0 ]; then
      log ">>> Entered college (${DIST}m)"
      IN_COLLEGE=1
      apply_college_mode
      LAST_VOLUME_CHANGE=0

    else
      CURR_VOL=$(get_stream_volume music)
      log "Volume check: current=${CURR_VOL} target=${COLLEGE_MEDIA_LEVEL}"

      if [ -n "$CURR_VOL" ] && [ -n "$COLLEGE_MEDIA_LEVEL" ] && [ "$CURR_VOL" != "$COLLEGE_MEDIA_LEVEL" ]; then
        NOW=$(date +%s)
        if [ "$LAST_VOLUME_CHANGE" -eq 0 ]; then
          LAST_VOLUME_CHANGE=$NOW
          log "Volume manually changed: ${CURR_VOL} → will revert in ${RESET_MINUTES}m"
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
    fi

  else
    if [ "$IN_COLLEGE" -eq 1 ]; then
      log "<<< Left college (${DIST}m)"
      IN_COLLEGE=0
      LAST_VOLUME_CHANGE=0
      COLLEGE_MEDIA_LEVEL=""
      apply_normal_mode
    fi
  fi

  sleep "$CHECK_INTERVAL"
done
