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

- **T15. User-defined sources and prefixes (owner's request 2026-11-19).** controlk part done
  2026-11-20 on `feature/task-custom-sources`: the `sources` option (`config.resolve` validates it
  and builds `source_map`, which `picker.lua` and the `?` list read instead of the registry; a
  built-in keeps its prefix on a clash), unit specs, three harness checks, and
  `:h controlk-custom-sources` with the item contract and a live-grep example. Still open: the
  owner's config part below, which waits for the owner's yes (dotfiles are a separate repo).
  Original text: today the sources
  are fixed in `sources/init.lua`; `prefixes` can only rename or remove them. Let a user's config
  add a source with its own prefix, then use it in the owner's config for their multigrep.
  - In controlk: a `sources` option, for example
    `sources = { multigrep = { prefix = "g", title = "Multi grep", items = function(query, ctx, done) ... end } }`.
    The registry accepts these next to the built-ins; `config.resolve` validates them (a
    function `items`, a valid prefix, no clash with a built-in id, the same prefix-clash report
    as today). They show in the `?` list and in prefix suggestions like any other source.
    Document the item contract (`text`, `path`, `lnum`, `col`, `passthrough`...) for users, since
    it becomes public surface.
  - In the owner's config (`~/Workspace/mDotFiles`, a separate repository): move the logic of
    `nvim/.config/nvim/lua/util/multigrep.lua` (mapped to `<leader>mg`) into a controlk source.
    It runs `rg`; the query is split on two spaces into a pattern (`-e`) and a glob (`-g`), with
    `--smart-case`. Items carry `path`, `lnum` and `col`, and `passthrough = true`, since rg
    already filtered them. Run `rg` with `vim.system` and wrap the callback in `vim.schedule`
    (fast-event rule), or reuse `util.await`. Keep `<leader>mg` working, or point it at the
    locator with the prefix typed. The owner's multigrep opens in Telescope's default layout
    today; inside controlk it takes the locator's style (cutie for the owner).
  - Acceptance: unit specs for the option's validation; a harness check that a user source
    with a prefix lists its rows, and that `?` shows it; the owner's `g pattern  *.lua` gives the
    same rows as `<leader>mg` with `pattern  *.lua`.

## Known limitations (no task yet)

- clangd returns a class and its constructor as two symbols under `:`. The picker shows both.
  Decide whether to group them.
- `f` lists directories and opens them with netrw. It does not create files, which Qt Creator does.
- `files` uses `rg --files`, which skips hidden paths. There is no option to include them.
- The picker title is fixed to "Locator".
- Telescope bug, not ours: when a resize makes the screen too narrow for the preview, Telescope
  raises `pickers.lua:204: attempt to index field 'preview' (a nil value)`. It happens with every
  style, `default` included. Not patched here (upstream rule); worth reporting to telescope.nvim.
- The harness has run only on Linux. macOS and Windows belong to the release gate.
