-- Test-only hook around vim.deprecate. The product code is not touched.
--
-- The rule: a deprecation fails the run only when controlk's own code can change to
-- remove it. So the hook looks at the caller of the deprecated feature, debug.getinfo(3):
-- level 1 is this wrapper, 2 the feature that called vim.deprecate, 3 the feature's caller.
-- C frames such as pcall are skipped, up to the first Lua caller.
--   - Caller under <root>/lua/ or <root>/tests/: controlk calls the deprecated feature. The hook
--     records it with a "controlk" mark and raises an error at once.
--   - Any other caller (Neovim, Telescope, plenary, anything in .tests/): the hook appends
--     `name<TAB>source:line` to the report and calls the real function.
-- tests/check_deprecations.lua reads the report afterwards.
local M = {}

local function starts_with(s, prefix)
  return s:sub(1, #prefix) == prefix
end

local function append(path, line)
  local f = assert(io.open(path, "a"))
  f:write(line, "\n")
  f:close()
end

--- Wraps vim.deprecate. Safe to call again, for example with another report path.
---@param root string repository root, without a trailing slash
---@param report string|nil file to append entries to; nil keeps no report
function M.install(root, report)
  -- Kept in a global, so a second install wraps the real function, not the previous wrapper.
  _G.__controlk_real_deprecate = _G.__controlk_real_deprecate or vim.deprecate
  local real = _G.__controlk_real_deprecate
  -- Exact prefixes: <root>/.tests/ holds the dependencies and must not match <root>/tests/.
  local ours = { "@" .. root .. "/lua/", "@" .. root .. "/tests/" }

  if report and report ~= "" then
    -- Absolute, because the integration harness changes directory into its fixtures.
    report = vim.fn.fnamemodify(report, ":p")
    -- Created now, so the check can tell "no deprecations" from "hook never ran". Append mode
    -- keeps what an earlier session in the same run wrote.
    assert(io.open(report, "a")):close()
  else
    report = nil
  end

  vim.deprecate = function(name, ...)
    -- A C function between the feature and its caller (pcall, xpcall) has no code to change,
    -- so the caller is the first Lua frame above it.
    local level = 3
    local info = debug.getinfo(level, "Sl")
    while info and info.what == "C" do
      level = level + 1
      info = debug.getinfo(level, "Sl")
    end
    local source = info and info.source or "?"
    local where = source:gsub("^@", "") .. ":" .. tostring(info and info.currentline or "?")
    local own = starts_with(source, ours[1]) or starts_with(source, ours[2])
    if report then
      append(report, name .. "\t" .. where .. (own and "\tcontrolk" or ""))
    end
    if own then
      error(("controlk calls deprecated %s at %s"):format(name, where), 0)
    end
    return real(name, ...)
  end
end

return M
