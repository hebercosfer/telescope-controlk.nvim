-- Fails on any deprecation in the report that the allow-list does not name. Run with:
--   DEPRECATION_REPORT=.tests/deprecations.log nvim -l tests/check_deprecations.lua
-- The report is written by tests/support/deprecations.lua, one `name<TAB>source:line` per call.
-- A third column "controlk" marks a call from controlk's own code. That is never allowed.
-- The allow-list (DEPRECATION_ALLOW, default tests/deprecations-allow.txt) has one entry per
-- line: the deprecated name, then its Neovim or plugin version and the reason. `#` starts a
-- comment.

-- print() under `nvim -l` writes no final newline, and a GitHub annotation must start a line.
local function say(line)
  io.stdout:write(line, "\n")
end

local report = os.getenv("DEPRECATION_REPORT") or ".tests/deprecations.log"
local allow_file = os.getenv("DEPRECATION_ALLOW") or "tests/deprecations-allow.txt"

local function lines(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local out = {}
  for line in f:lines() do
    table.insert(out, line)
  end
  f:close()
  return out
end

local entries = lines(report)
if not entries then
  say("::error::No deprecation report at " .. report .. ". Did the hook run?")
  os.exit(1)
end

local allowed = {}
for _, line in ipairs(lines(allow_file) or {}) do
  local name = line:gsub("#.*", ""):match("^%s*(%S+)")
  if name then
    allowed[name] = true
  end
end

local seen, failures = {}, 0
for _, line in ipairs(entries) do
  local name, where, mark = line:match("^([^\t]+)\t([^\t]+)\t?(.*)$")
  if name and not seen[line] then
    seen[line] = true
    if mark == "controlk" then
      failures = failures + 1
      say(("::error::controlk calls deprecated %s at %s"):format(name, where))
    elseif not allowed[name] then
      failures = failures + 1
      say(("::error::Deprecated %s called at %s, not in %s"):format(name, where, allow_file))
    end
  end
end

say(("Deprecations: %d report entries, %d not allowed."):format(#entries, failures))
os.exit(failures == 0 and 0 or 1)
