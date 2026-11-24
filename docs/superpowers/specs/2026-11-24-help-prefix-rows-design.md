# `? text` lists the matching prefixes and their help

Approved by the owner on 2026-11-24. A small change, before the 0.1.0 release.

## Why

`? text` searches Neovim's help tags. controlk's own sections are among them
(`controlk-source-marks`), but only for someone who knows the tag. The owner wants one search
to give both: the controlk prefix, to switch to it as before, and its help section, next to the
generic help.

## What `? text` lists, in this order

1. **Prefix rows** for the sources the text matches, as `?` alone shows them: Enter puts
   `<prefix> ` in the prompt and switches to that source.
2. **Help rows**, one per matched prefix: `controlk-source-<id>`, opened with `:help`.
3. **The help tags `?` lists today:** `:help`'s own matches, pinned, then every other tag,
   fuzzy matched. A tag already listed in 2 is not repeated.

Rows 1 and 2 are pinned, so they rank before everything else, in this order.

## Which prefixes match

The text, without surrounding spaces, equals the prefix (`? cm`), or the source's title
contains it, ignoring case (`? cmake` gives `cm` and `cmo`; `? symbol` gives `s`, `.`, `r`).
Not fuzzy: on short titles a fuzzy match lets `? help` reach half the list, and the rows above
the tags should be the ones meant. Prefix order is the list's own (sorted by prefix).

## Constraints and edge cases

- A user source has no section of its own: it gets a prefix row, no help row. `util.help_tag`
  falls back to `controlk-sources` for it; that fallback is not a help row here.
- Unchanged: `?` alone lists every prefix; outside `?`, a partly typed prefix narrows the list.
- The change stays in the help source and `prefixes.lua`; the picker is not touched (sources
  must not depend on the UI).

## Approaches

- **In the help source (chosen).** It already builds `? text`; it reuses `prefixes.rows` and the
  tag lookup of `util.help_tag`.
- In the picker: would make the picker know what a help row is, against the rule that the
  picker is only the Telescope adapter.

## Also

- `doc/controlk.txt`, `*controlk-source-help*`: describe the new rows.
- `CHANGELOG.md`, `[Unreleased]`: the `?` bullet is unreleased, so it is edited, not added to.
- Tests: a unit spec for the order and the matching; a harness check that Enter on a prefix row
  switches source and Enter on a help row opens the section.

## Left to the builder

The help row's `detail` text, and the names of helpers.
