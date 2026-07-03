#!/bin/sh
# Build a generic OpenWrt x86-64 image for Proxmox VE using the official
# ImageBuilder container. Requires docker. Output: bin/targets/x86/64/.
set -eu

# Renovate keeps this pinned to the latest stable release (docker datasource).
IMAGEBUILDER="openwrt/imagebuilder:x86-64-25.12.5@sha256:3eb52da7a3e521e601976a11439d44d7e489e944e02e91ad693eb6f8d2b3d603"

PROFILE="generic"
# x86 sysupgrade rewrites the partition table from the image: this value must
# never change once VMs are provisioned, or in-place upgrades will resize
# partitions out from under the installed system.
ROOTFS_PARTSIZE="1024"
EXTRA_IMAGE_NAME="proxmox"

PACKAGES="$(grep -v '^#' packages.txt | xargs)"

TAG="${IMAGEBUILDER#*:}"
TAG="${TAG%%@*}"
VERSION="${TAG#x86-64-}"

rm -rf bin
mkdir -p bin
# The imagebuilder container runs as its own 'buildbot' user (uid 1000), which
# must be able to write the mounted output dir regardless of the host uid.
chmod 777 bin

docker run --rm -u 1000 \
  -v "$(pwd)/bin:/builder/bin" \
  -v "$(pwd)/files:/builder/files:ro" \
  "$IMAGEBUILDER" \
  make image \
  PROFILE="$PROFILE" \
  ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE" \
  EXTRA_IMAGE_NAME="$EXTRA_IMAGE_NAME" \
  FILES="files" \
  PACKAGES="$PACKAGES"

OUTDIR="bin/targets/x86/64"
IMAGE="$OUTDIR/openwrt-$VERSION-$EXTRA_IMAGE_NAME-x86-64-$PROFILE-ext4-combined.img.gz"
test -f "$IMAGE"
# Written outside bin/ — the container user owns the output tree.
(cd "$OUTDIR" && sha256sum "$(basename "$IMAGE")") > sha256sums.txt

echo "Built $IMAGE"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$VERSION" >> "$GITHUB_OUTPUT"
  echo "image=$IMAGE" >> "$GITHUB_OUTPUT"
fi
