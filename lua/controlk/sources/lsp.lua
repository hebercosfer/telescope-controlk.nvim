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

-- clangd's default --limit-results. A reply of exactly this many symbols was probably cut.
M.LIMIT = 100

-- Progress percentages, by client id and progress token. Neovim keeps the titles of running
-- progress in client.progress.pending, but the percentages only reach LspProgress.
M.percent = {}
vim.api.nvim_create_autocmd("LspProgress", {
  group = vim.api.nvim_create_augroup("controlk_lsp_progress", { clear = true }),
  callback = function(ev)
    local data = ev.data or {}
    local params = data.params or {}
    local value = params.value or {}
    if not data.client_id or params.token == nil then
      return
    end
    local by_token = M.percent[data.client_id] or {}
    M.percent[data.client_id] = by_token
    if value.kind == "end" then
      by_token[params.token] = nil
    elseif value.percentage then
      by_token[params.token] = value.percentage
    end
  end,
})

local function same_project(client, root)
  local dir = client.root_dir or (client.config and client.config.root_dir)
  if type(dir) ~= "string" or type(root) ~= "string" then
    return false
  end
  return dir == root or vim.startswith(root, dir .. "/") or vim.startswith(dir, root .. "/")
end

--- The clients to ask. Those attached to the origin buffer; for workspace/symbol, which needs
--- no buffer, the clients running for the same project when none is attached, so the locator
--- also finds symbols when opened from a README, a directory or an empty buffer.
---@return table[] clients
---@return boolean attached true when they are attached to the origin buffer
function M.clients_for(ctx, method)
  local attached = vim.lsp.get_clients({ bufnr = ctx.origin_buf, method = method })
  if #attached > 0 or method ~= "workspace/symbol" then
    return attached, true
  end
  local running = vim.tbl_filter(function(client)
    return same_project(client, ctx.root)
  end, vim.lsp.get_clients({ method = method }))
  return running, false
end

--- Hints about results that may be incomplete: a server still indexing the project, and a
--- reply cut at the server's result limit.
---@param clients table[]
---@param counts table<integer, integer> symbols each client returned, by client id
---@param tag string
---@return table[] hints
function M.status_hints(clients, counts, tag)
  local hints = {}
  for _, client in ipairs(clients) do
    local pending = client.progress and client.progress.pending or {}
    for token, title in pairs(pending) do
      if type(title) == "string" and title:lower():find("index", 1, true) then
        local pct = M.percent[client.id] and M.percent[client.id][token]
        table.insert(
          hints,
          util.hint(
            ("%s is still indexing the project%s: results may be incomplete"):format(
              client.name,
              pct and (" (" .. pct .. "%)") or ""
            ),
            tag
          )
        )
        break
      end
    end
    if counts[client.id] == M.LIMIT then
      table.insert(
        hints,
        util.hint(
          ("%s returned %d results, its limit: type more to narrow them"):format(
            client.name,
            M.LIMIT
          ),
          tag
        )
      )
    end
  end
  return hints
end

local function client_request(client, method, params, handler, bufnr)
  if vim.fn.has("nvim-0.11") == 1 then
    return client:request(method, params, handler, bufnr)
  end
  return client.request(method, params, handler, bufnr)
end

--- Send a request to the clients for the origin buffer (see clients_for).
--- done(results, error_message, clients): results is { { client, symbols } ... }.
local function request(ctx, method, params, done)
  local bufnr = ctx.origin_buf
  local clients, attached = M.clients_for(ctx, method)
  if #clients == 0 then
    if method == "workspace/symbol" then
      return done(
        {},
        "no language server is running for this project: open one of its source files",
        {}
      )
    end
    return done({}, ("no LSP server attached to this buffer supports %s"):format(method), {})
  end

  local results, errors = {}, {}
  local function collect(client, err, result)
    if err then
      table.insert(errors, err.message)
    elseif client and type(result) == "table" then
      table.insert(results, { client = client, symbols = result })
    end
  end
  local function finish()
    done(results, #errors > 0 and table.concat(errors, "; ") or nil, clients)
  end

  if attached then
    vim.lsp.buf_request_all(bufnr, method, params, function(responses)
      for client_id, response in pairs(responses) do
        collect(vim.lsp.get_client_by_id(client_id), response.error, response.result)
      end
      finish()
    end)
    return
  end
  local waiting = #clients
  for _, client in ipairs(clients) do
    client_request(client, method, params, function(err, result)
      collect(client, err, result)
      waiting = waiting - 1
      if waiting == 0 then
        finish()
      end
    end)
  end
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

      request(ctx, "workspace/symbol", { query = query }, function(results, err, clients)
        local items = to_items(results, kinds, tag, ctx.origin_buf, true)
        local counts = {}
        for _, result in ipairs(results) do
          counts[result.client.id] = #result.symbols
        end
        local hints = M.status_hints(clients, counts, tag)
        if err then
          table.insert(hints, 1, util.hint(err, tag))
        end
        done(vim.list_extend(hints, items))
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
