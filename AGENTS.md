# quantus-miner-perf Agent Instructions

## Non-negotiables

- Surgical edits only: every changed line must trace to the request. No drive-by refactors, no reformatting untouched code, no deleting pre-existing dead code (mention it instead).
- Fix root causes. Never silence a warning, weaken a check, or patch a symptom to make a gate pass.
- Never report completion while any `just` gate below fails. Report the failure verbatim and stop.
- Stop and ask when a request is ambiguous, conflicts with existing conventions, or requires credentials, publishing, or destructive operations.
- When a correction reveals a missing rule, add one specific rule here ("always X for Y", never "be careful with Y"); delete rules that never catch real errors.

## Scope

- This repo distributes a prebuilt binary, not source: there is no Rust, no compiler and no build step in this tree. The miner is built in a separate checkout and published as GitHub release assets.
- What lives here: `README.md` (English), `README.zh.md` (Chinese), `scripts/install.sh` (installer), `scripts/bench-compare.sh` (A/B benchmark harness), `assets/wechat_group.png`.
- The two READMEs are a mirrored pair. Every number, endpoint, flag and command must exist in both; only the prose is translated. The switch line at the top of each file points at the other.
- `scripts/install.sh` is what every user executes via `curl … | bash` against `raw.githubusercontent.com/longcipher/quantus-miner-perf/master/scripts/install.sh`. A change here changes what runs on every install, so it needs a manual dry run.
- `scripts/bench-compare.sh` compares a locally built binary against an official upstream checkout; both default to machine-specific absolute paths, so the README documents the invocation with explicit overrides.
- English only in code, comments, docs, and commit messages. `README.zh.md` is the single intentional exception.

## Execution

- Parallelize aggressively: dispatch subagents for independent research, exploration, and implementation.
- Translate and edit together: change the English README first, mirror it into `README.zh.md`, then diff the tables field by field.
- NEVER use `git worktree`. Edit the current branch in place.
- There is no test suite to drive. For a script change, capture the current behaviour first, make the smallest change that reproduces it, then re-run the script's `--help` and the path you changed.

## Verification loop

After each feature or bug fix, in order; any failure means the task is not done:

```bash
just format
just lint
just check-cn
```

There is no build and no test suite: `lint` is a Markdown lint plus a shell syntax check (`bash -n`) of both scripts. `check-cn` covers everything except the two READMEs, which are bilingual by design.

## Shell rules

- Both scripts must keep `set -uo pipefail` (plus `set -euo pipefail` where files are installed) and must stay portable to macOS: `sort -V`, `sha256sum` and `readlink -f` are not everywhere. `install.sh` already compares versions with `awk` instead of `sort -V`.
- `install.sh` maps the platform onto a release asset named `quantus-miner-perf-<version>-<platform>[.tar.gz|.zip]`. Change that naming in one commit with the download URL, or the installer breaks silently for every user.
- Install is stage-then-rename: copy to a temp path, `chmod 755`, then `mv` into place. Never `cp` over a live binary — overwriting a running binary's text pages makes the next `exec` fail with `SIGKILL` and no output.
- On macOS, drop `com.apple.quarantine` from the staged file and ad-hoc re-sign it before the rename; an unsigned or stale-signed binary is killed at `exec` with no message.
- The install is fail-closed: after the rename, run `"$DST" -V` and abort if it prints nothing.
- `SHA256SUMS` must be verified before the archive is unpacked. The lookup uses `grep -F "  $ASSET"` — the two-space separator is part of the `sha256sum` format.
- `install.sh` flags are `--dir`, `--tag`, `--force`, `--simd`, `--no-simd`; the environment overrides are `REPO` and `QPERF_SIMD`. Document any new flag in the script header, `README.md` and `README.zh.md`.
- The version contract is `tag vX` ≡ `quantus-miner-perf -V` printing `X`. The installer compares the local binary against the latest release and skips the reinstall when the local copy is newer.
- `bench-compare.sh` reports the **median** of interleaved REF/OPT repeats. Never switch it to a mean or a single run — the median is what makes the numbers comparable across thermal states.
- The engine matrix (`fast`, `midstate`, `unrolled`) is what separates "the engine got faster" from "the harness got faster". Keep `--engines` in the default run.
- `bench-compare.sh` exits non-zero when a case has zero successful runs on either binary. Keep that exit status.
- `usage()` in both scripts is generated from the header comment with `sed -n '2,/^$/p'`. The header must stay the first comment block and must stay in sync with the real flags.

## Dependency choices

- The scripts may only rely on `bash`, `curl`, `tar` (or `unzip`), and `sha256sum` or `shasum`. They run on the user's machine with no package manager available.
- `rumdl` lints the Markdown and `typos` catches misspellings; both are dev-only and installed by `just setup`. `shellcheck` is not wired in — `bash -n` is the syntax gate.
- Never add a runtime dependency to the miner binary from this repo: the binary is built elsewhere and released as an asset.

## Code conventions

- Shell style: two-space indent, `snake_case` locals, `"$var"` quoting everywhere, `local` only inside functions, and `die()` on every failure path.
- Every script opens with a header comment saying what it does, how to invoke it, and what each option means.
- README tables are Markdown tables with one column per metric (`official`, `perf`, `speedup`). Keep the column set identical in both languages.
- Every benchmark figure carries the release tag it was produced by and the machine it was measured on; a number without both is not publishable.
- The pool endpoints are load-bearing: the direct IP `46.4.66.214` and the mainland relay `57.180.173.214` serve the same ports (9900 PPLNS, 9901 Solo) and the same TLS fingerprint. Changing one without the other strands users.
