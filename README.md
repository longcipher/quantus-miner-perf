# ⚡ quantus-miner-perf — 2.5× Faster Quantus Miner, Drop-in Replacement

[![Latest Release](https://img.shields.io/github/v/release/longcipher/quantus-miner-perf?style=flat-square)](https://github.com/longcipher/quantus-miner-perf/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-blue?style=flat-square)](#download)
[![Quantus](https://img.shields.io/badge/powered_by-Quantus_Network-7c3aed?style=flat-square)](https://www.quantus.com/)

> Same protocol as the official miner. Just faster.
> **CPU up to 2.5× · GPU +3–6% · split CPU/GPU reporting · lower host overhead.**

A high-performance Quantus external miner: midstate-optimized CPU engines, split
CPU/GPU reporting, and lower GPU host overhead — same protocol as the official
miner, drop-in replacement.

**Headline numbers (median of 3, official vs perf, same machine, same flags):**

| machine | CPU 1 worker | CPU all-core | GPU | combined |
|---------|--------------|--------------|-----|----------|
| AMD 7950X3D + RTX 3090 Ti (Linux) | 179K → **433K H/s (2.41x)** | 3.19M → **7.98M H/s (2.50x)** | 163M → **169M H/s (1.03x)** | 169M → **177M H/s (1.05x)** |
| Apple M1 Max (macOS, v4.0.2-perf1) | 140K → **366K H/s (2.61x)** | 0.78M → **1.91M H/s (2.46x)** | 19.2M → **19.7M H/s (1.02x)** | 17.8M → **20.9M H/s (1.17x)** |

Full methodology, per-run data and engine analysis below. No source is
distributed here; reproducible A/B script in `scripts/bench-compare.sh`.

## Download

Grab the latest release: <https://github.com/longcipher/quantus-miner-perf/releases/latest>

### Install / upgrade (recommended)

One-liner — detects OS/arch, picks the AVX2 (`-simd`) build on supported
Linux CPUs, verifies `SHA256SUMS`, and skips reinstall when your local
version is already ≥ the latest release:

```bash
curl -fsSL https://raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh | bash
```

```bash
# custom dir / force reinstall / pin a version
curl -fsSL https://raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh | bash -s -- --dir ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh | bash -s -- --force
curl -fsSL https://raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh | bash -s -- --tag v4.0.2-perf1
```

> Version check is `release tag vX` ≡ `quantus-miner-perf -V → … X`
> (script updates only when the release is newer than local).

### Manual download

| asset | platform |
|-------|----------|
| `quantus-miner-perf-*-macos-arm64.tar.gz` | macOS Apple Silicon (M1/M2/…) |
| `quantus-miner-perf-*-macos-x86_64.tar.gz` | macOS Intel |
| `quantus-miner-perf-*-linux-x86_64.tar.gz` | Linux 64-bit (x86_64) |
| `quantus-miner-perf-*-linux-x86_64-simd.tar.gz` | Linux 64-bit with AVX2 (auto-picked by install.sh) |
| `quantus-miner-perf-*-windows-x86_64.zip` | Windows 10/11 64-bit |

```bash
# macOS Apple Silicon example (replace * with the release tag)
tar xzf quantus-miner-perf-*-macos-arm64.tar.gz
./quantus-miner-perf benchmark --duration 10
```

> macOS Gatekeeper: unsigned binaries are blocked on first run. Right-click →
> Open, or run `xattr -d com.apple.quarantine quantus-miner-perf`.
> Windows SmartScreen: click "More info" → "Run anyway" on first launch.

## Quick start

Point it at your Quantus node (same flags as the official miner) — or skip
running a node entirely with the [sister pool](#sister-project-longcipher-quantus-pool)
below.

```bash
# Mine (CPU auto-detect + all GPUs)
quantus-miner-perf serve \
  --node-addr 127.0.0.1:9833 \
  --auth-token-file /path/to/miner-auth-token \
  --tls-cert-sha256-file /path/to/miner-tls-cert-sha256

# CPU-only, 8 workers, midstate engine (default)
quantus-miner-perf serve --node-addr 127.0.0.1:9833 \
  --auth-token-file /path/to/miner-auth-token \
  --tls-cert-sha256-file /path/to/miner-tls-cert-sha256 \
  --gpu-devices 0 --cpu-workers 8

# Check your own throughput
quantus-miner-perf benchmark --duration 15
quantus-miner-perf benchmark --cpu-workers 0 --gpu-devices 1 --duration 15  # GPU only
```

CPU engine selection (`--cpu-engine`, default `midstate`):

| value | meaning |
|-------|---------|
| `midstate` | midstate-optimized engine (default, fastest) |
| `fast` | original upstream engine (bit-identical behavior to official) |
| `unrolled` | midstate + 4x loop unrolling (≈ midstate, see matrix below) |

## Sister project: LongCipher Quantus pool

Solo mining needs a local node; the easy path is our sister pool —
**1% fee, PPLNS or Solo, no signup** (your `qz…` address is the account):
<https://quantus-pool.longcipher.com/>

It speaks the same miner protocol, so the **official miner** and this **perf
build** both work unchanged — the perf build just submits ~2.5x the CPU
shares on the same hardware. Type your address on the site and it generates
the exact command; PPLNS example:

```bash
quantus-miner-perf serve \
  --node-addr 46.4.66.214:9900 \
  --auth-token qzYOURADDRESS.rig1 \
  --tls-cert-sha256 8c700b8cd25a893f53f700f9650c4e96555989e2419a5b6241a1dcc43ed2feae \
  --cpu-workers 8 --gpu-devices 1
```

Solo mining is one tab away on the same page. Live stats, earnings
calculator, blocks and payouts: <https://quantus-pool.longcipher.com/>.

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

### macOS: Apple M1 Max (current release v4.0.2-perf1, 2026-09-09)

Machine `akmacstudio-2.local`: Apple M1 Max (10 cores), 32 GB RAM, M1 Max GPU
(24 cores, Metal), macOS 26.6.2 (arm64). Release profile (`opt-level=3`, fat
LTO), rustc 1.100.0-nightly. Official `miner-cli 4.0.2` @ `e0d7ac6` vs
perf `quantus-miner-perf 4.0.2-perf1` @ `36228c9`. Do not compare absolute
H/s across the two tables (different compilers/hardware).

| case | official | optimized | speedup |
|------|----------|-----------|---------|
| cpu1 (1 worker, 8 s) | 140.02K H/s | 365.87K H/s | **2.61x** |
| cpu10 (10 workers, 12 s) | 775.48K H/s | 1.91M H/s | **2.46x** |
| gpu (1 device, 15 s) | 19.20M H/s | 19.67M H/s | **1.02x** |
| all (10 CPU + 1 GPU, 15 s) | 17.84M H/s | 20.86M H/s | **1.17x** |

Per-run values (median of 3, REF/OPT interleaved, 3 s cooldown):

| case | official reps | optimized reps |
|------|---------------|----------------|
| cpu1 | 146.36, 130.96, 140.02K | 373.76, 365.87, 323.70K |
| cpu10 | 727.10, 775.48, 822.26K | 1.91, 1.73, 1.91M |
| gpu | 18.99, 19.45, 19.20M | 19.87, 19.67, 19.67M |
| all | 18.71, 17.33, 17.84M | 20.86, 20.83, 21.62M |

The optimized `all` run also reports the split the official build hides:
median **CPU 1.93M + GPU 19.04M ≈ 20.86M H/s**.

Method: `scripts/bench-compare.sh --repeats 3`, median reported, same flags
as the Linux table. Scalar-only gains on ARM (no AVX2 there) — x86_64 gets an
extra SIMD boost on top. All-core and GPU figures are thermally sensitive on
this integrated-GPU machine (see prior run below); single-worker CPU is the
most stable read at **~2.6x** in both runs.

Prior same-machine run (perf @ `dd792af`, `miner-cli 4.0.2`): cpu1 149.13K →
382.13K (**2.56x**), cpu10 891K → 1.55M (**1.74x**), gpu 19.91M → 21.08M
(**1.06x**), all 20.46M → 21.63M (**1.06x**). Combined picture: CPU
single-worker steady ~2.6x, all-core ~1.7–2.5x depending on thermal state,
GPU ~2–6%.

## 🔗 Quantus official links

New to Quantus? Start here:

| resource | link |
|----------|------|
| 🌐 Official site | <https://www.quantus.com/> |
| 📖 Mining guide (docs) | <https://docs.quantus.com/guides/mining/> |
| 📄 Whitepaper | <https://www.quantus.com/whitepaper/> |
| ⛏️ Official miner (upstream) | <https://github.com/Quantus-Network/quantus-miner> |
| 👛 CLI wallet | <https://github.com/Quantus-Network/quantus-cli> |
| 🖥️ Node / chain | <https://github.com/Quantus-Network/chain> |
| 🏢 GitHub org | <https://github.com/Quantus-Network> |
| 🔍 Explorer (official) | <https://explorer.quantus.com/> |
| 🔍 Explorer (blackbeard) | <https://blackbeard.observer/> |
| 📡 Telemetry | <https://telemetry.quantus.cat/> |
| 🐦 X / Twitter | <https://x.com/QuantusNetwork> |

This repo is a community perf build — same miner protocol, just faster hashing.
For consensus / wallet / network questions, the docs and repos above are
authoritative.

## 💬 Community — LongCipher miners

Questions, hashrate screenshots, rig tuning? Come chat:

- ✈️ Telegram: <https://t.me/longcipher>
- 💬 WeChat: scan below to join the group

<img src="assets/wechat_group.png" width="250" alt="LongCipher WeChat group QR code" />

Solo or pool, official or perf build — all Quantus miners welcome.