#!/bin/sh
echo -ne '\033c\033]0;SnakeMultiplayer\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Snake.x86_64" "$@"
