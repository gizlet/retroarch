#!/bin/sh
# Runs inside the runtime: every shipped core loads, and RetroArch runs the
# content-loading cores for 120 frames on a synthetic ROM with null drivers.
# RetroArch runs under QEMU as a Cortex-A35, the R36S's CPU: build hosts
# with pointer authentication and BTI would stop cores whose coroutines
# switch stacks, which the R36S's ARMv8.0 cores never check.
set -eu

roms=$1
cpu="/tmp/qemu-aarch64 -cpu cortex-a35"
cores=/usr/lib/aarch64-linux-gnu/libretro
export HOME=/tmp/smoke-home
mkdir -p "$HOME"
cat > /tmp/smoke.cfg <<'EOF'
video_driver = "null"
audio_driver = "null"
input_driver = "null"
input_joypad_driver = "null"
libretro_info_path = "/usr/share/libretro/info"
config_save_on_exit = "false"
EOF

$cpu /usr/bin/retroarch --version 2>&1 | grep -q '1\.22\.2' || { $cpu /usr/bin/retroarch --version; exit 1; }
$cpu /usr/bin/retroarch --features > /tmp/features.txt 2>&1
for feature in KMS EGL OpenGLES UDEV ALSA FreeType; do
    grep -Eq "^[[:space:]]*$feature[[:space:]]+-.*: yes$" /tmp/features.txt ||
        { echo "RetroArch lacks $feature" >&2; cat /tmp/features.txt; exit 1; }
done

for core in "$cores"/*_libretro.so; do
    if ldd "$core" | grep -q 'not found'; then
        echo "$core has missing libraries" >&2
        ldd "$core"
        exit 1
    fi
    info=/usr/share/libretro/info/$(basename "$core" .so).info
    [ -f "$info" ] || { echo "no core info for $core" >&2; exit 1; }
done

run() {
    core=$cores/$1_libretro.so
    if ! $cpu /usr/bin/retroarch --config /tmp/smoke.cfg --max-frames=120 --verbose -L "$core" "$roms/$2" > /tmp/smoke.log 2>&1; then
        cat /tmp/smoke.log
        echo "$1 did not run $2" >&2
        exit 1
    fi
    # The core reports its video geometry once it has accepted the content.
    grep -q '\[Core\] Geometry:' /tmp/smoke.log && grep -q 'Content ran for' /tmp/smoke.log || {
        cat /tmp/smoke.log
        echo "$1 did not load $2" >&2
        exit 1
    }
    echo "smoke: $1 ran $2"
}

run nestopia test.nes
run gambatte test.gb
run mgba test.gba
run bsnes_mercury_performance test.sfc
run mednafen_pce_fast test.pce
