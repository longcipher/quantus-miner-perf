# Justfile — quantus-miner-perf ships docs and shell scripts, not source.
#
# The miner binary is built in a separate checkout and published as a GitHub
# release asset. The gates below cover the two shell scripts and the
# bilingual README pair; there is no build and no test suite.
#
# The Markdown lint runs with the rules the shipped READMEs deliberately
# break (long lines, inline HTML, an emphasised pseudo-heading) disabled,
# so a new violation anywhere still fails the gate.

# Arguments forwarded to scripts/install.sh (for example: --dir ~/.local/bin)
install_args := ""

# Arguments forwarded to scripts/bench-compare.sh (for example: --repeats 5)
bench_args := ""

# Default recipe to display help
default:
  @just --list

# Install the dev tools this Justfile needs
setup:
  cargo install rumdl
  cargo install typos-cli

# Format the Markdown docs
format:
  rumdl fmt --disable MD013,MD028,MD033,MD036,MD047,MD064 .

# Auto-fix what format cannot
fix:
  rumdl check --fix --disable MD013,MD028,MD033,MD036,MD047,MD064 .

# Run all lints
lint:
  typos
  rumdl check --disable MD013,MD028,MD033,MD036,MD047,MD064 .
  bash -n scripts/install.sh
  bash -n scripts/bench-compare.sh

# Fail if Chinese characters appear outside the bilingual READMEs
check-cn:
  ! rg --line-number --column "\p{Han}" --glob '!README.md' --glob '!README.zh.md' .

# Full CI check
ci: lint check-cn

# Install or upgrade the miner from the latest GitHub release
install:
  bash scripts/install.sh {{install_args}}

# Run the A/B benchmark harness (official build vs this build)
bench:
  bash scripts/bench-compare.sh {{bench_args}}

# Remove the benchmark output directory
clean:
  rm -rf bench-results
