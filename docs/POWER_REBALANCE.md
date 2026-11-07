# NPX-001 power rebalance (rev B)

Status: derived estimates from the report's own reference model. Not measured.

## Power allocation, 600 W package

| Subsystem | Rev A (report) | Rev B |
|---|---:|---:|
| CiM + digital matrix | 210 | 150 |
| Photonic (optional prefill tile) | 90 | 30 |
| KV + local memory (HBM4-class) | 130 | 280 |
| Digital precision/nonlinear | 55 | 45 |
| Interconnect/IO/clock | 55 | 55 |
| Control/telemetry/margin | 60 | 40 |
| **Total** | **600** | **600** |

Memory fabric (weights 2 TB/s + KV 6 TB/s = 8 TB/s): model 269 W at 3.5 pJ/bit with 20% static/refresh overhead.
Sensitivity: 3.0 pJ/bit -> 230 W, 3.5 pJ/bit -> 269 W, 4.5 pJ/bit -> 346 W.
**Risk:** at 4.5 pJ/bit the memory fabric needs 346 W, above the 280 W slice. A per-stack figure of ~75 W at full rate x 4 stacks = 300 W also exceeds it. The slice is only closed if measured energy is <= ~3.6 pJ/bit. OPEN PROBLEM.

## Compute at the report's own efficiency (0.853 TFLOP/s per W)

- Compute slices 180 W -> 154 TFLOP/s BF16-eq, 600 TFLOP/s INT8-eq (was 256 / 1000).
- Arithmetic ceiling 1097 tok/s (70B, 140 GFLOP/token).
- Weight pass 35 ms at 2 TB/s; batch needed for 1,000 tok/s = 35; BF16 ridge at B = 38.
- Result: arithmetic ceiling and weight-bandwidth ridge now sit close together, which is what a balanced decode engine should look like.

## KV decode ceilings (tok/s per engine, 70B dense, rev B 6 TB/s KV path)

| Context | KV/seq (GB) | BF16 KV rev A (1 TB/s) | BF16 KV rev B | INT8 KV | INT4 KV |
|---:|---:|---:|---:|---:|---:|
| 8,000 | 2.62 | 381.5 | 2288.8 | 4577.6 | 9155.3 |
| 32,000 | 10.49 | 95.4 | 572.2 | 1144.4 | 2288.8 |
| 100,000 | 32.77 | 30.5 | 183.1 | 366.2 | 732.4 |
| 1,000,000 | 327.68 | 3.1 | 18.3 | 36.6 | 73.2 |

At 100k context rev B reaches ~183 tok/s BF16 against a 1097 tok/s arithmetic ceiling: still 6.0x below, so KV compression and attention-near-memory remain required, not optional.

## Capacity consequence

4 HBM4 stacks x 48 GB = 192 GB in package at 8 TB/s: 128 GB weights + 64 GB hot KV (one 100k BF16 sequence = 32.8 GB; two fit). The 256 GB KV pool of Table 8.1 becomes hot 64 GB (HBM) + warm tier on LPDDR5X/CXL outside the 600 W envelope. This changes Tier 1/Tier 2 of Section 5.2: Tier 2 is no longer 1 TB/s class.
