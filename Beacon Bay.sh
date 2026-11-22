#!/bin/sh
printf '\033c\033]0;%s\a' Beacon Bay
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Beacon Bay.x86_64" "$@"
