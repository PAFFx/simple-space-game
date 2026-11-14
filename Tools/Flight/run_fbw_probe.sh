#!/bin/sh
# Runs fbw_probe scenarios and prints the one-line summaries, JOBS at a time (default 2)
# at low priority so the machine stays usable.
#   run_fbw_probe.sh [-s "scenario ..."] [law_property=value ...]
# Without -s every scenario runs. Other arguments are passed on (control law overrides,
# e.g. rate_gain=9; fc.<property> and alloc.<property> reach the computer and allocator).
cd "$(dirname "$0")/../.." || exit 1
scenarios="cruise_fwd boost_fwd full_fwd boost_right full_right boost_down full_down full_back
	boost_diag cruise_boost_fwd cruise_boost_right cruise_boost_down boost_fwd_yaw full_fwd_yaw full_fwd_pitch cruise_fwd_roll boost_fwd_roll
	full_fwd_roll reversal reversal_full brake_yaw brake_roll brake_full_roll brake_full_yaw
	brake_full_pitch brake_full_only"
if [ "$1" = "-s" ]; then
	scenarios=$2
	shift 2
fi
out=$(mktemp -d)
running=0
for s in $scenarios; do
	(nice -n 19 timeout 300 "${GODOT:-godot-double}" --headless --path . \
		-s Tools/Flight/fbw_probe.gd -- "$s" "$@" 2>&1 | grep -E "^$s " > "$out/$s.txt") &
	running=$((running + 1))
	if [ "$running" -ge "${JOBS:-2}" ]; then
		wait
		running=0
	fi
done
wait
cat "$out"/*.txt
rm -rf "$out"
