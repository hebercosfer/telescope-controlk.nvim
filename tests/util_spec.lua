local util = require("controlk.util")

describe("util.memo", function()
  it("runs compute once and shares the value with every caller", function()
    local ctx = { cache = {} }
    local calls = 0
    local compute = function(finish)
      calls = calls + 1
      finish({ "a", "b" })
    end

    local seen = {}
    util.memo(ctx, "key", compute, function(value)
      table.insert(seen, value)
    end)
    util.memo(ctx, "key", compute, function(value)
      table.insert(seen, value)
    end)

    assert.are.equal(1, calls)
    assert.are.equal(2, #seen)
    assert.are.same({ "a", "b" }, seen[2])
  end)

  it("makes callers that arrive while computing wait for the same result", function()
    local ctx = { cache = {} }
    local pending_finish
    local compute = function(finish)
      pending_finish = finish
    end

    local seen = {}
    util.memo(ctx, "slow", compute, function(value)
      table.insert(seen, "first:" .. value)
    end)
    util.memo(ctx, "slow", compute, function(value)
      table.insert(seen, "second:" .. value)
    end)
    assert.are.equal(0, #seen)

    pending_finish("done")
    assert.are.same({ "first:done", "second:done" }, seen)
  end)

  it("keeps different keys apart", function()
    local ctx = { cache = {} }
    local got = {}
    util.memo(ctx, "one", function(finish)
      finish(1)
    end, function(value)
      got.one = value
    end)
    util.memo(ctx, "two", function(finish)
      finish(2)
    end, function(value)
      got.two = value
    end)
    assert.are.same({ one = 1, two = 2 }, got)
  end)
end)

describe("util.hint", function()
  it("builds a non-actionable passthrough item", function()
    local item = util.hint("type more", "sym")
    assert.is_true(item.hint)
    assert.is_true(item.passthrough)
    assert.are.equal("sym", item.tag)
  end)
end)

describe("util.help_tag", function()
  it("names the section of a built-in source", function()
    assert.are.equal("controlk-source-lsp_classes", util.help_tag("lsp_classes"))
    assert.are.equal("controlk-source-filesystem", util.help_tag("filesystem"))
  end)

  it("names the default view when no prefix is typed", function()
    assert.are.equal("controlk-default-view", util.help_tag(nil))
  end)

  it("falls back to the list of sources for a source with no section", function()
    assert.are.equal("controlk-sources", util.help_tag("multigrep"))
  end)

  it("has a section for every built-in source", function()
    for id in pairs(require("controlk.sources").by_id) do
      assert.are.equal("controlk-source-" .. id, util.help_tag(id))
    end
  end)
end)
