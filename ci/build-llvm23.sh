#!/bin/sh
# Build LLVM 23.1.1 (the version Bun pins) into /opt/llvm23.
#
# Arch tracks the latest LLVM, which is newer than the version Bun links
# against, so the release has to be built here. The build uses whatever LLVM
# Arch's clang/flang provide as the stage-1 compiler; the result is a normal
# LLVM 23 install whose bin/ is exactly the layout BUN_TOOLCHAIN_LLVM wants.
#
# POSIX sh, no arguments. Everything is idempotent: a second run that finds
# /opt/llvm23/bin/clang prints its version and exits.
set -eu

PREFIX=${PREFIX:-/opt/llvm23}
VERSION=${LLVM_VERSION:-23.1.1}
SRC=${SRC:-/tmp/llvm-project}

if [ -x "$PREFIX/bin/clang" ]; then
  echo "LLVM already at $PREFIX: $("$PREFIX/bin/clang" --version | head -1)"
  exit 0
fi

jobs=$(nproc 2>/dev/null || echo 4)

echo "==> fetching LLVM $VERSION"
rm -rf "$SRC"
git init -q "$SRC"
git -C "$SRC" remote add origin https://github.com/llvm/llvm-project.git
git -C "$SRC" fetch --depth 1 origin "refs/tags/llvmorg-$VERSION"
git -C "$SRC" checkout -q --detach FETCH_HEAD

echo "==> configuring with $jobs jobs"
common_flags="-DLLVM_ENABLE_PROJECTS="clang;lld" -DLLVM_ENABLE_RUNTIMES=compiler-rt \
-DLLVM_TARGETS_TO_BUILD=host -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
-DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_DOCS=OFF -DLLVM_ENABLE_BINDINGS=OFF \
-DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF \
-DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ASSERTIONS=OFF \
-DLLVM_USE_LINKER=lld -DCMAKE_BUILD_TYPE=Release \
-DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++"

# Stage 1: a clang fast enough to compile stage 2. The extra target above is
# so lld exists for stage 2's -DLLVM_USE_LINKER=lld.
cmake -G Ninja -S "$SRC/llvm" -B "$SRC/build-stage1" \
  -DCMAKE_C_FLAGS="-march=x86-64 -mtune=generic" \
  -DCMAKE_CXX_FLAGS="-march=x86-64 -mtune=generic" \
  $common_flags
ninja -C "$SRC/build-stage1" clang lld || ninja -C "$SRC/build-stage1"
rm -rf "$SRC/build-stage1/lib/clang"/*/lib/linux/libclang_rt.builtins* || true

# Stage 2: built by stage 1, with a deliberately generic CPU target so the
# compiler that ends up compiling Bun needs nothing exotic itself.
cmake -G Ninja -S "$SRC/llvm" -B "$SRC/build" \
  -DCMAKE_C_COMPILER="$SRC/build-stage1/bin/clang" \
  -DCMAKE_CXX_COMPILER="$SRC/build-stage1/bin/clang++" \
  -DCMAKE_C_FLAGS="-march=x86-64 -mtune=generic" \
  -DCMAKE_CXX_FLAGS="-march=x86-64 -mtune=generic" \
  $common_flags
ninja -C "$SRC/build" install

rm -rf "$SRC"
echo "==> installed $("$PREFIX/bin/clang" --version | head -1)"
"$PREFIX/bin/lld" --version
