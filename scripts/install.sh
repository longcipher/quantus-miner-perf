#!/usr/bin/env bash
# Install or upgrade quantus-miner-perf to the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh | bash
#
# What it does:
#   1. Detects OS/arch (macOS arm64/x86_64, Linux x86_64, Windows x86_64).
#   2. On Linux x86_64, picks the -simd build when the CPU has AVX2.
#   3. Compares latest release tag against `quantus-miner-perf -V`;
#      skips install when local is already >= latest (unless --force).
#   4. Verifies SHA256SUMS before installing.
#
# Options:
#   --dir DIR        install dir (default: /usr/local/bin)
#   --tag TAG        pin version, e.g. v4.0.2-perf1 (default: latest release)
#   -f, --force      reinstall even if up to date
#   --simd/--no-simd override AVX2 auto-detect (Linux x86_64 only)
#   -h, --help       this help
#
# Env: REPO override for forks; QPERF_SIMD=0|1 also overrides AVX2 auto-detect.

set -uo pipefail

REPO="${REPO:-longcipher/quantus-miner-perf}"
BIN="quantus-miner-perf"
DIR="/usr/local/bin"
TAG=""
FORCE=0
SIMD="${QPERF_SIMD:-auto}"

usage() { sed -n '2,/^$/p' "$0" | sed -E 's/^# ?//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --tag) TAG="$2"; shift 2;;
    -f|--force) FORCE=1; shift;;
    --simd) SIMD=1; shift;;
    --no-simd) SIMD=0; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "need '$1' installed first"; }
need curl; need tar

# ---- platform ---------------------------------------------------------------
case "$(uname -s)" in
  Darwin) case "$(uname -m)" in arm64) PLAT="macos-arm64";; x86_64) PLAT="macos-x86_64";; *) die "unsupported macOS arch: $(uname -m)";; esac; EXT="tar.gz";;
  Linux)  case "$(uname -m)" in x86_64|amd64) PLAT="linux-x86_64";; *) die "unsupported Linux arch: $(uname -m) (no release asset)";; esac; EXT="tar.gz";;
  MINGW*|MSYS*|CYGWIN*|Windows_NT) PLAT="windows-x86_64"; EXT="zip";;
  *) die "unsupported OS: $(uname -s)";;
esac
[ "$EXT" = zip ] && need unzip

# ---- SIMD (Linux x86_64 only: AVX2 -> -simd build) ----------------------------
SUFFIX=""
if [ "$PLAT" = "linux-x86_64" ] && [ "$SIMD" != "0" ]; then
  if [ "$SIMD" = "1" ] || grep -qw avx2 /proc/cpuinfo 2>/dev/null; then SUFFIX="-simd"; fi
fi

# ---- versions ---------------------------------------------------------------
# ponytail: sort -V is GNU-only (absent on macOS/BSD), so compare with awk.
ver_norm() { printf '%s' "$1" | sed -E 's/([0-9]+)/.\1./g; s/[.-]+/./g; s/^\.//; s/\.$//'; }
ver_gt() { # ver_gt A B: prints "yes" iff A > B
  awk -v a="$(ver_norm "$1")" -v b="$(ver_norm "$2")" 'BEGIN{
    n=split(a,A,/[-.]/); m=split(b,B,/[-.]/); k=n>m?n:m
    for(i=1;i<=k;i++){ x=A[i]; y=B[i]
      if(x==y) continue
      if(x==""){print "no"; exit} if(y==""){print "yes"; exit}
      xn=(x~/^[0-9]+$/); yn=(y~/^[0-9]+$/)
      if(xn&&yn){print (x+0>y+0?"yes":"no"); exit}
      print (x>y?"yes":"no"); exit}
    print "no"}'
}

latest_tag() { # via API, fallback to /releases/latest redirect (API rate limits)
  local t
  t="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | \
       sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$t" ] && { printf '%s' "$t"; return; }
  curl -fsSIL -o /dev/null -w '%{url_effective}' \
    "https://github.com/$REPO/releases/latest" 2>/dev/null | sed 's#.*/tag/##'
}

if [ -z "$TAG" ]; then
  TAG="$(latest_tag)"
  [ -n "$TAG" ] || die "cannot determine latest release (network or API rate limit?)"
fi
case "$TAG" in v*) ;; *) TAG="v$TAG";; esac
VER="${TAG#v}" # contract: tag vX == `-V` X == asset ...-X-...

local_ver() { # first version-like token of `$bin -V`, "" when not installed
  local b v
  for b in "$DIR/$BIN" "$(command -v "$BIN" 2>/dev/null)"; do
    [ -n "$b" ] && [ -x "$b" ] || continue
    v="$("$b" -V 2>/dev/null | grep -oE '[0-9][0-9A-Za-z._-]*' | head -1)"
    [ -n "$v" ] && { printf '%s' "$v"; return; }
  done
}
CUR="$(local_ver || true)"

if [ "$FORCE" -eq 0 ] && [ -n "$CUR" ]; then
  if [ "$CUR" = "$VER" ]; then echo "$BIN $CUR already up to date."; exit 0; fi
  if [ "$(ver_gt "$CUR" "$VER")" = yes ]; then
    echo "$BIN $CUR newer than release $VER, skip (use --force to reinstall)."; exit 0
  fi
  echo "$BIN $CUR < $VER, upgrading..."
fi

# ---- download + verify + install ----------------------------------------------
ASSET="${BIN}-${VER}-${PLAT}${SUFFIX}.${EXT}"
BASE="https://github.com/$REPO/releases/download/${TAG}"
TMP="$(mktemp -d /tmp/qperf-install.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
echo "+ $BASE/$ASSET"
curl -fsSL --retry 3 -o "$TMP/$ASSET" "$BASE/$ASSET" || die "download failed: $BASE/$ASSET"
curl -fsSL --retry 3 -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || die "checksum file download failed"

if command -v sha256sum >/dev/null 2>&1; then SUM="sha256sum -c";
elif command -v shasum >/dev/null 2>&1; then SUM="shasum -a 256 -c";
else die "need 'sha256sum' or 'shasum' to verify the download"; fi
(cd "$TMP" && grep -F "  $ASSET" SHA256SUMS | $SUM -) || die "checksum mismatch for $ASSET"

case "$EXT" in
  tar.gz) tar xzf "$TMP/$ASSET" -C "$TMP";;
  zip) unzip -q -o "$TMP/$ASSET" -d "$TMP";;
esac
SRC=""
for c in "$TMP/$BIN" "$TMP/quantus-miner" "$TMP/$BIN.exe" "$TMP/quantus-miner.exe"; do
  [ -f "$c" ] && { SRC="$c"; break; }
done
[ -n "$SRC" ] || die "archive has no miner binary (asset layout changed?)"

DST="$DIR/$BIN"; case "$SRC" in *.exe) DST="$DST.exe";; esac # ponytail: always install as quantus-miner-perf
mkdir -p "$DIR" || die "cannot create $DIR"
if [ -w "$DIR" ]; then cp "$SRC" "$DST" && chmod 755 "$DST"
else echo "no write access to $DIR, retrying with sudo..."
  sudo cp "$SRC" "$DST" && sudo chmod 755 "$DST" || die "install failed; try --dir ~/.local/bin"
fi
echo "installed: $("$DST" -V 2>&1 | head -1) -> $DST"
