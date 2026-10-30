#!/bin/bash
# Cross-compile the Breeze-TTS-2 C engine (ggml + breeze_core) for iOS and
# package it as an XCFramework the app target can link against.
#
# Usage:
#   Tools/build-engine-ios.sh            # device + simulator, then package
#   Tools/build-engine-ios.sh device     # device slice only
#
# Requirements: cmake + ninja from the managed python env (see below),
# Xcode with the iOS SDK. The upstream sources live in ../Breeze-TTS-2.Cpp
# (resolved through BREEZE_SRC or the sibling macOS checkout).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_OUT="$ROOT/Vendor"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/.build/engine}"

CMAKE_BIN="${CMAKE_BIN:-/Users/xxxx/.workbuddy/binaries/python/envs/default/lib/python3.13/site-packages/cmake/data/bin/cmake}"
NINJA_BIN="${NINJA_BIN:-/Users/xxxx/.workbuddy/binaries/python/envs/default/bin/ninja}"

# Upstream C++ sources are kept next to the macOS checkout.
BREEZE_SRC="${BREEZE_SRC:-/Users/xxxx/WorkBuddy/2026-10-27-19-57-25/BreezeTTS-macOS/Breeze-TTS-2.Cpp}"

if [ ! -x "$CMAKE_BIN" ]; then echo "error: cmake not found at $CMAKE_BIN" >&2; exit 1; fi
if [ ! -x "$NINJA_BIN" ]; then echo "error: ninja not found at $NINJA_BIN" >&2; exit 1; fi
if [ ! -f "$BREEZE_SRC/CMakeLists.txt" ]; then echo "error: Breeze-TTS-2.Cpp sources missing at $BREEZE_SRC" >&2; exit 1; fi

SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
DEPLOY_TARGET="${DEPLOY_TARGET:-16.0}"

build_slice() {
  local name="$1" sysroot="$2" arch="$3"
  local build="$BUILD_ROOT/$name"
  echo "==> configuring $name (sysroot=$sysroot arch=$arch)"
  "$CMAKE_BIN" -S "$BREEZE_SRC" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_MAKE_PROGRAM="$NINJA_BIN" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBREEZE_VULKAN=OFF \
    -DBREEZE_CUDA=OFF \
    -DBREEZE_BUILD_CLI=OFF \
    -DBREEZE_BUILD_SERVER=OFF \
    -DBREEZE_MP3=OFF \
    -DBREEZE_BUILD_TESTS=OFF \
    -DBREEZE_BUILD_SHARED=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_OPENMP=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_BLAS=OFF \
    -DGGML_ACCELERATE=OFF \
    -DGGML_BACKEND_DL=OFF \
    -DGGML_CPU_ALL_VARIANTS=OFF \
    -DGGML_CPU_ARM_ARCH=armv8.6-a+dotprod+i8mm+fp16 >/dev/null

  echo "==> building $name"
  CMAKE_BUILD_PARALLEL_LEVEL="$(sysctl -n hw.ncpu)" \
    "$CMAKE_BIN" --build "$build" --target breeze_core -j "$(sysctl -n hw.ncpu)"
}

merge_slice() {
  local name="$1" sysroot="$2" arch="$3"
  local build="$BUILD_ROOT/$name"
  local out="$BUILD_ROOT/$name/libbreeze.a"

  # The C API lives in c_api.cpp, which upstream only compiles into the shared
  # lib target. iOS wants a static archive, so compile it here and fold it in.
  local c_api_obj="$build/c_api.o"
  local target="$arch-apple-ios${DEPLOY_TARGET}"
  if [ "$sysroot" = "iphonesimulator" ]; then
    target="$arch-apple-ios${DEPLOY_TARGET}-simulator"
  fi
  echo "==> compiling c_api.cpp for $name"
  xcrun --sdk "$sysroot" clang++ \
    -arch "$arch" -target "$target" \
    -isysroot "$(xcrun --sdk "$sysroot" --show-sdk-path)" \
    -std=c++17 -O3 -fPIC -fvisibility=hidden \
    -I "$BREEZE_SRC/include" \
    -I "$BREEZE_SRC/third_party/ggml/include" \
    -c "$BREEZE_SRC/src/c_api.cpp" -o "$c_api_obj"

  local libs=()
  while IFS= read -r f; do libs+=("$f"); done < <(find "$build" -name "*.a" -type f | sort)
  if [ ${#libs[@]} -eq 0 ]; then echo "error: no static libs in $build" >&2; exit 1; fi
  echo "==> merging ${#libs[@]} archives for $name"
  # breeze_core first so its symbols win, then the ggml archives, then the C API
  local ordered=("$build/libbreeze_core.a")
  for f in "${libs[@]}"; do [ "$f" = "$build/libbreeze_core.a" ] || ordered+=("$f"); done
  ordered+=("$c_api_obj")
  libtool -static -o "$out" "${ordered[@]}" 2>/dev/null
  echo "==> $out"
  lipo -info "$out"
  nm -gU "$out" 2>/dev/null | grep -c "_breeze_" | xargs echo "    exported breeze_* symbols:"
}

WANT=("$@")
if [ ${#WANT[@]} -eq 0 ]; then WANT=(device simulator); fi

for slice in "${WANT[@]}"; do
  case "$slice" in
    device)    build_slice device iphoneos arm64;           merge_slice device iphoneos arm64 ;;
    simulator) build_slice simulator iphonesimulator arm64; merge_slice simulator iphonesimulator arm64 ;;
    *) echo "error: unknown slice $slice" >&2; exit 1 ;;
  esac
done

mkdir -p "$VENDOR_OUT/include/breeze"
cp "$BREEZE_SRC/include/breeze/breeze.h" "$VENDOR_OUT/include/breeze/"

if [ -f "$BUILD_ROOT/device/libbreeze.a" ] && [ -f "$BUILD_ROOT/simulator/libbreeze.a" ]; then
  echo "==> packaging BreezeEngine.xcframework"
  rm -rf "$VENDOR_OUT/BreezeEngine.xcframework"
  xcodebuild -create-xcframework \
    -library "$BUILD_ROOT/device/libbreeze.a" \
    -headers "$VENDOR_OUT/include" \
    -library "$BUILD_ROOT/simulator/libbreeze.a" \
    -headers "$VENDOR_OUT/include" \
    -output "$VENDOR_OUT/BreezeEngine.xcframework"
  echo "==> done"
  find "$VENDOR_OUT/BreezeEngine.xcframework" -maxdepth 2 | sort
fi

echo "iOS SDK $SDK_VERSION, deployment target $DEPLOY_TARGET"
