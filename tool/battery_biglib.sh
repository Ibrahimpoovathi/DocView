#!/usr/bin/env bash
# DocView — big-library battery (Phase 9).
#
# Requires the caller to have built the battery APK first with:
#   --dart-define=DOCVIEW_BATTERY=true
#   --dart-define=DOCVIEW_BATTERY_BIGLIB=200
#   --dart-define=DOCVIEW_BATTERY_OPEN=none
#
# Flow: fresh install → 200-doc seed (+ 8 normal seeds) → library grid
# capture → fling scroll → second capture. Measures cold-start activity
# wait time and exercises scroll/grid building on a big library.
set -u

NAME="${1:?usage: battery_biglib.sh <avd-name>}"
PROJ=/home/pseudo/Applications/OpenCode/DocView
OUT=/tmp/opencode/avd_out
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
mkdir -p "$OUT"

kill_daemons() {
  pkill -9 -f '[G]radleDaemon' 2>/dev/null
  pkill -9 -f '[K]otlinCompileDaemon' 2>/dev/null
}
kill_emus() { pkill -9 -f '[q]emu-system' 2>/dev/null; }

log() { echo "== $NAME/biglib $(date) == $1" >> "$OUT/${NAME}_biglib.log"; }

kill_emus; kill_daemons; sleep 2
log "boot"
"$EMU" -avd "$NAME" -no-window -no-snapshot -no-boot-anim -accel on \
  -gpu swiftshader_indirect -memory 3072 >> /tmp/opencode/emu_$NAME.log 2>&1 &
sleep 30
"$ADB" wait-for-device
for i in $(seq 1 120); do
  B=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [ "$B" = "1" ] && break
  sleep 1
done
log "boot done ($i s)"

"$ADB" shell pm uninstall com.docview.docview >/dev/null 2>&1
"$ADB" install -r "$PROJ/build/app/outputs/flutter-apk/app-release.apk" \
  >> "$OUT/${NAME}_biglib.log" 2>&1 && log "install ok" || log "INSTALL FAILED"

"$ADB" logcat -c
"$ADB" shell am start -W -n com.docview.docview/.MainActivity \
  > "$OUT/$NAME.biglib_amstart.txt" 2>&1
cat "$OUT/$NAME.biglib_amstart.txt" >> "$OUT/${NAME}_biglib.log"
sleep 45   # seed 208 docs (8 + 200) + grid settle
"$ADB" exec-out screencap -p > "$OUT/$NAME.biglib_grid.png"
log "grid capture done"

# Host-load noise can pop a modal "System UI isn't responding" dialog that
# swallows all input — detect it via uiautomator and tap its "Wait" button.
"$ADB" exec-out uiautomator dump /dev/tty 2>/dev/null > "$OUT/$NAME.biglib_ui.xml" || true
if grep -q "not responding" "$OUT/$NAME.biglib_ui.xml" 2>/dev/null; then
  BOUDS_LINE=$(grep -o '<node[^>]*text="Wait"[^>]*' "$OUT/$NAME.biglib_ui.xml" | head -1)
  BOUNDS=$(printf '%s' "$BOUDS_LINE" | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | tr -d '"' | tr -d 'bounds=')
  X1=${BOUNDS%%,*}; REST=${BOUNDS#*,}
  Y1=${REST%%]*}; PAIR=${BOUNDS#*][}
  X2=${PAIR%%,*}; Y2=${PAIR#*,}; Y2=${Y2%]*}
  "$ADB" shell input tap $(( (X1 + X2) / 2 )) $(( (Y1 + Y2) / 2 )) 2>/dev/null || true
  sleep 2
  log "ANR dialog dismissed (Wait)"
fi

# Fling scrolls (up x4) — exercise lazy grid building on 200+ cards.
for i in 1 2 3 4; do
  "$ADB" shell input swipe 540 1700 540 500 200
  sleep 1
done
"$ADB" exec-out screencap -p > "$OUT/$NAME.biglib_scrolled.png"
"$ADB" logcat -d > "$OUT/$NAME.biglib.logcat"
log "scroll capture done"

rg -i "FATAL EXCEPTION" -A8 "$OUT/$NAME.biglib.logcat" \
  | tail -30 >> "$OUT/${NAME}_biglib.log" || log "0 FATAL"

sleep 3
kill_emus; kill_daemons
"$ADB" emulator kill >/dev/null 2>&1
log "done"
