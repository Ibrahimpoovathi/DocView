#!/usr/bin/env bash
# DocView — Stage D+ reader-stress battery.
# Boots with the edge battery define (library auto-opens a doc), then hammers
# the reader: fast swipes both directions, center taps, menu taps, back to
# library, reopen, with rotation flips between rounds. Captures gfxinfo +
# meminfo before/after and scans for FATAL / renderer crashes.
# Usage: battery_monkey_stress.sh <avd-name> [rounds]
set -u
NAME="${1:?usage: battery_monkey_stress.sh <avd-name> [rounds]}"
ROUNDS="${2:-6}"
PROJ=/home/pseudo/Applications/OpenCode/DocView
OUT=/tmp/opencode/avd_out
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
LOG="$OUT/${NAME}_stress.log"
mkdir -p "$OUT"
log() { echo "== $NAME/stress $(date +%H:%M:%S) == $1" >> "$LOG"; }
kill_emus() { pkill -9 -f '[q]emu-system' 2>/dev/null; }

kill_emus; sleep 2
log "boot"
"$EMU" -avd "$NAME" -no-window -no-snapshot -no-boot-anim -accel on \
  -gpu swiftshader_indirect -memory 3072 >> /tmp/opencode/emu_$NAME.log 2>&1 &
sleep 40
"$ADB" wait-for-device
for i in $(seq 1 120); do
  B=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [ "$B" = "1" ] && break; sleep 1
done
log "boot done ($i s)"

# Reset airplane mode in case a monkey run toggled it (edge import needs net).
"$ADB" shell settings put global airplane_mode_on 0
"$ADB" shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false >/dev/null
"$ADB" root >/dev/null 2>&1; sleep 1

"$ADB" logcat -c
"$ADB" shell am start -n com.docview.docview/.MainActivity
sleep 20   # edge import + auto-open reader
log "reader open"

"$ADB" shell dumpsys gfxinfo com.docview.docview framestats 2>/dev/null \
  | grep -E "Total frames|Janky frames|50th|90th|95th|99th" > "$OUT/$NAME.stress_gfx_before.txt"
"$ADB" shell dumpsys meminfo com.docview.docview 2>/dev/null \
  | grep "TOTAL PSS" > "$OUT/$NAME.stress_mem_before.txt"

swipe() { # swipe <x1> <y1> <x2> <y2>
  "$ADB" shell input swipe "$1" "$2" "$3" "$4" 90
}

for r in $(seq 1 "$ROUNDS"); do
  log "round $r"
  for s in $(seq 1 12); do swipe 540 1500 540 700; done   # next-page bursts
  for s in $(seq 1 6);  do swipe 540 700 540 1500; done   # prev-page bursts
  swipe 100 1500 1000 900     # right-to-left
  swipe 1000 900 100 1500
  "$ADB" shell input tap 540 1200          # center tap (chrome toggle)
  sleep 1
  "$ADB" shell input tap 540 1200
  sleep 1
  "$ADB" shell input tap 68 130            # back arrow
  sleep 2
  "$ADB" shell input tap 240 620           # first library card (reopen)
  sleep 3
  # Rotation flip between rounds
  if [ $((r % 2)) -eq 0 ]; then
    "$ADB" shell settings put system accelerometer_rotation 0
    "$ADB" shell settings put system user_rotation 1
  else
    "$ADB" shell settings put system user_rotation 0
  fi
  sleep 2
done

"$ADB" shell settings put system user_rotation 0
sleep 3
"$ADB" shell dumpsys gfxinfo com.docview.docview framestats 2>/dev/null \
  | grep -E "Total frames|Janky frames|50th|90th|95th|99th" > "$OUT/$NAME.stress_gfx_after.txt"
"$ADB" shell dumpsys meminfo com.docview.docview 2>/dev/null \
  | grep "TOTAL PSS" > "$OUT/$NAME.stress_mem_after.txt"
"$ADB" logcat -d > "$OUT/$NAME.stress.logcat"
"$ADB" exec-out screencap -p > "$OUT/$NAME.stress_end.png"

F=$(grep -cE "FATAL EXCEPTION" "$OUT/$NAME.stress.logcat" || true)
W=$(grep -cE "aw_browser_terminator|Renderer process.*crash" "$OUT/$NAME.stress.logcat" || true)
log "FATAL=$F renderer_crashes=$W"
log "gfx before: $(cat "$OUT/$NAME.stress_gfx_before.txt" 2>/dev/null | tr '\n' ' ' | head -c 300)"
log "gfx after:  $(cat "$OUT/$NAME.stress_gfx_after.txt" 2>/dev/null | tr '\n' ' ' | head -c 300)"
log "mem before: $(cat "$OUT/$NAME.stress_mem_before.txt" 2>/dev/null)"
log "mem after:  $(cat "$OUT/$NAME.stress_mem_after.txt" 2>/dev/null)"

kill_emus
"$ADB" emulator kill >/dev/null 2>&1
log "done"
