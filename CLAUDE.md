# controlk: agent context

A Telescope locator modelled on Qt Creator's Locator (Ctrl+K). One picker; a prefix and a space
selects a source. Lua, Neovim 0.11+ (tested on 0.12.6), telescope.nvim master, plenary.nvim.
The owner is Heber (GitHub: hebercosfer). The task list is in TASKS.md; read it before starting work.

## Layout

- `lua/telescope/_extensions/controlk.lua`: extension registration, `:Telescope controlk`.
- `lua/controlk/init.lua`: setup and open facade.
- `lua/controlk/config.lua`: defaults, validation, `prefix_map`. Prefixes live only here.
- `lua/controlk/parse.lua`: pure prompt parser. Longest prefix wins; a space must follow it.
- `lua/controlk/picker.lua`: the only Telescope adapter (dynamic finders, source switching in
  `on_input_filter_cb`, sorter pass-through, select action).
- `lua/controlk/util.lua`: `await` (plenary oneshot), `memo`, `hint`, `terminal`, `act`, `tag_items`.
- `lua/controlk/cmake.lua`: CMake File API model reader, configure, CTest JSON parsing.
- `lua/controlk/cutie.lua`: geometry of the cutie style, pure Lua (`picker.lua` applies it).
- `lua/controlk/sources/*.lua`: one module per source. `sources/init.lua` is the registry.
- `tests/`: unit tests (plenary busted). `tests/integration/run.lua`: picker harness and fixtures.

## Rules that the design depends on

- The core is Telescope-free. Only `picker.lua` may require `telescope.*`. Keep it that way so a
  Snacks adapter stays possible.
- A source has one contract: `items(query, ctx, done)`. Items are plain tables: `text`, `detail`,
  `tag`, `path`, `lnum`, `col`, `bufnr`, `run`, `passthrough`, `hint`, `prompt`, `pinned`. A source
  must not assume a UI.
- `prompt` means picking the item replaces the input with that text instead of acting (the `?`
  list, prefix suggestions). `pinned = true` means the item ranks before every unpinned item, in
  its own order (prefix suggestions).
- `passthrough = true` means the source already filtered the results (LSP server, shell, web,
  eval, filesystem). Fuzzy matching must not drop them.
- Workspace-symbol sources need at least `lsp.min_query` characters. clangd caps an empty query at
  100 results, mostly from the standard library, so an empty query would mislead.
- Never `:edit` a file that is already open. It reloads the buffer and detaches its LSP clients.
  `util.act` uses `bufadd` and `nvim_set_current_buf` for that reason.
- Callbacks from `vim.system` and LSP handlers can run in a fast-event context. Anything that calls
  `vim.fn` or touches buffers must run on the main loop: wrap it in `vim.schedule`. `util.await`
  already does this.
- Do not patch upstream plugins (telescope, noice, nvim-lspconfig). Work around them in this code
  or report them.

## Commands

Unit tests (run from the repository root):

    nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

Integration harness (needs clangd, cmake with Ninja, ctest; see the header of `tests/integration/run.lua`):

    SESSION=lsp    nvim --headless -u NONE --cmd "set rtp+=$PWD,$HOME/.local/share/nvim/lazy/telescope.nvim,$HOME/.local/share/nvim/lazy/plenary.nvim" -c "luafile tests/integration/run.lua"
    SESSION=config (same command)

Both must pass before a commit. The last recorded results: unit 76/76; LSP+CMake 48/48;
config 15/15; 0 deprecations. `make test` and `make test-integration` run the same suites; the second also runs
the deprecation check. Run single specs through the directory runner: `PlenaryBustedFile` ignores
`tests/minimal_init.lua` and loads the owner's own config, so the deprecation hook is missing there.

Indentation is 2 spaces. The owner formats Lua with stylua.

## Commits and remotes

- The owner's global rules (`~/.claude/CLAUDE.md`) apply. Never run `git commit` from the agent
  shell. Write the message with a heredoc to `~/.claude/cmsg.txt`, dry-run with the pathspec, then
  open a tmux window: `tmux new-window -n commit -c <repo> "git commit -e -v -F ~/.claude/cmsg.txt -- <paths>"`.
- No `Co-Authored-By` or other trailers.
- New files need `git add -N <path>` first, because pathspecs cannot match untracked files.
- Join pathspecs with spaces, never newlines: `FILES=$(git ls-files | tr '\n' ' ')`. A newline
  list made tmux run each path as a separate shell command, and the first commit ended up with one
  file (TASKS.md, T1).
- Do not push, and do not create a GitHub repository, without an explicit yes from the owner.
- Amend only when the owner asks for an amend.

## Other context

- The owner's Neovim config is `~/Workspace/mDotFiles/nvim/.config/nvim` (symlinked from
  `~/.config/nvim`). It is a separate repository. Its `lua/config/options.lua:28` maps normal-mode
  `<c-k>` to window navigation, so the locator cannot use `<C-k>` until that is resolved (TASKS.md, T2).
- The owner's dotfiles are not part of this project. Do not change them from here.
