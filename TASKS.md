# controlk: task list

Status as of the last session. Re-check with `git status` and `git log` before acting.

## Repository state

- Changes go on `feature/` or `bugfix/` branches and land on `main` by PR, once CI is green.
- Remote `origin` is `git@github.com:hebercosfer/telescope-controlk.nvim.git`, private.
- CI (`.github/workflows/ci.yml`) runs on every PR and on pushes to `main`: four Neovim and
  Telescope pairs, each running the unit specs and the integration harness, plus lint and an
  aggregate `tests` check. The pairs are in `docs/superpowers/specs/2026-11-18-version-matrix-design.md`.
- The harness fails on any deprecated call from controlk's own code, and on any upstream
  deprecation not named in `tests/deprecations-allow.txt` (see `tests/check_deprecations.lua`).

## Blocked on the owner

These need a decision or an explicit yes. Do not start them on your own.

- **T1. Fix the commit history.** Resolved 2026-11-18 with option (b), a second commit. `72ea0af`
  was not amended. The options are kept for the record:
  (a) amend `72ea0af` so it includes every file, reusing the existing message. This needs an
      explicit amend request from the owner;
  (b) add a second commit with the remaining files.
  Either way, use the tmux commit window (see CLAUDE.md).
- **T2. Choose the locator key.** Resolved 2026-11-18: the plugin maps `<C-k>` in normal mode by
  default, through the `keymap` option. The owner's config frees the key, because Ctrl+K is
  tmux window navigation for them.
- **T3. Create the GitHub repository and push.** Done 2026-11-18: private repository, pushed at the
  owner's request.

## Ready for an agent

Ordered by value. Each item lists its acceptance check.

- **T4. Commit the rest of the work.** Done in the second commit, with the terminal fix and the help file. Stage with `git add -N` for new files. Acceptance:
  `git ls-tree -r HEAD --name-only | wc -l` shows every file in the project, and both test suites
  still pass on that commit.
- **T5. Add `:checkhealth controlk`.** Create `lua/controlk/health.lua` using `vim.health`. Report:
  `rg` or `git` available; `cmake`, `ctest` and `cmake` with Ninja available; any configuration
  warnings from `config.resolve`. Acceptance: `nvim --headless -c "checkhealth controlk" -c "qa"`
  reports OK or WARN lines and no errors.
- **T6. Write vimdoc.** Done: `doc/controlk.txt`, written from the README. `:helptags` runs clean,
  and `:help controlk-sources` opens on 0.10.4 and 0.12.6. Generating it from annotations, as
  telescope.nvim does, is still open. Acceptance: `:help controlk` opens, and `:helptags doc`
  runs without errors.
- **T7. Stream the default view.** `run_default` in `picker.lua` waits for all default sources
  before showing anything, so a large repository shows nothing until `rg --files` finishes. Show
  buffers first and add the rest as they arrive. Acceptance: on a repository with about 10k files,
  the first buffer entries appear before the file listing completes, and the existing tests pass.
- **T8. Per-file columns for workspace symbols.** `lsp.lua` converts columns with the origin
  buffer's lines, so symbols in other files can get wrong byte columns when lines contain multibyte
  characters. Convert using the target file's lines. Acceptance: a unit test with a multibyte line
  gives the right column.
- **T9. Cover the remaining sources in the harness.** Add checks to `tests/integration/run.lua` for
  `t` (fills the command line), `b` (marks), `r` (stub `vim.ui.open` and check the URL), `f`
  (directory entry), `!` (terminal opens), `=` (result copied to the unnamed register). Acceptance:
  the LSP session still passes, and the new checks pass.
- **T10. Decide `ai` (included files).** First write a feasibility note in `TASKS.md`. clangd does
  not return includes from `workspace/symbol`; options are `textDocument/documentLink` per file or
  parsing `#include` lines. Implement only after the note is agreed with the owner.
- **T11. Snacks adapter (wish, not a requirement).** Add `lua/controlk/snacks.lua`. Sources stay
  unchanged; the adapter maps `items(query, ctx, done)` to a Snacks `finder(opts, ctx)`. Acceptance:
  the prefixes work the same way, and the LSP session's counts match the Telescope run.
- **T12. Check Neovim 0.11.** Only 0.12.6 has been tested. Run both suites on 0.11, or change the
  README's "Neovim 0.11+" claim to 0.12.
- **T13. Consider a CI workflow.** Done 2026-11-19 (PR #2), with the deprecation check added
  after it. Still to build, from the version-matrix design: the README's Neovim floor (0.10.4),
  the weekly `compat.yml` job, and the release workflow.

- **T14. Prefix icons (wish, owner's request 2026-11-19).** When a prefix and a space are typed,
  show a Nerd Font icon for that source, for example a CMake icon for `cm`, `cmo` and `ct`, a class
  symbol for `c`, and a globe or "www" for `r`. Choose an icon for every other prefix too, and check
  each one renders in the owner's font. The icon belongs to the source, as a field next to `tag`,
  so `picker.lua` and a future Snacks adapter can both draw it, and a user without a Nerd Font
  can turn it off. Acceptance: each default prefix has an icon, the `?` list shows them, and
  turning icons off leaves today's text-only rows.

## Known limitations (no task yet)

- clangd returns a class and its constructor as two symbols under `:`. The picker shows both.
  Decide whether to group them.
- `f` lists directories and opens them with netrw. It does not create files, which Qt Creator does.
- `files` uses `rg --files`, which skips hidden paths. There is no option to include them.
- The picker title is fixed to "Locator".
- The harness has run only on Linux. macOS and Windows belong to the release gate.
