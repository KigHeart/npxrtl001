#!/usr/bin/env python3
"""NPX-001 power rebalance (rev B). Inputs: report Tables 8.1/9.1 + Section 8.6 model.
Every output is a derived estimate from stated assumptions, not a measurement."""
import json

# ---- report reference model (70B dense, L=80,Hkv=8,Dh=128) ----
L, HKV, DH = 80, 8, 128
KV_BYTES_PER_TOKEN_BF16 = 2 * L * HKV * DH * 2          # 327,680
P_PARAMS = 70e9
F_TOKEN = 2 * P_PARAMS                                    # 140 GFLOP/token
WEIGHT_GB = 70.0

# ---- rev A (report Table 9.1) ----
revA = {"CiM + digital matrix": 210, "Photonic": 90, "KV + local memory": 130,
        "Digital precision/nonlinear": 55, "Interconnect/IO/clock": 55,
        "Control/telemetry/margin": 60}
assert sum(revA.values()) == 600
# efficiency implied by report: 256 TFLOP/s BF16-eq from CiM+photonic slices
eff_tflops_per_w = 256.0 / (revA["CiM + digital matrix"] + revA["Photonic"])   # 0.8533

# ---- rev B (this note) ----
revB = {"CiM + digital matrix": 150, "Photonic (optional prefill tile)": 30,
        "KV + local memory (HBM4-class)": 280,
        "Digital precision/nonlinear": 45, "Interconnect/IO/clock": 55,
        "Control/telemetry/margin": 40}
assert sum(revB.values()) == 600, sum(revB.values())

mem_w = revB["KV + local memory (HBM4-class)"]
W_BW, KV_BW = 2.0e12, 6.0e12                              # B/s: weights, KV
def mem_power(pj_per_bit, overhead=0.20):
    bits = (W_BW + KV_BW) * 8
    return bits * pj_per_bit * 1e-12 * (1 + overhead)
sens = {pj: mem_power(pj) for pj in (3.0, 3.5, 4.5)}

compute_w = revB["CiM + digital matrix"] + revB["Photonic (optional prefill tile)"]
bf16_tflops = eff_tflops_per_w * compute_w                # same efficiency assumption as report
int8_tflops = bf16_tflops * (1000 / 256)                  # keep report's 4x INT8:BF16 ratio

arith_ceiling = bf16_tflops * 1e12 / F_TOKEN
weight_pass_ms = WEIGHT_GB / (W_BW / 1e9) * 1e3
ridge_B = (bf16_tflops * 1e12 / (W_BW)) / 2               # FLOP/byte / (2 FLOP per weight byte per seq)
B_for_1000 = 1000 * weight_pass_ms / 1e3

rows = []
for S in (8_000, 32_000, 100_000, 1_000_000):
    m = KV_BYTES_PER_TOKEN_BF16 * S
    rows.append(dict(S=S, kv_gb=m/1e9,
        bf16=KV_BW/m, int8=2*KV_BW/m, int4=4*KV_BW/m,
        bf16_revA=1e12/m))
out = dict(revA=revA, revB=revB, bf16_tflops=bf16_tflops, int8_tflops=int8_tflops,
           arith_ceiling_tok_s=arith_ceiling, weight_pass_ms=weight_pass_ms,
           ridge_batch=ridge_B, batch_for_1000tok_s=B_for_1000,
           mem_power_sens_w=sens, kv_rows=rows)
json.dump(out, open("/home/claude/npx/docs/rebalance.json", "w"), indent=1)

md = ["# NPX-001 power rebalance (rev B)\n",
      "Status: derived estimates from the report's own reference model. Not measured.\n",
      "## Power allocation, 600 W package\n", "| Subsystem | Rev A (report) | Rev B |", "|---|---:|---:|"]
mapA = {"CiM + digital matrix":210,"Photonic (optional prefill tile)":90,"KV + local memory (HBM4-class)":130,
        "Digital precision/nonlinear":55,"Interconnect/IO/clock":55,"Control/telemetry/margin":60}
for k,v in revB.items(): md.append(f"| {k} | {mapA[k]} | {v} |")
md += ["| **Total** | **600** | **600** |\n",
 f"Memory fabric (weights 2 TB/s + KV 6 TB/s = 8 TB/s): model {sens[3.5]:.0f} W at 3.5 pJ/bit with 20% static/refresh overhead.",
 "Sensitivity: " + ", ".join(f"{k} pJ/bit -> {v:.0f} W" for k,v in sens.items()) + ".",
 f"**Risk:** at 4.5 pJ/bit the memory fabric needs {sens[4.5]:.0f} W, above the {mem_w} W slice. A per-stack figure of ~75 W at full rate x 4 stacks = 300 W also exceeds it. The slice is only closed if measured energy is <= ~3.6 pJ/bit. OPEN PROBLEM.\n",
 "## Compute at the report's own efficiency (0.853 TFLOP/s per W)\n",
 f"- Compute slices {compute_w} W -> {bf16_tflops:.0f} TFLOP/s BF16-eq, {int8_tflops:.0f} TFLOP/s INT8-eq (was 256 / 1000).",
 f"- Arithmetic ceiling {arith_ceiling:.0f} tok/s (70B, 140 GFLOP/token).",
 f"- Weight pass {weight_pass_ms:.0f} ms at 2 TB/s; batch needed for 1,000 tok/s = {B_for_1000:.0f}; BF16 ridge at B = {ridge_B:.0f}.",
 "- Result: arithmetic ceiling and weight-bandwidth ridge now sit close together, which is what a balanced decode engine should look like.\n",
 "## KV decode ceilings (tok/s per engine, 70B dense, rev B 6 TB/s KV path)\n",
 "| Context | KV/seq (GB) | BF16 KV rev A (1 TB/s) | BF16 KV rev B | INT8 KV | INT4 KV |","|---:|---:|---:|---:|---:|---:|"]
for r in rows:
    md.append(f"| {r['S']:,} | {r['kv_gb']:.2f} | {r['bf16_revA']:.1f} | {r['bf16']:.1f} | {r['int8']:.1f} | {r['int4']:.1f} |")
md += ["\nAt 100k context rev B reaches ~%.0f tok/s BF16 against a %.0f tok/s arithmetic ceiling: still %.1fx below, so KV compression and attention-near-memory remain required, not optional." % (rows[2]['bf16'], arith_ceiling, arith_ceiling/rows[2]['bf16']),
 "\n## Capacity consequence\n",
 "4 HBM4 stacks x 48 GB = 192 GB in package at 8 TB/s: 128 GB weights + 64 GB hot KV (one 100k BF16 sequence = 32.8 GB; two fit). The 256 GB KV pool of Table 8.1 becomes hot 64 GB (HBM) + warm tier on LPDDR5X/CXL outside the 600 W envelope. This changes Tier 1/Tier 2 of Section 5.2: Tier 2 is no longer 1 TB/s class."]
open("/home/claude/npx/docs/POWER_REBALANCE.md","w").write("\n".join(md)+"\n")
print("\n".join(md))
