local cmdline = require("controlk.cmdline")
local util = require("controlk.util")

--- The row that runs what was typed as an Ex command: `: w`, `: 42`, `: s/a/b/g`. It ranks
--- before the other rows, as `!` runs a shell command. Its output and errors are notified.
local function run_row(query, ctx)
  return {
    text = ":" .. query,
    detail = "run",
    pinned = true,
    passthrough = true,
    run = function()
      cmdline.run(query, ctx.origin_win)
    end,
  }
end

return {
  id = "commands",
  title = "Ex commands",
  tag = "cmd",
  items = function(query, ctx, done)
    -- With a command and a space, list what <Tab> offers for its arguments (files, options,
    -- a plugin's subcommands) instead of command names.
    if query:find("%S%s") then
      local prefix = cmdline.prefix_of(ctx, "commands", ":")
      local list = { run_row(query, ctx) }
      vim.list_extend(
        list,
        cmdline.completions(query, function(line)
          return prefix .. " " .. line
        end)
      )
      return done(list)
    end
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
