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

## Built on Ubuntu 24.04

The build runs on stock Ubuntu 24.04, the distribution Bun's own build scripts
and documentation assume: `apt` for `build-essential`, `cmake`, `ninja-build`,
`nasm`, `libicu-dev`, `ruby`, `ruby-erb`, `golang`, `pkg-config`, `ccache` and
`libatomic1`, `apt.llvm.org` for LLVM 23, and `rustup` for the pinned nightly
(Bun needs nightly for `-Zbuild-std`). All of that is what the upstream
`CONTRIBUTING.md` tells a contributor to install.

One consequence to keep in mind: the binary is built against Ubuntu 24.04's
glibc (2.39), so it will not run on a distribution older than that — the
artifact's `ldd.txt` and `os-release.txt` record exactly what it was built
against. Bun's own CI goes further and links an ubuntu-20.04 glibc 2.31
sysroot for this reason; the `long_glibc` input here attempts that
(experimental, untested).

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

* **glibc.** Built on Ubuntu 24.04, the binary needs glibc ≥ 2.39. Set the
  `long_glibc` input to link against Bun's ubuntu-20.04 **glibc 2.31** sysroot
  instead (`ci/provision-glibc-sysroot.sh`); that path is newer and marked
  experimental here.
* **ICU.** Linked dynamically from Ubuntu's `libicu-dev`. The bundled
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
