#!/bin/sh
# Configure on every invocation so source relocation and option changes are
# never hidden by an old cache.
set -e

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
CONFIG="${1:-Release}"
if command -v cmake >/dev/null 2>&1; then
  CMAKE=cmake
elif [ -x "/c/Program Files/CMake/bin/cmake.exe" ]; then
  CMAKE="/c/Program Files/CMake/bin/cmake.exe"
else
  echo "cmake was not found" >&2
  exit 1
fi

"$CMAKE" -S "$ROOT" -B "$BUILD" -DCMAKE_BUILD_TYPE="$CONFIG"
"$CMAKE" --build "$BUILD" --target openssl-all --parallel "${OSSL_JOBS:-8}"

echo
echo "stage: $BUILD/stage"
[ ! -f "$BUILD/openssl/$CONFIG/configure-args.txt" ] || \
  cat "$BUILD/openssl/$CONFIG/configure-args.txt"
