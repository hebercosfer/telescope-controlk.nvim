local source = require("controlk.sources.lua")

local function list(query)
  local items
  source.items(query, {
    cache = {},
    origin_win = vim.api.nvim_get_current_win(),
    config = { prefix_map = { lua = "lua" } },
  }, function(r)
    items = r
  end)
  return items
end

describe("lua source", function()
  local notified
  local notify = vim.notify
  before_each(function()
    notified = {}
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end
  end)
  after_each(function()
    vim.notify = notify
  end)

  it("runs a statement from its first row", function()
    local row = list("vim.g.controlk_lua_probe = 5")[1]
    assert.is_true(row.pinned)
    row.run(row)
    assert.are.equal(5, vim.g.controlk_lua_probe)
    assert.are.same({}, notified)
  end)

  -- plenary's busted replaces the global print to capture test output, so this echoes
  -- instead; the harness checks print itself.
  it("notifies what the chunk writes", function()
    local row = list("vim.api.nvim_echo({ { tostring(6 * 7) } }, false, {})")[1]
    row.run(row)
    assert.are.same({ { msg = "42", level = vim.log.levels.INFO } }, notified)
  end)

  it("notifies a syntax error", function()
    local row = list("x = = 1")[1]
    row.run(row)
    assert.are.equal(vim.log.levels.ERROR, notified[1].level)
    assert.matches("^E5107: Lua: unexpected symbol", notified[1].msg)
  end)

  it("completes Lua names below the run row", function()
    local items = list("vim.api.nvim_buf_get_l")
    assert.are.equal("nvim_buf_get_lines", items[2].text)
    assert.are.equal("lua vim.api.nvim_buf_get_lines", items[2].prompt)
  end)

  it("lists the globals for an empty query, with no run row", function()
    local items = list("")
    assert.is_true(#items > 10)
    assert.is_nil(items[1].run)
  end)
end)
