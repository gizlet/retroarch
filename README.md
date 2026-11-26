# RetroArch for Gizlet

RetroArch 1.22.2 with free libretro cores, packaged as a Gizlet app for the R36S. Emulation Center ([gizlet/emulation-center](https://github.com/gizlet/emulation-center)) installs, updates and opens it, and it also runs on its own from the launcher. The package contains no games, BIOS files or game artwork; players open games they already have with RetroArch's own file browser.

## What is in the package

| Part | Source |
| --- | --- |
| `/usr/bin/retroarch` in `runtime.sqfs` | Debian's `retroarch` 1.22.2+dfsg-3 source, built in [`scripts/package.sh`](scripts/package.sh) for KMS, EGL and OpenGL ES 3 with udev input and ALSA. Networking (netplay, online updaters, thumbnail downloads), X11, Wayland, Qt, FFmpeg and Vulkan are left out, and the menu is RGUI. |
| Cores | Debian's `libretro-mgba`, `libretro-gambatte`, `libretro-nestopia`, `libretro-bsnes-mercury-performance`, `libretro-beetle-pce-fast` and `libretro-beetle-wswan`, and `libretro-core-info`. Cores from Debian's non-free section are not included. |
| Runtime | Mesa, ALSA, udev and the other libraries RetroArch needs, unmodified from the same Debian snapshot (`20261124T000000Z`, forky). |
| `bin/launch`, `bin/launch.sh`, `bin/session`, `bin/find-games` | The entry ([`app/`](app)): a static launcher, because the Gizlet Store requires an ELF entry, and the scripts it runs. |
| Configuration | [`config/`](config): first-launch defaults, the drivers and folders applied on every launch, and the R36S controls. |

## How it runs

`gizlet run io.gizlet.retroarch [--games DIR]` runs `bin/launch.sh` as root. It mounts `runtime.sqfs` as the root of a private mount and PID namespace, makes the display, controls, sound, `/home`, `/media`, `/mnt` and the app's save folder (as `/save`) visible, and starts RetroArch as `nobody` with the device groups it needs. Mounts propagate into the namespace, so a TF2 card inserted while RetroArch runs appears in it.

The file browser starts in `DIR`, which Emulation Center passes; without it, in the TF2 card where it is mounted ([`app/find-games`](app/find-games): a mounted filesystem on an MMC disk other than the one holding the root filesystem, preferring `/media/tf2`), else in `/home`. Saves, states, BIOS files (`system/`) and settings live in the save folder, `/opt/gizlet/saves/io.gizlet.retroarch`, so the card is only read.

Controls come from [`config/autoconfig/r36s_Gamepad.cfg`](config/autoconfig/r36s_Gamepad.cfg). Select is the hotkey: with X it opens the menu, with Start it quits, with L or R it loads or saves a state, with R2 it fast-forwards. Holding FN, or Select and Start for two seconds, is Gizlet OS's way back to the launcher.

## Build and test

On ARM64 Linux, install `mmdebstrap`, `squashfs-tools`, `debian-archive-keyring`, `qemu-user-static` and Python 3.11 or newer, then run `sudo ./scripts/package.sh`. It writes `dist/io.gizlet.retroarch-<version>-aarch64-unknown-linux-gnu-lite.gzl` and, under `dist/sources/`, the notices and the corresponding source archive. `GIZLET_DIST` chooses another output folder.

The build's smoke test ([`tests/smoke.sh`](tests/smoke.sh)) checks RetroArch's version and drivers and that every core's libraries and core info resolve. It then runs Nestopia, Gambatte, mGBA, bsnes-mercury and Beetle PCE Fast for 120 frames on synthetic ROMs that [`tests/make_roms.py`](tests/make_roms.py) writes from a few opcodes. They run under QEMU as a Cortex-A35, the R36S's CPU: build hosts with pointer authentication and BTI stop cores whose coroutines switch stacks, which the R36S never checks.

Display, sound and the physical controls need an R36S to verify.

## Release

Change `version` in [`gizlet.toml`](gizlet.toml) and merge to `main`. The version is RetroArch's plus a package revision (`1.22.2.1`). CI builds and tests on GitHub's ARM64 runner, publishes the GitHub Release and the Gizlet Store listing, then attaches `NOTICE.md` and the corresponding source archive to the release.

## Licenses and corresponding source

RetroArch is under the GNU GPL, version 3 or later. Each core and library keeps its own license, with its Debian copyright file in `runtime.sqfs` under `/usr/share/doc`. The package's `NOTICE.md` lists every Debian source package and version. Each release attaches `io.gizlet.retroarch-<version>-source.tar`, with those Debian source packages as downloaded from the snapshot, and this repository's scripts. The packaging scripts in this repository are under the MIT License. The Store icon is RetroArch's own (`media/com.libretro.RetroArch.svg`, GPL-3.0-or-later).
