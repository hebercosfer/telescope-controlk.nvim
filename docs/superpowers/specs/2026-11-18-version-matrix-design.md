# controlk: Neovim and Telescope version matrix

Status: approved by the owner. Built in this order: terminal fix, formatting, lint, CI, release. Date: 2026-11-18.

## Intent

controlk should prove, before each change lands, that it works on the Neovim and
Telescope versions it claims, and that its own code makes no deprecated calls.
Today it runs only on Neovim 0.12.6 with Telescope master, and it has no CI.
The README claims Neovim 0.11+. The owner wants 0.10 covered, with the earliest
Telescope release built for it.

## Goals

- Neovim 0.10.4 with Telescope v0.2.0 (the floor pair) passes every suite.
- Each leg pairs one Neovim with one Telescope. Four pairs, checked on every PR.
- A deprecated call made by controlk's own code fails the run. A deprecated call
  made by Neovim, Telescope or plenary does not.
- A weekly job runs the current pair against the newest Telescope master and
  reports drift, the way floating-claude.nvim's `compat.yml` does.
- A release is published only after the release gate passes on every OS (see
  Release plan).

## Non-goals

- `:checkhealth controlk` (TASKS T5), vimdoc (T6), and the Snacks adapter (T11).
  They are separate tasks, though they reuse the same patterns.
- Windows and macOS in PR checks. They are in the release gate instead (see
  Release gate). The harness has never run on either.
- Telescope releases before v0.2.0. v0.1.8 and v0.1.9 also pass the LSP session
  on Neovim 0.10.4, but they target Neovim 0.9, so controlk does not claim them.
- Nightly Neovim in PR checks and in the release gate. It runs once a week in the
  scheduled job, and that job blocks nothing.

## Constraints

- Telescope v0.2.0 and v0.2.2 both require Neovim 0.10.4 or newer, and both
  branch on `nvim-0.11` in `lua/telescope/debounce.lua` and `utils.lua`.
- Only Neovim 0.12.6 is installed on this machine. CI must download the others
  from neovim/neovim releases and verify their checksums.
- The tests must not depend on the owner's lazy.nvim directory. Today
  `tests/integration/run.lua` gets Telescope from `~/.local/share/nvim/lazy`.
- On Neovim 0.10.4, `jobstart(..., { term = true })` returns a job but does not
  create a terminal buffer. `util.terminal` relies on it, so `!`, the `cm` build
  and the `ct` run open an empty split there. Verified in a real tty on 0.10.4, and
  not in 0.12.6. The harness did not catch it: it checks that the command ran, not
  what the window shows. `termopen()` works on 0.10.4, and `:h deprecated` lists it
  as deprecated on 0.12. So the fix branches on version: `termopen()` before 0.11,
  `jobstart` with `term = true` from 0.11 on. This is now in `util.terminal`, and the harness checks the buffer type. Checked on 0.10.4 (also in a real tty), 0.11.7 and 0.12.6.
- The harness has only run on Linux. `util.terminal` opens a terminal job, and
  `web.lua` calls `vim.ui.open`, which launches a browser, so the harness has to
  stub that call on every OS. Telescope's own picker tests skip macOS and Windows
  as flaky. This plan does not skip: a failing OS is fixed, or the release says
  it is not supported.

## Approaches

1. **Matrix of one**, like floating-claude.nvim's maintenance branch. One Neovim
   per branch. Rejected: it does not answer whether controlk works across
   Neovim and Telescope versions.
2. **Full cross product**, three Neovim by three Telescope, nine legs. Rejected:
   the owner asked for pairs, and nine legs cost much more for little extra
   signal.
3. **Pairs**, one Neovim with one Telescope per leg. **Chosen by the owner,
   2026-11-18.**

## Design

### The pairs

| Leg | Neovim | Telescope | Why this pair |
|---|---|---|---|
| floor | v0.10.4 | v0.2.0 | First Telescope release whose minimum is 0.10.4. The 0.10 path of its `nvim-0.11` branches runs here. |
| legacy | v0.10.4 | v0.1.9 | Newest 0.1.x release, requested by the owner. It targets Neovim 0.9, so this leg shows the 0.1 line still runs on 0.10. |
| middle | v0.11.7 | v0.2.2 | Latest 0.11 patch with the latest Telescope tag. |
| current | v0.12.6 | master at `1e1bab7` | What controlk is developed on. Pinned, so PRs do not move under us. |

Plenary is pinned to one commit that passes all three legs. The builder chooses
it and checks it on each. floating-claude.nvim uses `74b06c6`, which has not
been run here.

### Workflow

- `ci.yml`, one job with a four-entry `include:` matrix. Each entry sets the
  Neovim version and the Telescope ref. The steps are: check out the repo, check
  out plenary at its pin, check out Telescope at the leg's ref into `.tests/`,
  install Neovim with `rhysd/action-setup-vim` at a pinned version, install
  clangd and ripgrep, then run `make test` and `make test-integration`.
- An aggregator job named `tests`, like floating-claude's, so a branch ruleset
  has one required check whatever the matrix size.
- A stylua job, as floating-claude has. It needs a `.stylua.toml`, which goes in
  the repo (see Minor calls).
- `compat.yml`, weekly. It runs the current pair against the newest Telescope
  `master` commit, and nightly Neovim on each OS. On failure it opens or comments on one `compat` issue, as
  floating-claude does.

### Harness and Makefile

- `make test` runs the unit specs. They do not load Telescope, as today.
- `make test-integration` runs the `lsp` and `config` sessions of
  `tests/integration/run.lua`. It takes `TELESCOPE_DIR` (default: the lazy path),
  the same way `PLENARY_DIR` works in floating-claude's Makefile.
- The `NVIM` variable selects the Neovim binary. CI sets it per leg.

### Deprecation policy

The owner's rule, 2026-11-18: a deprecation fails the run only when controlk's own code
can change to remove it. Otherwise it is an error only in the CI deprecation check.

- A hook in the test init wraps `vim.deprecate` before any plugin loads. It is for
  tests only. The product code is not touched.
- When a deprecation is reported, the hook takes the deprecated function's caller:
  the frame one level above the function that called `vim.deprecate`.
  - If that caller is in `lua/controlk/` or `tests/`, controlk's code calls the
    deprecated feature. The hook raises an error at once, and the test run fails.
  - Otherwise the caller is Neovim, Telescope or plenary, the runtime dependencies.
    The hook writes the deprecation to a report file and lets the run continue.
    claudecode.nvim is not in this list. controlk does not use it at runtime; only
    developing controlk does.
- Runtime frames have source names that start with `@vim/`, as the probe showed. The
  builder matches that form and an absolute `$VIMRUNTIME` path.
- The CI deprecation check runs the integration legs with the report on. Any entry
  in the report is an error in that job, annotated on the PR. My addition: known
  entries go in `tests/deprecations-allow.txt`, each with its version and reason. Then
  an upstream deprecation we cannot change does not turn every PR red, while a new
  entry still fails until someone allows it on purpose.
- Edge case under this rule: controlk calls a Neovim function that is not deprecated,
  and that function calls a deprecated one inside Neovim. The caller is Neovim, so the
  entry goes to the report. If it keeps appearing, the owner decides whether to change
  our call.
- `termopen()` is version-guarded in `util.terminal`. `vim.deprecate` never sees it,
  because it is a Vim function. A static check, if built, must accept it inside that
  branch.
- Telescope v0.2.0 does not call `vim.deprecate` (a grep of its source, not a run). So
  the hook cannot see Telescope's own deprecations. A Telescope `@deprecated`
  annotation on a function controlk calls needs a static check. Today controlk calls
  none. The builder adds the check if it is cheap, and otherwise records the gap.
- Only deprecations are errors. Warnings and errors from `vim.notify` are not.

### Acceptance

- Each leg passes `make test` and `make test-integration` locally, with `NVIM`
  and `TELESCOPE_DIR` set to that pair.
- The hook has its own spec. One case calls `vim.deprecate` from a controlk file
  and must fail. Another calls it from a Telescope file and must pass.
- The PR runs four legs and the aggregator, all green.
- The harness asserts that `!`, the `cm` build and the `ct` run open a `terminal`
  buffer, on every leg. Done 2026-11-18.
- The harness runs once with telescope-fzf-native loaded. Without that, a sorter bug
  broke the picker in the owner's config, and the harness did not notice.
- The README's Neovim floor moves from 0.11 to 0.10.4 only after the floor leg is
  green in CI. The README lists the four pairs and claims nothing wider. T12 is closed by this.

## Evidence from this session

Local runs, not CI. The 25/25 rows predate the terminal fix, which added four checks. After it, every leg passes all 29 LSP checks and all 6 config checks. The deprecation counts were measured before the fix.

| Neovim | Telescope | Unit | LSP session | Config session | Deprecation calls |
|---|---|---|---|---|---|
| v0.10.4 | v0.2.0 | 36/36 | 29/29 | 6/6 | 0 in LSP session |
| v0.10.4 | v0.1.9 | 36/36 | 29/29 | 6/6 | 0 in LSP and config sessions |
| v0.10.4 | v0.1.8 | | 25/25 | | |
| v0.12.6 | master `1e1bab7` | 36/36 | 29/29 | 6/6 | 0 in LSP session |
| v0.11.7 | v0.2.2 | 36/36 | 29/29 | 6/6 | not run |

Not checked: the deprecation hook over the config session for v0.2.0 and master. The unit suite does not load Telescope, so its 36/36 says nothing
about the Telescope pairs. The harness does not check what a terminal source
opens, so these runs say nothing about terminal buffers on 0.10.4 (see
Constraints).

## Minor calls (mine, for the builder to keep or change)

- Neovim downloads use `rhysd/action-setup-vim`, pinned to a release tag.
- Formatting always uses the owner's own `.stylua.toml` (column width 100, sorted
  requires, parentheses kept), copied into the repo. The owner's CLAUDE.md says they format with
  stylua. The formatting pass with that config changed 10 Lua files, and it is its own commit. `.stylua.toml` in the repo is the owner's file, so `stylua --check .` uses it.
- The weekly job covers Telescope `master` and Neovim nightly, on each OS. It runs
  once a week and blocks nothing.
- Linting: `.luacheckrc` (LuaJIT, lines up to 100 columns, like the owner's stylua).
  `make lint` runs `stylua --check .` and luacheck over `lua` and `tests`. `make format`
  runs stylua.

## Left to the builder

- Exact workflow YAML, Makefile targets, and the hook's file and name.
- Which plenary commit passes all three legs.
- Which clangd version the runner installs, and whether it matches the one the
  probes used (23.1).
- Whether the static `@deprecated` check is cheap enough to include now.
- The release workflow, `RELEASING.md`, `lua/controlk/version.lua`, and the seed
  `CHANGELOG.md`, all as described in the Release plan below.
- Package names for clangd, cmake, ninja and ripgrep on each runner, and the
  pinned clangd version.
- The harness stubs and any path or process fixes that Windows and macOS need.

## Release gate

The release gate runs on each release-candidate tag and on the final tag. It is
the PR matrix widened to every OS, plus nightly.

| Check | Legs | Blocks the release |
|---|---|---|
| The four pairs on each OS | 4 pairs × ubuntu, macos, windows = 12 | yes |
| stylua check | 1 | yes |
| Doc check | 1, once vimdoc exists (T6) | yes |
| Manual smoke test | the owner, checklist below | yes |
| Weekly scheduled job: drift, and nightly Neovim × Telescope master on each OS | scheduled | no |

Runner packages: on each OS, install clangd, cmake, ninja, ctest and ripgrep
with that OS's package manager. Pin the clangd version, because it shapes the
LSP session's results; the probes used clangd 23.1.

A release claims only what passed. If one OS leg fails, the release is blocked.
The owner can waive an OS, with the reason written into the CHANGELOG and the
README. That is a decision made for one release, not a default.

Manual smoke test, on the release candidate, with the owner's own Neovim
config:

1. Install the RC tag from a fresh clone.
2. `:checkhealth controlk` shows no error (needs T5 first).
3. In a real CMake project: `c`, `m`, `:`, and `cm` building one target, `ct`
   running the tests, and `r` opening a search URL.
4. Record the Neovim and Telescope versions used in the RC notes.

## Release plan

### Versioning

- Semver over the public surface: the `setup()` options and their keys, the
  prefix and source ids, the commands, `require("controlk").open`, and the
  `telescope` extension name. Internal modules are not public.
- Before 1.0 (my call): a fix is a patch. A feature, or a new supported Neovim or
  Telescope pair, is a minor. A breaking change or a dropped pair is also a minor,
  and becomes a major at 1.0.
- `lua/controlk/version.lua` holds the version. The release workflow fails if it,
  or the CHANGELOG heading, does not match the tag.

### Tags and branches

- Tags are `vX.Y.Z`, annotated. Release candidates are `vX.Y.Z-rc.N`. A tag is
  never moved or reused. A bad release gets a new patch.
- Releases come from `main`. A `support/X.Y` branch is created only when a newer
  major ships and the older one still needs fixes.
- Distribution: the GitHub release and its git tag. No LuaRocks for now (my call).
  Telescope publishes to LuaRocks, but controlk does not need it yet.
- Telescope's tags are inconsistent (`0.1.8` against `v0.2.0`), and its release
  workflow fires on any tag with no test gate. This plan copies neither.

### Files

- `CHANGELOG.md` in Keep a Changelog format. Each release lists the four pairs it
  was tested with under `### Compatibility`, the same convention as
  floating-claude.nvim.
- `RELEASING.md`: the checklist below, written by the builder.

### Steps

1. Pre-flight: `main` is green on the PR matrix, no blocker is open, and
   `## [Unreleased]` lists what changed.
2. Release PR on `release/X.Y.Z`: bump `version.lua`, move Unreleased into
   `## [X.Y.Z] - date`, and update the README's pairs. Merge once the PR matrix
   is green.
3. Tag `vX.Y.Z-rc.1` on the merge commit. The release gate runs.
4. Run the manual smoke test. Record the result in the RC notes.
5. If a blocking check fails: fix on `main` by PR, then tag `rc.2`. The RC number
   goes up. The tag does not move.
6. When the gate is green and the smoke test passes, tag `vX.Y.Z` on the same
   commit. The workflow checks that a green RC exists for that commit, and that
   `version.lua` and the CHANGELOG heading match. Then it publishes the GitHub
   release, using the CHANGELOG section as the notes.
7. Afterwards: the weekly drift job follows the new tag, and `## [Unreleased]`
   is reset.

### Rollback

A bad release gets a new patch, and its GitHub release is edited to say so. The
tag stays.

### Acceptance for the plan

- A dry-run RC on a throwaway tag passes every blocking leg on the three OSes.
- A throwaway tag whose `version.lua` does not match is refused by the workflow.
- The checklist is followed end to end once, on the first real RC.

### Decisions for the owner

- Windows and macOS block the release. (My pick.)
- Nightly runs once a week in the scheduled job, not in the release gate. (Adopted
  from the owner's suggestion.)
- The pre-1.0 Semver rules above.
