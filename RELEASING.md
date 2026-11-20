# Releasing controlk

The plan behind this checklist is in `docs/superpowers/specs/2026-11-18-version-matrix-design.md`
("Release gate" and "Release plan"). A tag is never moved or reused: a failed candidate gets the
next `rc` number, and a bad release gets a new patch.

## Versions

Semver over the public surface: the `setup()` options and their keys, the prefixes and source
ids, the commands, `require("controlk").open`, and the Telescope extension name. Internal modules
are not public. Before 1.0, a fix is a patch, and a feature, a new supported Neovim or Telescope
pair, a breaking change or a dropped pair is a minor.

## Checklist

1. Pre-flight: `main` is green, no blocker is open, and `## [Unreleased]` in `CHANGELOG.md` lists
   what changed.
2. Release PR on `release/X.Y.Z`: set `lua/controlk/version.lua` to `X.Y.Z`, rename
   `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` (and start a new empty `## [Unreleased]`), and
   check the README's tested pairs and the `### Compatibility` list. Merge once CI is green.
3. Tag the merge commit and push the tag:

       git tag -a vX.Y.Z-rc.1 -m "controlk X.Y.Z, release candidate 1" <merge commit>
       git push origin vX.Y.Z-rc.1

   `release.yml` runs the gate: the four pairs on ubuntu, macOS and Windows, lint, and the doc
   check. When it passes, it publishes the candidate as a pre-release.
4. Smoke test the candidate with a real configuration, and write the result in the pre-release
   notes:
   - Install the rc tag from a fresh clone.
   - `:checkhealth controlk` shows no error.
   - In a real CMake project: `c`, `m`, `s`, `cm` building one target, `ct` running the tests,
     and `w` opening a search URL.
   - Record the Neovim and Telescope versions used.
5. If a blocking check fails, fix it on `main` by PR, and tag `rc.2` on the new merge commit.
6. When the gate is green and the smoke test passed, tag `vX.Y.Z` on the same commit as the
   passing candidate. The workflow refuses it unless a green rc exists for that commit and
   `version.lua` and the CHANGELOG heading match. It then publishes the release with the
   CHANGELOG section as its notes.
7. Afterwards: reset `## [Unreleased]`, and let the weekly `compat.yml` job follow the new pins.

## Dry run

A tag `dryrun-vX.Y.Z[-rc.N]` runs every check of the gate and publishes nothing. Delete it
afterwards (`git push origin :refs/tags/dryrun-...`); it is not a release tag.

## Waiving an OS

A release claims only what passed. If one OS leg fails and cannot be fixed in time, only the
maintainer can waive it, for that release, with the reason written in the CHANGELOG and the
README.
