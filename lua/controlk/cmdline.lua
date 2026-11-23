-- The command line, as the locator uses it: what <Tab> would offer after a command line
-- (the same list a completion menu such as blink.cmp shows, and noice draws), and running a
-- command line with its output and errors sent to vim.notify. Shared by `:` and `lua`.

local M = {}

-- Where a completed piece may start: after a space, a dot, a bracket, a separator.
local BOUNDARY = "[%s%.%(%[{,:=/'\"]"

--- The line with the piece that `getcompletion` completed replaced by `completion`.
--- `getcompletion` gives only that piece (`tabstop` for `set tabst`, `lsp` for `lua vim.ls`,
--- `lua/controlk/` for `e lua/contr`), so it replaces the longest tail of the line that starts
--- at a boundary and that the completion begins with. With none, the completion is appended.
---@param line string
---@param completion string
---@return string
function M.apply(line, completion)
  local lower = completion:lower()
  for i = 1, #line + 1 do
    if i == 1 or line:sub(i - 1, i - 1):match(BOUNDARY) then
      local tail = line:sub(i):lower()
      if lower:sub(1, #tail) == tail then
        return line:sub(1, i - 1) .. completion
      end
    end
  end
  return line .. completion
end

--- Rows for what <Tab> offers after `line`, an Ex command line without its colon. They are
--- passthrough (Neovim already matched them) and act as prompts: picking one puts
--- `prompt_of(completed line)` in the input, so the user can keep typing.
---@param line string
---@param prompt_of fun(completed: string): string
---@return table[]
function M.completions(line, prompt_of)
  local ok, list = pcall(vim.fn.getcompletion, line, "cmdline")
  if not ok then
    return {}
  end
  local items = {}
  for _, completion in ipairs(list) do
    table.insert(items, {
      text = completion,
      passthrough = true,
      prompt = prompt_of(M.apply(line, completion)),
    })
  end
  return items
end

--- "...: Vim(lua):E5108: Lua: [string ":lua"]:1: boom\nstack traceback: ..." -> "E5108: Lua: boom".
---@param err any
---@return string
function M.error_message(err)
  local message = tostring(err)
  message = message:match("(E%d+:.*)") or message:gsub("^.-:%d+: ", "")
  message = message:gsub("\nstack traceback:.*", "")
  message = message:gsub('%[string ":lua"%]:%d+: ', "")
  return message
end

--- Run an Ex command line in `win` (the window the locator was opened from). Its output, if
--- any, goes to vim.notify at INFO, an error at ERROR: nothing goes to the message area.
---@param line string
---@param win integer|nil
function M.run(line, win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    win = vim.api.nvim_get_current_win()
  end
  local ok, result = pcall(vim.api.nvim_win_call, win, function()
    return vim.api.nvim_exec2(line, { output = true })
  end)
  if not ok then
    vim.notify(M.error_message(result), vim.log.levels.ERROR)
    return
  end
  local output = vim.trim(result.output or "")
  if output ~= "" then
    vim.notify(output, vim.log.levels.INFO)
  end
end

--- The prefix the user's configuration gives a source, for building a prompt.
---@param ctx table
---@param id string
---@param fallback string
---@return string
function M.prefix_of(ctx, id, fallback)
  for prefix, source in pairs(ctx.config and ctx.config.prefix_map or {}) do
    if source == id then
      return prefix
    end
  end
  return fallback
end

return M
