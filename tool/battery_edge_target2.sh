#!/usr/bin/env bash
# DocView — Stage D targeted edge verification, round 2.
#
# The installed APK's battery define points at /dav/edge/, so each phase
# rewrites that directory's _index.txt on the host (single doc per boot =
# deterministic auto-open target) instead of rebuilding.
#
# A: encrypted.pdf only → blind password interaction (Flutter release
#    builds don't expose text to uiautomator, so taps are fixed-coordinate
#    and results are verified by screenshot).
# B: sample.fb2 (valid XML) → boot+capture; sample2.cbz (valid PNGs) →
#    boot+capture.
# C: pm clear + all 10 edge docs → boot (auto-opens newest = huge) → 8 min
#    conversion watch → adb-root sqlite3 queries: doc count (Library·9
#    mystery), huge lastOpenedAt (markOpened persistence).
set -u

NAME="${1:?usage: battery_edge_target2.sh <avd-name>}"
PROJ=/home/pseudo/Applications/OpenCode/DocView
OUT=/tmp/opencode/avd_out
ADB=/opt/android-sdk/platform-tools/adb
EMU=/opt/android-sdk/emulator/emulator
EDGE=/tmp/opencode/dav/edge
LOG="$OUT/${NAME}_edge_target2.log"
mkdir -p "$OUT"

log() { echo "== $NAME/et2 $(date +%H:%M:%S) == $1" >> "$LOG"; }
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
"$ADB" logcat -c

# ---- Phase A: encrypted.pdf password flow ----
edge_list encrypted.pdf
boot_app
sleep 30
"$ADB" exec-out screencap -p > "$OUT/$NAME.et2_enc_dialog.png"
# Blind interaction: field (~y1180) then Unlock (~y1420).
"$ADB" shell input tap 540 1180; sleep 1
"$ADB" shell input text "wrong1"; sleep 1
"$ADB" shell input tap 850 1420; sleep 5
"$ADB" exec-out screencap -p > "$OUT/$NAME.et2_enc_wrong1.png"
"$ADB" shell input tap 540 1180; sleep 1
"$ADB" shell input text "wrong2"; sleep 1
"$ADB" shell input tap 850 1420; sleep 5
"$ADB" exec-out screencap -p > "$OUT/$NAME.et2_enc_wrong2.png"
"$ADB" shell input tap 540 1180; sleep 1
"$ADB" shell input text "batpass"; sleep 1
"$ADB" shell input tap 850 1420; sleep 8
"$ADB" exec-out screencap -p > "$OUT/$NAME.et2_enc_ok.png"
"$ADB" logcat -d > "$OUT/$NAME.et2_enc.logcat"
"$ADB" shell input keyevent KEYCODE_BACK; sleep 2
log "phase A done"

# ---- Phase B: valid fb2, then valid cbz ----
cp /tmp/opencode/dav/edge2/sample.fb2 "$EDGE/sample.fb2"
edge_list sample.fb2
boot_app
sleep 22
"$ADB" exec-out screencap -p > "$OUT/$NAME.et2_fb2.png"
"$ADB" logcat -d > "$OUT/$NAME.et2_fb2.logcat"
"$ADB" shell input keyevent KEYCODE_BACK; sleep 2
log "fb2 done"

cp /tmp/opencode/dav/edge/sample2.cbz "$EDGE/sample2.cbz"
edge_list sample2.cbz
boot_app
sleep 22
"$ADB" exec-out screencap -p > "$OUT/$NAME.et2_cbz.png"
"$ADB" logcat -d > "$OUT/$NAME.et2_cbz.logcat"
"$ADB" shell input keyevent KEYCODE_BACK; sleep 2
log "cbz done"

# ---- Phase C: all 10 docs + huge conversion watch + DB checks ----
edge_list bad.epub empty.pdf empty.txt encrypted.pdf garbage.pdf \
  huge.txt sample.cbz sample.fb2 sample.mobi truncated.pdf
"$ADB" shell pm clear com.docview.docview >/dev/null 2>&1
log "C: data cleared, 10-doc import boot"
"$ADB" logcat -c
boot_app
sleep 25
for t in $(seq 1 16); do
  sleep 30
  "$ADB" exec-out screencap -p > "$OUT/$NAME.et2_huge_$t.png"
  log "C: huge poll t=$(( t * 30 ))s captured"
done
"$ADB" logcat -d > "$OUT/$NAME.et2_huge.logcat"

# DB checks via adb root (google_apis image).
"$ADB" root >/dev/null 2>&1; sleep 2
"$ADB" shell "ls /data/data/com.docview.docview/" > "$OUT/$NAME.et2_ls.txt" 2>&1
DBF=$("$ADB" shell "find /data/data/com.docview.docview -name '*.db' 2>/dev/null" | tr -d '\r' | head -1)
log "db file: $DBF"
if [ -n "$DBF" ]; then
  "$ADB" pull "$DBF" "$OUT/$NAME.et2.db" >> "$LOG" 2>&1 && log "db pulled"
  if command -v sqlite3 >/dev/null; then
    sqlite3 "$OUT/$NAME.et2.db" "SELECT original_name, format, last_opened_at IS NOT NULL FROM documents ORDER BY original_name;" \
      > "$OUT/$NAME.et2_docs.txt" 2>&1
    sqlite3 "$OUT/$NAME.et2.db" "SELECT COUNT(*) FROM documents;" >> "$OUT/$NAME.et2_docs.txt" 2>&1
    log "doc query done ($(wc -l < "$OUT/$NAME.et2_docs.txt") lines)"
  else
    log "no sqlite3 on host"
  fi
fi

sleep 2
kill_emus; kill_daemons
"$ADB" emulator kill >/dev/null 2>&1
log "done"
