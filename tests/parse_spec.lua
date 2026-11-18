local parse = require("controlk.parse")

local map = {
  o = "buffers",
  a = "files",
  c = "lsp_classes",
  cm = "cmake_targets",
  cmo = "cmake_open",
  ["?"] = "help",
}

describe("parse", function()
  it("returns the source and the text after prefix and space", function()
    local id, query, prefix = parse.parse("c Widget", map)
    assert.are.same({ "lsp_classes", "Widget", "c" }, { id, query, prefix })
  end)

  it("needs a space after the prefix", function()
    local id, query = parse.parse("c", map)
    assert.is_nil(id)
    assert.are.equal("c", query)
  end)

  it("prefers the longest matching prefix", function()
    local id, query = parse.parse("cm build", map)
    assert.are.equal("cmake_targets", id)
    assert.are.equal("build", query)

    id, query = parse.parse("cmo main", map)
    assert.are.equal("cmake_open", id)
    assert.are.equal("main", query)
  end)

  it("accepts an empty query after the prefix", function()
    local id, query = parse.parse("o ", map)
    assert.are.equal("buffers", id)
    assert.are.equal("", query)
  end)

  it("treats the whole prompt as the query when no prefix matches", function()
    local id, query = parse.parse("Widget", map)
    assert.is_nil(id)
    assert.are.equal("Widget", query)
  end)

  it("only looks at the start of the prompt", function()
    local id, query = parse.parse("Widget c", map)
    assert.is_nil(id)
    assert.are.equal("Widget c", query)
  end)

  it("matches prefixes that are regex or pattern characters", function()
    local id, query = parse.parse("? vector", map)
    assert.are.equal("help", id)
    assert.are.equal("vector", query)
  end)

  it("handles an empty prompt", function()
    local id, query = parse.parse("", map)
    assert.is_nil(id)
    assert.are.equal("", query)
  end)
end)
