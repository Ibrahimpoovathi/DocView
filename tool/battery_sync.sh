#!/usr/bin/env bash
# DocView — WebDAV sync battery (Phase 7).
#
# Requires the caller to have built the battery APK first with:
#   --dart-define=DOCVIEW_BATTERY=true
#   --dart-define=DOCVIEW_BATTERY_SYNC=http://10.0.2.2:8080/dav/
#   --dart-define=DOCVIEW_BATTERY_OPEN=none
#
# Modes:
#   push    — fresh install: seed-imports books, configures the WebDAV
#             account from the define, boot-syncs (push). Two boots give
#             sync time to settle; server should end with manifest+books.
#   restore — pm clear first (fresh device): boot re-saves the account from
#             the define and pulls the library down (cloud-only docs).
#
# Host WebDAV (wsgidav) must be running: 0.0.0.0:8080 → /tmp/opencode/dav.
set -u

NAME="${1:?usage: battery_sync.sh <avd-name> <push|restore>}"
MODE="${2:?usage: battery_sync.sh <avd-name> <push|restore>}"
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

log() { echo "== $NAME/$MODE $(date) == $1" >> "$OUT/${NAME}_sync.log"; }

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
  >> "$OUT/${NAME}_sync.log" 2>&1 && log "install ok" || log "INSTALL FAILED"

if [ "$MODE" = restore ]; then
  # Fresh-device simulation: wipe app data (DB + secure storage); the
  # battery define re-saves the account at boot, then auto-sync pulls.
  "$ADB" shell pm clear com.docview.docview >/dev/null
  log "app data cleared"
fi

"$ADB" logcat -c
"$ADB" shell am start -n com.docview.docview/.MainActivity
sleep 35   # seed import + (push|pull) sync cycle
"$ADB" exec-out screencap -p > "$OUT/$NAME.sync_$MODE.png"
"$ADB" logcat -d > "$OUT/$NAME.sync_$MODE.logcat"
log "first capture done"

# Second boot: another auto-sync round + resume-style screenshot.
"$ADB" shell am force-stop com.docview.docview
sleep 2
"$ADB" shell am start -n com.docview.docview/.MainActivity
sleep 18
"$ADB" exec-out screencap -p > "$OUT/$NAME.sync_${MODE}2.png"
"$ADB" logcat -d > "$OUT/$NAME.sync_${MODE}2.logcat"
log "second capture done"

rg -i "FATAL EXCEPTION" -A8 "$OUT/$NAME.sync_$MODE.logcat" \
  "$OUT/$NAME.sync_${MODE}2.logcat" | tail -30 >> "$OUT/${NAME}_sync.log" || log "0 FATAL"

sleep 3
kill_emus; kill_daemons
"$ADB" emulator kill >/dev/null 2>&1
log "done"
