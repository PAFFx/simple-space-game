#!/usr/bin/env bash
# Runs draw_snapshot.gd on desktop 7 and tiles its stills into <out_dir>/sheet.png.
#   Tools/Godot/draw_snapshot.sh <out_dir> [args for draw_snapshot.gd]
set -e
out="$1"; shift
mkdir -p "$out"; rm -f "$out"/*.png
bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating rectangle=1280x720+0+0 2>/dev/null || true
timeout 300 nice -n 19 godot-double --path . --resolution 1280x720 -s Tools/Godot/draw_snapshot.gd -- "$out" "$@" 2>&1 | grep -E "DRAW|ERROR|SCRIPT" || true
cols=$(head -1 "$out/files.txt")
mapfile -t files < <(tail -n +2 "$out/files.txt")
montage "${files[@]}" -tile "${cols}x" -geometry 640x360+2+2 "$out/sheet.png"
echo "$out/sheet.png"
