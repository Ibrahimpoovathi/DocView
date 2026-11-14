#!/usr/bin/env bash
# DocView — Stage D targeted edge verification (audit).
#
# Phase T1: sample.fb2 (fixed XML) + sample.cbz + sample.mobi + encrypted.pdf
#           over wsgidav /dav/edge2/. Boot cycles auto-open each doc;
#           the encrypted boot exercises wrong×2 → correct password.
# Phase T2: fresh data, huge.txt (50 MB) only — times the TXT→EPUB
#           conversion by polling the reader progress % every 10 s.
# Phase T3: after T1's four opens, one more boot + library capture to
#           verify markOpened persistence (no re-open of already-opened
#           docs; "Continue reading" shows the opened ones).
#
# Caller builds with DOCVIEW_BATTERY=true +
# DOCVIEW_BATTERY_EDGE_URL=http://10.0.2.2:8080/dav/edge2/ (T1/T3) — T2
# flips the define to .../edge3/ internally via a rebuild? No: T2 keeps the
# same define and reads /dav/edge3/_index.txt by rewriting the URL file —
# the app URL points at edge2; we just serve huge.txt from edge2 during T2.
set -u

NAME="${1:?usage: battery_edge_target.sh <avd-name>}"
PROJ=/home/pseudo/Applications/OpenCode/DocView
OUT=/tmp/opencode/avd_out
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
LOG="$OUT/${NAME}_edge_target.log"
mkdir -p "$OUT"

log() { echo "== $NAME/edge-target $(date +%H:%M:%S) == $1" >> "$LOG"; }
kill_daemons() { pkill -9 -f '[G]radleDaemon' 2>/dev/null; pkill -9 -f '[K]otlinCompileDaemon' 2>/dev/null; }
kill_emus() { pkill -9 -f '[q]emu-system' 2>/dev/null; }

dump_ui() { "$ADB" exec-out uiautomator dump /dev/tty 2>/dev/null > "$1" || true; }

dismiss_dialog() {
  dump_ui "$OUT/$NAME.et_ui_d.xml"
  if grep -q "not responding" "$OUT/$NAME.et_ui_d.xml" 2>/dev/null; then
    LINE=$(grep -o '<node[^>]*text="Wait"[^>]*' "$OUT/$NAME.et_ui_d.xml" | head -1)
    B=$(printf '%s' "$LINE" | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' | head -1)
    X1=${B%%,*}; R=${B#*,}; Y1=${R%%]*}
    P=${B#*][}; X2=${P%%,*}; Y2=${P#*,}; Y2=${Y2%]*}
    "$ADB" shell input tap $(( (X1 + X2) / 2 )) $(( (Y1 + Y2) / 2 )) 2>/dev/null || true
    sleep 2
    log "ANR dialog dismissed (Wait)"
  fi
}

# Tap the center of the first node whose text contains $1.
tap_node() {
  dump_ui "$OUT/$NAME.et_ui_t.xml"
  LINE=$(grep -o "<node[^>]*text=\"[^\"]*$1[^\"]*\"[^>]*" "$OUT/$NAME.et_ui_t.xml" | head -1)
  if [ -z "$LINE" ]; then log "tap_node miss: $1"; return 1; fi
  B=$(printf '%s' "$LINE" | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' | head -1)
  X1=${B%%,*}; R=${B#*,}; Y1=${R%%]*}
  P=${B#*][}; X2=${P%%,*}; Y2=${P#*,}; Y2=${Y2%]*}
  "$ADB" shell input tap $(( (X1 + X2) / 2 )) $(( (Y1 + Y2) / 2 )) 2>/dev/null || true
  return 0
}

boot_app() {
  "$ADB" shell am force-stop com.docview.docview 2>/dev/null; sleep 2
  "$ADB" shell am start -n com.docview.docview/.MainActivity
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
  >> "$LOG" 2>&1 && log "install ok" || { log "INSTALL FAILED"; kill_emus; exit 1; }
"$ADB" logcat -c

# ---------------- Phase T1: samples + encrypted ----------------
boot_app
sleep 45   # import 4 small docs + first auto-open (newest = encrypted.pdf)
dismiss_dialog
sleep 3
dump_ui "$OUT/$NAME.et_ui_b1.xml"
"$ADB" exec-out screencap -p > "$OUT/$NAME.et_boot1.png"
if grep -q "Password required" "$OUT/$NAME.et_ui_b1.xml" 2>/dev/null; then
  log "boot1: password dialog detected"
  tap_node "Document password" || "$ADB" shell input tap 540 1180
  sleep 1; "$ADB" shell input text "wrong1"; sleep 1
  tap_node "Unlock" || "$ADB" shell input tap 850 1420; sleep 4
  "$ADB" exec-out screencap -p > "$OUT/$NAME.et_enc_wrong1.png"
  dump_ui "$OUT/$NAME.et_ui_w1.xml"
  tap_node "Document password" || "$ADB" shell input tap 540 1180
  sleep 1; "$ADB" shell input text "wrong2"; sleep 1
  tap_node "Unlock" || "$ADB" shell input tap 850 1420; sleep 4
  "$ADB" exec-out screencap -p > "$OUT/$NAME.et_enc_wrong2.png"
  tap_node "Document password" || "$ADB" shell input tap 540 1180
  sleep 1; "$ADB" shell input text "batpass"; sleep 1
  tap_node "Unlock" || "$ADB" shell input tap 850 1420; sleep 6
  "$ADB" exec-out screencap -p > "$OUT/$NAME.et_enc_ok.png"
  dump_ui "$OUT/$NAME.et_ui_ok.xml"
  grep -q "Password required" "$OUT/$NAME.et_ui_ok.xml" \
    && log "password dialog STILL VISIBLE after correct password" \
    || log "password accepted, dialog gone"
  "$ADB" shell input keyevent KEYCODE_BACK; sleep 2
else
  log "boot1: NO password dialog for encrypted.pdf"
fi
"$ADB" logcat -d > "$OUT/$NAME.et_boot1.logcat"
log "boot1 done (encrypted)"

for b in 2 3 4; do
  boot_app
  sleep 18
  dismiss_dialog
  sleep 3
  "$ADB" exec-out screencap -p > "$OUT/$NAME.et_boot$b.png"
  dump_ui "$OUT/$NAME.et_ui_b$b.xml"
  "$ADB" logcat -d > "$OUT/$NAME.et_boot$b.logcat"
  "$ADB" shell input keyevent KEYCODE_BACK; sleep 2
  log "boot$b done"
done

# ---------------- Phase T3: markOpened persistence ----------------
boot_app
sleep 18
dismiss_dialog
sleep 3
"$ADB" exec-out screencap -p > "$OUT/$NAME.et_boot5.png"
log "boot5 done (auto-open after all opened)"
# Reader auto-opened — go back to library and capture "Continue reading".
"$ADB" shell input keyevent KEYCODE_BACK; sleep 3
"$ADB" exec-out screencap -p > "$OUT/$NAME.et_library.png"
dump_ui "$OUT/$NAME.et_ui_lib.xml"
log "library captured"

# ---------------- Phase T2: huge.txt conversion timing ----------------
# Serve huge.txt only (edge2 is the define-target dir; add it AFTER T1 so
# its boots don't import it).
cp /tmp/opencode/edge/huge.txt /tmp/opencode/dav/edge2/huge.txt
printf 'huge.txt\n' > /tmp/opencode/dav/edge2/_index.txt
"$ADB" shell pm clear com.docview.docview >/dev/null 2>&1
log "T2: data cleared"
boot_app
sleep 20
dismiss_dialog
# Poll the reader progress for up to 3 minutes.
START=$(date +%s)
for t in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do
  sleep 10
  dump_ui "$OUT/$NAME.et_ui_huge.xml"
  PCT=$(grep -o 'text="[0-9]\+%"' "$OUT/$NAME.et_ui_huge.xml" | head -1 | grep -o '[0-9]\+')
  NOW=$(date +%s)
  log "T2 t=$(( NOW - START ))s progress=${PCT:-none}%"
  "$ADB" exec-out screencap -p > "$OUT/$NAME.et_huge_$t.png"
  [ -n "$PCT" ] && [ "$PCT" -gt 0 ] 2>/dev/null && break
done
"$ADB" logcat -d > "$OUT/$NAME.et_huge.logcat"
log "T2 done"

"$ADB" logcat -d > "$OUT/$NAME.et_final.logcat"
rg -i "FATAL EXCEPTION" -A10 "$OUT/$NAME".et_*.logcat | tail -40 >> "$LOG" || log "0 FATAL"

sleep 2
kill_emus; kill_daemons
"$ADB" emulator kill >/dev/null 2>&1
log "done"
