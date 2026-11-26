#!/bin/sh
# Builds RetroArch from Debian's source package, assembles its runtime from the
# same Debian snapshot, runs the smoke tests and writes the .gzl and its
# corresponding source under dist/ (or $GIZLET_DIST).
set -eu

project=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
dist=${GIZLET_DIST:-$project/dist}
if [ "$(id -u)" -ne 0 ] || [ "$(uname -m)" != aarch64 ]; then
    echo 'Build on ARM64 Linux as root.' >&2
    exit 1
fi
build_dir=$(mktemp -d)
cleanup() {
    for root in "$build_dir/build" "$build_dir/runtime"; do
        umount -R "$root/dev" 2>/dev/null || true
        umount "$root/proc" 2>/dev/null || true
    done
    rm -rf --one-file-system "$build_dir"
}
trap cleanup EXIT

snapshot=20261124T000000Z
mirror=https://snapshot.debian.org/archive/debian/$snapshot/
suite=forky
retroarch=1.22.2+dfsg-3
cores="libretro-mgba libretro-gambatte libretro-nestopia libretro-bsnes-mercury-performance libretro-beetle-pce-fast libretro-beetle-wswan"
build_packages="ca-certificates,build-essential,pkgconf,dpkg-dev,libasound2-dev,libdrm-dev,libgbm-dev,libegl-dev,libgles-dev,libudev-dev,zlib1g-dev,libfreetype-dev,libzstd-dev,libxkbcommon-dev,libxxhash-dev,libstb-dev,libflac-dev"
runtime_packages="ca-certificates,libasound2t64,libasound2-data,libdrm2,libegl1,libegl-mesa0,libgbm1,libgles2,libgl1-mesa-dri,mesa-libgallium,libfreetype6,libpng16-16t64,libudev1,libxkbcommon0,xkb-data,libzstd1,zlib1g,libstdc++6,libretro-core-info,mount,util-linux"

# snapshot.debian.org is slow and drops connections: retry, and give up on a
# stalled one instead of waiting forever.
apt_options='-o Acquire::Check-Valid-Until=false -o Acquire::Retries=8 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60'

# Debian's archive key, on the build host and then in each chroot. Ubuntu does
# not trust it by default, so the sources name it.
keyring=/usr/share/keyrings/debian-archive-keyring.gpg

bootstrap() {
    mmdebstrap --mode=root --variant=minbase --architectures=arm64 \
        --aptopt='Acquire::Check-Valid-Until "false"' \
        --aptopt='Acquire::Retries "8"' \
        --aptopt='Acquire::http::Timeout "60"' \
        --aptopt='Acquire::https::Timeout "60"' \
        --aptopt='APT::Install-Recommends "false"' \
        --include="$1" --format=directory "$suite" "$2" \
        "deb [signed-by=$keyring] $mirror $suite main" "deb-src [signed-by=$keyring] $mirror $suite main"
}

# in_chroot DIR SCRIPT: runs SCRIPT in DIR with the host's /dev and a /proc,
# which apt's TLS and the build tools need.
in_chroot() {
    find "$1/dev" -mindepth 1 -maxdepth 1 -exec rm -rf --one-file-system {} +
    mount --rbind /dev "$1/dev"
    mount --make-rslave "$1/dev"
    mount -t proc proc "$1/proc"
    status=0
    chroot "$1" /bin/sh -ec "$2" || status=$?
    umount -R "$1/dev"
    umount "$1/proc"
    return "$status"
}

# RetroArch itself: Debian's DFSG source, configured for KMS, EGL and
# OpenGL ES 3 on the R36S, with udev input and ALSA. Networking (netplay, the
# online updaters and thumbnail downloads), X11, Wayland, Qt, FFmpeg and
# Vulkan are left out.
bootstrap "$build_packages" "$build_dir/build"
cp "$project/app/launch.c" "$build_dir/build/root/launch.c"
in_chroot "$build_dir/build" "
    apt-get $apt_options update -qq
    cd /root
    apt-get $apt_options source -qq --download-only retroarch=$retroarch
    dpkg-source -x --no-check retroarch_${retroarch}.dsc src >/dev/null
    cd src
    ./configure --prefix=/usr \
        --disable-x11 --disable-wayland --disable-qt --disable-sdl --disable-sdl2 \
        --disable-ffmpeg --disable-networking --disable-ssl --disable-builtinmbedtls \
        --disable-builtinbearssl --disable-builtinflac --disable-builtinzlib \
        --disable-builtinglslang --disable-pulse --disable-jack --disable-pipewire \
        --disable-oss --disable-v4l2 --disable-libusb --disable-dbus --disable-vulkan \
        --disable-cheevos --disable-discord --disable-translate --disable-microphone \
        --disable-update_assets --disable-update_cores --disable-cg \
        --disable-materialui --disable-xmb --disable-ozone --enable-rgui \
        --enable-kms --enable-egl --enable-opengles --enable-opengles3 \
        --enable-udev --enable-alsa --enable-freetype --enable-zlib >/root/configure.log
    make -j\$(nproc) >/root/make.log 2>&1 || { tail -50 /root/make.log; exit 1; }
    strip retroarch
    cc -Wall -Wextra -Werror -std=c17 -O2 -static -s /root/launch.c -o /root/launch
"

runtime=$build_dir/runtime
bootstrap "$runtime_packages" "$runtime"
# Debian's cores depend on `retroarch | libretro-frontend`. This RetroArch is
# built here, so an empty package provides libretro-frontend first, and apt
# does not bring in Debian's own RetroArch with Qt, FFmpeg and its assets.
frontend=$build_dir/frontend
mkdir -p "$frontend/DEBIAN"
cat > "$frontend/DEBIAN/control" <<EOF
Package: gizlet-retroarch-frontend
Version: ${retroarch%%+*}
Architecture: all
Maintainer: Gizlet <hello@gizlet.io>
Provides: libretro-frontend
Description: RetroArch as built for Gizlet
 An empty package: RetroArch itself is /usr/bin/retroarch, built from Debian's
 retroarch source package.
EOF
dpkg-deb --root-owner-group --build "$frontend" "$runtime/tmp/frontend.deb" >/dev/null
in_chroot "$runtime" "
    dpkg -i /tmp/frontend.deb >/dev/null
    apt-get $apt_options update -qq
    apt-get $apt_options install -y -qq --no-install-recommends $cores >/dev/null
    apt-get clean
    ! dpkg -s retroarch >/dev/null 2>&1
"
rm -rf "$frontend" "$runtime/tmp/frontend.deb"
install -m 0755 "$build_dir/build/root/src/retroarch" "$runtime/usr/bin/retroarch"
share=$runtime/usr/share/gizlet-retroarch
mkdir -p "$share/autoconfig" "$runtime/usr/share/doc/retroarch"
install -m 0644 "$project/config/defaults.cfg" "$project/config/gizlet.cfg" "$share/"
install -m 0644 "$project/config/autoconfig/"*.cfg "$share/autoconfig/"
install -m 0644 "$build_dir/build/root/src/debian/copyright" "$runtime/usr/share/doc/retroarch/copyright"
install -m 0644 "$build_dir/build/root/src/COPYING" "$runtime/usr/share/doc/retroarch/COPYING"
mkdir -p "$runtime/save" "$runtime/media" "$runtime/mnt" "$runtime/home" \
    "$runtime/proc" "$runtime/sys" "$runtime/run" "$runtime/dev" "$runtime/tmp"
touch "$runtime/etc/asound.conf"

# Smoke tests: RetroArch with null drivers runs each core on a synthetic ROM.
python3 "$project/tests/make_roms.py" "$runtime/tmp/roms"
install -m 0755 "$project/tests/smoke.sh" "$runtime/tmp/smoke.sh"
install -m 0755 "$(readlink -f "$(command -v qemu-aarch64-static || command -v qemu-aarch64)")" "$runtime/tmp/qemu-aarch64"
in_chroot "$runtime" "/bin/sh /tmp/smoke.sh /tmp/roms"
rm -rf "$runtime/tmp/"* "$runtime/tmp/".[!.]* 2>/dev/null || true

# Corresponding source: every Debian source package in the runtime, plus
# RetroArch's own (built here), from the same snapshot.
chroot "$runtime" dpkg-query -W -f '${source:Package}=${source:Version}\n' | sort -u > "$build_dir/sources.list"
sed -i '/^gizlet-retroarch-frontend=/d' "$build_dir/sources.list"
grep -q "^retroarch=" "$build_dir/sources.list" || echo "retroarch=$retroarch" >> "$build_dir/sources.list"
sort -u -o "$build_dir/sources.list" "$build_dir/sources.list"
mkdir -p "$build_dir/build/root/sources"
cp "$build_dir/sources.list" "$build_dir/build/root/sources.list"
in_chroot "$build_dir/build" "
    cd /root/sources
    xargs apt-get $apt_options source -qq --download-only < /root/sources.list >/dev/null
"

rm -f "$runtime/etc/resolv.conf"
rm -rf "$runtime/var/lib/apt/lists/"* "$runtime/var/cache/apt/"* "$runtime/var/log/"*
find "$runtime/dev" -mindepth 1 -delete

app=$build_dir/app
mkdir -p "$app/bin" "$app/licenses" "$dist" "$dist/sources"
install -m 0755 "$build_dir/build/root/launch" "$app/bin/launch"
install -m 0755 "$project/app/launch.sh" "$app/bin/launch.sh"
install -m 0755 "$project/app/session" "$app/bin/session"
install -m 0755 "$project/app/find-games" "$app/bin/find-games"
python3 "$project/scripts/manifest.py" "$project/gizlet.toml" "$app/manifest.json"
version=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$app/manifest.json")
python3 "$project/scripts/notice.py" "$project" "$runtime" "$build_dir/sources.list" "$version" "$app/NOTICE.md"
install -m 0644 "$project/LICENSE" "$app/licenses/gizlet-retroarch-packaging-MIT.txt"
cp "$app/NOTICE.md" "$dist/sources/io.gizlet.retroarch-$version-NOTICE.md"
mksquashfs "$runtime" "$app/runtime.sqfs" -comp zstd -noappend -no-progress -quiet
python3 "$project/scripts/pack.py" "$app" "$dist"

mkdir "$build_dir/build/root/packaging"
tar -C "$project" --exclude=./dist --exclude=./.git -cf - . | tar -C "$build_dir/build/root/packaging" -xf -
tar --format=ustar -cf "$dist/sources/io.gizlet.retroarch-$version-source.tar" \
    -C "$build_dir/build/root" sources.list sources packaging
ls -l "$dist" "$dist/sources"
