# telescope-controlk.nvim

One picker for everything, selected by a prefix, in the style of Qt Creator's Locator (Ctrl+K).
Type nothing for open buffers, project files and line jumps. Type a prefix and a space to switch
to a source: symbols, CMake targets, help, commands and more.

Requirements: Neovim 0.11+ (tested on 0.12), telescope.nvim (master), plenary.nvim.
Optional: ripgrep (faster file listing; git is the fallback), a language server for symbol
sources, and cmake and ctest for the CMake sources.

## Install

```lua
{
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
},
{
  url = "git@github.com:hebercosfer/telescope-controlk.nvim.git",
  dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
  config = function()
    require("telescope").load_extension("controlk")
  end,
},
```

The locator is mapped to Ctrl+K in normal mode when the extension loads. Choose another
key with `keymap` in the configuration below, or set `keymap = false` to map nothing.
A key you have mapped yourself is never taken over. The mapping is normal mode only: in
insert mode Ctrl+K starts a digraph.

A key for the locator in your Telescope configuration is a suggestion, not something the
plugin sets:

```lua
vim.keymap.set("n", "<leader>fk", "<cmd>Telescope controlk<cr>", { desc = "Locator" })
```

## Sources and prefixes

| Prefix | Source | Enter does | Needs |
|---|---|---|---|
| (none) | open buffers, project files, line jump | open | |
| `o` | open buffers | open | |
| `a` | files in the project | open | rg or git |
| `l` | line, or `line:column`, in the current buffer | jump | |
| `f` | file system, prefix match on names | open | |
| `?` | the prefixes in this table, with what each one searches | puts the prefix in the prompt | |
| `h` | Neovim help tags | open help | |
| `t` | Ex commands | fills `:name ` for arguments | |
| `b` | marks | jump | |
| `=` | Lua expression | copies the result | |
| `!` | shell command | runs in a terminal | |
| `r` | web search engines | opens the URL | |
| `:` | workspace symbols | jump | LSP with `workspace/symbol` |
| `c` | workspace classes, structs, enums | jump | LSP |
| `m` | workspace functions, methods, constructors | jump | LSP |
| `.` | symbols in the current document | jump | LSP with `textDocument/documentSymbol` |
| `cm` | CMake build targets | builds in a terminal | cmake |
| `cmo` | CMake target definitions | jump | cmake |
| `ct` | CTest tests | runs in a terminal | cmake, ctest |

Type `?` when you do not remember a prefix: the list shows at once, without a space. Enter on an
entry replaces `?` with that prefix and switches to its source, so `?` then Enter on `c` leaves
`c ` in the prompt, ready for a class name.

A partly typed prefix suggests the prefixes it could become. `c` lists `c`, `cm`, `cmo` and `ct`
first, then the buffers, files and lines that match `c`, so nothing is lost while you decide.
Enter on a suggestion works like Enter in the `?` list.

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
above the status line, and nothing else until you type. The first character opens the list above
the prompt and the preview to its right; clearing the prompt hides them again. The best match is
the row right above the prompt.

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

- `cutie.width`: columns of the prompt and the list, 40 by default. `"auto"` matches a sidebar
  split on the left (the leftmost window at column 0, narrower than half the screen), whichever
  plugin draws it; a floating file tree is not a split, so it gives 40.
- `cutie.height`: rows of the list, 15 by default. A short screen gets fewer.
- `cutie.preview`: false turns the preview off. It is also left out when it would be narrower
  than 20 columns.

## Configuration

Every option is optional. These are the defaults:

```lua
require("telescope").setup({
  extensions = {
    controlk = {
      -- Normal-mode key for the locator. false maps nothing.
      keymap = "<C-k>",
      -- How the locator looks: "default", a Telescope layout or theme, or "cutie".
      style = "default",
      -- Passed to Telescope for the Telescope styles.
      layout_config = nil,
      -- The cutie style. width: columns, or "auto" to match a sidebar split on the left.
      cutie = { width = 40, height = 15, preview = true },
      -- Prefix per source. false removes the prefix.
      prefixes = {
        buffers = "o", files = "a", lines = "l", filesystem = "f", help = "h",
        prefixes = "?",
        commands = "t", marks = "b", eval = "=", shell = "!", web = "r",
        lsp_symbols = ":", lsp_classes = "c", lsp_functions = "m", lsp_document = ".",
        cmake_targets = "cm", cmake_open = "cmo", cmake_tests = "ct",
      },
      -- Your own sources, keyed by id: { prefix, title, tag, items }.
      sources = {},
      -- Sources merged when no prefix is typed.
      default_sources = { "buffers", "files", "lines" },
      -- Sources removed entirely.
      disabled = {},
      lsp = { min_query = 1 },
      cmake = { build_dir = nil }, -- or "build", or an absolute path
      web = {
        engines = {
          Google = "https://www.google.com/search?q=%s",
          DuckDuckGo = "https://duckduckgo.com/?q=%s",
          Wikipedia = "https://en.wikipedia.org/w/index.php?search=%s",
          cppreference = "https://en.cppreference.com/mwiki/index.php?search=%s",
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
    default_sources = { "buffers", "files" },          -- drop the line jump from the default view
    disabled = { "web" },
    web = { engines = { Google = false, Neovim = "https://neovim.io/search/?q=%s" } },
  },
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
