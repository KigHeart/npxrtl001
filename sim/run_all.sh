#!/usr/bin/env bash
# Regenerate golden vectors from Rust, then run every RTL testbench under Verilator. Run from repo root.
set -euo pipefail
if command -v verilator >/dev/null 2>&1; then VL=verilator; else export VERILATOR_ROOT="${VERILATOR_ROOT:-/usr/local/lib/python3.13/site-packages/verilator}"; VL="$VERILATOR_ROOT/bin/verilator"; fi
( cd golden && cargo test --release -q && cargo run --release -q --bin gen_vectors -- ../sim/vec ../rtl )
for m in alloc cim softmax decode; do
  case $m in alloc) top=kv_page_alloc;; cim) top=cim_tile;; softmax) top=softmax_q15;; decode) top=cmd_decode;; esac
  $VL --binary --timing -CFLAGS "-std=c++20 -fcoroutines" -Wno-fatal -Wno-lint -Wno-style -Irtl --top-module tb_$m -Mdir sim/obj_$m \
      tb/tb_$m.sv rtl/$top.sv >/dev/null
  ./sim/obj_$m/Vtb_$m +vec=sim/vec
done
