#!/bin/bash
set -euo pipefail

worker_root="$(cd "$(dirname "$0")" && pwd)"
build_root="$worker_root/build"
output_root="$build_root/release"
case "${1:-}" in
  ""|--universal) build_mode=universal ;;
  --arm64-only) build_mode=arm64 ;;
  *) echo "usage: $0 [--universal|--arm64-only]" >&2; exit 2 ;;
esac
mkdir -p "$build_root" "$output_root"

# Match ShoutOut's macOS 15 deployment target on both Rust and native C++.
export MACOSX_DEPLOYMENT_TARGET=15.0
export TRANSCRIBE_CMAKE_ARGS="-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 ${TRANSCRIBE_CMAKE_ARGS:-}"

if ! command -v cmake >/dev/null 2>&1; then
  cmake_root="$build_root/tools/cmake"
  if [[ ! -x "$cmake_root/bin/cmake" ]]; then
    python3 -m pip install --disable-pip-version-check --target "$cmake_root" cmake==3.31.10
  fi
  export PYTHONPATH="$cmake_root${PYTHONPATH:+:$PYTHONPATH}"
  export PATH="$cmake_root/bin:$PATH"
fi

export CARGO_TARGET_DIR="$build_root/target"
if ! rustup target list --installed | grep -Fxq aarch64-apple-darwin; then
  rustup target add aarch64-apple-darwin
fi
cargo build --release --locked --target aarch64-apple-darwin --manifest-path "$worker_root/Cargo.toml"
arm64_binary="$CARGO_TARGET_DIR/aarch64-apple-darwin/release/hex-speech-worker"

if [[ "$build_mode" == arm64 ]]; then
  cp "$arm64_binary" "$output_root/hex-speech-worker"
else
  if ! rustup target list --installed | grep -Fxq x86_64-apple-darwin; then
    rustup target add x86_64-apple-darwin
  fi
  cargo build --release --locked --target x86_64-apple-darwin --manifest-path "$worker_root/Cargo.toml"
  lipo -create \
    "$arm64_binary" \
    "$CARGO_TARGET_DIR/x86_64-apple-darwin/release/hex-speech-worker" \
    -output "$output_root/hex-speech-worker"
fi

if otool -L "$output_root/hex-speech-worker" | grep -E '^[[:space:]]+(@rpath|@loader_path|@executable_path)' >&2; then
  echo "worker has a non-system dynamic library dependency" >&2
  exit 1
fi

cp "$worker_root/ModelMetadata.json" "$output_root/ModelMetadata.json"
cp "$worker_root/THIRD_PARTY_NOTICES.md" "$output_root/THIRD_PARTY_NOTICES.md"
rm -rf "$output_root/Licenses"
cp -R "$worker_root/Licenses" "$output_root/Licenses"
codesign --force --sign - --timestamp=none "$output_root/hex-speech-worker"
(cd "$output_root" && shasum -a 256 hex-speech-worker > SHA256SUMS)
lipo -info "$output_root/hex-speech-worker"
echo "Release helper: $output_root/hex-speech-worker"
