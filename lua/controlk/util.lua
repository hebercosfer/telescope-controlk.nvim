local channel = require("plenary.async.control").channel

local M = {}

--- Await a callback-style function from inside a telescope dynamic finder.
--- Telescope runs finders in a plenary async context, so the receive can yield.
--- The value is delivered on the main loop, so callbacks may come from libuv.
---@param start fun(done: fun(value: any))
---@return any
function M.await(start)
  local tx, rx = channel.oneshot()
  start(function(value)
    vim.schedule(function()
      tx(value)
    end)
  end)
  return rx()
end

--- Run `compute` once per picker session and share its result.
--- Callers that arrive while it is still running wait for the same value.
---@param ctx table session context (its `cache` table holds the entries)
---@param key string
---@param compute fun(finish: fun(value: any))
---@param done fun(value: any)
function M.memo(ctx, key, compute, done)
  local entry = ctx.cache[key]
  if entry and entry.ready then
    return done(entry.value)
  end
  if entry then
    table.insert(entry.waiters, done)
    return
  end

  entry = { waiters = { done } }
  ctx.cache[key] = entry
  compute(function(value)
    entry.ready = true
    entry.value = value
    local waiters = entry.waiters
    entry.waiters = nil
    for _, waiter in ipairs(waiters) do
      waiter(value)
    end
  end)
end

---@param bufnr integer
---@return string directory of the buffer's file, or the cwd for unnamed buffers
function M.buffer_dir(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
end

---@param bufnr integer
---@return string project root: nearest .git ancestor, else the cwd
function M.project_root(bufnr)
  return vim.fs.root(M.buffer_dir(bufnr), { ".git" }) or vim.fn.getcwd()
end

--- A non-actionable line, shown for empty queries and errors.
---@param text string
---@param tag string
---@return table
function M.hint(text, tag)
  return { text = text, tag = tag, hint = true, passthrough = true }
end

--- Run a command in a terminal split at the bottom of the window.
--- On Neovim 0.10, jobstart({ term = true }) starts the job in an empty buffer, so
--- termopen() is used there. From 0.11 on, jobstart is the supported way.
---@param cmd string|string[]
---@param cwd string
function M.terminal(cmd, cwd)
  vim.cmd("botright 12new")
  if vim.fn.has("nvim-0.11") == 1 then
    vim.fn.jobstart(cmd, { term = true, cwd = cwd })
  else
    vim.fn.termopen(cmd, { cwd = cwd })
  end
  vim.cmd("startinsert")
end

--- Give every item a tag, falling back to the source's tag.
---@param items table[]
---@param tag string
---@return table[] items
function M.tag_items(items, tag)
  for _, item in ipairs(items) do
    item.tag = item.tag or tag
  end
  return items
end

--- Carry out the default action for a picked item.
---@param item table
function M.act(item)
  if item.hint then
    return
  end
  if item.run then
    return item.run(item)
  end

  if item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr) then
    vim.api.nvim_set_current_buf(item.bufnr)
  elseif item.path then
    -- Not `:edit`: editing a file that is already open reloads it, which
    -- detaches its language server.
    local bufnr = vim.fn.bufadd(item.path)
    vim.bo[bufnr].buflisted = true
    vim.api.nvim_set_current_buf(bufnr)
  else
    return
  end

  if item.lnum then
    local row = math.max(1, math.min(item.lnum, vim.api.nvim_buf_line_count(0)))
    local col = math.max((item.col or 1) - 1, 0)
    pcall(vim.api.nvim_win_set_cursor, 0, { row, col })
    vim.cmd("normal! zz")
  end
end

return M
