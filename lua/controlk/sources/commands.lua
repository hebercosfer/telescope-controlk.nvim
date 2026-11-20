local util = require("controlk.util")

--- The row that runs what was typed as an Ex command: `: w`, `: 42`, `: s/a/b/g`. It ranks
--- before the command list, as `!` runs a shell command.
local function run_row(query, ctx)
  return {
    text = ":" .. query,
    detail = "run",
    pinned = true,
    passthrough = true,
    run = function()
      local ok, err = pcall(vim.api.nvim_win_call, ctx.origin_win, function()
        vim.cmd(query)
      end)
      if not ok then
        local message = tostring(err):gsub("^.-:%d+: ", "")
        vim.notify(message, vim.log.levels.ERROR)
      end
    end,
  }
end

return {
  id = "commands",
  title = "Ex commands",
  tag = "cmd",
  items = function(query, ctx, done)
    util.memo(ctx, "commands", function(finish)
      local user = vim.api.nvim_get_commands({})
      local items = {}
      for _, name in ipairs(vim.fn.getcompletion("", "command")) do
        local definition = user[name] and user[name].definition
        table.insert(items, {
          text = name,
          detail = definition,
          -- Open the command line with the name filled in, so arguments can follow.
          run = function()
            vim.api.nvim_feedkeys(":" .. name .. " ", "n", false)
          end,
        })
      end
      finish(items)
    end, function(items)
      if query == "" then
        return done(items)
      end
      local list = { run_row(query, ctx) }
      vim.list_extend(list, items)
      done(list)
    end)
  end,
}
