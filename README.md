# college-mode

Puts your Android phone on vibrate when you get to college and turns the volume back up when you leave. Runs as a bash script in Termux. No root needed.

## What it does

- Within 150 m of your college: ringer to vibrate, media volume to 20%, notifications muted.
- More than 250 m away: everything back to full volume.
- Only active between 07:30 and 17:30. Outside those hours it doesn't use location at all.
- With headphones connected, it waits and applies the change once you unplug them.
- If you turn the volume up while on campus, it's set back after 5 minutes.
- If the script is stopped while you're on campus, it restores full volume first.
- If Android kills it, the boot script starts it again within 30 seconds and it picks up where it left off.

## Requirements

- Android phone with [Termux](https://f-droid.org/packages/com.termux/) and [Termux:API](https://f-droid.org/packages/com.termux.api/), both from F-Droid (the Play Store versions don't work)
- [Termux:Boot](https://f-droid.org/packages/com.termux.boot/) if you want it to start automatically after a reboot

## Setup

**1. Permissions.** In Android settings:

- Location → Termux:API and Termux → **Allow all the time**
- Battery → Termux → **Unrestricted**
- Open Termux:Boot once, if you're using it

**2. Install.**

```sh
pkg install termux-api python git
git clone https://github.com/chakri192/college-mode.git ~/college-mode
chmod +x ~/college-mode/college_mode.sh
```

**3. Set your location.** Long-press your college building in Google Maps to get its coordinates, then create `~/.college-mode.env`:

```sh
export COLLEGE_LAT="12.345678"
export COLLEGE_LON="77.654321"
```

**4. Start it.**

```sh
. ~/.college-mode.env
nohup bash ~/college-mode/college_mode.sh > /dev/null 2>&1 &
```

Watch what it's doing with `tail -f ~/college.log`.

**5. Start on boot (optional).**

```sh
mkdir -p ~/.termux/boot
cp ~/college-mode/boot/college-mode.sh ~/.termux/boot/
chmod +x ~/.termux/boot/college-mode.sh
```

That script is also a watchdog. Android can kill background processes without warning, and a process killed that way can't clean up after itself. The watchdog runs the script as a child and starts it again if it dies. The script keeps a note of whether you're on campus in `~/.college-mode.state`, so a restarted copy knows to restore full volume when you leave.

It does not restart the script if you stopped it on purpose or if a setting is invalid. To stop everything, including the watchdog:

```sh
pkill -f college-mode.sh
```

`pkill -f college_mode.sh` (underscore) stops only the script, and the watchdog starts it again.

## Settings

Add any of these to `~/.college-mode.env`.

| Variable | Default | |
|---|---|---|
| `COLLEGE_LAT`, `COLLEGE_LON` | none | Your college's coordinates (required) |
| `RADIUS_METERS` | `150` | Distance that counts as arriving |
| `EXIT_RADIUS_METERS` | `250` | Distance that counts as leaving (must be larger) |
| `ACTIVE_START`, `ACTIVE_END` | `0730`, `1730` | Active hours |
| `CHECK_INTERVAL` | `60` | Seconds between location checks |
| `COLLEGE_MEDIA_PCT` | `20` | Media volume on campus, in percent |
| `COLLEGE_RINGER` | `0` | Ringer level on campus (0 = vibrate) |
| `NORMAL_RINGER_PCT` | `100` | Ringer volume after leaving, in percent |
| `RESET_MINUTES` | `5` | How long a manual volume change is kept |
| `LOG_FILE` | `~/college.log` | Log file |
| `RESTART_DELAY` | `30` | Seconds the watchdog waits before restarting a killed script |
| `TERMUX_TIMEOUT` | `30` | Seconds before a hung Termux call is given up on |

If a setting is invalid, the script stops and says why in the log.

## Log

```
[09:12:04] Coords: 12.345701, 77.654298 | Dist: 31m | In college: 0
[09:12:04] >>> Entered college (31m)
[09:12:05] Applied college mode (media=5/25, ringer=0)
[09:41:07] Volume manually changed: 14 → will revert in 5m
[09:46:09] Reverting volume after 5m
```

## Testing

Test mode fakes the location and volume, so you can try it anywhere:

```sh
TEST_MODE=1 TEST_LAT=12.345678 TEST_LON=77.654321 \
  COLLEGE_LAT=12.345678 COLLEGE_LON=77.654321 \
  CHECK_INTERVAL=2 ACTIVE_START=0000 ACTIVE_END=2359 bash college_mode.sh
```

There's also an automated test suite that runs on any machine with bash (54 checks, including the watchdog):

```sh
bash tests/run.sh
```

## Troubleshooting

| Problem | Fix |
|---|---|
| Log only shows `Could not get location` | Set location to "Allow all the time" for Termux:API and Termux |
| Stops after a few hours | Turn off battery optimisation for Termux. On Android 12 and later, also turn on **Developer options → Disable child process restrictions**, which stops Android killing background processes. Without it the watchdog restarts the script, but the kills still happen |
| `watchdog: daemon died (exit 137)` in the log | Android killed the script and the watchdog restarted it. See the row above |
| Never switches to vibrate | Check the coordinates, and that it's within active hours |
| Volume doesn't change | Headphones are connected; it will change when you unplug them |
| `already running` | Another copy is running. Stop it, or delete `~/.college-mode.pid`. For the watchdog, the file is `~/.college-mode-supervisor.pid` |
| Doesn't start after reboot | Open Termux:Boot once. If you cloned somewhere other than `~/college-mode`, add `export COLLEGE_MODE_SCRIPT=/path/to/college_mode.sh` to `~/.college-mode.env` |

## Contributors

| | |
|---|---|
| [chakri192](https://github.com/chakri192) | Author |
| [aider](https://github.com/Aider-AI/aider) | AI pair programmer |
