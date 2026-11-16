#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v cargo >/dev/null || { echo 'Install Rust from https://rustup.rs first'; exit 1; }
command -v swift >/dev/null || { echo 'Install Xcode / Command Line Tools first'; exit 1; }
(cd "$ROOT/backend" && cargo build --release)
mkdir -p "$HOME/.local/bin" "$HOME/.config/gpushift"
cp "$ROOT/backend/target/release/gpushift" "$HOME/.local/bin/gpushift"
if [[ ! -f "$HOME/.config/gpushift/profiles.tsv" ]]; then
  cp "$ROOT/config/profiles.example.tsv" "$HOME/.config/gpushift/profiles.tsv"
fi
(cd "$ROOT/macos" && swift build -c release)
echo "CLI: $HOME/.local/bin/gpushift"
echo "App binary: $ROOT/macos/.build/release/GPUShift"
echo "Configure $HOME/.config/gpushift/profiles.tsv before connecting."
