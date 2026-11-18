local lsp = require("controlk.sources.lsp")
local SymbolKind = vim.lsp.protocol.SymbolKind

describe("lsp symbol kinds", function()
  it("classes include classes, structs and enums, not methods", function()
    assert.is_true(lsp.kinds.classes[SymbolKind.Class])
    assert.is_true(lsp.kinds.classes[SymbolKind.Struct])
    assert.is_true(lsp.kinds.classes[SymbolKind.Enum])
    assert.is_nil(lsp.kinds.classes[SymbolKind.Method])
  end)

  it("functions include methods, free functions and constructors", function()
    assert.is_true(lsp.kinds.functions[SymbolKind.Method])
    assert.is_true(lsp.kinds.functions[SymbolKind.Function])
    assert.is_true(lsp.kinds.functions[SymbolKind.Constructor])
    assert.is_nil(lsp.kinds.functions[SymbolKind.Class])
  end)

  it("the general symbol set leaves out String (macros in clangd)", function()
    assert.is_nil(lsp.kinds.symbols[SymbolKind.String])
    assert.is_true(lsp.kinds.symbols[SymbolKind.Class])
    assert.is_true(lsp.kinds.symbols[SymbolKind.Field])
  end)
end)

describe("lsp sources without a server", function()
  it("reports that no server supports the request", function()
    local ctx = { origin_buf = vim.api.nvim_create_buf(false, true), config = { lsp = { min_query = 1 } }, cache = {} }
    local got
    lsp.lsp_symbols.items("Widget", ctx, function(items)
      got = items
    end)
    assert.are.equal(1, #got)
    assert.is_true(got[1].hint)
    assert.is_truthy(got[1].text:find("no LSP server", 1, true))
  end)

  it("asks for a query before searching workspace symbols", function()
    local ctx = { origin_buf = 0, config = { lsp = { min_query = 3 } }, cache = {} }
    local got
    lsp.lsp_classes.items("Wi", ctx, function(items)
      got = items
    end)
    assert.is_true(got[1].hint)
    assert.is_truthy(got[1].text:find("3 character", 1, true))
  end)
end)
