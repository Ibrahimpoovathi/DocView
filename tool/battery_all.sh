#!/usr/bin/env bash
# DocView — battery on all 4 AVDs, strictly sequentially (one emulator
# at a time; never overlaps a flutter build; never exceeds 1 qemu).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
for avd in quick_phone old_phone pixel_7 pixel_tablet; do
  echo "########## $avd ##########"
  bash "$HERE/battery_one.sh" "$avd"
  sleep 5
done
grep -liE "FATAL EXCEPTION" /tmp/opencode/avd_out/*.logcat || echo "ALL FATAL-FREE"
