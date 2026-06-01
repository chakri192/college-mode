
#!/data/data/com.termux/files/usr/bin/bash
COLLEGE_LAT=0.000000
COLLEGE_LON=0.000000
RADIUS_METERS=150
CHECK_INTERVAL=120
RESET_MINUTES=5
COLLEGE_MEDIA=3
COLLEGE_RINGER=0
NORMAL_MEDIA=15
NORMAL_RINGER=7
IN_COLLEGE=0
LAST_VOLUME_CHANGE=0
distance() {
  python3 -c "
import math
lat1,lon1,lat2,lon2 = map(math.radians, [$1,$2,$3,$4])
dlat=lat2-lat1; dlon=lon2-lon1
a=math.sin(dlat/2)**2+math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
print(int(6371000*2*math.asin(math.sqrt(a))))
"
}
headphones_connected() {
  audio_state=$(termux-audio-info 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wired_headset_connected',False))" 2>/dev/null)
  [ "$audio_state" = "True" ] && return 0
  bt_state=$(termux-bluetooth-info 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(any(x.get('connected') for x in d.get('paired_devices',[])))" 2>/dev/null)
  [ "$bt_state" = "True" ] && return 0
  return 1
}
apply_college_mode() {
  headphones_connected && return
  termux-volume music $COLLEGE_MEDIA
  termux-volume ring $COLLEGE_RINGER
  termux-volume notification 0
  termux-toast "College mode: vibrate + 20%"
}
apply_normal_mode() {
  headphones_connected && return
  termux-volume music $NORMAL_MEDIA
  termux-volume ring $NORMAL_RINGER
  termux-volume notification 7
  termux-toast "Normal mode: full volume"
}
get_current_media_volume() {
  termux-volume 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for item in d:
  if item.get('stream')=='music':
    print(item.get('volume',0)); break
" 2>/dev/null
}
echo "College mode daemon started"
while true; do
  location=$(termux-location -p gps -r once 2>/dev/null)
  if [ -z "$location" ]; then
    location=$(termux-location -p network -r once 2>/dev/null)
  fi
  CURR_LAT=$(echo "$location" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('latitude','0'))" 2>/dev/null)
  CURR_LON=$(echo "$location" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('longitude','0'))" 2>/dev/null)
  if [ -z "$CURR_LAT" ] || [ "$CURR_LAT" = "0" ]; then
    sleep $CHECK_INTERVAL
    continue
  fi
  DIST=$(distance $CURR_LAT $CURR_LON $COLLEGE_LAT $COLLEGE_LON)
  if [ "$DIST" -le "$RADIUS_METERS" ]; then
    if [ "$IN_COLLEGE" -eq 0 ]; then
      echo "Entered college (${DIST}m)"
      IN_COLLEGE=1
      apply_college_mode
      LAST_VOLUME_CHANGE=0
    else
      CURR_VOL=$(get_current_media_volume)
      if [ "$CURR_VOL" != "$COLLEGE_MEDIA" ] && [ "$CURR_VOL" != "" ]; then
        NOW=$(date +%s)
        if [ "$LAST_VOLUME_CHANGE" -eq 0 ]; then
          LAST_VOLUME_CHANGE=$NOW
          echo "Volume manually changed to $CURR_VOL, will revert in ${RESET_MINUTES}m"
        else
          ELAPSED=$(( (NOW - LAST_VOLUME_CHANGE) / 60 ))
          if [ "$ELAPSED" -ge "$RESET_MINUTES" ]; then
            echo "Reverting volume after ${ELAPSED}m"
            apply_college_mode
            LAST_VOLUME_CHANGE=0
          fi
        fi
      else
        LAST_VOLUME_CHANGE=0
      fi
    fi
  else
    if [ "$IN_COLLEGE" -eq 1 ]; then
      echo "Left college (${DIST}m)"
      IN_COLLEGE=0
      LAST_VOLUME_CHANGE=0
      apply_normal_mode
    fi
  fi
  sleep $CHECK_INTERVAL
done
