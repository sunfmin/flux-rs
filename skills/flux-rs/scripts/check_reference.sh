#!/bin/sh
# Runs Flux, then a stable build, over every rust block of references/*.md, so
# the reference cannot drift from the Flux it describes. Each file becomes one
# module of a throwaway crate. Run it after changing the pinned revision in
# SKILL.md or any block in a reference.
#
#   scripts/check_reference.sh            every reference file
#   scripts/check_reference.sh traits     only references/traits.md
set -e
skill="$(cd "$(dirname "$0")/.." && pwd)"
rev="$(sed -n 's/.*rev = "\([0-9a-f]\{40\}\)".*/\1/p' "$skill/SKILL.md" | head -1)"
crate="$(mktemp -d)"
trap 'rm -rf "$crate"' EXIT
mkdir "$crate/src"
cat > "$crate/Cargo.toml" <<TOML
[package]
name = "flux-reference"
version = "0.0.0"
edition = "2024"

[dependencies]
flux-rs = { git = "https://github.com/flux-rs/flux.git", rev = "$rev" }
flux-core = { git = "https://github.com/flux-rs/flux.git", rev = "$rev" }
flux-alloc = { git = "https://github.com/flux-rs/flux.git", rev = "$rev" }

[package.metadata.flux]
enabled = true
check_overflow = "strict"

[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(flux)'] }
TOML
printf '#![allow(dead_code, unused)]\nextern crate flux_alloc;\nextern crate flux_core;\n' > "$crate/src/lib.rs"
for file in "$skill"/references/${1:-*}.md; do
    module="$(basename "$file" .md | tr '-' '_')"
    awk '/^```rust/{on=1;next} /^```/{on=0} on' "$file" > "$crate/src/$module.rs"
    [ -s "$crate/src/$module.rs" ] && echo "mod $module;" >> "$crate/src/lib.rs"
done
# cargo-flux re-invokes `cargo +<its nightly>`, which only rustup's cargo
# understands, and rustup needs some toolchain to start from.
PATH="$HOME/.cargo/bin:$PATH"
: "${RUSTUP_TOOLCHAIN:=$(rustup toolchain list | head -1 | cut -d' ' -f1)}"
export PATH RUSTUP_TOOLCHAIN
cd "$crate"
cargo flux
cargo +stable build --quiet
