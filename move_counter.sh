#!/bin/bash

start="$1"

# Validate input
[[ "$start" =~ ^[0-9]{2}$ ]] || { echo "Usage: $0 <two-digit-start>" >&2; exit 1; }

# Get all files matching [0-9][0-9]_*
files=( [0-9][0-9]_* )
[[ -e "${files[0]}" ]] || exit 0  # exit if no matches

# Find max prefix present (to know where to start from)
max=00
for f in "${files[@]}"; do
    p="${f:0:2}"
    [[ "$p" =~ ^[0-9]{2}$ ]] && (( 10#$p > 10#$max )) && max="$p"
done

# Process from max down to $start
current=$((10#$max))
while (( current >= 10#$start )); do
    cur_str=$(printf "%02d" "$current")
    next_str=$(printf "%02d" $((current + 1)))

    for f in "$cur_str"_*; do
        [ -e "$f" ] || continue
        new="$next_str${f#"$cur_str"}"
        mv -- "$f" "$new"
    done

    ((current--))
done
