<div align="center">

# college-mode

**Location-aware volume management for Android, in pure bash.**

Switches the phone to vibrate on arrival at a defined location and restores full volume on departure. No root, no paid automation app, no account.

<p>
  <img alt="Platform" src="https://img.shields.io/badge/Android-Termux-1c1c1e?style=flat-square&logo=android&logoColor=3DDC84" />
  <img alt="Shell" src="https://img.shields.io/badge/pure-bash-1c1c1e?style=flat-square&logo=gnubash&logoColor=4EAA25" />
  <img alt="Root" src="https://img.shields.io/badge/root-not%20required-1c1c1e?style=flat-square" />
  <img alt="Tested" src="https://img.shields.io/badge/tested-Pixel%208%20·%20Android%2016-1c1c1e?style=flat-square" />
</p>

</div>

---

## Overview

Within 150 m of the configured location, the phone drops to vibrate with media volume at 20%. Beyond 250 m, full volume is restored. Between those two distances nothing happens, which is what prevents the script oscillating.

It also defers to the user in two situations: outside configured hours it does not activate the GPS at all, and while headphones are connected it does not alter volume in either direction. A change deferred by headphones is not lost: it is applied as soon as they are removed.

| Condition | Behaviour |
|---|---|
| Entering the 150 m radius | Vibrate, media 20%, notifications 0, confirmation toast |
| Beyond the 250 m radius | Ringer restored, media 100%, notifications maximum |
| Movement near the boundary | No change — entry and exit thresholds differ |
| Headphones connected, wired or Bluetooth | No change while connected; the pending profile is applied once removed |
| Volume raised manually on site | Left for five minutes, then restored |
| Outside 07:30–17:30 | Dormant; location is not polled. If still on site when the window closes, full volume is restored |
| Daemon stopped (`kill`, Ctrl-C) while on site | Full volume is restored before exit |
| Second instance started | Refuses to run while the first is alive |
| Device reboot | Restarted by Termux:Boot |

## Why two radii

A single 150 m geofence is unreliable in practice. Consumer GPS drifts by tens of metres while stationary, so a device resting at 148 m reports 152 m a minute later and 147 m after that. Each crossing would toggle the ringer, emit a toast, and revert any manual adjustment.

Entry and exit therefore use different thresholds: entry at 150 m, exit only beyond 250 m. The intervening band absorbs positional noise, and crossing both requires actual movement.

The same principle governs manual overrides. Raising the volume on site starts a five-minute timer rather than triggering an immediate correction. Restoring it manually resets the timer; leaving it causes the configured state to be reapplied.

## Requirements

- Android device with [Termux](https://f-droid.org/repo/com.termux_118.apk), [Termux:API](https://f-droid.org/repo/com.termux.api_51.apk), and [Termux:Boot](https://f-droid.org/repo/com.termux.boot_7.apk), installed **from F-Droid**. The Play Store builds are outdated and lack the required functionality.
- `termux-api`, `python`, and `git` packages. Python is used only to parse the JSON returned by the `termux-*` utilities and to compute haversine distance.

## Installation

### 1. Permissions

```sh
termux-setup-storage
```

In Android settings:

- **Location** → Termux → **Allow all the time**. "While in use" is insufficient for a background process.
- **Battery** → Termux → **Unrestricted**.
- Open the Termux:Boot application once to activate it.

### 2. Dependencies

```sh
pkg install termux-api python git
git clone https://github.com/chakri192/college-mode.git
cd college-mode && chmod +x college_mode.sh
```

### 3. Coordinates

Obtain them from Google Maps by long-pressing the target building. Configure them in the shell profile rather than editing the script:

```sh
export COLLEGE_LAT="12.345678"
export COLLEGE_LON="77.654321"
```

The defaults are `0.000000`, so the script takes no action until these are set.

### 4. Startup

```sh
nohup bash college_mode.sh > /dev/null 2>&1 &
```

The script writes `~/college.log` itself, so stdout is discarded. Redirecting it to the same file would duplicate every line.

### 5. Start on boot

Put the configuration in `~/.college-mode.env`:

```sh
export COLLEGE_LAT="12.345678"
export COLLEGE_LON="77.654321"
```

Then install the boot script. It takes a wake lock, loads that file, and starts the daemon:

```sh
mkdir -p ~/.termux/boot
cp boot/college-mode.sh ~/.termux/boot/ && chmod +x ~/.termux/boot/college-mode.sh
```

Termux:Boot must have been opened once (see Permissions). The lock file prevents a second copy if the daemon is already running.

## Testing without travelling

`TEST_MODE=1` replaces every Termux call with a stub — synthetic coordinates, volume levels, and headphone state — and logs the actions it would otherwise perform.

```sh
TEST_MODE=1 TEST_LAT=12.345678 TEST_LON=77.654321 \
  COLLEGE_LAT=12.345678 COLLEGE_LON=77.654321 \
  CHECK_INTERVAL=2 bash college_mode.sh
```

Adding `TEST_HEADPHONES=1` verifies the headphone bypass. Volume changes are logged as `[SIM] set music → 5`; no device state is modified.

### Automated scenarios

```sh
bash tests/run.sh
```

The suite drives the daemon through scripted scenarios, one line per poll, and asserts on the log. It covers entry and exit, jitter inside the hysteresis band, headphones on arrival and departure, the active window closing on site, the manual-override timer, malformed location data, configuration validation, duplicate instances, and log rotation. It needs no device.

## Configuration

All values are environment variables.

| Variable | Default | Description |
|---|---|---|
| `COLLEGE_LAT` · `COLLEGE_LON` | `0.000000` | Target coordinates — **required** |
| `RADIUS_METERS` | `150` | Entry threshold |
| `EXIT_RADIUS_METERS` | `250` | Exit threshold; must exceed the entry threshold |
| `CHECK_INTERVAL` | `60` | Seconds between location polls |
| `RESET_MINUTES` | `5` | Duration a manual override is honoured |
| `COLLEGE_MEDIA_PCT` | `20` | On-site media volume, as a percentage of maximum |
| `COLLEGE_RINGER` | `0` | On-site ringer level; `0` is vibrate |
| `NORMAL_RINGER_PCT` | `100` | Ringer percentage after departure |
| `ACTIVE_START` · `ACTIVE_END` | `0730` · `1730` | Daily active window, `HHMM` |
| `LOG_FILE` | `~/college.log` | Log destination |
| `LOG_MAX_BYTES` · `LOG_KEEP_LINES` | `1048576` · `1000` | Log is trimmed to the last `LOG_KEEP_LINES` lines beyond this size |
| `PID_FILE` | `~/.college-mode.pid` | Lock file preventing duplicate instances |
| `TERMUX_TIMEOUT` | `30` | Seconds before a hung `termux-*` call is abandoned and logged as a warning |

Test-mode variables: `TEST_MODE`, `TEST_LAT`, `TEST_LON`, `TEST_MUSIC_VOL`, `TEST_MAX_VOL`, `TEST_HEADPHONES`, `TEST_BLUETOOTH`.

Invalid values (for example an exit radius not larger than the entry radius, or coordinates still at `0,0`) are rejected at startup with a message in the log and on stderr.

## Operation

```sh
tail -f ~/college.log
```

```
[09:12:04] Coords: 12.345701, 77.654298 | Dist: 31m | In college: 0
[09:12:04] >>> Entered college (31m)
[09:12:05] Applied college mode (media=5/25, ringer=0)
[09:41:07] Volume manually changed: 14 → will revert in 5m
[09:46:09] Reverting volume after 5m
```

## Troubleshooting

| Symptom | Cause |
|---|---|
| Only `WARN: Could not get location` | Location permission set to "while in use". Grant **Allow all the time** to both **Termux** and **Termux:API**; the API app is the one that requests location |
| Terminates after several hours | Battery optimisation enabled for Termux |
| Never registers entry | Coordinates unset, or latitude and longitude transposed |
| Repeated toggling | Not possible with a valid config: an exit radius at or below the entry radius is rejected at startup |
| Volume changes deferred | Headphones or a Bluetooth audio device connected — intentional; applied once removed |
| No activity at any point | Current time outside `ACTIVE_START`–`ACTIVE_END` |
| `already running` on start | Another instance holds `PID_FILE`; stop it or delete a stale file |
| Exits immediately | Check the last log line: invalid configuration is reported there |

## Resource usage

Location is polled once per minute during the active window and not at all outside it, using the network provider in preference to GPS. Each poll costs two short Python invocations (location and distance, volume state). This is the difference between a script that remains installed and one that is removed after a day.

## Contributors

| | |
|---|---|
| [chakri192](https://github.com/chakri192) | Author |
| [aider](https://github.com/Aider-AI/aider) | AI pair programmer |
