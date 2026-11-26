"""Writes NOTICE.md for the package: what it contains, under which licenses,
and where the corresponding source is.
Usage: notice.py PROJECT RUNTIME SOURCES_LIST VERSION OUTPUT"""

from pathlib import Path
import re
import sys

project, runtime, sources_list, version, output = sys.argv[1:]
runtime = Path(runtime)
sources = [line.strip() for line in Path(sources_list).read_text().splitlines() if line.strip()]
snapshot = re.search(r"^snapshot=(\S+)$", Path(project, "scripts/package.sh").read_text(), re.M).group(1)
release = f"https://github.com/gizlet/retroarch/releases/tag/v{version}"


def licenses(package: str) -> str:
    copyright = runtime / "usr/share/doc" / package / "copyright"
    if not copyright.is_file():
        return ""
    found = []
    for match in re.finditer(r"^License:\s*(\S.*)$", copyright.read_text(errors="replace"), re.M):
        name = match.group(1).strip()
        if name not in found:
            found.append(name)
    return ", ".join(found[:6])


installed = sorted(p.name for p in (runtime / "usr/share/doc").iterdir() if p.is_dir())
lines = [
    f"# RetroArch {version} for Gizlet: notices",
    "",
    "This package contains RetroArch, built from Debian's `retroarch` source package with the",
    "configuration in `scripts/package.sh` of https://github.com/gizlet/retroarch, and a runtime",
    f"of unmodified Debian packages from https://snapshot.debian.org/archive/debian/{snapshot}/.",
    "It contains no games, BIOS or firmware files, and no game artwork.",
    "",
    "RetroArch is free software under the GNU General Public License, version 3 or later. Each",
    "libretro core and runtime library keeps its own license; the full copyright and license",
    "text of every Debian package is in `runtime.sqfs` under `/usr/share/doc/<package>/copyright`,",
    "and RetroArch's own is at `/usr/share/doc/retroarch/`.",
    "",
    "## Corresponding source",
    "",
    f"The complete corresponding source is attached to the release this package comes from, {release},",
    f"as `io.gizlet.retroarch-{version}-source.tar`: every Debian source package listed below,",
    "exactly as built and installed, and this package's build scripts and configuration.",
    "The same Debian sources stay available from the snapshot above.",
    "",
    "| Source package | Version |",
    "| --- | --- |",
]
for entry in sources:
    name, _, ver = entry.partition("=")
    lines.append(f"| {name} | {ver} |")
lines += ["", "## Installed packages and their licenses", "", "| Package | Licenses (from its copyright file) |", "| --- | --- |"]
for package in installed:
    lines.append(f"| {package} | {licenses(package) or 'see its copyright file'} |")
Path(output).write_text("\n".join(lines) + "\n", encoding="utf-8")
