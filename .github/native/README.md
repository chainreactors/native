# Native SDKs

This repository publishes the prebuilt native artifacts that chainreactors
projects link or embed. Nothing here is committed to the tree: every artifact
is built by CI on a matching native runner and attached to a versioned release.

Two SDK families are published:

| SDK | Asset | Release tag | Built by |
| --- | --- | --- | --- |
| static RE2 | `native-re2-static-<version>-<platform>.tar.gz` | `re2-static-<version>` | [`rebuild-static.yml`](../workflows/rebuild-static.yml) |
| recorder | `aiscan-record-native-<version>-<platform>-<arch>.tar.gz` | `record-native-ffmpeg-…-x264-…` | [`record-native-sdk.yml`](../workflows/record-native-sdk.yml) |

Both workflows run from this repository and publish with their own
`GITHUB_TOKEN`; consumers only download. Every archive ships a `.sha256`
sidecar, and every extracted prefix carries a `.versions` manifest that
consumers compare against their own pins before use.

`.github/native/versions.env` is the single source of truth for both families.
The asset names are a contract with downstream consumers — bump the version and
the release tag together, and never replace an existing SDK version with
incompatible contents.

## Static RE2 SDK

`scripts/build-static.sh` compiles the pinned `google/re2` release plus the CRE2
C wrapper into one `libre2_cre2.a`, then packages it as `dist/re2-static/<platform>/`
and `native-re2-static-<version>-<platform>.tar.gz`.

Downstream Go consumers select it with the `re2_cgo re2_static` build tags and
point CGO at the extracted prefix:

```bash
export CGO_LDFLAGS="-L<prefix>/lib"
```

`CGO_LDFLAGS` is the only source of the library search path — `#cgo` directives
can expand `${SRCDIR}` but not environment variables, which is why the archives
can no longer live inside the module.

Supported platforms are `linux_amd64`, `linux_arm64`, `darwin_amd64`,
`darwin_arm64`, and `windows_amd64`. Each is built on a native runner: `zig c++`
uses libc++ and is not ABI-compatible with Linux/Windows consumers that link
libstdc++. The pinned RE2 release is the last one before the Abseil dependency,
which keeps archives small and avoids MinGW pthread shutdown issues.

## Recorder SDK

`record.sh` is the maintainer/CI implementation for the optional recorder
backend: a feature-minimal static FFmpeg and x264. Product repositories call
their own `make record`, which downloads and verifies the published bundle;
they do not build it here.

```bash
bash .github/native/record.sh fetch linux amd64
bash .github/native/record.sh build linux amd64
bash .github/native/record.sh package linux amd64 dist/native
bash .github/native/record.sh env linux amd64
```

Supported bundles are `linux-amd64`, `linux-arm64`, and `windows-amd64`. FFmpeg
and x264 are static, so the distributed executable does not require separate
FFmpeg/x264 installation. Operating-system libraries remain external
dependencies: Linux uses glibc and X11/XCB; Windows uses system DLLs. The source
builder uses an explicit component allowlist (capture input, H.264 encoder, MP4
muxer, and file output only), and packaging rejects static-library sets larger
than 16 MiB by default.

Environment overrides:

*   `CYBER_RECORD_PREFIX`: SDK install/cache directory.
*   `CYBER_RECORD_NATIVE_URL`: release or mirror base URL containing the archive and `.sha256` sidecar.
*   `CYBER_RECORD_OFFLINE=1`: forbid downloads and require an already cached matching SDK.
*   `CYBER_RECORD_SOURCE`: pinned source checkout directory.
*   `CYBER_RECORD_MAX_LIB_BYTES`: static-library size budget (default 16 MiB).

## macOS CGO cross-build

Product release workflows build macOS binaries on an Ubuntu runner using the Zig
C/C++ driver with a pinned macOS SDK, `CGO_ENABLED=1`, and external Go linking
so the Darwin `libcstx` and static RE2 archives can link against `Security`,
`CoreFoundation`, `libresolv`, and libc++. Those Zig and macOS SDK pins belong
to the consumer repository, not to this one.

No macOS GitHub Actions runner is used for the recorder: native recording is
supported only on the Linux and Windows bundles above.
