#!/usr/bin/env bash
# A/B benchmark comparison between the optimized build (this repo) and the
# official upstream build.
#
# What it does:
#   Runs a fixed case matrix on both binaries with interleaved repeats,
#   takes the MEDIAN per case (robust against GPU boost/thermal jitter),
#   and prints a side-by-side table with speedups. Raw logs, per-run CSV
#   and a Markdown summary are written to an output directory for archiving
#   (e.g. to back docs/benchmark.md numbers).
#
# Usage:
#   scripts/bench-compare.sh [options] [OPT_BIN] [REF_BIN]
#
#   OPT_BIN defaults to <repo>/target/release/quantus-miner
#   REF_BIN defaults to <official-checkout>/target/release/quantus-miner
#     (Linux: /home/akagi201/tmp/quantus-miner/…,
#      macOS: /Volumes/akext/tmp/quantus/quantus-miner/…).
#   Both are overridable with positional args OPT_BIN REF_BIN.
#   The script is cross-platform (Linux/macOS): CPU count, CPU model and
#   GPU info degrade gracefully
#   (nproc→sysctl/getconf, lscpu→sysctl, nvidia-smi→system_profiler).
#
# Options:
#   -r, --repeats N        repeats per case (default: 3, median is reported)
#   --cases LIST           comma list from: cpu1,cpuN,gpu,all (default: all four)
#   --d-cpu1 S             duration for cpu1 case (default: 8)
#   --d-cpun S             duration for cpuN case (default: 12)
#   --d-gpu S              duration for gpu case (default: 15)
#   --d-all S              duration for combined case (default: 15)
#   --engines LIST         extra --cpu-engine variants run on OPT for cpu1,
#                          comma list from: fast,midstate,unrolled
#                          (default: fast,unrolled; midstate == OPT default run)
#   --no-engine-matrix     skip the engine-variant matrix
#   --no-gpu               skip gpu/all cases (CPU-only machines)
#   --cooldown S           sleep between runs (default: 3)
#   --out-dir DIR          results dir (default: bench-results/bench-<timestamp>)
#   -h, --help             this help
#
# Fairness notes (also documented in docs/benchmark.md):
#   * REF (official) has no --cpu-engine flag: it always runs FastCpuEngine
#     (5 Poseidon2 permutations per nonce, blended per-worker reporting).
#   * OPT defaults to --cpu-engine midstate (midstate fast path + AVX2 SIMD4
#     on x86_64, scalar fallback on aarch64, split CPU/GPU reporting). The engine matrix isolates the
#     engine gain from harness changes: OPT+fast vs REF+fast is apples to
#     apples on the harness, OPT+midstate vs OPT+fast isolates the engine.
#   * Both binaries run with DEFAULT batch sizes out of the box. Note the
#     harness floors differ: gpu range floor is 12M nonces on OPT vs 1M on
#     REF (amortizes per-search host overhead on the GPU path).
#
# Exit status: 0 unless a case has zero successful runs on either binary.

set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"

REPEATS=3
CASES="cpu1,cpuN,gpu,all"
D_CPU1=8; D_CPUN=12; D_GPU=15; D_ALL=15
ENGINES="fast,unrolled"
ENGINE_MATRIX=1
NO_GPU=0
COOLDOWN=3
OUT_DIR=""
OPT_BIN=""; REF_BIN=""

usage() { sed -n '2,/^$/p' "$0" | sed -E 's/^# ?//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repeats)      REPEATS="$2"; shift 2;;
    --cases)           CASES="$2"; shift 2;;
    --d-cpu1)          D_CPU1="$2"; shift 2;;
    --d-cpun)          D_CPUN="$2"; shift 2;;
    --d-gpu)           D_GPU="$2"; shift 2;;
    --d-all)           D_ALL="$2"; shift 2;;
    --engines)         ENGINES="$2"; shift 2;;
    --no-engine-matrix) ENGINE_MATRIX=0; shift;;
    --no-gpu)          NO_GPU=1; shift;;
    --cooldown)        COOLDOWN="$2"; shift 2;;
    --out-dir)         OUT_DIR="$2"; shift 2;;
    -h|--help)         usage; exit 0;;
    --)                shift; break;;
    -*)                echo "Unknown option: $1" >&2; usage >&2; exit 2;;
    *)                 if [ -z "$OPT_BIN" ]; then OPT_BIN="$1";
                       elif [ -z "$REF_BIN" ]; then REF_BIN="$1";
                       else echo "Too many positional args: $1" >&2; exit 2; fi
                       shift;;
  esac
done

BIN="${OPT_BIN:-$HERE/target/release/quantus-miner}"
default_ref() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) printf '%s' "/Volumes/akext/tmp/quantus/quantus-miner/target/release/quantus-miner";;
    *)      printf '%s' "/home/akagi201/tmp/quantus-miner/target/release/quantus-miner";;
  esac
}
REF="${REF_BIN:-$(default_ref)}"

die() { echo "ERROR: $*" >&2; exit 1; }
[ -x "$BIN" ] || die "optimized binary not found/executable: $BIN (run cargo build -p miner-cli --release)"
[ -x "$REF" ] || die "reference binary not found/executable: $REF (build the official checkout first)"
case "$REPEATS" in ''|*[!0-9]*|0) die "--repeats must be a positive integer";; esac

nproc_portable() {
  if command -v nproc >/dev/null 2>&1; then
    nproc 2>/dev/null && return
  fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu 2>/dev/null && return
  fi
  getconf _NPROCESSORS_ONLN 2>/dev/null || echo 32
}
NPROC="$(nproc_portable 2>/dev/null || echo 32)"
case "$NPROC" in ''|*[!0-9]*) NPROC=32;; esac

cpu_model() {
  if command -v lscpu >/dev/null 2>&1; then
    lscpu 2>/dev/null | awk -F: '/Model name/{sub(/^ +/,"",$2); print $2; exit}'
    return
  fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n machdep.cpu.brand_string 2>/dev/null && return
  fi
  awk -F: '/model name/{sub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null
}

gpu_info() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null | head -1
    return
  fi
  if [ "$(uname -s 2>/dev/null)" = "Darwin" ] && command -v system_profiler >/dev/null 2>&1; then
    system_profiler SPDisplaysDataType 2>/dev/null | \
      awk '/Chipset Model:/{m=$0; sub(/^ *Chipset Model: /,"",m); gsub(/^ +| +$/,"",m); c=c ? c", "m : m} /Total Number of Cores:/{n=$0; sub(/^.*: /,"",n); cores=n} END{if (c) print c (cores ? " ("cores" cores)" : "")}'
    return
  fi
  echo "(no GPU info tool available)"
}

mktemp_portable() { mktemp /tmp/bench-compare.XXXXXX 2>/dev/null; }
CPU_N_LABEL="cpu${NPROC}"

# Filter cases (--no-gpu drops gpu/all).
ACTIVE_CASES=""
for c in $(printf '%s' "$CASES" | tr ',' ' '); do
  case "$c" in
    cpuN) c="$CPU_N_LABEL";;
  esac
  case "$c" in
    cpu1|cpu[0-9]*) ;;
    gpu|all) [ "$NO_GPU" -eq 1 ] && continue;;
    *) die "unknown case '$c' (want cpu1,cpuN,gpu,all)";;
  esac
  ACTIVE_CASES="$ACTIVE_CASES $c"
done
[ -n "${ACTIVE_CASES// /}" ] || die "no cases left after filtering"

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$HERE/bench-results/bench-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUT_DIR/raw" || die "cannot create $OUT_DIR"
CSV="$OUT_DIR/runs.csv"
printf 'rep,binary,case,engine,rate_hs,cpu_hs,gpu_hs,total_hashes,elapsed_s,log\n' > "$CSV"

# ---- environment header -------------------------------------------------
{
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host: $(hostname 2>/dev/null || echo unknown)"
  echo "cpu: $(cpu_model)"
  echo "nproc: $NPROC"
  echo "gpu: $(gpu_info)"
  for tag in "opt:$BIN" "ref:$REF"; do
    name="${tag%%:*}"; path="${tag#*:}"
    echo "$name: $path"
    echo "  version: $("$path" --version 2>&1 | head -1)"
    dir="$(dirname "$(dirname "$path")")"
    if [ -d "$dir/.git" ]; then
      echo "  git: $(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo unknown) ($(git -C "$dir" log --oneline -1 --format=%s 2>/dev/null || echo unknown))"
    fi
  done
  echo "repeats: $REPEATS (median reported)"
  echo "durations: cpu1=${D_CPU1}s $(echo "$CPU_N_LABEL" | sed 's/cpu/cpus=/')=${D_CPUN}s gpu=${D_GPU}s all=${D_ALL}s"
  echo "cooldown: ${COOLDOWN}s between runs, REF/OPT interleaved per case"
} | tee "$OUT_DIR/env.txt"
echo

# ---- helpers ------------------------------------------------------------
# "433.35K" / "167.58M" / "1.23G" / "512" -> integer H/s ("" on failure).
to_hs() {
  awk -v v="$1" 'BEGIN{
    if (v=="") exit 1
    m=1
    s=substr(v,length(v))
    if (s=="G"||s=="M"||s=="K") { v=substr(v,1,length(v)-1);
      m=(s=="G")?1e9:((s=="M")?1e6:1e3) }
    if (v+0<=0) exit 1
    printf "%.0f", v*m
  }' 2>/dev/null
}

fmt() { # raw H/s -> 1.23M (or FAIL)
  if [ -z "${1:-}" ]; then printf '-'; return; fi
  awk -v n="$1" 'BEGIN{ if (n>=1e9) printf "%.2fG", n/1e9;
                       else if (n>=1e6) printf "%.2fM", n/1e6;
                       else if (n>=1e3) printf "%.2fK", n/1e3;
                       else printf "%.0f", n }'
}

# run_once <which> <rep> <case> <engine> <bin> -- <bench args...>
# Appends one row to $CSV, echoes "<rate_hs> <log>" for progress.
run_once() {
  local which="$1" rep="$2" case="$3" engine="$4" bin="$5"; shift 5
  [ "${1:-}" = "--" ] && shift
  local log="$OUT_DIR/raw/${case}_${which}_rep${rep}.log"
  local cmd_str="$bin benchmark $*"
  printf '+ [%s rep%d/%d] %s\n' "$case" "$rep" "$REPEATS" "$cmd_str"
  echo "\$ $cmd_str" > "$log"
  "$bin" benchmark "$@" >> "$log" 2>&1
  local rate_raw cpu_raw gpu_raw total elapsed
  rate_raw="$(sed -n 's/^Average rate: \([^ ]*\) H\/s$/\1/p' "$log" | head -1)"
  cpu_raw="$(sed -n 's/^CPU: \([^ ]*\) H\/s.*/\1/p' "$log" | head -1)"
  gpu_raw="$(sed -n 's/^GPU: \([^ ]*\) H\/s.*/\1/p' "$log" | head -1)"
  total="$(sed -n 's/^Total hashes: \([0-9]*\)$/\1/p' "$log" | head -1)"
  elapsed="$(sed -n 's/^Total time: \([0-9.]*\)s$/\1/p' "$log" | head -1)"
  local rate_hs="" cpu_hs="" gpu_hs=""
  rate_hs="$(to_hs "$rate_raw" || true)"
  [ -n "${cpu_raw:-}" ] && cpu_hs="$(to_hs "$cpu_raw" || true)"
  [ -n "${gpu_raw:-}" ] && gpu_hs="$(to_hs "$gpu_raw" || true)"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$rep" "$which" "$case" "$engine" \
    "$rate_hs" "$cpu_hs" "$gpu_hs" "${total:-}" "${elapsed:-}" "$log" >> "$CSV"
  if [ -n "$rate_hs" ]; then
    echo "  -> $(fmt "$rate_hs") H/s"
  else
    echo "  -> FAILED to parse rate (see $log)"
  fi
  sleep "$COOLDOWN"
}

case_args() { # <case> -> bench args
  case "$1" in
    cpu1)        printf '%s' "--gpu-devices 0 --cpu-workers 1 --duration $D_CPU1";;
    "$CPU_N_LABEL") printf '%s' "--gpu-devices 0 --cpu-workers $NPROC --duration $D_CPUN";;
    gpu)         printf '%s' "--cpu-workers 0 --gpu-devices 1 --duration $D_GPU";;
    all)         printf '%s' "--duration $D_ALL";;
  esac
}

echo "== Reference (official): $REF"
echo "== Optimized (this repo): $BIN"
echo "== Results dir: $OUT_DIR"
echo

# ---- main matrix: interleave REF/OPT per case per repeat -----------------
rep=1
while [ "$rep" -le "$REPEATS" ]; do
  for c in $ACTIVE_CASES; do
    # shellcheck disable=SC2086
    run_once ref "$rep" "$c" "-" "$REF" -- $(case_args "$c")
    # shellcheck disable=SC2086
    run_once opt "$rep" "$c" default "$BIN" -- $(case_args "$c")
    # Engine-variant matrix on OPT cpu1 (midstate == default run above).
    if [ "$ENGINE_MATRIX" -eq 1 ] && [ "$c" = "cpu1" ]; then
      for eng in $(printf '%s' "$ENGINES" | tr ',' ' '); do
        [ "$eng" = "midstate" ] && continue # already covered by default run
        case "$eng" in fast|midstate|unrolled) ;;
          *) die "unknown engine '$eng' (want fast,midstate,unrolled)";; esac
        # shellcheck disable=SC2086
        run_once "opt-$eng" "$rep" "$c" "$eng" "$BIN" -- \
          --gpu-devices 0 --cpu-workers 1 --duration "$D_CPU1" --cpu-engine "$eng"
      done
    fi
  done
  rep=$((rep + 1))
done

# ---- aggregation ----------------------------------------------------------
SUMMARY_MD="$OUT_DIR/summary.md"
MED_CSV="$OUT_DIR/medians.csv"
printf 'case,ref_median_hs,opt_median_hs,speedup\n' > "$MED_CSV"

median_of() { # file with one number per line -> median (or "")
  awk 'NF{print}' "$1" | sort -n | awk '{a[NR]=$1} END{
    if (NR==0) exit 1
    if (NR%2) printf "%.0f", a[(NR+1)/2]
    else printf "%.0f", (a[NR/2]+a[NR/2+1])/2 }' 2>/dev/null || true
}

FAIL=0
{
  echo "# Benchmark comparison $(date +%Y-%m-%d)"
  echo
  echo "Source: \`scripts/bench-compare.sh\`, full logs under \`$(basename "$OUT_DIR")/raw/\`."
  echo
  echo "## Environment"
  echo
  echo '```'
  cat "$OUT_DIR/env.txt"
  echo '```'
  echo
  echo "## A/B medians (per case, $REPEATS repeats)"
  echo
  echo "| case | reference | optimized | speedup |"
  echo "|------|-----------|-----------|---------|"
} > "$SUMMARY_MD"

printf '\n%-10s %16s %16s %10s %14s\n' "case" "reference" "optimized" "speedup" "(n ref/opt)"
printf '%-10s %16s %16s %10s %14s\n' "----" "---------" "---------" "-------" "-----------"
for c in $ACTIVE_CASES; do
  tmp_r="$(mktemp_portable)"; tmp_o="$(mktemp_portable)"
  awk -F, -v c="$c" '$2=="ref" && $3==c && $5!=""{print $5}' "$CSV" > "$tmp_r"
  awk -F, -v c="$c" '$2=="opt" && $3==c && $5!=""{print $5}' "$CSV" > "$tmp_o"
  n_r="$(wc -l < "$tmp_r" | tr -d ' ')"; n_o="$(wc -l < "$tmp_o" | tr -d ' ')"
  r="$(median_of "$tmp_r")"; o="$(median_of "$tmp_o")"
  rm -f "$tmp_r" "$tmp_o"
  if [ -n "$r" ] && [ -n "$o" ] && [ "$r" -gt 0 ] 2>/dev/null; then
    x="$(awk -v r="$r" -v o="$o" 'BEGIN{printf "%.2fx", o/r}')"
    xs="$(awk -v r="$r" -v o="$o" 'BEGIN{printf "%.2f", o/r}')"
  else
    x="?"; xs=""; FAIL=1
  fi
  printf '%-10s %16s %16s %10s %6s/%-6s\n' "$c" "$(fmt "$r")${r:+ H/s}" "$(fmt "$o")${o:+ H/s}" "$x" "$n_r" "$n_o"
  printf '| %s | %s | %s | %s |\n' "$c" "$(fmt "$r")${r:+ H/s}" "$(fmt "$o")${o:+ H/s}" "$x" >> "$SUMMARY_MD"
  printf '%s,%s,%s,%s\n' "$c" "$r" "$o" "$xs" >> "$MED_CSV"
done

# Engine-variant medians (OPT cpu1).
if [ "$ENGINE_MATRIX" -eq 1 ] && printf '%s' " $ACTIVE_CASES " | grep -q " cpu1 "; then
  echo
  echo "OPT cpu1 engine matrix (median of $REPEATS, isolates engine vs harness gains):"
  {
    echo
    echo "## OPT cpu1 engine matrix (median of $REPEATS)"
    echo
    echo "| --cpu-engine | median | vs OPT/fast |"
    echo "|--------------|--------|-------------|"
  } >> "$SUMMARY_MD"
  printf '%-12s %16s %12s\n' "engine" "median" "vs fast"
  printf '%-12s %16s %12s\n' "------" "------" "-------"
  # Fast baseline: OPT+fast rows if present, else REF cpu1 rows (same engine).
  tmp_b="$(mktemp_portable)"
  awk -F, '$2=="opt-fast" && $3=="cpu1" && $5!=""{print $5}' "$CSV" > "$tmp_b"
  if [ ! -s "$tmp_b" ]; then
    awk -F, '$2=="ref" && $3=="cpu1" && $5!=""{print $5}' "$CSV" > "$tmp_b"
  fi
  f_med="$(median_of "$tmp_b")"; rm -f "$tmp_b"
  for eng in $(printf 'default,%s' "$ENGINES" | tr ',' ' '); do
    case "$eng" in
      default)  key="opt";          disp="midstate(default)";;
      midstate) key="opt-midstate"; disp="midstate";;
      *)        key="opt-$eng";     disp="$eng";;
    esac
    tmp_e="$(mktemp_portable)"
    awk -F, -v k="$key" '$2==k && $3=="cpu1" && $5!=""{print $5}' "$CSV" > "$tmp_e"
    # default run already is midstate: merge for the midstate row.
    if [ "$eng" = "default" ]; then
      awk -F, '$2=="opt-midstate" && $3=="cpu1" && $5!=""{print $5}' "$CSV" >> "$tmp_e"
    fi
    e_med="$(median_of "$tmp_e")"; rm -f "$tmp_e"
    if [ -n "$e_med" ] && [ -n "$f_med" ] && [ "$f_med" -gt 0 ] 2>/dev/null; then
      rel="$(awk -v e="$e_med" -v f="$f_med" 'BEGIN{printf "%.2fx", e/f}')"
    else
      rel="?"
    fi
    # fast baseline: OPT default-vs-fast uses opt-fast if present else REF.
    printf '%-20s %16s %12s\n' "$disp" "$(fmt "$e_med")${e_med:+ H/s}" "$rel"
    printf '| %s | %s | %s |\n' "$disp" "$(fmt "$e_med")${e_med:+ H/s}" "$rel" >> "$SUMMARY_MD"
  done
  {
    echo
    echo "Reading guide: OPT/fast vs REF shows harness-only delta (same engine);"
    echo "OPT/midstate vs OPT/fast isolates the midstate+SIMD engine gain."
  } >> "$SUMMARY_MD"
fi

echo
echo "Optimized-build CPU/GPU split medians (runs that report them):"
for c in $ACTIVE_CASES; do
  tmp_c="$(mktemp_portable)"; tmp_g="$(mktemp_portable)"
  awk -F, -v c="$c" '$2=="opt" && $3==c && $6!=""{print $6}' "$CSV" > "$tmp_c"
  awk -F, -v c="$c" '$2=="opt" && $3==c && $7!=""{print $7}' "$CSV" > "$tmp_g"
  cm="$(median_of "$tmp_c")"; gm="$(median_of "$tmp_g")"
  rm -f "$tmp_c" "$tmp_g"
  [ -n "$cm" ] && cm="$(fmt "$cm") H/s" || cm="-"
  [ -n "$gm" ] && gm="$(fmt "$gm") H/s" || gm="-"
  printf '  %-10s cpu=%-14s gpu=%-14s\n' "$c" "$cm" "$gm"
done

{
  echo
  echo "## How to reproduce"
  echo
  echo '```bash'
  echo "# 1. Build both trees (default features = GPU enabled where available)"
  echo "cargo build -p miner-cli --release                                   # this repo (OPT)"
  echo "cargo build -p miner-cli --release                                   # official checkout (REF)"
  echo
  echo "# 2. Run the comparison (tune repeats/durations as needed)"
  echo "scripts/bench-compare.sh --repeats $REPEATS --cases $CASES \\"
  echo "  --d-cpu1 $D_CPU1 --d-cpun $D_CPUN --d-gpu $D_GPU --d-all $D_ALL"
  echo '```'
  echo
  echo "Raw logs: \`raw/\`, per-run data: \`runs.csv\`, medians: \`medians.csv\`."
} >> "$SUMMARY_MD"

echo
echo "Wrote: $OUT_DIR/{env.txt,runs.csv,medians.csv,summary.md,raw/}"
[ "$FAIL" -eq 0 ] || echo "WARNING: at least one case has no successful runs on one side (? above)" >&2
exit "$FAIL"
