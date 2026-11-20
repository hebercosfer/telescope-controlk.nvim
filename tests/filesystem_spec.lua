local filesystem = require("controlk.sources.filesystem")

local root

local function list(query)
  local items
  filesystem.items(query, { root = root }, function(result)
    items = result
  end)
  return items
end

local function find(items, text)
  for _, item in ipairs(items) do
    if item.text == text then
      return item
    end
  end
end

describe("filesystem source", function()
  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/lua/controlk", "p")
    vim.fn.writefile({}, root .. "/README.md")
    vim.fn.writefile({}, root .. "/.hidden")
    vim.fn.writefile({}, root .. "/lua/init.lua")
  end)

  after_each(function()
    vim.fn.delete(root, "rf")
  end)

  it("lists the root with directories first, hidden entries included", function()
    local texts = vim.tbl_map(function(item)
      return item.text
    end, list(""))
    assert.are.same({ "lua/", ".hidden", "README.md" }, texts)
  end)

  it("narrows by the start of the name, ignoring case", function()
    local items = list("re")
    assert.are.equal(1, #items)
    assert.are.equal(root .. "/README.md", items[1].path)
  end)

  it("gives a directory the query that enters it, keeping what was typed", function()
    assert.are.equal("lua/", find(list(""), "lua/").query)
    assert.are.equal("lua/controlk/", find(list("lua/"), "controlk/").query)
    assert.is_nil(find(list("lua/"), "init.lua").query)
  end)

  it("keeps an absolute path absolute", function()
    assert.are.equal(root .. "/lua/", find(list(root .. "/"), "lua/").query)
  end)

  it("lists nothing, without an error, for a directory that does not exist", function()
    vim.v.errmsg = ""
    assert.are.same({}, list("nothere/"))
    assert.are.equal("", vim.v.errmsg)
  end)
end)
