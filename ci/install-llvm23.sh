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

# LLVM's release builds -- but not the clang this container builds against --
# are linked against LLVM's bundled ICU, which is at soname 70 while the
# system ICU has moved on. LD_LIBRARY_PATH rather than ld.so.conf: the
# container's ldconfig wants libc.so.6 from the host's newer glibc, so
# running it here is not safe. The PATH entry that puts this toolchain first
# is paired with this variable in the workflow.
echo "==> llvm23 links LLVM's bundled ICU"
cat > /etc/profile.d/llvm23.sh <<EOF
export BUN_TOOLCHAIN_LLVM=$PREFIX
export LD_LIBRARY_PATH=$PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
EOF
if ! LD_LIBRARY_PATH="$PREFIX/lib" "$PREFIX/bin/lld" --version; then
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
