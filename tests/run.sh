#!/usr/bin/env bash
# Scenario tests for college_mode.sh, driven entirely by TEST_MODE stubs.
# Each scenario feeds one line per poll (see TEST_SEQUENCE in the script) and
# asserts on the log. Run: bash tests/run.sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/college_mode.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Campus at 12.345678, 77.654321. 0.001 deg lat ≈ 111 m.
IN="lat=12.345678 lon=77.654321"      # 0 m
BAND="lat=12.346978 lon=77.654321"    # ~145 m: inside enter radius
MID="lat=12.347578 lon=77.654321"     # ~211 m: inside the hysteresis band
OUT="lat=12.360000 lon=77.654321"     # ~1.5 km

PASS=0 FAIL=0

# run <name> <max_iterations> [ENV=val ...] <<< sequence lines
# Leaves the log in $LOG and the exit code in $RC.
run() {
  local name=$1 iters=$2; shift 2
  LOG="$WORK/$name.log"; : > "$LOG"
  cat > "$WORK/$name.seq"
  env TEST_MODE=1 COLLEGE_LAT=12.345678 COLLEGE_LON=77.654321 \
      CHECK_INTERVAL=0 MAX_ITERATIONS="$iters" LOG_FILE="$LOG" \
      PID_FILE="$WORK/$name.pid" STATE_FILE="$WORK/$name.state" TEST_SEQUENCE="$WORK/$name.seq" "$@" \
      bash "$SCRIPT" > /dev/null 2>&1
  RC=$?
}

has()   { grep -qF -- "$1" "$LOG"; }
count() { grep -cF -- "$1" "$LOG"; }

check() {  # check <description> <command...>
  local desc=$1; shift
  if "$@"; then PASS=$((PASS + 1)); echo "  ok   $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL $desc"; fi
}
eq() { [ "$1" = "$2" ]; }

echo "enter, then leave"
run enter_exit 4 <<SEQ
time=0900 $OUT
time=0900 $IN
time=0900 $IN
time=0900 $OUT
SEQ
check "enters college"            has ">>> Entered college"
check "college media = 20% of 25" has "media=5/25"
check "leaves college"            has "<<< Left college"
check "restores media to max"     has "[SIM] set music → 25"
check "clean exit"                eq "$RC" 0

echo "jitter inside the hysteresis band"
run jitter 5 <<SEQ
time=0900 $BAND
time=0900 $MID
time=0900 $BAND
time=0900 $MID
time=0900 $BAND
SEQ
check "enters exactly once"       eq "$(count '>>> Entered')" 1
check "never leaves"              eq "$(count '<<< Left')" 0

echo "arrive wearing headphones, unplug on site (bug: state desync)"
run hp_enter 4 <<SEQ
time=0900 hp=1 $IN
time=0900 hp=1 $IN
time=0900 hp=0 $IN
time=0900 hp=0 $IN
SEQ
check "defers on arrival"         has "deferring college volume change"
check "applies once unplugged"    has "Applied college mode"
check "applied exactly once"      eq "$(count 'Applied college mode')" 1

echo "leave wearing headphones, unplug later (bug: stuck on vibrate)"
run hp_exit 5 <<SEQ
time=0900 hp=0 $IN
time=0900 hp=0 $IN
time=0900 hp=1 $OUT
time=0900 hp=1 $OUT
time=0900 hp=0 $OUT
SEQ
check "defers the restore"        has "deferring normal volume restore"
check "restores after unplug"     has "Applied normal mode"

echo "window closes while on site (bug: never restored)"
run window 3 <<SEQ
time=1700 $IN
time=1729 $IN
time=1731 $IN
SEQ
check "restores at close"         has "Active window closed while on site"
check "normal mode applied"       has "Applied normal mode"
check "not polling after close"   eq "$(count 'Coords:')" 2

echo "dormant outside the window"
run dormant 3 <<SEQ
time=0600 $IN
time=0600 $IN
time=2300 $IN
SEQ
check "no location polling"       eq "$(count 'Coords:')" 0
check "no volume changes"         eq "$(count 'SIM')" 0

echo "custom window via ACTIVE_START/ACTIVE_END"
run custom 2 ACTIVE_START=0600 ACTIVE_END=2200 <<SEQ
time=0630 $IN
time=0630 $IN
SEQ
check "0630 is inside 0600-2200"  has ">>> Entered college"

echo "manual volume override reverts after RESET_MINUTES"
run override 5 <<SEQ
time=0900 min=0 $IN
time=0900 min=1 vol=14 $IN
time=0900 min=3 $IN
time=0900 min=7 $IN
time=0900 min=8 $IN
SEQ
check "notices the change"        has "Volume manually changed: 14"
check "reverts after 5+ min"      has "Reverting volume after"

echo "restoring the volume resets the timer"
run override_reset 4 <<SEQ
time=0900 min=0 $IN
time=0900 min=1 vol=14 $IN
time=0900 min=2 vol=5 $IN
time=0900 min=9 $IN
SEQ
check "timer reset"               has "timer reset"
check "no revert"                 eq "$(count 'Reverting volume')" 0

echo "malformed location does not crash"
run badloc 3 <<SEQ
time=0900 loc=bad $IN
time=0900 $IN
time=0900 $IN
SEQ
check "warns"                     has "WARN: Unusable location fix"
check "recovers and enters"       has ">>> Entered college"
check "no shell errors in log"    eq "$(count 'integer expression')" 0

echo "hung termux-location times out instead of freezing"
STUBS="$WORK/stubs"; mkdir -p "$STUBS"
printf '#!/bin/sh\nsleep 30\n' > "$STUBS/termux-location"
for c in termux-volume termux-audio-info termux-toast; do printf '#!/bin/sh\nexit 0\n' > "$STUBS/$c"; done
chmod +x "$STUBS"/*
START=$SECONDS
run hung 1 TEST_MODE=0 PATH="$STUBS:$PATH" TERMUX_TIMEOUT=1 ACTIVE_START=0000 ACTIVE_END=2359 <<< "$IN"
check "logs a warning"            has "WARN: Could not get location"
check "returns within 10s"        test $((SECONDS - START)) -lt 10
check "exits cleanly"             eq "$RC" 0

echo "startup validation"
run coords0 1 COLLEGE_LAT=0.000000 COLLEGE_LON=0.000000 <<< "$IN"
check "rejects 0,0"               eq "$RC" 1
run radii 1 RADIUS_METERS=300 EXIT_RADIUS_METERS=200 <<< "$IN"
check "rejects exit <= enter"     eq "$RC" 1
run badto 1 TERMUX_TIMEOUT=0 <<< "$IN"
check "rejects zero timeout"      eq "$RC" 1
run badwin 1 ACTIVE_START=2500 <<< "$IN"
check "rejects bad HHMM"          eq "$RC" 1
run inject 1 COLLEGE_LAT="0;touch $WORK/pwned" <<< "$IN"
check "rejects code in config"    eq "$RC" 1
check "nothing executed"          test ! -e "$WORK/pwned"

echo "duplicate instance"
echo $$ > "$WORK/dup.pid"          # this shell is alive, so the lock is held
run dup 1 PID_FILE="$WORK/dup.pid" <<< "time=0900 $IN"
check "refuses to start"          eq "$RC" 1
check "says why"                  has "already running"
echo 999999 > "$WORK/stale.pid"    # dead pid: lock is stale
run stale 1 PID_FILE="$WORK/stale.pid" <<< "time=0900 $OUT"
check "takes over a stale lock"   eq "$RC" 0
check "lock removed on exit"      test ! -e "$WORK/stale.pid"

echo "shutdown on site restores volume"
run shutdown 2 <<SEQ
time=0900 $IN
time=0900 $IN
SEQ
check "restores on exit"          has "Shutting down — restoring normal volume"

echo "daemon killed on site, restarted after leaving (bug: stuck on college volume)"
echo 1 > "$WORK/resume_out.state"
run resume_out 2 STATE_FILE="$WORK/resume_out.state" <<SEQ
time=0900 $OUT
time=0900 $OUT
SEQ
check "resumes the visit"         has "Resuming: previous run ended while on site"
check "restores on leaving"       has "<<< Left college"
check "normal volume applied"     has "Applied normal mode"
check "state cleared"             eq "$(cat "$WORK/resume_out.state")" 0

echo "daemon killed on site, restarted still on site"
echo 1 > "$WORK/resume_in.state"
run resume_in 2 STATE_FILE="$WORK/resume_in.state" <<SEQ
time=0900 $IN
time=0900 $IN
SEQ
check "does not re-enter"         eq "$(count '>>> Entered')" 0
check "does not reset volume"     eq "$(count 'Applied college mode')" 0

echo "state file tracks visits"
run state_on 2 <<SEQ
time=0900 $IN
time=0900 $IN
SEQ
check "cleared by clean shutdown" eq "$(cat "$WORK/state_on.state")" 0

echo "log rotation"
seq 1 500 | sed 's/^/filler line /' > "$WORK/rot.log"
run rot 1 LOG_FILE="$WORK/rot.log" LOG_MAX_BYTES=2000 LOG_KEEP_LINES=20 <<< "time=0600 $OUT"
check "log truncated"             test "$(wc -l < "$WORK/rot.log")" -lt 100

echo "watchdog"
BOOT="$ROOT/boot/college-mode.sh"
FAKE="$WORK/fake_daemon.sh"
cat > "$FAKE" <<'FAKE'
#!/usr/bin/env bash
# dies with SIGKILL-style status twice, then exits as if stopped by SIGTERM
n=$(cat "$COUNT_FILE" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$COUNT_FILE"
case "$n" in 1|2) exit 137 ;; *) exit "${FINAL_RC:-143}" ;; esac
FAKE
wd() {  # wd <name> <final_rc> -> runs the supervisor; COUNT in $WORK/<name>.count
  LOG="$WORK/$1.log"; : > "$LOG"; rm -f "$WORK/$1.count"
  env HOME="$WORK" COLLEGE_MODE_SCRIPT="$FAKE" COUNT_FILE="$WORK/$1.count" FINAL_RC="$2" \
      LOG_FILE="$LOG" RESTART_DELAY=0 SUPERVISOR_PID_FILE="$WORK/$1.sup" \
      timeout 20 bash "$BOOT" > /dev/null 2>&1
  RC=$?
}
wd killed 143
check "restarts after each kill"  eq "$(cat "$WORK/killed.count")" 3
check "logs both deaths"          eq "$(count 'daemon died (exit 137)')" 2
check "stops on deliberate TERM"  has "not restarting"
check "supervisor lock removed"   test ! -e "$WORK/killed.sup"
wd clean 0
check "no restart after clean exit" eq "$(cat "$WORK/clean.count")" 3
echo 12345 > "$WORK/dupsup.sup"; sleep 30 & SLP=$!; echo $SLP > "$WORK/dupsup.sup"
LOG="$WORK/dupsup.log"; : > "$LOG"
env HOME="$WORK" COLLEGE_MODE_SCRIPT="$FAKE" COUNT_FILE="$WORK/dupsup.count" LOG_FILE="$LOG" \
    SUPERVISOR_PID_FILE="$WORK/dupsup.sup" timeout 10 bash "$BOOT" > /dev/null 2>&1
kill $SLP 2> /dev/null; wait $SLP 2> /dev/null
check "second supervisor declines" has "already supervising"
check "and starts no daemon"       test ! -e "$WORK/dupsup.count"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
