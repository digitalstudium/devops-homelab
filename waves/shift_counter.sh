#!/bin/bash

input_prefix="$1"

# Get all files matching [0-9][0-9]_*
filenames=( [0-9][0-9]* )
[[ -e "${filenames[0]}" ]] || exit 0  # exit if no matches

if [ $# -eq 1 ]; then
  input_filename=$(ls "$input_prefix"*)
  right_index=-1
  right_filename="${filenames[$right_index]}"
  right_prefix="${filenames[$right_index]:0:2}"
  while [ $input_filename != $right_filename ]; do
    new_filename_prefix=$(printf "%02d" $(( 10#$right_prefix + 1 )))
    right_filename="${filenames[$right_index]}"
    right_suffix="${filenames[$right_index]:2}"
    new_filename=$new_filename_prefix$right_suffix
    mv $right_filename $new_filename
    right_prefix=$(( 10#$right_prefix - 1 ))
    ((right_index--))
  done
elif [ $# -eq 2 ]; then
 while [ -e "$input_prefix"* ]; do
    input_filename=$(ls "$input_prefix"*)
    prefix="$input_prefix"
    suffix="${input_filename:2}"
    new_filename_prefix=$(printf "%02d" $(( 10#$prefix - 1 )))
    if [ -e "$new_filename_prefix"* ]; then
      echo "Тут не сдвинешь"
      exit 0
    fi
    new_filename=$new_filename_prefix$suffix
    mv $input_filename $new_filename
    input_prefix=$(printf "%02d" $(( 10#$input_prefix + 1 )))
 done
fi
