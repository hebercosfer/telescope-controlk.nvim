local config = require("controlk.config")
local prefixes = require("controlk.sources.prefixes")

local function list(user)
  local cfg = config.resolve(user)
  local items
  prefixes.items("", { config = cfg }, function(result)
    items = result
  end)
  return items
end

local function find(items, prefix)
  for _, item in ipairs(items) do
    if item.tag == prefix then
      return item
    end
  end
end

describe("prefixes source", function()
  it("is reached with ? and help tags move to h", function()
    local cfg = config.resolve({})
    assert.are.equal("prefixes", cfg.prefix_map["?"])
    assert.are.equal("help", cfg.prefix_map["h"])
  end)

  it("lists every other prefix once, with its source's title", function()
    local items = list()
    local cfg = config.resolve({})
    assert.are.equal(vim.tbl_count(cfg.prefix_map) - 1, #items)
    assert.is_nil(find(items, "?"))
    assert.are.equal("Workspace classes", find(items, "c").text)
    assert.are.equal("CMake build targets", find(items, "cm").text)
  end)

  it("puts the prefix and a space in the prompt when picked", function()
    local item = find(list(), "cmo")
    assert.are.equal("cmo ", item.prompt)
  end)

  it("sorts the list by prefix", function()
    local shown = vim.tbl_map(function(item)
      return item.tag
    end, list())
    local sorted = vim.deepcopy(shown)
    table.sort(sorted)
    assert.are.same(sorted, shown)
  end)

  it("follows the configured prefixes", function()
    local items = list({ prefixes = { lsp_classes = "cl", web = false } })
    assert.are.equal("cl ", find(items, "cl").prompt)
    assert.is_nil(find(items, "c"))
    assert.is_nil(find(items, "r"))
  end)

  it("keeps working when ? itself is moved", function()
    local items = list({ prefixes = { prefixes = "??" } })
    assert.is_nil(find(items, "??"))
    assert.is_not_nil(find(items, "o"))
  end)
end)
