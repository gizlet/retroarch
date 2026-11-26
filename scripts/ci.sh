#!/bin/sh
# CI entry: installs the packaging tools on GitHub's Ubuntu ARM64 runner, then
# builds, tests and packages as root. dist/ is handed back to the runner user.
set -eu

project=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
sudo apt-get update -q
sudo apt-get install -y -q --no-install-recommends mmdebstrap squashfs-tools debian-archive-keyring python3 qemu-user-static
sudo "$project/scripts/package.sh"
sudo chown -R "$(id -u):$(id -g)" "$project/dist"
