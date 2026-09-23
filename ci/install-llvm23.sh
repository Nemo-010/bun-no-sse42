#!/bin/sh
# Install LLVM 23 (the version Bun's build pins) from Arch's extra-staging
# repository.
#
# Arch's [extra] has moved past 23 and Bun's build compares clang's own
# version against its pin (scripts/build/tools.ts, LLVM_VERSION_RANGE) and
# refuses anything else, because mixing LLVM versions in one link is what
# causes the runtime allocation failures the build system warns about.
# [extra-staging] carries the 23.1.1 packages before they move to [extra],
# and they are built against the ICU and libstdc++ this container already has
# -- unlike LLVM's own release tarball, whose lld wants libicu*.so.70.
#
# Each package page redirects to a mirror that has the staging tree; follow
# it rather than trusting the mirrorlist, which serves [extra].
#
# POSIX sh, no arguments. Idempotent: a second run reuses
# /var/cache/pacman/pkg and pacman leaves the installed versions alone.
set -eu

CACHE=${CACHE:-/var/cache/pacman/pkg}
PACKAGES=${PACKAGES:-llvm clang lld llvm-libs}

for pkg in $PACKAGES; do
  url=$(curl -fsSL "https://archlinux.org/packages/extra-staging/x86_64/$pkg/download/" \
    -o /dev/null -w '%{url_effective}')
  file=${url##*/}
  if [ ! -f "$CACHE/$file" ]; then
    echo "==> $pkg"
    curl -fsSL -o "$CACHE/$file" "$url"
  fi
  pacman -U --noconfirm --needed "$CACHE/$file"
done

clang --version | head -1
# `lld` is the generic driver and exits non-zero without a flavor argument;
# ld.lld is the Unix one and is what the build looks for beside clang.
ld.lld --version
