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
    local ctx = {
      origin_buf = vim.api.nvim_create_buf(false, true),
      config = { lsp = { min_query = 1 } },
      cache = {},
    }
    local got
    lsp.lsp_symbols.items("Widget", ctx, function(items)
      got = items
    end)
    assert.are.equal(1, #got)
    assert.is_true(got[1].hint)
    assert.is_truthy(got[1].text:find("no language server is running", 1, true))
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

describe("lsp status hints", function()
  local function client(fields)
    return vim.tbl_extend("force", { id = 7, name = "clangd", progress = { pending = {} } }, fields)
  end

  after_each(function()
    lsp.percent = {}
  end)

  it("warns while the server is indexing, with the percentage when known", function()
    local c = client({ progress = { pending = { tok = "indexing" } } })
    lsp.percent[7] = { tok = 40 }
    local hints = lsp.status_hints({ c }, {}, "class")
    assert.are.equal(1, #hints)
    assert.is_true(hints[1].hint)
    assert.are.equal(
      "clangd is still indexing the project (40%): results may be incomplete",
      hints[1].text
    )
  end)

  it("warns while indexing even when no percentage was seen", function()
    local c = client({ progress = { pending = { tok = "Indexing" } } })
    assert.matches("still indexing the project:", lsp.status_hints({ c }, {}, "sym")[1].text)
  end)

  it("ignores other progress, such as a file being parsed", function()
    local c = client({ progress = { pending = { tok = "Parsing main.cpp" } } })
    assert.are.same({}, lsp.status_hints({ c }, {}, "sym"))
  end)

  it("warns when a reply has exactly the configured result limit", function()
    local hints = lsp.status_hints({ client({}) }, { [7] = 100 }, "func", 100)
    assert.are.equal(1, #hints)
    assert.matches("returned 100 results, which looks like its limit", hints[1].text)
    assert.are.same({}, lsp.status_hints({ client({}) }, { [7] = 99 }, "func", 100))
    assert.are.equal(1, #lsp.status_hints({ client({}) }, { [7] = 500 }, "func", 500))
  end)

  it("never warns about the limit when it is false", function()
    assert.are.same({}, lsp.status_hints({ client({}) }, { [7] = 100 }, "func", false))
  end)
end)

describe("lsp clients for a request", function()
  local real = vim.lsp.get_clients
  local attached, running

  before_each(function()
    attached, running = {}, {}
    vim.lsp.get_clients = function(filter)
      return filter.bufnr and attached or running
    end
  end)

  after_each(function()
    vim.lsp.get_clients = real
  end)

  local ctx = { origin_buf = 1, root = "/work/proj" }

  it("prefers the clients attached to the origin buffer", function()
    attached = { { id = 1 } }
    running = { { id = 2, root_dir = "/work/proj" } }
    local clients, is_attached = lsp.clients_for(ctx, "workspace/symbol")
    assert.are.same({ { id = 1 } }, clients)
    assert.is_true(is_attached)
  end)

  it("falls back to the project's running clients for workspace symbols", function()
    running = {
      { id = 2, root_dir = "/work/proj" },
      { id = 3, root_dir = "/work/proj/sub" },
      { id = 4, root_dir = "/work/other" },
      { id = 5 },
    }
    local clients, is_attached = lsp.clients_for(ctx, "workspace/symbol")
    local ids = vim.tbl_map(function(c)
      return c.id
    end, clients)
    assert.are.same({ 2, 3 }, ids)
    assert.is_false(is_attached)
  end)

  it("never falls back for the document's own symbols", function()
    running = { { id = 2, root_dir = "/work/proj" } }
    assert.are.same({}, (lsp.clients_for(ctx, "textDocument/documentSymbol")))
  end)
end)

describe("lsp symbol columns", function()
  it("converts a character offset to a byte column in each encoding", function()
    local line = "/* é */ struct Widget {};"
    -- "é" is two bytes in UTF-8, one unit in UTF-16 and UTF-32.
    assert.are.equal(16, lsp.byte_col(line, 15, "utf-16"))
    assert.are.equal(16, lsp.byte_col(line, 15, "utf-32"))
    assert.are.equal(16, lsp.byte_col(line, 16, "utf-8"))
    assert.are.equal(#line, lsp.byte_col(line, 200, "utf-16"))
  end)

  it("takes a workspace symbol's column from its own file, not the origin buffer", function()
    local path = vim.fn.tempname() .. ".h"
    vim.fn.writefile({ "// header", "/* é */ struct Widget {};" }, path)
    local origin = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(origin, 0, -1, false, { "int a;", "int bbbbbbbbbbbbbbbbbbbbb;" })
    local symbol = {
      name = "Widget",
      kind = vim.lsp.protocol.SymbolKind.Struct,
      location = {
        uri = vim.uri_from_fname(path),
        range = { start = { line = 1, character = 15 }, ["end"] = { line = 1, character = 21 } },
      },
    }
    local items = lsp.to_items(
      { { client = { offset_encoding = "utf-16" }, symbols = { symbol } } },
      nil,
      "sym",
      origin,
      true
    )
    assert.are.equal(1, #items)
    assert.are.equal(2, items[1].lnum)
    assert.are.equal(17, items[1].col)
    vim.fn.delete(path)
  end)
end)
