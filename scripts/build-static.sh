#!/bin/bash
# Build RE2 + CRE2 as a single static archive, then package it as a
# relocatable SDK archive for the current native platform.
#
# Usage:
#   ./scripts/build-static.sh [PLATFORM]
#
# Requires: g++/clang++ (or CXX), ar, curl, tar, sha256sum

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# RE2_VERSION and RE2_STATIC_VERSION live with the rest of the native SDK
# coordinates so the packaged asset name and the workflow release tag agree.
if [ -f "$REPO_ROOT/.github/native/versions.env" ]; then
    # shellcheck source=/dev/null
    . "$REPO_ROOT/.github/native/versions.env"
fi

RE2_VERSION="${RE2_VERSION:-2023-03-01}"
RE2_STATIC_VERSION="${RE2_STATIC_VERSION:-${RE2_VERSION}-1}"

CRE2_DIR="$REPO_ROOT/internal/cre2"

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  HOST_PLATFORM="linux_amd64" ;;
    Linux-aarch64) HOST_PLATFORM="linux_arm64" ;;
    Darwin-x86_64) HOST_PLATFORM="darwin_amd64" ;;
    Darwin-arm64)  HOST_PLATFORM="darwin_arm64" ;;
    MINGW*|MSYS*)  HOST_PLATFORM="windows_amd64" ;;
    *)             HOST_PLATFORM="unknown" ;;
esac

PLATFORM="${1:-$HOST_PLATFORM}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$REPO_ROOT/dist/re2-static}"
PREFIX="$OUTPUT_ROOT/$PLATFORM"
ARCHIVE="native-re2-static-${RE2_STATIC_VERSION}-${PLATFORM}.tar.gz"

if [ "$HOST_PLATFORM" = "unknown" ]; then
    echo "unsupported build host: $(uname -s)/$(uname -m)" >&2
    exit 1
fi
if [ "$PLATFORM" != "$HOST_PLATFORM" ] && [ -z "${ALLOW_CROSS:-}" ]; then
    echo "refusing to publish a native archive for $PLATFORM from $HOST_PLATFORM" >&2
    echo "run this script on the matching native runner, or set ALLOW_CROSS=1 with an ABI-compatible CXX/CC toolchain" >&2
    exit 1
fi

case "$HOST_PLATFORM" in
    darwin_*) DEFAULT_CXX="clang++" ;;
    *)        DEFAULT_CXX="g++" ;;
esac
CXX="${CXX:-$DEFAULT_CXX}"
AR="${AR:-ar}"

echo "Building RE2 $RE2_VERSION static SDK $RE2_STATIC_VERSION for $PLATFORM"
echo "  host=$HOST_PLATFORM"
echo "  CXX=$CXX"
echo "  AR=$AR"
echo "  prefix=$PREFIX"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SOURCE_ARCHIVE="$TMPDIR/re2-${RE2_VERSION}.tar.gz"
curl --fail --location --silent --show-error \
    --retry 5 --retry-all-errors \
    --output "$SOURCE_ARCHIVE" \
    "https://github.com/google/re2/archive/refs/tags/${RE2_VERSION}.tar.gz"
tar xzf "$SOURCE_ARCHIVE" -C "$TMPDIR"
RE2_SRC="$TMPDIR/re2-${RE2_VERSION}"

mkdir -p "$TMPDIR/build"
for f in "$RE2_SRC"/re2/*.cc "$RE2_SRC"/util/rune.cc "$RE2_SRC"/util/strutil.cc; do
    [ -f "$f" ] || continue
    OBJ="$TMPDIR/build/$(basename "$f" .cc).o"
    $CXX -std=c++17 -O2 -DNDEBUG -fPIC -I"$RE2_SRC" -c "$f" -o "$OBJ"
done

$CXX -std=c++17 -O2 -DNDEBUG -fPIC \
    -I"$RE2_SRC" -I"$CRE2_DIR" \
    -c "$CRE2_DIR/cre2.cpp" \
    -o "$TMPDIR/build/cre2.o"

# MinGW's std::call_once ABI changed between GCC 15 and 16. Bundle the
# matching libstdc++ implementation object so the archive remains linkable
# when the downstream CGO compiler is a different MinGW GCC release.
if [ "$PLATFORM" = "windows_amd64" ]; then
    LIBSTDCXX="$($CXX -print-file-name=libstdc++.a)"
    if [ ! -f "$LIBSTDCXX" ]; then
        echo "unable to locate static libstdc++: $LIBSTDCXX" >&2
        exit 1
    fi
    (
        cd "$TMPDIR/build"
        "$AR" x "$LIBSTDCXX" mutex.o
        mv mutex.o libstdcxx_mutex.o
    )
fi

# glibc compat: on glibc >=2.38, gcc emits __isoc23_strtol calls; bundle weak
# fallbacks so the archive links on older glibc too.
if [ "$PLATFORM" = "linux_amd64" ] || [ "$PLATFORM" = "linux_arm64" ]; then
    ${CC:-gcc} -O2 -fPIC -c "$CRE2_DIR/isoc23_compat_linux.c" -o "$TMPDIR/build/isoc23_compat.o"
fi

rm -rf "$PREFIX"
mkdir -p "$PREFIX/lib" "$PREFIX/share/licenses/re2"
"$AR" rcs "$PREFIX/lib/libre2_cre2.a" "$TMPDIR"/build/*.o

cp "$RE2_SRC/LICENSE" "$PREFIX/share/licenses/re2/LICENSE"

if [ "$PLATFORM" = "windows_amd64" ]; then
    CXX_PREFIX="$(dirname "$(dirname "$(command -v "$CXX")")")"
    mkdir -p "$PREFIX/share/licenses/gcc"
    cp "$CXX_PREFIX/share/licenses/gcc-libs/COPYING3" "$PREFIX/share/licenses/gcc/COPYING3"
    cp "$CXX_PREFIX/share/licenses/gcc-libs/COPYING.RUNTIME" "$PREFIX/share/licenses/gcc/COPYING.RUNTIME"
fi

printf '%s' "bundle=${RE2_STATIC_VERSION} platform=${PLATFORM} re2=${RE2_VERSION}" > "$PREFIX/.versions"
cat > "$PREFIX/README.txt" <<EOF
native static RE2 SDK ${RE2_STATIC_VERSION}
Target: ${PLATFORM}
RE2: ${RE2_VERSION} (final release before the Abseil dependency)

This bundle contains libre2_cre2.a, a static archive combining RE2 and the CRE2
C wrapper. Link consumers with CGO_LDFLAGS=-L<prefix>/lib and the
"re2_cgo re2_static" build tags. OS system libraries remain external
platform dependencies.
EOF

mkdir -p "$OUTPUT_ROOT"
# GNU tar's reproducibility flags do not exist in bsdtar, which is what macOS
# ships. Use them where they are supported so that repeated builds of the same
# source produce byte-identical archives, and fall back to a plain archive
# otherwise: consumers verify the sha256 sidecar, not a pinned digest.
TAR_VERSION="$(tar --version 2>/dev/null || true)"
if printf '%s' "${TAR_VERSION}" | grep -qi 'gnu tar'; then
    tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
        -C "$PREFIX" -cf - . | gzip -n > "$OUTPUT_ROOT/${ARCHIVE}"
else
    tar -C "$PREFIX" -cf - . | gzip -n > "$OUTPUT_ROOT/${ARCHIVE}"
fi
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$OUTPUT_ROOT" && sha256sum "${ARCHIVE}" > "${ARCHIVE}.sha256")
else
    digest="$(shasum -a 256 "$OUTPUT_ROOT/${ARCHIVE}" | awk '{print $1}')"
    printf '%s  %s\n' "${digest}" "${ARCHIVE}" > "$OUTPUT_ROOT/${ARCHIVE}.sha256"
fi

echo "Built: $PREFIX/lib/libre2_cre2.a ($(du -h "$PREFIX/lib/libre2_cre2.a" | cut -f1))"
echo "Packaged: $OUTPUT_ROOT/${ARCHIVE}"
