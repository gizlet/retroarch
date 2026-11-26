#!/bin/sh
# RetroArch's Gizlet entry script, run as root by `gizlet run` through
# bin/launch. It starts RetroArch from the package's read-only runtime in a
# private mount namespace.
#
#   launch [--games DIR]
#
# The file browser opens in DIR, which Emulation Center passes; without it,
# in the TF2 card where it is mounted, else /home.
set -eu

app_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(id -u)" -ne 0 ]; then
    echo 'RetroArch needs the Gizlet launcher to mount its runtime.' >&2
    exit 1
fi

games=
while [ $# -gt 0 ]; do
    case $1 in
        --games) games=${2:-}; [ $# -lt 2 ] || shift ;;
        --games=*) games=${1#--games=} ;;
    esac
    shift
done
if [ -z "$games" ] || [ ! -d "$games" ]; then
    games=$("$app_dir/bin/find-games")
fi
games=$(readlink -f -- "$games")
save=${GIZLET_SAVE_DIR:-/opt/gizlet/saves/io.gizlet.retroarch}
mkdir -p "$save"

session_dir=$(mktemp -d /run/gizlet-retroarch.XXXXXX)
trap 'rmdir "$session_dir/root" "$session_dir" 2>/dev/null || true' EXIT
mkdir "$session_dir/root"
# Slave propagation lets a TF2 card inserted while RetroArch runs appear in it.
unshare --mount --propagation slave --pid --fork --kill-child \
    /bin/sh "$app_dir/bin/session" "$app_dir" "$session_dir/root" "$save" "$games" &
session_pid=$!
# unshare --fork ignores SIGTERM and SIGINT while it waits, so a request to
# stop goes to the session it forked, which becomes RetroArch. If that is
# still running three seconds later, it is killed, and unshare with it.
stop() {
    children=$(pgrep -P "$session_pid" 2>/dev/null || :)
    for child in $children; do
        kill -TERM "$child" 2>/dev/null || :
    done
    tries=0
    while kill -0 "$session_pid" 2>/dev/null && [ "$tries" -lt 30 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    for child in $children; do
        kill -KILL "$child" 2>/dev/null || :
    done
    kill -KILL "$session_pid" 2>/dev/null || :
    wait "$session_pid" 2>/dev/null || :
    exit 143
}
trap stop TERM INT
wait "$session_pid"
