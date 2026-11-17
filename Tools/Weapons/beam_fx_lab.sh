#!/usr/bin/env bash
# Runs beam_fx_lab.gd windowed on bspwm desktop ^7 at a fixed frame rate.
#   Tools/Weapons/beam_fx_lab.sh [-s SLOW] <out_dir> [lab args...]
# SLOW (default 4): sim frames per 1/60 s, so captures land within 1/(60*SLOW) s and a
# video plays back SLOW times slower than real.
set -euo pipefail
slow=4
if [[ ${1:-} == -s ]]; then slow=$2; shift 2; fi
cd "$(dirname "$0")/../.."
command -v bspc >/dev/null && bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating rectangle=480x270+0+0
exec nice -n 19 godot-double --path . --resolution 480x270 --fixed-fps $((60 * slow)) \
	-s Tools/Weapons/beam_fx_lab.gd -- "$@"
