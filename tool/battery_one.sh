#!/usr/bin/env bash
# DocView — one AC cycle on a single AVD.
#
# RAM lesson (2026-11-06): Gradle/Kotlin daemons hold 3.5–4.5 GB on a
# 7.6 GB host for up to 2 h after every `flutter build apk`, which kills
# qemu silently. Therefore this script:
#   * kills daemons BEFORE and AFTER the run
#   * caps qemu at 2048 MB
#   * never builds an APK (caller must build first)
#
# usage: tool/battery_one.sh <avd-name>
set -u

NAME="${1:?usage: battery_one.sh <avd-name>}"
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

log() { echo "== $NAME $(date) == $1"; } >> "$OUT/$NAME.log"

kill_emus; kill_daemons; sleep 2
log "boot"
"$EMU" -avd "$NAME" -no-window -no-snapshot -no-boot-anim -accel on \
  -gpu swiftshader_indirect -memory 2048 >> /tmp/opencode/emu_$NAME.log 2>&1 &
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
  >> "$OUT/$NAME.log" 2>&1 && log "install ok" || log "INSTALL FAILED"

"$ADB" logcat -c
"$ADB" shell am start -n com.docview.docview/.MainActivity
sleep 20
"$ADB" exec-out screencap -p > "$OUT/$NAME.png"
sleep 3
"$ADB" shell input swipe 900 1200 200 1200 250   # page turn (left)
sleep 4
"$ADB" exec-out screencap -p > "$OUT/$NAME.turn.png"
"$ADB" logcat -d > "$OUT/$NAME.logcat"
log "screencap + logcat captured"

# resume round-trip: kill app, relaunch, capture restored position
"$ADB" shell am force-stop com.docview.docview
sleep 2
"$ADB" shell am start -n com.docview.docview/.MainActivity
sleep 14
"$ADB" exec-out screencap -p > "$OUT/$NAME.resume.png"
"$ADB" logcat -d > "$OUT/$NAME.logcat2"
log "resume captured"

grep " flutter :" "$OUT/$NAME.logcat" | grep -vE "IMPORTANT|EGL Error" \
  | head -40 >> "$OUT/$NAME.log"
rg -i "FATAL EXCEPTION" -A8 "$OUT/$NAME.logcat" \
  | tail -20 >> "$OUT/$NAME.log" || true

sleep 3
kill_emus; kill_daemons
"$ADB" emulator kill >/dev/null 2>&1
log "done"
