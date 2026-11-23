# Changelog

All notable changes to controlk are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) as RELEASING.md describes: before 1.0,
a feature or a breaking change is a minor version, a fix is a patch.

## [Unreleased]

### Added

- One Telescope picker, `:Telescope controlk`, that switches source by prefix: open buffers `b`,
  project files `p`, file system `f`, line `l`, help `?`, Ex commands `:`, marks `'`, Lua value
  `=`, run Lua `lua`, shell `!`, web search `w`, workspace symbols `s`, classes `c`, functions
  `m`, document symbols `.`, references to a symbol by name `r`, CMake targets `cm`, target
  definitions `cmo` and CTest tests `ct`.
- With text and no prefix, the locator browses the file system; Enter on a directory goes into it.
- The locator opens on the list of prefixes and shows only prefixes until a space is typed.
  `?` alone shows the list too; `? text` searches help, `:help`'s own matches first, then fuzzy.
- `:` runs what you typed as an Ex command from its first row, as `!` does for the shell. After
  a command and a space, the list completes its arguments as `<Tab>` does (`: set tabst`).
- `lua` runs Lua as `:lua` does, and completes it as `<Tab>` does. `=` still shows a value.
- What `:` and `lua` run reports its output and errors with `vim.notify`.
- Enter on an empty list, or on a hint, opens the help section of that source.
- User-defined sources with their own prefix (`sources`), with the item contract in
  `:h controlk-custom-sources`. A source that raises an error, calls back twice or never calls
  back cannot break the locator: it shows as a hint, and the default view lists the others.
- Styles: any Telescope layout or theme, and `cutie`, after Qt Creator's locator (bottom left,
  60 columns by default).
- The `Direct` web engine opens the typed address itself.
- `files = { hidden, ignored }` lets `p` list dotfiles and git-ignored files.
- Workspace symbols are asked from the project's language servers even from a buffer they are
  not attached to, and hints say when results may be incomplete: a server still indexing, a reply
  at `lsp.result_limit`, or no server running yet.
- `:checkhealth controlk`, including where clangd finds `compile_commands.json`.
- The CMake "Configure project" item exports `compile_commands.json`.
- Warnings for unknown options and invalid values.

### Compatibility

The release gate tests these pairs on Linux, macOS and Windows:

- Neovim 0.10.4 and Telescope v0.1.9
- Neovim 0.10.4 and Telescope v0.2.0
- Neovim 0.11.7 and Telescope v0.2.2
- Neovim 0.12.6 and Telescope master (`1e1bab7`)
