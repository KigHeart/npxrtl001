![sim](https://github.com/KigHeart/npxrtl001/actions/workflows/sim.yml/badge.svg)

# NPX-001 Scope A RTL (rev B)

Nelix PhotonicX Core, Tilil Systems Group, TR-TEG-2026-NPX-001. Status: architecture-baseline RTL for review.
Not a measured result, a quotation or a guarantee. Every RTL block is behavioural/synthesizable-subset SystemVerilog
checked against a Rust golden model; nothing here is silicon-proven.

## Layout
- `docs/POWER_REBALANCE.md`, `docs/rebalance.json`: rev B 600 W budget (memory 280 W) and re-derived ceilings. `tools/rebalance.py` regenerates them.
- `golden/`: Rust crate (no dependencies, `#![forbid(unsafe_code)]`). Bit-exact models + vector generator. Single source of truth for contracts and for `rtl/exp2_lut.svh`.
- `rtl/`: `kv_page_alloc.sv` (Section 5.3), `cim_tile.sv` (Section 3, bit-serial digital CiM), `softmax_q15.sv` (digital precision island), `cmd_decode.sv` (Section 6.2 descriptor + Section 7.3 invariant), `exp2_lut.svh` (generated).
- `tb/`, `sim/run_all.sh`: SystemVerilog testbenches replay Rust vectors under Verilator. Run `./sim/run_all.sh` from this directory.

## Verified (this session)
| Block | Vectors | Result |
|---|---:|---|
| kv_page_alloc | 6,026 ops, all 6 error statuses hit | 0 mismatches |
| cim_tile | 400 (extreme-value corners included) | 0 mismatches |
| softmax_q15 | 1,000 (incl. full-range and saturated inputs) | 0 mismatches |
| cmd_decode | 6,000 (all 8 statuses hit, no-dispatch-on-error invariant checked) | 0 mismatches |

Four deliberately injected RTL bugs (tenant check removed, wrong log2(e) constant, wrong MSB-plane sign, tenant compare removed) were each caught.
Verilator `-Wall` lint is clean. Yosys generic `synth` completes on all four modules.

## Known gaps (not hidden)
1. `softmax_q15` uses a combinational divider per lane: Yosys reports about 215k generic cells. It is a reference implementation; replace with a shared sequential divider or reciprocal-LUT multiply before any area claim.
2. Softmax accuracy bound (600 Q15 LSB, about 1.8%) is empirical over 2,000 random cases, dominated by the 369/256 approximation of log2(e). Not proved.
3. No photonic or analog-CiM RTL. Those stay behavioural-model-only (Scope B, not yet written); the decoder already refuses photonic dispatch when `cfg_photonic_en` is low.
4. No HBM4 controller/PHY (licensed hard IP), no NoC, no top-level integration, no timing/power numbers. Gate counts are not area or power.
5. Memory fabric power is the open risk: the 280 W slice closes only if measured energy is at or below about 3.6 pJ/bit (see POWER_REBALANCE.md).
6. CiM tile latency is 9 clock edges (1 load + 8 bit-planes); the first testbench expectation of 8 was wrong and was corrected.

## Running on Windows (PowerShell)
1. Install Rust (rustup.rs) and Git.
2. For the RTL simulation pick one: (a) WSL2 Ubuntu: `wsl --install`, then inside Ubuntu `sudo apt install verilator g++ make` (most reliable); or (b) the OSS CAD Suite Windows build, opened from its own shell so `verilator` is on PATH.
3. From the repo root: `.\sim\run_all.ps1`. Expected: five Rust tests pass, then four lines ending `PASS`.
Linux/macOS/WSL: `./sim/run_all.sh`.
