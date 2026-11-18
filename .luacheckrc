-- Lint settings for luacheck, run by `make lint` over lua/ and tests/.
-- The line length follows the owner's .stylua.toml (column width 100).

std = "luajit"
codes = true
cache = true
self = false

-- Unused arguments are how callbacks name what they ignore, so they are not
-- reported. Setting a read-only global is not reported either.
ignore = { "212", "122" }

max_line_length = 100
max_comment_line_length = 100

-- The Neovim API, plus the globals that plenary's busted runner provides in tests.
read_globals = {
  "vim",
  "describe",
  "it",
  "before_each",
  "after_each",
  "pending",
  "assert",
}
