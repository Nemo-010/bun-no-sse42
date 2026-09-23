#!/bin/sh
# Install LLVM 23.1.1 (the version Bun pins) into /opt/llvm23.
#
# Arch tracks the latest LLVM, which is newer than what Bun's build accepts
# (it compares clang's own version against its pin and refuses anything else),
# so a 23.1.1 toolchain has to be put next to Arch's. LLVM publishes one:
# use it instead of building LLVM on the runner.
#
# The release opens with `#!/usr/bin/env python3`, so python has to be in PATH
# here — the container has an older glibc than the tarball assumes.
#
# POSIX sh, no arguments. Idempotent: a second run finds /opt/llvm23 and exits.
set -eu

PREFIX=${PREFIX:-/opt/llvm23}
VERSION=${LLVM_VERSION:-23.1.1}
ARCHIVE=${ARCHIVE:-/tmp/LLVM-$VERSION-Linux-X64.tar.xz}
URL=${URL:-https://github.com/llvm/llvm-project/releases/download/llvmorg-$VERSION/LLVM-$VERSION-Linux-X64.tar.xz}

if [ -x "$PREFIX/bin/clang" ]; then
  echo "LLVM already at $PREFIX: $("$PREFIX/bin/clang" --version | head -1)"
  exit 0
fi

echo "==> downloading LLVM $VERSION"
[ -f "$ARCHIVE" ] || curl -fsSL "$URL" -o "$ARCHIVE"

echo "==> extracting to $PREFIX"
rm -rf "$PREFIX"
mkdir -p "$PREFIX"
# --strip-components=1: the archive holds a single top-level directory.
tar -xJf "$ARCHIVE" -C "$PREFIX" --strip-components=1
rm -f "$ARCHIVE"

version=$("$PREFIX/bin/clang" --version | head -1)
case "$version" in
  *"clang version $VERSION"*) ;;
  *)
    echo "clang at $PREFIX reports '$version', expected 'clang version $VERSION'" >&2
    exit 1
    ;;
esac
echo "==> installed $version"
"$PREFIX/bin/lld" --version
