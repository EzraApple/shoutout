#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

PRODUCT_NAME="LanguagePassSmoke"
CONFIGURATION="${CONFIGURATION:-release}"

build_mlx_metal_runtime_for_cli() {
    local output_dir="$1"
    local source_dir=".build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
    local temp_dir=".build/language-pass-smoke-metal"

    if [ ! -d "$source_dir" ]; then
        echo "Missing MLX generated Metal sources at $source_dir" >&2
        exit 1
    fi

    if ! xcrun --sdk macosx --find metal >/dev/null 2>&1 \
        || ! xcrun --sdk macosx --find metallib >/dev/null 2>&1; then
        echo "Language pass smoke needs Apple's Metal Toolchain." >&2
        echo "Install it with: xcodebuild -downloadComponent MetalToolchain" >&2
        exit 1
    fi

    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    local has_sources=false
    for metal_source in "$source_dir"/*.metal; do
        if [ ! -f "$metal_source" ]; then
            continue
        fi
        has_sources=true
        local kernel_name
        kernel_name="$(basename "$metal_source" .metal)"
        xcrun -sdk macosx metal \
            -x metal \
            -Wall \
            -Wextra \
            -fno-fast-math \
            -Wno-c++17-extensions \
            -Wno-c++20-extensions \
            -mmacosx-version-min=14.0 \
            -c "$metal_source" \
            -I"$source_dir" \
            -o "$temp_dir/$kernel_name.air"
    done

    if [ "$has_sources" = false ]; then
        echo "No MLX .metal sources found in $source_dir" >&2
        exit 1
    fi

    xcrun -sdk macosx metallib "$temp_dir"/*.air -o "$output_dir/default.metallib"
    cp "$output_dir/default.metallib" "$output_dir/mlx.metallib"
    echo "Built MLX Metal runtime: $output_dir/mlx.metallib"
}

swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME"
BIN_DIR="$(swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME" --show-bin-path)"
build_mlx_metal_runtime_for_cli "$BIN_DIR"
"$BIN_DIR/$PRODUCT_NAME"
