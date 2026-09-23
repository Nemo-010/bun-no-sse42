#!/usr/bin/env bash
# Provision /opt/linux-sysroot-glibc the way scripts/build/ci-images/spec.ts does:
# ubuntu 20.04's root filesystem (glibc 2.31, focal libc headers) plus gcc-13's
# libstdc++ headers and libraries. Bun's build detects this path and links the
# native Linux build against it, so the resulting binary needs only glibc 2.31.
set -euo pipefail

SYSROOT=/opt/linux-sysroot-glibc
CODENAME=focal
DEB=amd64
MIRROR=http://archive.ubuntu.com/ubuntu
GCC_DEBS=https://github.com/oven-sh/WebKit/releases/download/gcc-13-focal-debs/gcc-13-${CODENAME}-${DEB}.tar.gz

if [ -d "$SYSROOT/usr/include/c++/13" ]; then
  echo "glibc sysroot already present at $SYSROOT"
  exit 0
fi

sudo mkdir -p "$SYSROOT"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "==> extracting ubuntu:${CODENAME} root filesystem"
docker pull "ubuntu:20.04"
id=$(docker create "ubuntu:20.04")
docker export "$id" | sudo tar -C "$SYSROOT" -xf -
docker rm "$id"

echo "==> fetching libc packages from ${CODENAME}"
curl -fsSL "$MIRROR/dists/${CODENAME}-updates/main/binary-${DEB}/Packages.gz" -o "$work/updates.gz"
curl -fsSL "$MIRROR/dists/${CODENAME}/main/binary-${DEB}/Packages.gz" -o "$work/release.gz"
gzip -dc "$work/updates.gz" "$work/release.gz" > "$work/Packages"
for pkg in libc6 libc6-dev linux-libc-dev libcrypt1 libcrypt-dev; do
  path=$(awk -v p="$pkg" '$1=="Package:"&&$2==p{f=1} f&&$1=="Filename:"{print $2; exit}' "$work/Packages")
  if [ -z "$path" ]; then
    echo "no ${pkg} found in ${CODENAME} Packages" >&2
    exit 1
  fi
  curl -fsSL "$MIRROR/$path" -o "$work/${pkg}.deb"
  sudo dpkg-deb -x "$work/${pkg}.deb" "$SYSROOT"
done

echo "==> fetching gcc-13 libstdc++"
curl -fsSL "$GCC_DEBS" -o "$work/gcc.tar.gz"
mkdir -p "$work/gcc"
tar -xzf "$work/gcc.tar.gz" -C "$work/gcc"
for deb in "$work"/gcc/*.deb; do
  sudo dpkg-deb -x "$deb" "$SYSROOT"
done

test -d "$SYSROOT/usr/include/c++/13"
echo "glibc sysroot ready at $SYSROOT"
