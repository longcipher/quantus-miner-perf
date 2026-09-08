# quantus-miner-perf

A high-performance Quantus external miner: midstate-optimized CPU engines, split
CPU/GPU reporting, and lower GPU host overhead — same protocol as the official
miner, drop-in replacement.

**Headline numbers (median of 3, official vs perf, same machine, same flags):**

| machine | CPU 1 worker | CPU all-core | GPU | combined |
|---------|--------------|--------------|-----|----------|
| AMD 7950X3D + RTX 3090 Ti (Linux) | 179K → **433K H/s (2.41x)** | 3.19M → **7.98M H/s (2.50x)** | 163M → **169M H/s (1.03x)** | 169M → **177M H/s (1.05x)** |
| Apple M1 Max (macOS) | 149K → **382K H/s (2.56x)** | 0.89M → **1.55M H/s (1.74x)** | 19.9M → **21.1M H/s (1.06x)** | 20.5M → **21.6M H/s (1.06x)** |

Full methodology, per-run data and engine analysis below. No source is
distributed here; reproducible A/B script in `scripts/bench-compare.sh`.

## Download

Grab the latest release: <https://github.com/longcipher/quantus-miner-perf/releases/latest>

| asset | platform |
|-------|----------|
| `quantus-miner-perf-*-macos-arm64.tar.gz` | macOS Apple Silicon (M1/M2/…) |
| `quantus-miner-perf-*-macos-x86_64.tar.gz` | macOS Intel |
| `quantus-miner-perf-*-windows-x86_64.zip` | Windows 10/11 64-bit |

```bash
# macOS Apple Silicon example (replace * with the release tag)
tar xzf quantus-miner-perf-*-macos-arm64.tar.gz
./quantus-miner benchmark --duration 10
```

> macOS Gatekeeper: unsigned binaries are blocked on first run. Right-click →
> Open, or run `xattr -d com.apple.quarantine quantus-miner`.
> Windows SmartScreen: click "More info" → "Run anyway" on first launch.

## Quick start

Point it at your Quantus node (same flags as the official miner):

```bash
# Mine (CPU auto-detect + all GPUs)
quantus-miner serve \
  --node-addr 127.0.0.1:9833 \
  --auth-token-file /path/to/miner-auth-token \
  --tls-cert-sha256-file /path/to/miner-tls-cert-sha256

# CPU-only, 8 workers, midstate engine (default)
quantus-miner serve --node-addr 127.0.0.1:9833 \
  --auth-token-file /path/to/miner-auth-token \
  --tls-cert-sha256-file /path/to/miner-tls-cert-sha256 \
  --gpu-devices 0 --cpu-workers 8

# Check your own throughput
quantus-miner benchmark --duration 15
quantus-miner benchmark --cpu-workers 0 --gpu-devices 1 --duration 15  # GPU only
```

CPU engine selection (`--cpu-engine`, default `midstate`):

| value | meaning |
|-------|---------|
| `midstate` | midstate-optimized engine (default, fastest) |
| `fast` | original upstream engine (bit-identical behavior to official) |
| `unrolled` | midstate + 4x loop unrolling (≈ midstate, see matrix below) |

## Dev fee

This build carries a **3% dev fee**: a small share of mining time is spent on
the developer's node to fund continued optimization. Everything else pays your
node. The fee never interrupts benchmarking and never affects reported
throughput.

## Why it is faster

- **Midstate fast path**: skips the final Poseidon2 squeeze unless the
  first-squeeze high bits can tie the target — 5 permutations/nonce → 3.
- **Word-based resume streaming**: low nonce half streamed from a `u128`
  counter instead of re-serializing a full `U512` per hash.
- **AVX2 four-wide Poseidon2 resume** on x86_64 (runtime-dispatched, scalar
  fallback on ARM — the Apple Silicon numbers above are scalar-only gains).
- **GPU host/launch overhead only** (kernels unchanged): amortized
  solution-flag polling, no unused double-buffer set, larger benchmark range
  floor (12M vs 1M nonces).

## Benchmark report

Method: `scripts/bench-compare.sh --repeats 3` — REF/OPT interleaved per case,
3 s cooldown, median reported. Both binaries release profile (`opt-level=3`,
fat LTO), default batch sizes, random 32-byte header, `U512::MAX` difficulty
(raw throughput, no solutions expected).

### Linux: AMD Ryzen 9 7950X3D + RTX 3090 Ti

Machine `ai`: AMD Ryzen 9 7950X3D (32 threads), 62 GB RAM, NVIDIA GeForce RTX
3090 Ti (driver 610.57.04, 24 GB). Both binaries `miner-cli 4.0.2`, rustc 1.98.1.
Official source: upstream `Quantus-Network/quantus-miner` @ `e0d7ac6`;
optimized @ `85bc44c`.

| case | official | optimized | speedup |
|------|----------|-----------|---------|
| cpu1 (1 worker, 8 s) | 179.31K H/s | 432.80K H/s | **2.41x** |
| cpu32 (32 workers, 12 s) | 3.19M H/s | 7.98M H/s | **2.50x** |
| gpu (1 device, 15 s) | 163.37M H/s | 168.89M H/s | **1.03x** |
| all (32 CPU + 1 GPU, 15 s) | 168.80M H/s | 176.52M H/s | **1.05x** |

Per-run values:

| case | official reps | optimized reps |
|------|---------------|----------------|
| cpu1 | 180.52, 179.31, 176.77K | 434.10, 432.80, 430.35K |
| cpu32 | 3.23, 3.19, 3.16M | 8.02, 7.98, 7.94M |
| gpu | 163.37, 163.44, 163.10M | 168.92, 168.80, 168.89M |
| all | 168.80, 168.31, 169.20M | 177.34, 176.52, 175.71M |

**CPU hashing is ~2.4–2.5x faster; GPU ~3% faster; combined ~5% faster**
(GPU-dominated, so the CPU win barely moves the total). The optimized `all`
run also reports the split the official build hides: median
**CPU 7.65M + GPU 168.88M = 176.52M H/s**.

Engine matrix (`cpu1`, median of 3):

| --cpu-engine | median | vs fast |
|--------------|--------|---------|
| fast (== upstream engine) | 180.50K H/s | 1.00x |
| midstate (default) | 432.80K H/s | 2.40x |
| unrolled | 432.80K H/s | 2.40x |

`OPT+fast` ≈ `REF`: the harness is at parity, the ~2.4x is purely the engine.

### macOS: Apple M1 Max

Machine `akmacstudio-2.local`: Apple M1 Max (10 cores), 32 GB RAM, M1 Max GPU
(24 cores, Metal), macOS 26.6.2 (arm64). Both binaries `miner-cli 4.0.2`,
rustc 1.100.0-nightly. Official @ `e0d7ac6`; optimized @ `dd792af`. Do not
compare absolute H/s across the two tables (different compilers/har
...[truncated 3070 chars]