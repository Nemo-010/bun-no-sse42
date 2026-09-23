# bun-no-sse42

A GitHub Actions harness that compiles [Bun](https://bun.sh) for x86-64 CPUs
that have **neither SSE4.2 nor AVX**.

Upstream Bun's x64 build is compiled with `-march=nehalem`, so it requires
SSE4.2 (and, for the shipped WebKit archives, `-march=nehalem` too). This
workflow rewrites the one place that CPU target is chosen —
[`scripts/build/flags.ts`](https://github.com/oven-sh/bun/blob/main/scripts/build/flags.ts),
`cpuTargetFlags` — and rebuilds everything from source, including
WebKit/JavaScriptCore.

## What is actually changed

Only one line:

```diff
-    flag: "-march=nehalem",
+    flag: "-march=x86-64",
     when: c => c.x64,
-    desc: "x64: Nehalem (2008) — no AVX, broadest compatibility",
+    desc: "x64: generic x86-64 (SSE2) — no SSE4.2, no AVX",
```

That table is spread into `globalFlags`, so the change propagates to Bun's own
C/C++, every vendored dependency, the Rust crates (`-Ctarget-cpu=x86-64`) and
the local WebKit/JavaScriptCore build. Runtime-dispatched SIMD (zlib, BoringSSL,
libwebp, libjpeg-turbo, highway, …) is untouched: those files keep their own
`-msse4.2`/`-mavx2` flags and gate execution on `cpuid`.

`-march=x86-64` is the SSE2 baseline: any 64-bit x86 CPU can run it. If you
want a slightly newer floor, the workflow can build `core2` (SSSE3 + SSE4.1,
still no SSE4.2 and no AVX) or `penryn` instead.

A prebuilt WebKit cannot be reused. `oven-sh/WebKit`'s release archives are
themselves compiled with `-march=nehalem`, so the workflow clones the pinned
WebKit commit and builds `jsc` from source with the patched flags.

## Built on Arch Linux

The build runs inside the `archlinux:latest` container, because Arch carries
one current LLVM, one current glibc, and every package Bun's build needs from
one repository. The workflow installs `base-devel`, `clang`/`llvm`/`lld`,
`cmake`, `ninja`, `nasm`, `icu`, `ruby`, `go`, `pkgconf`, `python`, `ccache`,
`qemu-user` and Rust's pinned nightly with `rustup` (Arch's `rust` is stable,
and Bun needs the pinned nightly for `-Zbuild-std`).

Two consequences to keep in mind:

* The binary is built against the glibc Arch ships at the time of the run
  (2.44 or newer), so it is **not** runnable on older distributions — the
  artifact's `ldd.txt` and `os-release-arch.txt` record exactly what it was
  built against. Bun's own CI sticks to an ubuntu-20.04 glibc 2.31 sysroot for
  this reason; the `long_glibc` input here attempts that (experimental).
* Arch's `[extra]` has moved past LLVM 23, and Bun's build accepts only 23.x —
  it compares clang's own version against its pin on purpose, because mixing
  LLVM versions in one link is what causes the runtime allocation failures the
  build system warns about. `ci/install-llvm23.sh` therefore installs the
  **23.1.1** `llvm`, `clang`, `lld` and `llvm-libs` packages from Arch's
  `[extra-staging]` (the staging tree of the same repository, so they are built
  against the ICU and libstdc++ the container already has). Nothing is
  compiled to get them. LLVM's own release tarball is deliberately *not* used:
  its `lld` needs LLVM's bundled `libicu*.so.70`, which Arch does not have.

## Running it

Actions → **bun-no-sse42** → *Run workflow*. The defaults build the commit this
repository was set up against with `-march=x86-64`. A push to `main` also runs
it.

The result is uploaded as the artifact `bun-linux-x64-<march>` and contains:

| file | what it is |
| --- | --- |
| `bun` | the release binary |
| `libicu*.so.*` | the ICU libraries it was linked against (Linux local-WebKit builds link ICU dynamically) |
| `ldd.txt` | its full dynamic library list |

```sh
mkdir bun-bundle && cd bun-bundle
unzip /path/to/bun-linux-x64-x86-64.zip
LD_LIBRARY_PATH="$PWD" ./bun --version
./bun --version && ./bun -e 'console.log("hello")'
```

If a `libicu` of the same soname is already installed on the target, the
`LD_LIBRARY_PATH` is not needed; the bundled copies are just insurance.

## Verifying the CPU floor

The workflow runs the binary under QEMU user emulation with a CPU model that
reports no SSE4.2 and no AVX (`qemu64` for `-march=x86-64`, `core2duo` for
`core2`). To repeat locally:

```sh
qemu-x86_64 -cpu qemu64 ./bun --version
qemu-x86_64 -cpu qemu64 ./bun -e 'console.log([1,2,3].map(x => x * 2))'
```

You can also disassemble and look for the instructions that must not appear
outside a `cpuid`-guarded dispatcher:

```sh
objdump -d ./bun | grep -E '\b(crc32|popcnt|v[a-z]+)\b' | head
```

## Caveats

* **glibc.** Built on Arch, the binary needs Arch's glibc (≥ 2.44 at the time
  of writing). Set the `long_glibc` input to link against Bun's ubuntu-20.04
  **glibc 2.31** sysroot instead (`ci/provision-glibc-sysroot.sh`); that path is
  newer and marked experimental here.
* **ICU.** Linked dynamically from Arch's `icu` package. The bundled
  `libicu*.so.*` covers systems without it; a matching soname elsewhere works
  too.
* **Build size and time.** WebKit from source plus Bun is large (~30-40 GB of
  disk) and slow: on the free 4-core public runner expect a few hours. If it
  exceeds the job's 350-minute timeout, a larger runner will be needed.
* **This is not an official Bun distribution.** It is a reproducible build
  recipe; report Bun bugs to `oven-sh/bun`.

## Pinned revisions

| what | revision |
| --- | --- |
| Bun | `6d504dd983bd6017c9baa5087066afefbee70e66` |
| WebKit | `299c5323879e79af282d7bb7bac8b8446a0be3f3` (`WEBKIT_VERSION`) |
| Rust | `nightly-2026-09-15` (`rust-toolchain.toml`) |
| LLVM | 23.1.1 (`apt.llvm.org`) |
