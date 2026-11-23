# controlk: roadmap

Open work, roughly in order of value. Changes go on `feature/` or `bugfix/` branches and land on
`main` by pull request, rebased (no merge commits), once CI is green. What is done is in
`CHANGELOG.md` and in the git history.

## Next

- **T7. Stream the default view.** The default view lists its sources together, once each has
  answered. Show each source's rows as they arrive instead. Acceptance: on a repository with
  about 10k files, the first rows appear before the slowest source has answered, and the
  existing tests pass.
- **T10. Included files.** A source listing the files the current file includes. clangd does not
  return includes from `workspace/symbol`; the options are `textDocument/documentLink` per file,
  or parsing `#include` lines. Write a feasibility note first, then implement the chosen way.
- **T14. Prefix icons.** When a prefix and a space are typed, show a Nerd Font icon for that
  source: a CMake icon for the CMake sources, a class symbol for classes, a globe for web search,
  and one for every other prefix. The icon belongs to the source, as a field next to `tag`, so
  the Telescope adapter and a future Snacks adapter can both draw it, and a user without a Nerd
  Font can turn it off. Acceptance: each default prefix has an icon, the prefix list shows them,
  and turning icons off leaves the text-only rows.
- **T11. Snacks adapter.** Add `lua/controlk/snacks.lua`. Sources stay unchanged; the adapter
  maps `items(query, ctx, done)` to a Snacks `finder(opts, ctx)`. Acceptance: the prefixes work
  the same way, and the LSP session's counts match the Telescope run.

## Known limitations

- clangd returns a class and its constructor as two workspace symbols, and the picker shows
  both. Grouping them is open.
- The file system browser does not create files, which Qt Creator's locator does.
- The picker title is fixed to "Locator".
- Telescope bug, not controlk's: when a resize makes the screen too narrow for the preview,
  Telescope raises `pickers.lua:204: attempt to index field 'preview' (a nil value)`, with every
  style, `default` included. It is not patched here; it belongs upstream in telescope.nvim.
