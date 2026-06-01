# college-mode

Automatically switches your Android phone to vibrate + 20% volume when you enter college, and restores full volume when you leave. Built with Termux and pure bash — no paid apps, no root required.

## Features

- Geofence-based trigger using GPS
- Auto vibrate + 20% media volume on college entry
- Auto full volume + ringer on exit
- Headphone bypass — wired and Bluetooth unaffected
- 5-minute revert if you manually change volume inside college
- Auto-starts on reboot via Termux:Boot
- Near-zero battery impact (~1-3% per day)

## Requirements

- Android phone (tested on Pixel 8, Android 16)
- [Termux](https://f-droid.org/repo/com.termux_118.apk) via F-Droid
- [Termux:API](https://f-droid.org/repo/com.termux.api_51.apk) via F-Droid
- [Termux:Boot](https://f-droid.org/repo/com.termux.boot_7.apk) via F-Droid

## Installation

### 1. Install Termux and plugins via ADB from Mac/PC
```bash
adb install termux.apk
adb install termux-api.apk
adb install termux-boot.apk
```

### 2. Inside Termux install dependencies
```bash
pkg install termux-api python
```

### 3. Clone and configure
```bash
pkg install git
git clone https://github.com/chakri192/college-mode.git
cd college-mode
```

Edit `college_mode.sh` and set your coordinates:
```bash
COLLEGE_LAT=13.00938
COLLEGE_LON=77.71497
RADIUS_METERS=150
```
Get coordinates by long pressing your college on Google Maps.

### 4. Run
```bash
chmod +x college_mode.sh
nohup bash college_mode.sh > ~/college.log 2>&1 &
```

### 5. Auto-start on reboot
```bash
mkdir -p ~/.termux/boot
echo '#!/data/data/com.termux/files/usr/bin/bash
nohup bash ~/college_mode.sh > ~/college.log 2>&1 &' > ~/.termux/boot/start.sh
chmod +x ~/.termux/boot/start.sh
```
Open Termux:Boot app once to activate.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `COLLEGE_LAT` | `13.00938` | College latitude |
| `COLLEGE_LON` | `77.71497` | College longitude |
| `RADIUS_METERS` | `150` | Geofence radius in meters |
| `CHECK_INTERVAL` | `120` | Location check interval in seconds |
| `RESET_MINUTES` | `5` | Minutes before reverting manual volume change |
| `COLLEGE_MEDIA` | `3` | Media volume inside college (out of 15) |
| `COLLEGE_RINGER` | `0` | Ringer volume inside college |
| `NORMAL_MEDIA` | `15` | Media volume outside college |
| `NORMAL_RINGER` | `7` | Ringer volume outside college |

## Useful Commands

```bash
# Check if running
pgrep -f college_mode.sh && echo running || echo stopped

# View live log
tail -f ~/college.log

# Stop
pkill -f college_mode.sh

# Restart
nohup bash ~/college_mode.sh > ~/college.log 2>&1 &
```

## How It Works

1. Runs as a background daemon in Termux
2. Every 120 seconds fetches GPS coordinates via `termux-location`
3. Calculates distance to college using the Haversine formula
4. Within 150m → vibrate + 20% volume
5. Outside 150m → full volume + ringer
6. Checks for headphones before every change — skips if connected
7. Tracks manual volume changes and reverts after 5 minutes

## Troubleshooting

| Problem | Fix |
|---|---|
| Script stops after a while | Settings → Apps → Termux → Battery → Unrestricted |
| Location not updating | Grant location "Allow all the time" to Termux |
| Volume not changing | Grant DND access to Termux:API |
| Doesn't start on reboot | Open Termux:Boot app once to activate |
