# college-mode

Automatically switches your Android phone to vibrate + 20% volume when you enter college, and restores full volume when you leave. Built with Termux and pure bash — no paid apps, no root required.

## Demo

| Scenario | Behavior |
|---|---|
| Enter college geofence | Vibrate on, media → 20%, notification → 0 |
| Leave college geofence | Ringer on, media → 100%, notification → max |
| Headphones connected | Volume unchanged regardless of location |
| Manual volume change inside college | Reverts back after 5 minutes |
| Outside active hours (7:30am–5:30pm) | Script sleeps, no changes made |
| Phone reboot | Script auto-restarts via Termux:Boot |

---

## Requirements

- Android phone (tested on **Pixel 8, Android 16**)
- [Termux](https://f-droid.org/repo/com.termux_118.apk) — install from F-Droid (not Play Store)
- [Termux:API](https://f-droid.org/repo/com.termux.api_51.apk) — install from F-Droid
- [Termux:Boot](https://f-droid.org/repo/com.termux.boot_7.apk) — install from F-Droid

> Use F-Droid versions only. The Play Store versions of Termux are outdated and missing features.

---

## Installation

### 1. Install Termux and plugins

Download the three APKs above and install via ADB from your computer:

```bash
adb install termux.apk
adb install termux-api.apk
adb install termux-boot.apk
```

Or sideload directly on the phone by tapping the downloaded APKs.

### 2. Grant permissions

Open Termux and run:

```bash
termux-setup-storage
```

Tap **Allow** on the permission popup. Then grant the following manually:

- **Location** → Settings → Apps → Termux → Permissions → Location → Allow all the time
- **Battery** → Settings → Apps → Termux → Battery → Unrestricted
- Open **Termux:Boot** app once to activate boot listener

### 3. Install dependencies

Inside Termux:

```bash
pkg install termux-api python git
```

### 4. Clone the repo

```bash
git clone https://github.com/chakri192/college-mode.git
cd college-mode
```

### 5. Set your college coordinates

Edit `college_mode.sh` and update the default values:

```bash
COLLEGE_LAT="${COLLEGE_LAT:-YOUR_LAT}"
COLLEGE_LON="${COLLEGE_LON:-YOUR_LON}"
```

To get your coordinates: open Google Maps → long press your college building → coordinates appear at the top.

Or use sed:

```bash
sed -i 's/COLLEGE_LAT:-0.000000/COLLEGE_LAT:-YOUR_LAT/' college_mode.sh
sed -i 's/COLLEGE_LON:-0.000000/COLLEGE_LON:-YOUR_LON/' college_mode.sh
```

### 6. Run

```bash
chmod +x college_mode.sh
nohup bash college_mode.sh > ~/college.log 2>&1 &
```

### 7. Auto-start on reboot

```bash
mkdir -p ~/.termux/boot
echo '#!/data/data/com.termux/files/usr/bin/bash
nohup bash ~/college_mode.sh > ~/college.log 2>&1 &' > ~/.termux/boot/start.sh
chmod +x ~/.termux/boot/start.sh
```

Make sure you have opened the **Termux:Boot** app at least once to activate it.

---

## Configuration

All values can be overridden via environment variables without editing the script.

| Variable | Default | Description |
|---|---|---|
| `COLLEGE_LAT` | `0.000000` | College latitude |
| `COLLEGE_LON` | `0.000000` | College longitude |
| `RADIUS_METERS` | `150` | Geofence radius in meters |
| `CHECK_INTERVAL` | `60` | Location check interval in seconds |
| `REVERT_MINUTES` | `5` | Minutes before reverting manual volume change |
| `COLLEGE_MEDIA_PCT` | `20` | Media volume inside college as percentage |
| `COLLEGE_RINGER` | `0` | Ringer volume inside college |
| `NORMAL_RINGER` | `7` | Ringer volume outside college |
| `ACTIVE_START` | `0730` | Script active from this time (24hr format, HHMM) |
| `ACTIVE_END` | `1730` | Script active until this time (24hr format, HHMM) |

Example — run with custom radius and faster revert for testing:

```bash
RADIUS_METERS=300 REVERT_MINUTES=1 bash college_mode.sh
```

---

## Testing

### Test without going to college

Set your current location as the college target:

```bash
COLLEGE_LAT=YOUR_CURRENT_LAT COLLEGE_LON=YOUR_CURRENT_LON RADIUS_METERS=200 bash college_mode.sh
```

Should immediately print `Entered college` and drop volume.

### Test volume revert

While the above test is running, change volume with physical buttons. Within 60 seconds the log should show:

```
Volume manually changed: X → will revert in 5m
```

After 5 minutes:

```
Reverting volume after 5m
```

### Test headphone bypass

Plug in wired earphones, then run the location test above. Log should show:

```
Headphones connected — skipping college volume change
```

### Automated test suite (runs on Mac/Linux, no phone needed)

```bash
chmod +x test_college_mode.sh
bash test_college_mode.sh
```

Runs 7 scenarios including enter/exit geofence, headphone bypass, volume revert timer, and bad location handling.

---

## Useful Commands

```bash
# Check if running
college-status

# View live log
college-log

# Stop
college-stop

# Restart
college
```

Add these aliases to `~/.bashrc` in Termux:

```bash
echo "alias college='nohup bash ~/college_mode.sh > ~/college.log 2>&1 &'" >> ~/.bashrc
echo "alias college-stop='pkill -f college_mode.sh'" >> ~/.bashrc
echo "alias college-log='tail -f ~/college.log'" >> ~/.bashrc
echo "alias college-status='pgrep -f college_mode.sh && echo running || echo stopped'" >> ~/.bashrc
source ~/.bashrc
```

---

## How It Works

1. Runs as a background daemon inside Termux
2. Outside active hours (7:30am–5:30pm) the script sleeps and makes no changes
3. Every 60 seconds fetches your GPS coordinates via `termux-location` (network fallback if GPS unavailable)
4. Calculates distance to college using the **Haversine formula**
5. Within radius → applies college profile (vibrate + 20% media volume)
6. Outside radius → applies normal profile (full volume + ringer)
7. Before every volume change, checks for wired or Bluetooth headphones — skips if connected
8. Tracks manual volume changes inside college and reverts after 5 minutes
9. Logs every action with timestamps to `~/college.log`

---

## Resource Usage

| Resource | Usage |
|---|---|
| CPU | Near zero — sleeps 60s between cycles |
| RAM | ~15–20MB |
| Battery | ~1–3% extra per day (GPS ping every 60s) |
| Storage | ~162MB total (Python + Termux) |

To reduce battery impact, increase `CHECK_INTERVAL` to 120 or 180 seconds.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Script stops after a while | Settings → Apps → Termux → Battery → Unrestricted |
| Location not updating | Grant location "Allow all the time" to Termux |
| Volume not changing | Grant DND access to Termux:API |
| Doesn't start on reboot | Open Termux:Boot app once to activate |
| Geofence triggers too early | Increase `RADIUS_METERS` to 200–300 |
| Geofence triggers too late | Decrease `RADIUS_METERS` to 100 |
| VPN interference | GPS mode unaffected by VPN; network fallback may be affected |
| Nothing happens at college | Check time — script only runs 7:30am–5:30pm |

---

## Notes

- **Active hours**: Script only runs between 7:30am and 5:30pm. Outside those hours it sleeps and makes no volume changes, saving battery. Edit `HOUR -lt "0730"` and `HOUR -gt "1730"` in the script to change the window.
- **VPN**: GPS hardware is unaffected by VPN. Only the network location fallback could theoretically be affected, but in practice Android's location service is local and bypasses the VPN tunnel.
- **Always-on display**: The 5-minute revert is purely time-based and does not depend on screen state, so it works with always-on display enabled.

---

## License

MIT

## Contributors

| Contributor | Role |
|-------------|------|
| [chakri192](https://github.com/chakri192) | Author |
| [aider](https://github.com/Aider-AI/aider) | AI pair programmer |

### AI tooling

README and code contributions assisted by [aider](https://github.com/Aider-AI/aider) using local LLMs via [Ollama](https://ollama.com):

| Model | Used for |
|-------|----------|
| `qwen2.5-coder:7b` | Code suggestions, refactoring |
| `llama3.1:8b` | Prose, documentation, commit messages |
