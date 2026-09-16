# Static CGO backend

> See also the [Static CGO section in README.md](README.md#static-cgo-no-runtime-dll-dependencies) for usage instructions.

## How it works

The `re2_static` build tag selects platform-specific Go files that link a
pre-built static archive (`libre2_cre2.a`) instead of using `pkg-config` to
find a system-installed libre2. The archive bundles RE2 and the CRE2 C wrapper
into a single `.a` file, and the `#cgo LDFLAGS` directive statically links the
C++ runtime as well.

The archive is **not** committed to this repository. It is built and published
as a release asset (`native-re2-static-<RE2_VERSION>-<platform>.tar.gz`), and
the consumer supplies the library search path:

```bash
export CGO_LDFLAGS="-L<prefix>/lib"
```

`CGO_LDFLAGS` is the only source of `-L`: `#cgo` directives can expand
`${SRCDIR}` but not arbitrary environment variables, so embedding a
checkout-relative path is not an option once the archive lives outside the
module.

### Build tag matrix

| Tags | Backend | Linking |
|------|---------|---------|
| *(none)* | wazero WASM | Pure Go, no CGO |
| `re2_cgo` | System libre2 via `pkg-config` | Dynamic (`libre2.so` / `libre2.dll`) |
| `re2_cgo re2_static` | Published `libre2_cre2.a` | Static (no C/C++ runtime deps) |

### Platform files

```
internal/cre2/
├── cre2_re2_cgo.go                 # re2_cgo && !re2_static → pkg-config
├── cre2_re2_static.go              # re2_cgo && re2_static && windows/amd64
├── cre2_re2_static_linux_amd64.go  # re2_cgo && re2_static && linux/amd64
├── cre2_re2_static_linux_arm64.go  # re2_cgo && re2_static && linux/arm64
└── cre2_re2_static_darwin.go       # re2_cgo && re2_static && darwin/amd64|arm64
```

### RE2 version

Archives use RE2 **2023-03-01**, the final release before the Abseil
dependency was added. This keeps archives small (~1 MB) and avoids MinGW
pthread shutdown issues that Abseil can trigger.

The Windows archive also contains the `mutex.o` implementation from the
build-time libstdc++. This isolates RE2's `std::call_once` ABI from MinGW GCC
version changes (notably the GCC 15 to 16 transition); the remaining GNU C++
runtime is still selected and linked statically by CGO.

### CI build and publish

The [rebuild-static.yml](.github/workflows/rebuild-static.yml) workflow
triggers on changes to `cre2.cpp`, `cre2.h`, `cre2_re2_static*.go`, or
`scripts/build-static*`. It builds each archive on a matching native CI runner
(Ubuntu GCC, Apple Clang, or MSYS2 MinGW GCC), verifies it with
`go test -tags "re2_cgo re2_static" ./...`, packages a per-platform archive
with a SHA-256 sidecar, and publishes everything to the `re2-static-*` release
in this repository using the workflow's own `GITHUB_TOKEN`. Nothing is
committed back to the tree.

Native toolchains are intentional: `zig c++` uses libc++ and is not
ABI-compatible with Linux/Windows consumers that link libstdc++.

### Adding a new platform

1. Add the platform to the CI matrix in `rebuild-static.yml` with a matching
   native runner
2. Create `internal/cre2/cre2_re2_static_<os>_<arch>.go` with the appropriate
   build constraint and `#cgo LDFLAGS` for the extra link flags that platform
   needs (the `-L` comes from the consumer's `CGO_LDFLAGS`)
