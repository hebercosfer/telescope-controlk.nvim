local marks = require("controlk.sources.marks")

local function list(query, buf)
  local items
  marks.items(query, { origin_buf = buf or 0 }, function(result)
    items = result
  end)
  return items
end

local function by_mark(items)
  local found = {}
  for _, item in ipairs(items) do
    found[item.text] = item
  end
  return found
end

describe("marks source", function()
  local dir = vim.fn.tempname()
  local other = dir .. "/Quirks/notes.txt"
  local target = dir .. "/src/main.cpp"

  before_each(function()
    vim.fn.mkdir(vim.fs.dirname(other), "p")
    vim.fn.mkdir(vim.fs.dirname(target), "p")
    vim.fn.writefile({ "a", "b" }, other)
    vim.fn.writefile({ "a", "b" }, target)
    vim.cmd.edit(other)
    vim.api.nvim_buf_set_mark(0, "Z", 2, 0, {})
    vim.cmd.edit(target)
    vim.api.nvim_buf_set_mark(0, "Q", 2, 0, {})
  end)

  after_each(function()
    vim.cmd("delmarks Q Z")
    vim.cmd("%bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  it("pins the mark the query names, above a mark whose path holds that letter", function()
    -- Z's path, .../Quirks/..., fuzzy-matches "Q" as well as Q itself; Enter must jump to Q.
    local found = by_mark(list("Q"))
    assert.is_true(found.Q.pinned)
    assert.is_nil(found.Z.pinned)
  end)

  it("pins nothing for a query that names no mark", function()
    for _, item in ipairs(list("main")) do
      assert.is_nil(item.pinned)
    end
  end)

  it("ignores spaces around the mark name", function()
    assert.is_true(by_mark(list(" Q "))["Q"].pinned)
  end)
end)
