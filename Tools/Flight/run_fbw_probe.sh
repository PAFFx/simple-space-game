#!/bin/sh
# Runs every fbw_probe scenario in parallel and prints the one-line summaries.
# Arguments are passed on (control law overrides, e.g. rate_gain=9).
cd "$(dirname "$0")/../.." || exit 1
out=$(mktemp -d)
for s in cruise_fwd boost_fwd full_fwd boost_right full_right boost_down full_down full_back \
		boost_diag boost_fwd_yaw full_fwd_yaw full_fwd_pitch \
		cruise_fwd_roll boost_fwd_roll full_fwd_roll reversal reversal_full \
		brake_yaw brake_roll brake_full_roll brake_full_yaw brake_full_pitch brake_full_only; do
	(timeout 300 "${GODOT:-godot-double}" --headless --path . -s Tools/Flight/fbw_probe.gd -- "$s" "$@" 2>&1 \
		| grep -E "^$s " > "$out/$s.txt") &
done
wait
cat "$out"/*.txt
rm -rf "$out"
