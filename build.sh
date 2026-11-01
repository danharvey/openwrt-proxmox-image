#!/bin/sh
# Build a generic OpenWrt x86-64 image for Proxmox VE using the official
# ImageBuilder container. Requires docker. Output: bin/targets/x86/64/.
#
#   ./build.sh            build the image
#   ./build.sh --version  print the OpenWrt version that would be built
#
# RELEASE_TAG (e.g. 25.12.6-2, the release tag without its leading v) is
# written into the image as /etc/openwrt_release_tag, so a running system can
# tell which build revision it has: /etc/openwrt_release only carries the
# OpenWrt version. CI sets it; local builds without it don't ship the file.
set -eu

# Renovate keeps this pinned to the latest stable release (docker datasource).
IMAGEBUILDER="openwrt/imagebuilder:x86-64-25.12.6@sha256:b7cc4a580367f48436f4b2c00ef4aa8f8a0024d63ffc8248900ffa4b960761b4"

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

if [ "${1:-}" = "--version" ]; then
  echo "$VERSION"
  exit 0
fi

RELEASE_TAG="${RELEASE_TAG:-}"
case "$RELEASE_TAG" in
  "" | "$VERSION"-[0-9]*) ;;
  *)
    echo "RELEASE_TAG '$RELEASE_TAG' does not match OpenWrt version $VERSION" >&2
    exit 1
    ;;
esac

# Stage files/ so build-time files can be added without touching the repo.
# The imagebuilder container user (uid 1000) must be able to read it.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -a files/. "$STAGE/"
if [ -n "$RELEASE_TAG" ]; then
  mkdir -p "$STAGE/etc"
  printf '%s\n' "$RELEASE_TAG" > "$STAGE/etc/openwrt_release_tag"
fi
chmod -R a+rX "$STAGE"

rm -rf bin
mkdir -p bin
# The imagebuilder container runs as its own 'buildbot' user (uid 1000), which
# must be able to write the mounted output dir regardless of the host uid.
chmod 777 bin

docker run --rm -u 1000 \
  -v "$(pwd)/bin:/builder/bin" \
  -v "$STAGE:/builder/files:ro" \
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
