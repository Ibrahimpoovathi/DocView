#!/usr/bin/env bash
# DocView — Stage D targeted edge verification, round 3.
#
# A: fb2 repro — open valid fb2, stream logcat DURING open/interact/close
#    (renderer crash last round only appeared after the -d dump window),
#    probe TOC + swipe, capture everything.
# B: password flow with corrected coordinates (field 540,760 / Unlock 715,940).
# C: all-10 import + DB queries (Library·9 mystery, markOpened persistence).
set -u

NAME="${1:?usage: battery_edge_target3.sh <avd-name>}"
PROJ=/home/pseudo/Applications/OpenCode/DocView
OUT=/tmp/opencode/avd_out
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
EDGE=/tmp/opencode/dav/edge
LOG="$OUT/${NAME}_edge_target3.log"
mkdir -p "$OUT"

log() { echo "== $NAME/et3 $(date +%H:%M:%S) == $1" >> "$LOG"; }
kill_daemons() { pkill -9 -f '[G]radleDaemon' 2>/dev/null; pkill -9 -f '[K]otlinCompileDaemon' 2>/dev/null; }
kill_emus() { pkill -9 -f '[q]emu-system' 2>/dev/null; }
edge_list() { printf '%s\n' "$@" > "$EDGE/_index.txt"; }
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

# ---- Phase A: fb2 repro with streaming logcat ----
edge_list sample.fb2
"$ADB" logcat -c
"$ADB" logcat -v time > "$OUT/$NAME.et3_fb2_stream.log" 2>&1 &
STREAM_PID=$!
boot_app
sleep 25
"$ADB" exec-out screencap -p > "$OUT/$NAME.et3_fb2_open.png"
# Probe: TOC (list icon, appbar right ~x889,y208)
"$ADB" shell input tap 889 208; sleep 4
"$ADB" exec-out screencap -p > "$OUT/$NAME.et3_fb2_toc.png"
"$ADB" shell input keyevent KEYCODE_BACK; sleep 2
# Probe: swipe up (does body content exist below?)
"$ADB" shell input swipe 540 1600 540 500 400; sleep 3
"$ADB" exec-out screencap -p > "$OUT/$NAME.et3_fb2_swipe.png"
# Close the reader (streaming logcat must catch the renderer crash).
"$ADB" shell input keyevent KEYCODE_BACK; sleep 4
"$ADB" exec-out screencap -p > "$OUT/$NAME.et3_fb2_back.png"
kill $STREAM_PID
log "phase A done"

# ---- Phase B: password flow, corrected coords ----
edge_list encrypted.pdf
"$ADB" logcat -c
"$ADB" logcat -v time > "$OUT/$NAME.et3_enc_stream.log" 2>&1 &
STREAM_PID=$!
boot_app
sleep 25
"$ADB" exec-out screencap -p > "$OUT/$NAME.et3_enc_dialog.png"
"$ADB" shell input tap 540 760; sleep 1
"$ADB" shell input text "wrong1"; sleep 1
"$ADB" shell input tap 715 940; sleep 5
"$ADB" exec-out screencap -p > "$OUT/$NAME.et3_enc_wrong1.png"
"$ADB" shell input tap 540 760; sleep 1
"$ADB" shell input text "batpass"; sleep 1
"$ADB" shell input tap 715 940; sleep 8
"$ADB" exec-out screencap -p > "$OUT/$NAME.et3_enc_ok.png"
kill $STREAM_PID
"$ADB" shell input keyevent KEYCODE_BACK; sleep 2
log "phase B done"

# ---- Phase C: all-10 import + DB queries ----
edge_list bad.epub empty.pdf empty.txt encrypted.pdf garbage.pdf \
  huge.txt sample.cbz sample.fb2 sample.mobi truncated.pdf
"$ADB" shell pm clear com.docview.docview >/dev/null 2>&1
"$ADB" root >/dev/null 2>&1; sleep 2
boot_app
sleep 30
"$ADB" exec-out screencap -p > "$OUT/$NAME.et3_lib10.png"
DBF=/data/data/com.docview.docview/app_flutter/docview.db
"$ADB" shell "ls -la $DBF" >> "$LOG" 2>&1
"$ADB" pull "$DBF" "$OUT/$NAME.et3.db" >> "$LOG" 2>&1 && log "db pulled"
if [ -f "$OUT/$NAME.et3.db" ]; then
  sqlite3 "$OUT/$NAME.et3.db" \
    "SELECT original_name || ' | ' || format || ' | opened=' || (CASE WHEN last_opened_at IS NULL THEN 'no' ELSE 'yes' END) FROM documents ORDER BY original_name;" \
    > "$OUT/$NAME.et3_docs.txt" 2>&1
  echo "COUNT: $(sqlite3 "$OUT/$NAME.et3.db" 'SELECT COUNT(*) FROM documents;')" >> "$OUT/$NAME.et3_docs.txt"
  log "db queries done"
fi

sleep 2
kill_emus; kill_daemons
"$ADB" emulator kill >/dev/null 2>&1
log "done"
