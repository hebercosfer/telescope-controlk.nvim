-- The deprecation hook (tests/support/deprecations.lua). Each case builds a deprecated
-- "feature" and a caller from chunks with a chosen source name, so the hook sees the caller
-- at the path under test.
local root = vim.fn.getcwd()
local hook = dofile(root .. "/tests/support/deprecations.lua")

-- A function that calls vim.deprecate itself, as a deprecated Neovim function does.
local feature =
  assert(load("vim.deprecate('fake.old', 'fake.new', '0.99', nil, false)", "@/rt/fake.lua"))

-- Calls the feature from line 5 of a file at `path`.
local function call_from(path)
  local caller = assert(load(string.rep("\n", 4) .. "(...)()", "@" .. path))
  return function()
    caller(feature)
  end
end

local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return text
end

describe("deprecation hook", function()
  local report

  before_each(function()
    report = vim.fn.tempname()
    hook.install(root, report)
  end)

  after_each(function()
    hook.install(root, os.getenv("DEPRECATION_REPORT"))
    os.remove(report)
  end)

  it("creates the report when it is installed", function()
    assert.are.equal("", read(report))
  end)

  it("fails when controlk's code calls a deprecated feature", function()
    local ok, err = pcall(call_from(root .. "/lua/controlk/fake.lua"))
    assert.is_false(ok)
    assert.matches("fake%.old", err)
    -- Recorded as well, so a pcall in the caller cannot hide it from the CI check.
    assert.matches("^fake%.old\t.-/lua/controlk/fake%.lua:5\tcontrolk\n$", read(report))
  end)

  it("looks past a C function such as pcall to controlk's code", function()
    local path = root .. "/lua/controlk/fake.lua"
    local caller = assert(load(string.rep("\n", 4) .. "pcall(...)", "@" .. path))
    caller(feature)
    assert.matches("^fake%.old\t.-/lua/controlk/fake%.lua:5\tcontrolk\n$", read(report))
  end)

  it("reports a deprecated call made from a telescope file", function()
    local path = root .. "/.tests/telescope.nvim/lua/telescope/fake.lua"
    assert.has_no.errors(call_from(path))
    assert.are.equal("fake.old\t" .. path .. ":5\n", read(report))
  end)

  it("does not count a .tests/ dependency as controlk's code", function()
    local path = root .. "/.tests/plenary.nvim/lua/plenary/fake.lua"
    assert.has_no.errors(call_from(path))
    assert.are.equal("fake.old\t" .. path .. ":5\n", read(report))
  end)

  it("is safe to install twice", function()
    hook.install(root, report)
    local ok = pcall(call_from(root .. "/lua/controlk/fake.lua"))
    assert.is_false(ok)
    assert.matches("^fake%.old\t.-/lua/controlk/fake%.lua:5\tcontrolk\n$", read(report))
  end)
end)
