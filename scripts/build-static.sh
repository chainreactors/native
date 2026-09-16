#!/bin/bash
# Build RE2 + CRE2 as a single static archive for the current native platform.
#
# Usage:
#   ./scripts/build-static.sh [PLATFORM]
#
# Requires: g++/clang++ (or CXX), ar, curl

set -euo pipefail

RE2_VERSION="${RE2_VERSION:-2023-03-01}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
OUTPUT_ROOT="${OUTPUT_ROOT:-$CRE2_DIR/lib}"
OUTPUT_DIR="$OUTPUT_ROOT/$PLATFORM"

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

echo "Building RE2 $RE2_VERSION static archive for $PLATFORM"
echo "  host=$HOST_PLATFORM"
echo "  CXX=$CXX"
echo "  AR=$AR"

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

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/libre2_cre2.a"
$AR rcs "$OUTPUT_DIR/libre2_cre2.a" "$TMPDIR"/build/*.o

cp "$RE2_SRC/LICENSE" "$OUTPUT_DIR/RE2_LICENSE"

if [ "$PLATFORM" = "windows_amd64" ]; then
    CXX_PREFIX="$(dirname "$(dirname "$(command -v "$CXX")")")"
    cp "$CXX_PREFIX/share/licenses/gcc-libs/COPYING3" "$OUTPUT_DIR/GCC_COPYING3"
    cp "$CXX_PREFIX/share/licenses/gcc-libs/COPYING.RUNTIME" "$OUTPUT_DIR/GCC_COPYING.RUNTIME"
fi

echo "Built: $OUTPUT_DIR/libre2_cre2.a ($(du -h "$OUTPUT_DIR/libre2_cre2.a" | cut -f1))"
