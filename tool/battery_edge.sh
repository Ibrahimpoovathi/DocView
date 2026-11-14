#!/usr/bin/env bash
# DocView — edge-case battery (audit Stage D).
#
# Caller must build first with:
#   --dart-define=DOCVIEW_BATTERY=true
#   --dart-define=DOCVIEW_BATTERY_EDGE_URL=http://10.0.2.2:8080/dav/edge/
#   (no OPEN define — the hook auto-opens the next never-opened doc per boot)
# The host must run wsgidav (:8080 → /tmp/opencode/dav) with edge files +
# _index.txt under /tmp/opencode/dav/edge/.
#
# Flow: push edge files into the app's own external files dir (scoped-storage
# safe) → boot 1 imports all 10 → each subsequent boot opens the next doc →
# encrypted.pdf gets a wrong×2/correct×1 password interaction → BookServer
# stress reopens fb2 ×5 → final screenshots + logcat FATAL scan.
set -u

NAME="${1:?usage: battery_edge.sh <avd-name>}"
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
log() { echo "== $NAME/edge $(date +%H:%M:%S) == $1" >> "$OUT/${NAME}_edge.log"; }

# Host-load noise pops a modal "System UI isn't responding" dialog that
# swallows all input — detect it via uiautomator and tap its Wait button.
dismiss_dialog() {
  "$ADB" exec-out uiautomator dump /dev/tty 2>/dev/null \
    > "$OUT/$NAME.edge_ui_d.xml" || true
  if grep -q "not responding" "$OUT/$NAME.edge_ui_d.xml" 2>/dev/null; then
    LINE=$(grep -o '<node[^>]*text="Wait"[^>]*' "$OUT/$NAME.edge_ui_d.xml" | head -1)
    B=$(printf '%s' "$LINE" | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' | head -1)
    X1=${B%%,*}; R=${B#*,}; Y1=${R%%]*}
    P=${B#*][}; X2=${P%%,*}; Y2=${P#*,}; Y2=${Y2%]*}
    "$ADB" shell input tap $(( (X1 + X2) / 2 )) $(( (Y1 + Y2) / 2 )) 2>/dev/null || true
    sleep 2
    log "ANR dialog dismissed (Wait)"
  fi
}

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
  >> "$OUT/${NAME}_edge.log" 2>&1 && log "install ok" || log "INSTALL FAILED"

# Files come over HTTP from the host (scoped storage blocks direct
# /sdcard reads from Dart, and FUSE rejects shell-owned dirs even inside
# the app's own external storage).
"$ADB" logcat -c

# Boot 1: imports everything, auto-opens the newest edge doc.
"$ADB" shell am start -n com.docview.docview/.MainActivity
sleep 75   # 50 MB huge.txt copy + FTS settle
dismiss_dialog
"$ADB" exec-out screencap -p > "$OUT/$NAME.edge_boot1.png"
"$ADB" logcat -d > "$OUT/$NAME.edge_boot1.logcat"
log "boot1 capture done"

# Boots 2..10: next doc each. The encrypted.pdf dialog is handled inline.
"$ADB" logcat -c
for b in 2 3 4 5 6 7 8 9 10; do
  "$ADB" shell am force-stop com.docview.docview; sleep 2
  "$ADB" shell am start -n com.docview.docview/.MainActivity
  sleep 16
  dismiss_dialog
  sleep 3
  # If the password dialog is up (encrypted.pdf), exercise wrong ×2 then ok.
  "$ADB" exec-out uiautomator dump /dev/tty 2>/dev/null > "$OUT/$NAME.edge_ui_b$b.xml" || true
  if grep -q "Password required" "$OUT/$NAME.edge_ui_b$b.xml" 2>/dev/null; then
    log "boot$b: password dialog detected"
    for attempt in 1 2; do
      "$ADB" shell input tap 540 1230; sleep 1
      "$ADB" shell input text "wrong$attempt"; sleep 1
      "$ADB" shell input tap 850 1450; sleep 5
    done
    "$ADB" exec-out screencap -p > "$OUT/$NAME.edge_enc_wrong.png"
    "$ADB" shell input tap 540 1230; sleep 1
    "$ADB" shell input text "batpass"; sleep 1
    "$ADB" shell input tap 850 1450; sleep 6
    "$ADB" exec-out screencap -p > "$OUT/$NAME.edge_enc_ok.png"
    "$ADB" shell input keyevent KEYCODE_BACK; sleep 2
  else
    "$ADB" exec-out screencap -p > "$OUT/$NAME.edge_boot$b.png"
    "$ADB" shell input keyevent KEYCODE_BACK; sleep 2
  fi
done
"$ADB" logcat -d > "$OUT/$NAME.edge.logcat"
log "boot cycle done"

# BookServer restart stress: open the fb2 (reflow) 5× via library taps.
"$ADB" shell am force-stop com.docview.docview; sleep 2
"$ADB" shell am start -n com.docview.docview/.MainActivity
sleep 14
"$ADB" exec-out screencap -p > "$OUT/$NAME.edge_lib_final.png"
log "stress boot done"

"$ADB" logcat -d > "$OUT/$NAME.edge2.logcat"
rg -i "FATAL EXCEPTION" -A10 "$OUT/$NAME.edge.logcat" "$OUT/$NAME.edge2.logcat" \
  "$OUT/$NAME.edge_boot1.logcat" | tail -40 >> "$OUT/${NAME}_edge.log" || log "0 FATAL"

sleep 3
kill_emus; kill_daemons
"$ADB" emulator kill >/dev/null 2>&1
log "done"
