#!/usr/bin/env bash
# DocView — Stage D sync-fail leg, round 2.
#
# edge/_index.txt is EMPTY so the edge hook no-ops and the library screen
# stays mounted (auto-open used to unmount it before autoSync ran).
# 1. boot1: account saved by the battery hook (setup/autoSync race → no sync).
# 2. boot2: push sync vs live wsgidav → dav dir must gain files.
# 3. wsgidav killed, boot3: auto-sync fails → snackbar, no crash.
# 4. wsgidav restarted, boot4: sync recovers.
# APK built with DOCVIEW_BATTERY=true + DOCVIEW_BATTERY_SYNC + OPEN=none.
set -u

NAME="${1:?usage: battery_syncfail.sh <avd-name>}"
PROJ=/home/pseudo/Applications/OpenCode/DocView
OUT=/tmp/opencode/avd_out
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
LOG="$OUT/${NAME}_syncfail.log"
mkdir -p "$OUT"

log() { echo "== $NAME/syncfail $(date +%H:%M:%S) == $1" >> "$LOG"; }
kill_daemons() { pkill -9 -f '[G]radleDaemon' 2>/dev/null; pkill -9 -f '[K]otlinCompileDaemon' 2>/dev/null; }
kill_emus() { pkill -9 -f '[q]emu-system' 2>/dev/null; }
boot_app() {
  "$ADB" shell am force-stop com.docview.docview 2>/dev/null; sleep 2
  "$ADB" shell am start -n com.docview.docview/.MainActivity
}
dav_state() { log "dav: $(find /tmp/opencode/dav -newer /tmp/opencode/dav/edge -type f 2>/dev/null | head -5 | tr '\n' ' ')"; }

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
"$ADB" install -r "$PROJ/build/app/outputs/flutter-apk/app-x86_64-release.apk" \
  >> "$LOG" 2>&1 && log "install ok" || { log "INSTALL FAILED"; kill_emus; exit 1; }

# --- 1. boot1: account setup ---
"$ADB" logcat -c
boot_app
sleep 20
"$ADB" exec-out screencap -p > "$OUT/$NAME.sf2_boot1.png"
log "boot1 done (account setup)"

# --- 2. boot2: push sync ---
boot_app
sleep 25
"$ADB" exec-out screencap -p > "$OUT/$NAME.sf2_push.png"
"$ADB" logcat -d > "$OUT/$NAME.sf2_push.logcat"
dav_state
log "boot2 done (push)"

# --- 3. fail: kill wsgidav, boot3 ---
pkill -f wsgidav; sleep 2
curl -s -o /dev/null -m 2 http://127.0.0.1:8080/ \
  && log "wsgidav STILL UP" || log "wsgidav down"
boot_app
sleep 7    # connection-refused fails fast → snackbar ~t+3s, lasts 4s
"$ADB" exec-out screencap -p > "$OUT/$NAME.sf2_fail_early.png"
sleep 19
"$ADB" exec-out screencap -p > "$OUT/$NAME.sf2_fail.png"
"$ADB" logcat -d > "$OUT/$NAME.sf2_fail.logcat"
log "boot3 done (fail)"

# --- 4. recover: restart wsgidav, boot4 ---
~/.local/bin/wsgidav --config /tmp/opencode/wsgidav.yaml > /tmp/opencode/wsgidav.log 2>&1 &
sleep 3
curl -s -o /dev/null -m 2 http://127.0.0.1:8080/dav/edge/_index.txt \
  && log "wsgidav back up" || log "wsgidav RESTART FAILED"
boot_app
sleep 25
"$ADB" exec-out screencap -p > "$OUT/$NAME.sf2_recover.png"
"$ADB" logcat -d > "$OUT/$NAME.sf2_recover.logcat"
dav_state
log "boot4 done (recover)"

for f in sf2_push sf2_fail sf2_recover; do
  rg -i "FATAL EXCEPTION" -A8 "$OUT/$NAME.$f.logcat" | tail -12 >> "$LOG" || true
done
rg -c "FATAL EXCEPTION" "$OUT/$NAME".sf2_*.logcat >/dev/null 2>&1 || log "0 FATAL"

sleep 2
kill_emus; kill_daemons
"$ADB" emulator kill >/dev/null 2>&1
log "done"
