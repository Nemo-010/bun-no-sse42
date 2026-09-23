#!/bin/sh
# Install LLVM 23 for Bun into /opt/llvm23.
#
# Arch tracks the latest LLVM, which is newer than what Bun's build accepts:
# it compares clang's own version against its pin (scripts/build/tools.ts,
# LLVM_VERSION_RANGE) and refuses anything else, because mixing LLVM versions
# in one link is what causes the runtime allocation failures the build system
# warns about.
#
# LLVM's own release tarball is not usable here: its non-clang tools link
# against LLVM's bundled ICU at libicu*.so.70, which this distribution neither
# has nor should have. Debian's packages for LLVM 23 are built against the
# system ICU instead, so llvm.org's apt repository is the source. Extracting
# the .debs rather than installing them keeps dpkg out of a pacman-managed
# system; what they need at runtime (libedit, libffi, zstd, libxml2, z3) is
# either already installed or comes from Arch's llvm-libs.
#
# POSIX sh, no arguments. Idempotent: a second run finds /opt/llvm23 and exits.
set -eu

PREFIX=${PREFIX:-/opt/llvm23}
REPO=${REPO:-https://apt.llvm.org/jammy}
SUITE=${SUITE:-llvm-toolchain-jammy-23}
PACKAGES=${PACKAGES:-clang-23 lld-23 libclang-rt-23-dev}

if [ -x "$PREFIX/bin/clang" ]; then
  echo "LLVM already at $PREFIX: $("$PREFIX/bin/clang" --version | head -1)"
  exit 0
fi

echo "==> reading $SUITE from $REPO"
index=/tmp/llvm23-Packages
curl -fsSL "$REPO/dists/$SUITE/main/binary-amd64/Packages.gz" -o "$index.gz"
gzip -dc "$index.gz" > "$index"
rm -f "$index.gz"

# Packages list relative paths under pool/; the archive's root is $REPO.
filename_of() {
  awk -v p="$1" '
    /^Package: / { want = ($2 == p) }
    want && /^Filename: / { print $2; exit }
  ' "$index"
}

rm -rf "$PREFIX"
mkdir -p "$PREFIX"

for pkg in $PACKAGES; do
  path=$(filename_of "$pkg")
  if [ -z "$path" ]; then
    echo "no $pkg in $SUITE" >&2
    exit 1
  fi
  echo "==> $pkg"
  deb=/tmp/llvm23.deb
  curl -fsSL "$REPO/$path" -o "$deb"
  dpkg-deb -x "$deb" "$PREFIX"
  rm -f "$deb"
done

# The packages install under usr/{bin,lib,include,share}; flatten so that
# $PREFIX/bin/clang is what BUN_TOOLCHAIN_LLVM is expected to point at.
if [ -d "$PREFIX/usr" ]; then
  for d in "$PREFIX"/usr/*; do
    name=$(basename "$d")
    if [ -e "$PREFIX/$name" ]; then
      cp -a "$d/." "$PREFIX/$name/"
    else
      mv "$d" "$PREFIX/$name"
    fi
  done
  rm -rf "$PREFIX/usr"
fi

for tool in clang clang++ clang-23 ld.lld lld llvm-ar llvm-nm llvm-ranlib llvm-strip llvm-objcopy; do
  if [ ! -e "$PREFIX/bin/$tool" ]; then
    echo "missing $PREFIX/bin/$tool" >&2
    exit 1
  fi
done

version=$("$PREFIX/bin/clang" --version | head -1)
case "$version" in
  *"clang version 23."*) ;;
  *)
    echo "clang at $PREFIX reports '$version', expected 23.x" >&2
    exit 1
    ;;
esac
echo "==> installed $version"
"$PREFIX/bin/ld.lld" --version
