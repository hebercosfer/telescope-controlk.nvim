# controlk: task list

Status as of the last session. Re-check with `git status` and `git log` before acting.

## Repository state

- `HEAD` is the commit after `72ea0af`, which holds the rest of the project. `72ea0af` still
  contains only `.luarc.json`, because its commit window ran a newline-joined pathspec.
- Every file is tracked as of the second commit, including `doc/controlk.txt` and the design under
  `docs/superpowers/specs/`.
- No remote yet. Pushing waits for the owner's commit to land.

## Blocked on the owner

These need a decision or an explicit yes. Do not start them on your own.

- **T1. Fix the commit history.** Resolved 2026-11-18 with option (b), a second commit. `72ea0af`
  was not amended. The options are kept for the record:
  (a) amend `72ea0af` so it includes every file, reusing the existing message. This needs an
      explicit amend request from the owner;
  (b) add a second commit with the remaining files.
  Either way, use the tmux commit window (see CLAUDE.md).
- **T2. Choose the locator key.** `<c-k>` in normal mode is already window navigation in
  `~/Workspace/mDotFiles/nvim/.config/nvim/lua/config/options.lua:28`. Pick another key for
  `:Telescope controlk`, or move the window navigation. The README uses `<C-k>` as an example.
- **T3. Create the GitHub repository and push.** This is outward-facing. Wait for a yes.

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
- **T13. Consider a CI workflow.** Only after T3. Run the unit suite, and the integration harness with
  clangd, cmake and ctest installed.

## Known limitations (no task yet)

- clangd returns a class and its constructor as two symbols under `:`. The picker shows both.
  Decide whether to group them.
- `f` lists directories and opens them with netrw. It does not create files, which Qt Creator does.
- `files` uses `rg --files`, which skips hidden paths. There is no option to include them.
- The picker title is fixed to "Locator".
- The integration harness is not run in CI. It depends on local clangd, cmake and ctest.
