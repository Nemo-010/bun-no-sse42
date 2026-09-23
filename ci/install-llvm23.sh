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
ICU_VERSION=${ICU_VERSION:-70.1}
ICU_BASE=${ICU_BASE:-https://raw.githubusercontent.com/freebsd/freebsd-ports/main/distfiles}
URL=${URL:-https://github.com/llvm/llvm-project/releases/download/llvmorg-$VERSION/LLVM-$VERSION-Linux-X64.tar.xz}

if [ -x "$PREFIX/bin/clang" ]; then
  echo "LLVM already at $PREFIX: $("$PREFIX/bin/clang" --version | head -1)"
  exit 0
fi

echo "==> downloading LLVM $VERSION"
[ -f "$ARCHIVE" ] || curl -fsSL "$URL" -o "$ARCHIVE"
case "$(od -An -tx1 -N2 "$ARCHIVE" | tr -d ' \n')" in
  fd37) ;;
  *)
    echo "$URL did not return an xz archive (is the release asset still there?)" >&2
    exit 1
    ;;
esac

rm -rf "$PREFIX"
mkdir -p "$PREFIX"
# --strip-components=1: the archive holds a single top-level directory,
# whose bin/ has the clang-23 symlink beside clang.
tar -xJf "$ARCHIVE" -C "$PREFIX" --strip-components=1
rm -f "$ARCHIVE"

# LLVM's release build here is linked against LLVM's own ICU 70, which the
# distribution does not have and should not have. Ask the loader what exactly
# it is missing and fetch those libraries (FreeBSD base-system style naming)
# into the prefix, rather than dragging an old ICU in for its sake.
echo "==> resolving llvm23's own libraries"
libdir=$PREFIX/lib
LD_LIBRARY_PATH=$libdir ldd "$PREFIX/bin/lld" 2>/dev/null \
  | awk '/not found/ { print $1 }' \
  | while read -r name; do
      case "$name" in
        libicu*) ;;
        *) echo "no known source for $name" >&2; exit 1 ;;
      esac
      curl -fsSL "$ICU_BASE/${name}-${ICU_VERSION}.txz" -o /tmp/"${name}.txz"
      tar -xJf /tmp/"${name}.txz" --strip-components=3 -C "$libdir"
      rm -f /tmp/"${name}.txz"
    done

if ! LD_LIBRARY_PATH=$libdir "$PREFIX/bin/lld" --version; then
  echo "lld still cannot load; the archive's layout changed" >&2
  exit 1
fi

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
