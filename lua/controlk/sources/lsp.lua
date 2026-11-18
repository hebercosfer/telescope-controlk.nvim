-- Symbol sources. They work with any language server attached to the buffer
-- that was current when the locator opened.

local util = require("controlk.util")

local SymbolKind = vim.lsp.protocol.SymbolKind

local function kind_set(names)
  local set = {}
  for _, name in ipairs(names) do
    set[SymbolKind[name]] = true
  end
  return set
end

local M = {}

M.kinds = {
  -- Everything except String: clangd reports macros as String, which is noise here.
  symbols = (function()
    local set = {}
    for kind = 1, 26 do
      if kind ~= SymbolKind.String then
        set[kind] = true
      end
    end
    return set
  end)(),
  classes = kind_set({ "Class", "Struct", "Enum", "Interface" }),
  functions = kind_set({ "Method", "Function", "Constructor" }),
}

--- Send a request to every client attached to the origin buffer.
--- done(results, error_message): results is { { client, symbols } ... }.
local function request(ctx, method, params, done)
  local bufnr = ctx.origin_buf
  if #vim.lsp.get_clients({ bufnr = bufnr, method = method }) == 0 then
    return done({}, ("no LSP server attached to this buffer supports %s"):format(method))
  end

  vim.lsp.buf_request_all(bufnr, method, params, function(responses)
    local results, errors = {}, {}
    for client_id, response in pairs(responses) do
      local client = vim.lsp.get_client_by_id(client_id)
      if response.error then
        table.insert(errors, response.error.message)
      elseif client and type(response.result) == "table" then
        table.insert(results, { client = client, symbols = response.result })
      end
    end
    done(results, #errors > 0 and table.concat(errors, "; ") or nil)
  end)
end

local function to_items(results, kinds, tag, bufnr, passthrough)
  local items = {}
  for _, result in ipairs(results) do
    local symbols = result.symbols
    if kinds then
      symbols = vim.tbl_filter(function(symbol)
        return kinds[symbol.kind]
      end, symbols)
    end
    for _, location in
      ipairs(vim.lsp.util.symbols_to_items(symbols, bufnr, result.client.offset_encoding))
    do
      table.insert(items, {
        text = location.text,
        path = location.filename,
        lnum = location.lnum,
        col = location.col,
        tag = tag,
        passthrough = passthrough,
      })
    end
  end
  return items
end

local function workspace_source(title, tag, kinds)
  return {
    title = title,
    tag = tag,
    items = function(query, ctx, done)
      local min = ctx.config.lsp.min_query
      if #query < min then
        return done({
          util.hint(("type at least %d character(s) to search symbols"):format(min), tag),
        })
      end

      request(ctx, "workspace/symbol", { query = query }, function(results, err)
        local items = to_items(results, kinds, tag, ctx.origin_buf, true)
        if err then
          table.insert(items, 1, util.hint(err, tag))
        end
        done(items)
      end)
    end,
  }
end

M.lsp_symbols = workspace_source("Workspace symbols", "sym", M.kinds.symbols)
M.lsp_classes = workspace_source("Workspace classes", "class", M.kinds.classes)
M.lsp_functions = workspace_source("Workspace functions", "func", M.kinds.functions)

M.lsp_document = {
  title = "Symbols in current document",
  tag = "doc",
  items = function(_, ctx, done)
    request(ctx, "textDocument/documentSymbol", {
      textDocument = vim.lsp.util.make_text_document_params(ctx.origin_buf),
    }, function(results, err)
      local items = to_items(results, nil, "doc", ctx.origin_buf, false)
      if err then
        table.insert(items, 1, util.hint(err, "doc"))
      end
      done(items)
    end)
  end,
}

return M
