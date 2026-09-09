# ⚡ quantus-miner-perf — 提速 2.5× 的 Quantus 矿工，可直接替换官方矿工

**[English](README.md) · [简体中文](README.zh.md)**

[![Latest Release](https://img.shields.io/github/v/release/longcipher/quantus-miner-perf?style=flat-square)](https://github.com/longcipher/quantus-miner-perf/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-blue?style=flat-square)](#下载)
[![Quantus](https://img.shields.io/badge/powered_by-Quantus_Network-7c3aed?style=flat-square)](https://www.quantus.com/)

> 与官方矿工协议完全一致，只是更快。
> **CPU 最高 2.6× · GPU 最高 2.12× · CPU/GPU 分开上报 · 更低的宿主开销。**

> **可接入任意矿池，不绑定任何一家。** 本版本使用**官方 Quantus 矿工协议**，
> 因此你可以把它指向**任何支持官方矿工的矿池**——LongCipher 矿池、你自己的
> 节点，或任意第三方矿池。本程序没有任何矿池专属逻辑：改掉 `--node-addr` /
> `--auth-token`，就换到别处挖矿了。

`quantus-miner-perf` 是一个高性能 Quantus 外部矿工：midstate 优化的 CPU 引擎、
原生 CUDA 后端、CPU/GPU 分开上报——协议与官方矿工一致，可直接替换。

**核心数据（3 次取中位数，官方 vs perf，同一台机器、同样的参数，版本
`v4.0.2-perf1`）：**

| 机器 | CPU 单线程 | CPU 全核 | GPU | 合计 |
|---------|--------------|--------------|-----|----------|
| AMD 7950X3D + RTX 3090 Ti（Linux） | 179K → **432K H/s（2.41x）** | 3.15M → **7.94M H/s（2.52x）** | 164M → **347M H/s（2.12x）** | 170M → **352M H/s（2.08x）** |
| Apple M1 Max（macOS，v4.0.2-perf1） | 140K → **366K H/s（2.61x）** | 0.78M → **1.91M H/s（2.46x）** | 19.2M → **19.7M H/s（1.02x）** | 17.8M → **20.9M H/s（1.17x）** |

完整测试方法、逐次运行数据与引擎分析见下文。本仓库不分发源码；可复现的 A/B
脚本见 `scripts/bench-compare.sh`。

## 下载

获取最新发布版：<https://github.com/longcipher/quantus-miner-perf/releases/latest>

### 安装 / 升级（推荐）

一行命令——自动检测系统/架构，在支持的 Linux CPU 上选用 AVX2（`-simd`）构建，
校验 `SHA256SUMS`，并在本地版本已 ≥ 最新版时跳过重装：

```bash
curl -fsSL https://raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh | bash
```

```bash
# 自定义目录 / 强制重装 / 指定版本
curl -fsSL https://raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh | bash -s -- --dir ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh | bash -s -- --force
curl -fsSL https://raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh | bash -s -- --tag v4.0.2-perf1
```

> 版本判定规则：`release tag vX` ≡ `quantus-miner-perf -V → … X`
> （仅当发布版比本地版本更新时才会升级）。

### 手动下载

| 文件 | 平台 |
|-------|----------|
| `quantus-miner-perf-*-macos-arm64.tar.gz` | macOS Apple Silicon（M1/M2/…） |
| `quantus-miner-perf-*-macos-x86_64.tar.gz` | macOS Intel |
| `quantus-miner-perf-*-linux-x86_64.tar.gz` | Linux 64 位（x86_64） |
| `quantus-miner-perf-*-linux-x86_64-simd.tar.gz` | 支持 AVX2 的 Linux 64 位（install.sh 自动选择） |
| `quantus-miner-perf-*-windows-x86_64.zip` | Windows 10/11 64 位 |

```bash
# macOS Apple Silicon 示例（把 * 替换为发布标签）
tar xzf quantus-miner-perf-*-macos-arm64.tar.gz
./quantus-miner-perf benchmark --duration 10
```

> macOS Gatekeeper：未签名二进制首次运行会被拦截。右键 → 打开，或执行
> `xattr -d com.apple.quarantine quantus-miner-perf`。
> Windows SmartScreen：首次启动时点击"更多信息" → "仍要运行"。

## 快速开始

指向你的 Quantus 节点（参数与官方矿工一致）——也可以完全不跑节点，直接用下面的
[LongCipher 矿池](#接入-longcipher-quantus-矿池)。任何其他支持官方协议的矿池，
用法完全相同。

```bash
# 挖矿（CPU 自动检测 + 全部 GPU）
./quantus-miner-perf serve \
  --node-addr 127.0.0.1:9833 \
  --auth-token-file /path/to/miner-auth-token \
  --tls-cert-sha256-file /path/to/miner-tls-cert-sha256

# 仅 CPU，8 线程，midstate 引擎（默认）
./quantus-miner-perf serve --node-addr 127.0.0.1:9833 \
  --auth-token-file /path/to/miner-auth-token \
  --tls-cert-sha256-file /path/to/miner-tls-cert-sha256 \
  --gpu-devices 0 --cpu-workers 8

# 测一下自己的算力
./quantus-miner-perf benchmark --duration 15
./quantus-miner-perf benchmark --cpu-workers 0 --gpu-devices 1 --duration 15  # 仅 GPU
```

CPU 引擎选择（`--cpu-engine`，默认 `midstate`）：

| 取值 | 含义 |
|-------|---------|
| `midstate` | midstate 优化引擎（默认，最快） |
| `fast` | 上游原始引擎（与官方逐位一致） |
| `unrolled` | midstate + 4 路循环展开（≈ midstate，见下文矩阵） |

## 接入 LongCipher Quantus 矿池

Solo 挖矿通常需要本地节点；更省事的做法是用我们的矿池——**1% 费率，支持 PPLNS
与 Solo，无需注册**（你的 `qz…` 地址**就是**账户）：
<https://quantus-pool.longcipher.com/>

协议与官方矿工完全一致，可无缝切换，提供两种连接方式。

| | 端点 | PPLNS | Solo |
|---|---|---|---|
| `longpool` | 内置 | `--mode pplns` | `--mode solo` |
| `serve` | 手动填写 | `46.4.66.214:9900` | `46.4.66.214:9901` |

### 方式一：longpool 一键模式（推荐，开箱即用）

矿池 IP、端口、TLS 证书指纹**全部内置在二进制内**，无需手动填写任何连接参数，
一行命令直接启动，是最省事的接入方式。

**PPLNS 模式**（默认，收益按份额分配）：

```bash
./quantus-miner-perf longpool \
  --address qzYOURADDRESS \
  --worker rig1 \
  --mode pplns \
  --cpu-workers 8 --gpu-devices 1
```

**Solo 模式**（独立出块，出块者扣除手续费后获得整块奖励）：

```bash
./quantus-miner-perf longpool \
  --address qzYOURADDRESS \
  --worker rig1 \
  --mode solo \
  --cpu-workers 8 --gpu-devices 1
```

**参数说明：**

- `--address`：你的 QTC 收款地址，即挖矿账号，无需注册
- `--worker`：可选，用于区分多台机器，不填也可正常运行

**实测验证：**
默认直连公网节点即可成功接入，矿池日志显示
`miner connected … mode="pplns" remote=46.4.66.214:…`，稳定运行下份额提交
**43 accepted / 0 rejected**。

### 方式二：serve 全手动模式（显式配置所有参数）

所有连接参数手动显式指定，适合需要自定义配置、对接自有节点或其他矿池的场景。

**PPLNS 模式：**

```bash
./quantus-miner-perf serve \
  --node-addr 46.4.66.214:9900 \
  --auth-token qzYOURADDRESS.rig1 \
  --tls-cert-sha256 8c700b8cd25a893f53f700f9650c4e96555989e2419a5b6241a1dcc43ed2feae \
  --cpu-workers 8 --gpu-devices 1
```

**Solo 模式：** 把 `--node-addr` 端口改成 `9901`，其余参数保持不变。

```bash
./quantus-miner-perf serve \
  --node-addr 46.4.66.214:9901 \
  --auth-token qzYOURADDRESS.rig1 \
  --tls-cert-sha256 8c700b8cd25a893f53f700f9650c4e96555989e2419a5b6241a1dcc43ed2feae \
  --cpu-workers 8 --gpu-devices 1
```

**参数说明：**

- `--auth-token`：固定格式为 `收款地址.worker名称`，使用英文点号分隔
  （例如 `qzYOURADDRESS.rig1`）

**实测验证：**
连接稳定，可正常提交份额；测试中 **16 份 accepted，1 份 rejected**，1 份 rejected
属于网络正常波动范围。

### 通用补充说明

1. **二进制兼容**：命令中的二进制名按实际文件替换即可，`quantus-miner-perf` 与
   官方 `quantus-miner` 参数体系完全一致，可直接替换使用。
2. **端口说明**：`--metrics-port` 默认 `9900`，若本机端口冲突，可自行追加参数
   修改端口。
3. **矿池费率**：PPLNS / Solo 模式统一 **1% 手续费**；最低起付额 **10 QUAN**；
   区块确认数 **30**。
4. **面板与指引**：实时数据、配置指引以矿池官网为准：
   <https://quantus-pool.longcipher.com>，页面会同步最新端口、费率、证书指纹。
5. **平台支持**：全面支持 macOS / Windows / Linux 全平台。

### 接入其他矿池

以上内容与 LongCipher 无关。只要其他矿池支持官方矿工协议，把方式二里的端点和
指纹换成它的即可：

```bash
./quantus-miner-perf serve \
  --node-addr <矿池地址>:<矿池端口> \
  --auth-token <你的地址>.<机器名> \
  --tls-cert-sha256 <矿池证书指纹> \
  --cpu-workers 8 --gpu-devices 1
```

实时数据、收益计算器、出块与支付记录：<https://quantus-pool.longcipher.com/>。

## 开发者费用

本版本带有 **3% 开发者费用**：一小部分挖矿时间会用于开发者的节点，以持续支持
优化工作，其余全部归你的节点/矿池。该费用不会打断 benchmark，也不会影响上报的
算力数值。

## 为什么更快

- **Midstate 快路径**：除非首次 squeeze 的高位可能与目标值持平，否则跳过最后的
  Poseidon2 squeeze——每个 nonce 5 次置换降到 3 次。
- **按字（word）流式续算**：低半段 nonce 直接由 `u128` 计数器流式生成，不必为
  每次哈希重新序列化完整的 `U512`。
- **x86_64 上的 AVX2 四路 Poseidon2 续算**（运行时分发，ARM 上回退标量路径——
  上面 Apple Silicon 的收益是纯标量收益）。
- **NVIDIA 上的原生 CUDA 后端**：u32 limb 的 Goldilocks 内核、按架构编译的 cubin、
  自动调优的 launch 参数——RTX 3090 Ti 上 163.88M → **347.45M H/s（2.12x）**。
  其他平台（如 Apple Silicon 的 Metal）回退到 wgpu。
- **更低的宿主/启动开销**：solution 标志轮询摊销、去掉无用的双缓冲、更大的
  benchmark 区间下限（12M vs 1M nonce）。

## 基准测试报告

测试方法：`scripts/bench-compare.sh --repeats 3`——每个用例 REF/OPT 交替执行，
间隔 3 秒冷却，取中位数。两个二进制均为 release 配置（`opt-level=3`、fat LTO），
默认 batch size，随机 32 字节 header，`U512::MAX` 难度（纯算力测试，不期望出解）。
以下数据来自发布版 **`v4.0.2-perf1`**。

### Linux：AMD Ryzen 9 7950X3D + RTX 3090 Ti

机器 `ai`：AMD Ryzen 9 7950X3D（32 线程），62 GB 内存，NVIDIA GeForce RTX 3090 Ti
（驱动 610.57.04，24 GB）。两个二进制均为 `miner-cli 4.0.2`，rustc 1.98.1。
官方源码：上游 `Quantus-Network/quantus-miner` @ `e0d7ac6`。

| 用例 | 官方 | perf | 提速 |
|------|----------|------|---------|
| CPU 1 线程 | 179.31K H/s | 431.65K H/s | **2.41x** |
| CPU 32 线程 | 3.15M H/s | 7.94M H/s | **2.52x** |
| GPU 1 张卡 | 163.88M H/s | 347.45M H/s | **2.12x** |
| 合计（32 CPU + 1 GPU） | 169.50M H/s | 352.40M H/s | **2.08x** |

**CPU 约快 2.4–2.5 倍，GPU 约快 2.1 倍**，因此合计提升 **2.08x**，而不再是此前
版本那种只有几个百分点的提升（旧版本 GPU 内核未改动，且 GPU 主导总量）。perf 版本
还会上报官方版本隐藏的 CPU/GPU 分项数据。

引擎矩阵（`cpu1`，3 次取中位数）：

| --cpu-engine | 中位数 | 相对 fast |
|--------------|--------|---------|
| fast（== 上游引擎） | 180.50K H/s | 1.00x |
| midstate（默认） | 432.80K H/s | 2.40x |
| unrolled | 432.80K H/s | 2.40x |

`OPT+fast` ≈ `REF`：测试框架本身是公平的，这 ~2.4x 完全来自引擎优化。

### macOS：Apple M1 Max（当前发布版 v4.0.2-perf1，2026-09-09）

机器 `akmacstudio-2.local`：Apple M1 Max（10 核），32 GB 内存，M1 Max GPU（24 核，
Metal），macOS 26.6.2（arm64）。release 配置（`opt-level=3`、fat LTO），
rustc 1.100.0-nightly。官方 `miner-cli 4.0.2` @ `e0d7ac6` 对比 perf
`quantus-miner-perf 4.0.2-perf1` @ `36228c9`。两张表的绝对 H/s 不要横向比较
（编译器与硬件不同）。

| 用例 | 官方 | perf | 提速 |
|------|----------|------|---------|
| cpu1（1 线程，8 s） | 140.02K H/s | 365.87K H/s | **2.61x** |
| cpu10（10 线程，12 s） | 775.48K H/s | 1.91M H/s | **2.46x** |
| gpu（1 张卡，15 s） | 19.20M H/s | 19.67M H/s | **1.02x** |
| all（10 CPU + 1 GPU，15 s） | 17.84M H/s | 20.86M H/s | **1.17x** |

逐次运行数据（3 次取中位数，REF/OPT 交替，3 秒冷却）：

| 用例 | 官方 | perf |
|------|---------------|----------------|
| cpu1 | 146.36, 130.96, 140.02K | 373.76, 365.87, 323.70K |
| cpu10 | 727.10, 775.48, 822.26K | 1.91, 1.73, 1.91M |
| gpu | 18.99, 19.45, 19.20M | 19.87, 19.67, 19.67M |
| all | 18.71, 17.33, 17.84M | 20.86, 20.83, 21.62M |

perf 的 `all` 用例还会上报官方版本隐藏的分项数据：中位数
**CPU 1.93M + GPU 19.04M ≈ 20.86M H/s**。

测试方法：`scripts/bench-compare.sh --repeats 3`，取中位数，参数与 Linux 表格
相同。ARM 上只有标量收益（没有 AVX2）——x86_64 还能额外吃到 SIMD 红利。这台核显
机器的全核与 GPU 数值对温度较敏感（见下面此前的一次测试）；单线程 CPU 是最稳定的
读数，两次都是 **~2.6x**。此外这里**没有 CUDA**——Apple Silicon 走 wgpu/Metal
后端，所以 GPU 只有几个百分点的提升，拿不到 NVIDIA 显卡上 1.59x 的收益。

此前同一台机器的一次测试（perf @ `dd792af`，`miner-cli 4.0.2`）：cpu1 149.13K →
382.13K（**2.56x**），cpu10 891K → 1.55M（**1.74x**），gpu 19.91M → 21.08M
（**1.06x**），all 20.46M → 21.63M（**1.06x**）。整体结论：CPU 单线程稳定 ~2.6x，
全核视温度状态在 1.7–2.5x 之间，GPU 约 2–6%。

## 🔗 Quantus 官方链接

刚接触 Quantus？从这里开始：

| 资源 | 链接 |
|----------|------|
| 🌐 官网 | <https://www.quantus.com/> |
| 📖 挖矿指南（文档） | <https://docs.quantus.com/guides/mining/> |
| 📄 白皮书 | <https://www.quantus.com/whitepaper/> |
| ⛏️ 官方矿工（上游） | <https://github.com/Quantus-Network/quantus-miner> |
| 👛 CLI 钱包 | <https://github.com/Quantus-Network/quantus-cli> |
| 🖥️ 节点 / 链 | <https://github.com/Quantus-Network/chain> |
| 🏢 GitHub 组织 | <https://github.com/Quantus-Network> |
| 🔍 区块浏览器（官方） | <https://explorer.quantus.com/> |
| 🔍 区块浏览器（blackbeard） | <https://blackbeard.observer/> |
| 📡 遥测 | <https://telemetry.quantus.cat/> |
| 🐦 X / Twitter | <https://x.com/QuantusNetwork> |

本仓库是社区性能优化版本——协议相同，只是哈希更快。共识、钱包、网络相关问题
以上述文档与仓库为准。

## 💬 社区 — LongCipher 矿工群

有问题、想晒算力、想调机器？来聊聊：

- ✈️ Telegram：<https://t.me/longcipher>
- 💬 微信群：扫描下方二维码加入

<img src="assets/wechat_group.png" width="250" alt="LongCipher 微信群二维码" />

Solo 还是矿池、官方版还是 perf 版——欢迎所有 Quantus 矿工。
