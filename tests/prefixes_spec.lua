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
    assert.is_nil(find(items, "w"))
  end)

  it("keeps working when ? itself is moved", function()
    local items = list({ prefixes = { prefixes = "??" } })
    assert.is_nil(find(items, "??"))
    assert.is_not_nil(find(items, "b"))
  end)
end)

describe("prefixes.matching", function()
  local map = config.resolve({}).prefix_map
  local function tags(rows)
    return vim.tbl_map(function(r)
      return r.tag
    end, rows)
  end

  it("lists the prefixes a partial prefix could become, in order", function()
    assert.are.same({ "c", "cm", "cmo", "ct" }, tags(prefixes.matching("c", map)))
    assert.are.same({ "cm", "cmo" }, tags(prefixes.matching("cm", map)))
  end)

  it("gives nothing for text that starts no prefix", function()
    assert.are.same({}, prefixes.matching("cmx", map))
    assert.are.same({}, prefixes.matching("Widget", map))
    assert.are.same({}, prefixes.matching("", map))
  end)

  it("marks rows pinned and fills the prompt", function()
    local row = prefixes.matching("ct", map)[1]
    assert.is_true(row.pinned)
    assert.are.equal("ct ", row.prompt)
    assert.are.equal("CTest tests", row.text)
  end)

  it("follows custom and removed prefixes, and never suggests itself", function()
    local m = config.resolve({
      prefixes = { lsp_classes = "cl", cmake_tests = false, prefixes = "c?" },
    }).prefix_map
    assert.are.same({ "cl", "cm", "cmo" }, tags(prefixes.matching("c", m)))
  end)
end)

describe("prefixes source with user sources", function()
  local user = {
    sources = {
      multigrep = {
        prefix = "g",
        title = "Multi grep",
        items = function(_, _, done)
          done({})
        end,
      },
    },
  }

  it("lists a user source with its title", function()
    local items = list(user)
    assert.are.equal("Multi grep", find(items, "g").text)
  end)

  it("suggests a user source's prefix", function()
    local cfg = config.resolve(user)
    local items = prefixes.matching("g", cfg.prefix_map, cfg.source_map)
    assert.are.equal(1, #items)
    assert.are.equal("Multi grep", items[1].text)
    assert.is_true(items[1].pinned)
  end)
end)
