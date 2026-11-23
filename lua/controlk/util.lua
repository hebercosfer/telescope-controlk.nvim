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

--- Whether a path is absolute: `/x`, or on Windows `C:/x`, `C:\x` and `\\server\share`.
---@param path string
---@return boolean
function M.is_absolute(path)
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil or path:sub(1, 2) == "\\\\"
end

--- A non-actionable line, shown for empty queries and errors.
---@param text string
---@param tag string
---@return table
function M.hint(text, tag)
  return { text = text, tag = tag, hint = true, passthrough = true }
end

--- The help tag that explains a source: what Enter on an empty list, or on a hint, opens.
--- nil is the default view. A source with no section of its own (a user source) gets the
--- list of sources.
---@param id string|nil source id, as config.prefix_map gives it
---@return string tag
function M.help_tag(id)
  local tag = id and ("controlk-source-" .. id) or "controlk-default-view"
  if vim.tbl_contains(vim.fn.getcompletion(tag, "help"), tag) then
    return tag
  end
  return "controlk-sources"
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

--- How long the default view waits for one of its sources before it lists the others
--- without it. A source picked by its prefix has no limit: it is the only one listed.
M.DEFAULT_TIMEOUT_MS = 5000

-- "file.lua:12: boom" -> "boom".
local function error_message(err)
  return (tostring(err):gsub("^.-:%d+: ", ""))
end

--- Ask one source for its items, so that a source that misbehaves cannot break the picker.
--- Since user sources (the `sources` option) anyone can write one. An error becomes a
--- notification and a hint row naming the source; only the first answer counts; a nil answer
--- is no items. With `timeout_ms`, a source that has not answered by then gives a hint
--- instead, and its late answer is ignored. An error raised later from a source's own
--- callback (a `vim.schedule`, a job) cannot be caught here.
---@param source table a source: `id`, `tag`, `items(query, ctx, done)`
---@param query string
---@param ctx table
---@param done fun(items: table[])
---@param timeout_ms integer|nil
function M.call_source(source, query, ctx, done, timeout_ms)
  local id = source.id or "?"
  local answered = false
  local timer

  local function finish(items)
    if answered then
      return
    end
    answered = true
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    done(M.tag_items(type(items) == "table" and items or {}, source.tag))
  end

  if timeout_ms then
    timer = vim.uv.new_timer()
    timer:start(
      timeout_ms,
      0,
      vim.schedule_wrap(function()
        finish({ M.hint(("%s gave no answer within %d ms"):format(id, timeout_ms), source.tag) })
      end)
    )
  end

  local ok, err = pcall(source.items, query, ctx, finish)
  if not ok then
    local message = error_message(err)
    vim.notify(("controlk: source %s failed: %s"):format(id, message), vim.log.levels.ERROR)
    finish({ M.hint(("%s failed: %s"):format(id, message), source.tag) })
  end
end

--- Ask several sources at once, and hand over all their items, in the sources' order, once
--- each has answered (or given up, see `call_source`).
---@param sources table[]
---@param query string
---@param ctx table
---@param done fun(items: table[])
---@param timeout_ms integer|nil
function M.collect(sources, query, ctx, done, timeout_ms)
  local results, pending = {}, #sources
  if pending == 0 then
    return done({})
  end
  for index, source in ipairs(sources) do
    M.call_source(source, query, ctx, function(items)
      results[index] = items
      pending = pending - 1
      if pending == 0 then
        local all = {}
        for i = 1, #sources do
          vim.list_extend(all, results[i])
        end
        done(all)
      end
    end, timeout_ms)
  end
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
    -- detaches its language server. Normalized first: bufadd() takes "~/x" literally and
    -- would make a new, empty buffer of that name (getmarklist() writes paths so).
    local bufnr = vim.fn.bufadd(vim.fs.normalize(item.path))
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
