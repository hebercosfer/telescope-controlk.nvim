# telescope-controlk.nvim

One picker for everything, selected by a prefix, in the style of Qt Creator's Locator (Ctrl+K).
Type nothing to browse the file system. Type a prefix and a space to switch to a source: project
files, symbols, CMake targets, help, commands and more.

## Requirements

- Neovim 0.10.4 or newer
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) and
  [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

Optional: ripgrep (faster file listing; git is the fallback), a language server for the symbol
sources, and cmake and ctest for the CMake sources. `:checkhealth controlk` tells you what is
missing.

CI tests these pairs on every change:

| Neovim | Telescope |
|---|---|
| 0.10.4 | v0.1.9 |
| 0.10.4 | v0.2.0 |
| 0.11.7 | v0.2.2 |
| 0.12.6 | master |

## Install

```lua
{
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
},
{
  "hebercosfer/telescope-controlk.nvim",
  dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
  config = function()
    require("telescope").load_extension("controlk")
  end,
},
```

The locator is mapped to `<leader>k` in normal mode when the extension loads, using the leader
set at that moment: set `mapleader` before your plugin manager loads plugins, as most
configurations already do. Choose another key with `keymap` in the configuration below, or set
`keymap = false` to map nothing. A key you have mapped yourself is never taken over.

Qt Creator's own key, Ctrl+K, is not the default because most Neovim configurations use it to move
between splits. If yours does not, `keymap = "<C-k>"` gives you the Qt Creator key. You can also
map it yourself:

```lua
vim.keymap.set("n", "<C-k>", "<cmd>Telescope controlk<cr>", { desc = "Locator" })
```

## Sources and prefixes

| Prefix | Source | Enter does | Needs |
|---|---|---|---|
| (none) | the file system, as `f`, and a line number, as `l` | open, or enter the directory | |
| `b` | open buffers | open | |
| `p` | files in the project | open | rg or git |
| `l` | line, or `line:column`, in the current buffer | jump | |
| `f` | file system from the project root, prefix match on names | open, or enter the directory | |
| `?` | alone, the prefixes in this table; with text, Neovim help tags | puts the prefix in the prompt, or opens the help | |
| `:` | Ex commands; the first row runs what you typed (`: w`, `: 42`), and after a space the list completes the arguments as `<Tab>` does | runs it (output and errors as notifications), or fills the prompt | |
| `'` | marks | jump | |
| `=` | Lua expression | copies the result | |
| `lua` | runs Lua, as `:lua`; the list completes it as `<Tab>` does | runs it (output and errors as notifications), or fills the prompt | |
| `!` | shell command | runs in a terminal | |
| `w` | web search engines | opens the URL | |
| `s` | workspace symbols | jump | LSP with `workspace/symbol` |
| `c` | workspace classes, structs, enums | jump | LSP |
| `m` | workspace functions, methods, constructors | jump | LSP |
| `.` | symbols in the current document | jump | LSP with `textDocument/documentSymbol` |
| `r` | references to the symbol under the cursor | jump | LSP with `textDocument/references` |
| `cm` | CMake build targets | builds in a terminal | cmake |
| `cmo` | CMake target definitions | jump | cmake |
| `ct` | CTest tests | runs in a terminal | cmake, ctest |

The locator opens on the list of prefixes, and shows only prefixes until you type a space. A
partly typed prefix narrows the list: `c` lists `c`, `cm`, `cmo` and `ct`. Enter on one replaces
the prompt with that prefix and a space and switches to its source, so Enter on `c` leaves `c ` in
the prompt, ready for a class name. Text that can become no prefix (`con`, `src/`, `42`) searches
the default view below.

`?` alone shows the same list. `? text` searches the help: first what `:help text` would offer, in
Neovim's own order, then every other tag, fuzzy matched, so `? bufgetlines` still finds
`nvim_buf_get_lines()`.

With text and no prefix, the locator browses the file system like `f`: it opens on the project root (the
git root of the current buffer), narrows by the start of each name, and Enter on a directory goes
into it (`src/` becomes the prompt), while Enter on a file opens it. You can type a path too:
`src/wid`, `~/notes/`, `/etc/`. A number jumps to that line, as `l` does. To search open buffers
and every project file instead, as `b` and `p` do, set
`default_sources = { "buffers", "files", "lines" }`.

When nothing matches, or only a hint is shown, Enter opens the help for the source you typed
(`:h controlk-source-<id>`), so you can see what it expects.

Prefixes must be followed by a space: `c Widget` searches classes for `Widget`, while `c` on its own
searches the project. The longest matching prefix wins, so `cm` never triggers `c`.

Symbol sources need at least one character: language servers cap an empty query (clangd returns
100 results, mostly from the standard library), so the picker asks you to type instead.

### Your own sources

The `sources` option adds sources with their own prefix. They show in the `?` list and in prefix
suggestions like the built-ins:

```lua
extensions = {
  controlk = {
    sources = {
      todo = {
        prefix = "td",
        title = "TODO comments",
        items = function(query, ctx, done)
          -- Call done once, now or later, with a list of items.
          done({ { text = "fix the parser", path = ctx.root .. "/parse.lua", lnum = 12 } })
        end,
      },
    },
  },
},
```

An item is a plain table: `text`, and optionally `detail`, `tag`, `path`, `bufnr`, `lnum`, `col`,
`run`, `passthrough` (the source already filtered its rows, so fuzzy matching keeps them all),
`ordinal`, `hint`, `prompt` and `pinned`. `:h controlk-custom-sources` describes each field, `ctx`,
and a live-grep example. Call `done` on the main loop: wrap it in `vim.schedule` inside a
`vim.system` callback.

Symbols come from your language servers' indexes, so `s`, `c` and `m` work with any server that
supports `workspace/symbol`. Many servers index the project in the background when they start, and
until they finish the results are partial; the locator says so while it lasts, and also when a
reply looks cut at the server's result cap (`lsp.result_limit`). Since controlk follows Qt Creator,
a C++ IDE, the help also covers clangd: it needs `compile_commands.json`, which the CMake
"Configure project" item exports. `:h controlk-lsp` explains both.

CMake sources use CMake's File API, so they work with Makefiles, Ninja and other generators. The
build directory is the first one under the project that contains a `CMakeCache.txt`. If none
exists, the picker offers a "Configure project" item.

## Styles

`style` chooses how the locator looks. Every Telescope layout and theme is a style, and `cutie`
is controlk's own:

| Style | Fits a locator | Notes |
|---|---|---|
| `default` | yes | Telescope's own default, from your `telescope.setup` (normally `horizontal`) |
| `flex` | yes, suggested | `horizontal` on wide screens, `vertical` on narrow ones |
| `horizontal` | yes | list on the left, preview on the right; no preview under 120 columns |
| `vertical` | yes | preview above the list; for tall or narrow screens |
| `ivy`, `bottom_pane` | yes, suggested | a full-width pane at the bottom of the screen |
| `dropdown`, `center` | yes | a compact box in the middle; the preview is small on small screens |
| `cutie` | yes | after Qt Creator's locator (see below) |
| `cursor` | no | the theme: a 23-column list that opens wherever the cursor is |
| `current_buffer` | no | covers the window you are working in, preview over your code |

The two that do not fit work, with a warning. `layout_config` is passed to Telescope as is for
the Telescope styles. For one call, `:Telescope controlk style=ivy`. Telescope's own `theme=` and
`layout_strategy=` still work, and win over `style`.

### Cutie

`style = "cutie"` looks like Qt Creator's locator: a small prompt in the bottom-left corner, right
above the status line, with the list above it and the preview to its right. An empty prompt
lists the prefixes. The best match is the row right above the prompt.

```
┌──────────────────────────────────────────────────────────────────────┐
│                       your code, untouched                           │
├────────────────────────────┬─────────────────────────────────────────┤
│ class  Whatever   core     │ widget.h                                │
│ class  Wing                │ 12  class Widget : public QObject {     │
│ class  Widget     ui       │ 13    Q_OBJECT                          │
├────────────────────────────┤ 14  public:                             │
│ > c W                      │ 15    void repaint();                   │
├────────────────────────────┴─────────────────────────────────────────┤
│ status line and command line stay visible                            │
└──────────────────────────────────────────────────────────────────────┘
```

- `cutie.width`: columns of the prompt and the list, 60 by default. `"auto"` matches a sidebar
  split on the left (the leftmost window at column 0, narrower than half the screen), whichever
  plugin draws it; a floating file tree is not a split, so it gives 60.
- `cutie.height`: rows of the list, 15 by default. A short screen gets fewer.
- `cutie.preview`: false turns the preview off. It is also left out when it would be narrower
  than 20 columns.

## Health check

`:checkhealth controlk` checks the Neovim version, Telescope and plenary, the tools the sources
use, your options, and, for the current project, whether clangd can find `compile_commands.json`
and which language servers answer workspace symbols. Run it first when a source lists nothing.

## Configuration

Every option is optional. These are the defaults:

```lua
require("telescope").setup({
  extensions = {
    controlk = {
      -- Normal-mode key for the locator. false maps nothing.
      keymap = "<leader>k",
      -- How the locator looks: "default", a Telescope layout or theme, or "cutie".
      style = "default",
      -- Passed to Telescope for the Telescope styles.
      layout_config = nil,
      -- The cutie style. width: columns, or "auto" to match a sidebar split on the left.
      cutie = { width = 60, height = 15, preview = true },
      -- Prefix per source. false removes the prefix.
      prefixes = {
        buffers = "b", files = "p", lines = "l", filesystem = "f", help = "?",
        commands = ":", marks = "'", eval = "=", lua = "lua", shell = "!", web = "w",
        lsp_symbols = "s", lsp_classes = "c", lsp_functions = "m", lsp_document = ".",
        lsp_references = "r",
        cmake_targets = "cm", cmake_open = "cmo", cmake_tests = "ct",
      },
      -- Your own sources, keyed by id: { prefix, title, tag, items }.
      sources = {},
      -- Sources merged when no prefix is typed. { "buffers", "files", "lines" } searches open
      -- buffers and project files instead of browsing.
      default_sources = { "filesystem", "lines" },
      -- Sources removed entirely.
      disabled = {},
      -- `p` also lists hidden (dotfiles) or git-ignored files. ignored needs rg.
      files = { hidden = false, ignored = false },
      lsp = { min_query = 1, result_limit = 100 },
      cmake = { build_dir = nil }, -- or "build", or an absolute path
      web = {
        engines = {
          -- The query itself as an address: `w neovim.io` opens https://neovim.io.
          Direct = "%s",
          Google = "https://www.google.com/search?q=%s",
          DuckDuckGo = "https://duckduckgo.com/?q=%s",
          Wikipedia = "https://en.wikipedia.org/w/index.php?search=%s",
          cppreference = "https://en.cppreference.com/index.php?search=%s",
        },
      },
    },
  },
})
```

Examples:

```lua
extensions = {
  controlk = {
    prefixes = { lsp_classes = "C", eval = false },   -- C for classes, no Lua prefix
    default_sources = { "buffers", "files" },          -- fuzzy-search buffers and files, no browsing
    disabled = { "web" },
    web = { engines = { Google = false, Neovim = "https://neovim.io/search/?q=%s" } },
  },
},
```

### Qt Creator's prefixes

The default prefixes follow Vim: `:` for Ex commands as `!` is for the shell, `b` for buffers, `'`
for marks. If your hands know Qt Creator's locator, this gives you its letters back:

```lua
prefixes = {
  buffers = "o", files = "a", commands = "t", marks = "b", web = "r",
  lsp_symbols = ":", lsp_references = false,
},
```

Configuration problems (duplicate or invalid prefixes, unknown source ids) are reported as warnings
when the extension is set up.

## Tests

```sh
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
```

The parsers (prompt, configuration, CMake model, CTest output, LSP kinds) are covered by unit tests
with real CMake and CTest output as fixtures.

The picker is covered by an integration harness that types into the real Telescope prompt, against
clangd and a sample CMake project. It needs clangd, cmake (Ninja) and ctest:

```sh
SESSION=lsp    nvim --headless -u NONE --cmd "set rtp+=$PWD,$HOME/.local/share/nvim/lazy/telescope.nvim,$HOME/.local/share/nvim/lazy/plenary.nvim" -c "luafile tests/integration/run.lua"
SESSION=config nvim --headless -u NONE --cmd "set rtp+=$PWD,$HOME/.local/share/nvim/lazy/telescope.nvim,$HOME/.local/share/nvim/lazy/plenary.nvim" -c "luafile tests/integration/run.lua"
```

The harness works in a temporary copy of `tests/integration/fixtures`, so build output and clangd's
cache never land in the repository.

## License

MIT, see [LICENSE](LICENSE).
